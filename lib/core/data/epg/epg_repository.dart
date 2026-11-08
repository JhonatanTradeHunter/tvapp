import 'dart:async';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/models/playlist_source.dart';

/// Baixa o XMLTV da fonte e importa numa geração nova. A geração anterior
/// continua valendo até o fim; em erro ou cancelamento só a nova sai.
class EpgRepository {
  EpgRepository({
    required AppDatabase db,
    http.Client Function()? clientFactory,
    XmltvImporter? importer,
  }) : _db = db,
       _clientFactory = clientFactory ?? http.Client.new,
       _importer = importer ?? XmltvImporter();

  final AppDatabase _db;
  final http.Client Function() _clientFactory;
  final XmltvImporter _importer;

  static const Duration staleAfter = Duration(hours: 12);

  bool isStale(SourceRow row, DateTime now) {
    final url = row.epgUrl;
    if (url == null || url.isEmpty) return false;
    final last = row.epgRefresh;
    return last == null || now.difference(last) > staleAfter;
  }

  Future<XmltvImportResult> refresh(
    int sourceId, {
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final row = await _db.sourceDao.byId(sourceId);
    final url = row?.epgUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (row == null || uri == null || uri.host.isEmpty) {
      throw const SourceException(SourceError.notFound, detail: 'epg-url');
    }
    final generation = row.epgGeneration + 1;
    final client = _clientFactory();
    cancel?.onCancel(client.close);

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(PlaylistLoader.defaultHeaders);
      final http.StreamedResponse response;
      try {
        response = await client
            .send(request)
            .timeout(PlaylistLoader.responseTimeout);
      } on TimeoutException {
        throw const SourceException(SourceError.timeout);
      }
      final failure = PlaylistLoader.classifyResponse(
        response.statusCode,
        response.headers['content-type'],
        credentialsMode: false,
      );
      if (failure != null) throw failure;

      final result = await _importer.run(
        bytes: response.stream,
        totalBytes: response.contentLength,
        cancel: cancel,
        onProgress: onProgress,
        channelSink: (batch) =>
            _db.epgDao.insertChannels(sourceId, generation, batch),
        programmeSink: (batch) =>
            _db.epgDao.insertProgrammes(sourceId, generation, batch),
      );

      await _db.transaction(() async {
        await _db.epgDao.deleteOtherGenerations(sourceId, generation);
        await _db.sourceDao.updateSource(
          sourceId,
          SourcesCompanion(
            epgGeneration: Value(generation),
            epgRefresh: Value(DateTime.now().toUtc()),
          ),
        );
      });
      return result;
    } catch (error) {
      await _db.epgDao.deleteGeneration(sourceId, generation);
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
      if (error is SourceException) rethrow;
      throw SourceException(SourceError.network, detail: '$error');
    } finally {
      client.close();
    }
  }
}
