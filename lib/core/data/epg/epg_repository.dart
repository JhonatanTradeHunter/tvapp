import 'dart:async';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_parser.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/secure/secret_store.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/models/playlist_source.dart';

/// Baixa o XMLTV da fonte e importa numa geração nova. A geração anterior
/// continua valendo até o fim; em erro ou cancelamento só a nova sai.
class EpgRepository {
  EpgRepository({
    required AppDatabase db,
    http.Client Function()? clientFactory,
    XmltvImporter? importer,
    PlaylistLoader? loader,
    SecretStore? secrets,
  }) : _db = db,
       _secrets = secrets ?? SecureSecretStore(),
       _clientFactory = clientFactory ?? http.Client.new,
       _importer = importer ?? XmltvImporter(),
       _loader = loader ?? PlaylistLoader(clientFactory: clientFactory);

  final AppDatabase _db;
  final SecretStore _secrets;
  final http.Client Function() _clientFactory;
  final XmltvImporter _importer;
  final PlaylistLoader _loader;

  /// Falta algo que versões antigas não gravavam: `epgUrl` (antes da fase 2)
  /// ou, em Xtream, o fuso do painel (antes do banco v5).
  static bool needsMetadata(SourceRow row) {
    final url = row.epgUrl;
    if (url == null || url.isEmpty) return true;
    return row.kind == SourceKind.xtream && row.serverTimezone == null;
  }

  /// Recupera o que [needsMetadata] aponta. Xtream: `xmltv.php` montado com
  /// as credenciais e fuso lido do `player_api`. M3U: `url-tvg` do cabeçalho,
  /// lendo só o começo da lista. Falhas deixam o campo como estava.
  Future<void> recoverMetadata(int sourceId) async {
    final row = await _db.sourceDao.byId(sourceId);
    if (row == null || !needsMetadata(row)) return;
    var epgUrl = row.epgUrl;
    var timezone = row.serverTimezone;
    final missingUrl = epgUrl == null || epgUrl.isEmpty;

    final credentials = await xtreamCredentialsFor(row, _secrets);
    if (credentials != null) {
      if (missingUrl) epgUrl = xtreamEpgMarker;
      if (timezone == null) {
        try {
          final account = await XtreamClient(
            credentials,
            clientFactory: _clientFactory,
          ).authenticate();
          timezone = account.serverTimezone;
        } on SourceException {
          timezone = null;
        }
      }
    } else if (missingUrl) {
      epgUrl = await _headerEpgUrl(row);
    }

    await _db.sourceDao.updateSource(
      sourceId,
      SourcesCompanion(epgUrl: Value(epgUrl), serverTimezone: Value(timezone)),
    );
  }

  Future<String?> _headerEpgUrl(SourceRow row) async {
    final source = PlaylistSource(
      name: row.name,
      kind: row.kind,
      location: row.location,
    );
    PlaylistStream? stream;
    try {
      stream = await _loader.open(source);
      await for (final raw in M3uStreamReader.lines(stream.bytes)) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('#EXTM3U')) return null;
        return firstEpgUrl(M3uParser.parseHeader(line).urlTvg);
      }
      return null;
    } on SourceException {
      return null;
    } finally {
      await stream?.close();
    }
  }

  /// `url-tvg` pode trazer várias URLs separadas por vírgula.
  static String? firstEpgUrl(String? raw) {
    if (raw == null) return null;
    for (final part in raw.split(',')) {
      final candidate = part.trim();
      final uri = Uri.tryParse(candidate);
      if (uri != null && uri.host.isNotEmpty) return candidate;
    }
    return null;
  }

  /// URL gravada, ou o `xmltv.php` montado com a senha do cofre.
  Future<Uri?> _resolveEpgUri(SourceRow row) async {
    final url = row.epgUrl;
    if (url == null) return null;
    if (url != xtreamEpgMarker) return Uri.tryParse(url);
    final credentials = await xtreamCredentialsFor(row, _secrets);
    if (credentials == null) return null;
    try {
      return credentials.xmltvUri();
    } on SourceException {
      return null;
    }
  }

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
    final uri = row == null ? null : await _resolveEpgUri(row);
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
