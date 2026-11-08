import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_importer.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/playlist_source.dart';

class SourceRepository {
  SourceRepository({
    required AppDatabase db,
    required PlaylistLoader loader,
    M3uImporter? importer,
    XtreamImporter? xtreamImporter,
    XtreamClient Function(XtreamCredentials credentials)? xtreamClientFactory,
  }) : _db = db,
       _loader = loader,
       _importer = importer ?? M3uImporter(),
       _xtreamImporter = xtreamImporter ?? XtreamImporter(),
       _xtreamClientFactory = xtreamClientFactory ?? XtreamClient.new;

  final AppDatabase _db;
  final PlaylistLoader _loader;
  final M3uImporter _importer;
  final XtreamImporter _xtreamImporter;
  final XtreamClient Function(XtreamCredentials credentials)
  _xtreamClientFactory;

  Stream<PlaylistSource?> watchActive() => _db.sourceDao.watchActive().map(
    (row) => row == null ? null : _toModel(row),
  );

  Future<PlaylistSource> save(PlaylistSource source) async {
    final id = source.id;
    if (id == null) {
      final newId = await _db.sourceDao.insertSource(_insertCompanion(source));
      return source.copyWith(id: newId);
    }
    await _db.sourceDao.updateSource(id, _updateCompanion(source));
    return source;
  }

  Future<Directory> _playlistDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'playlists'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Grava o arquivo escolhido na pasta do app, por stream. No Android o
  /// seletor devolve URI de SAF sem caminho, então a cópia é a única forma
  /// de a fonte continuar válida para refresh.
  Future<String> persistPickedFile(String name, Stream<List<int>> bytes) async {
    final dir = await _playlistDir();
    final safeName = p.basename(name).replaceAll(RegExp(r'[^\w.\-]'), '_');
    final target = File(
      p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_$safeName'),
    );
    final sink = target.openWrite();
    try {
      await sink.addStream(bytes);
    } finally {
      await sink.close();
    }
    return target.path;
  }

  /// Copia um caminho local para a pasta do app, se ainda não estiver lá.
  Future<String> persistLocalFile(String path) async {
    final dir = await _playlistDir();
    if (p.isWithin(dir.path, path)) return path;
    return persistPickedFile(p.basename(path), File(path).openRead());
  }

  /// Importa numa geração nova. A geração anterior continua visível até o
  /// fim; em erro ou cancelamento só a geração nova é descartada.
  Future<ImportResult> importSource(
    PlaylistSource source, {
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
    bool activate = true,
  }) async {
    final isNew = source.id == null;
    final saved = await save(source);
    final sourceId = saved.id!;
    final current = await _db.sourceDao.byId(sourceId);
    final generation = (current?.activeGeneration ?? 0) + 1;

    PlaylistStream? stream;
    try {
      final ImportResult result;
      final credentials = saved.xtream;
      if (saved.kind == SourceKind.xtream && credentials != null) {
        result = await _importXtream(
          credentials,
          sourceId,
          generation,
          cancel,
          onProgress,
        );
      } else {
        stream = await _loader.open(saved, cancel: cancel);
        result = await _importer.run(
          bytes: stream.bytes,
          totalBytes: stream.length,
          cancel: cancel,
          onProgress: onProgress,
          sink: (batch, start) =>
              _db.channelDao.insertEntries(sourceId, generation, start, batch),
        );
      }
      if (result.imported == 0) {
        throw const SourceException(SourceError.empty);
      }
      await _db.transaction(() async {
        await _db.channelDao.deleteOtherGenerations(sourceId, generation);
        await _db.vodDao.deleteOtherGenerations(sourceId, generation);
        await _db.sourceDao.markRefreshed(
          sourceId,
          generation,
          DateTime.now().toUtc(),
        );
        if (activate) await _db.sourceDao.setActive(sourceId);
        final epgUrl = result.epgUrl ?? _xtreamEpgUrl(saved);
        if (epgUrl != null) {
          await _db.sourceDao.updateSource(
            sourceId,
            SourcesCompanion(epgUrl: Value(epgUrl)),
          );
        }
      });
      return result;
    } catch (error) {
      await _db.channelDao.deleteGeneration(sourceId, generation);
      await _db.vodDao.deleteGeneration(sourceId, generation);
      if (isNew) await _db.sourceDao.deleteSource(sourceId);
      throw _normalize(error, saved.kind, cancel);
    } finally {
      await stream?.close();
    }
  }

  /// Xtream pela API: canais nas mesmas tabelas do M3U, VOD e séries nas
  /// tabelas de catálogo, tudo na mesma geração.
  Future<ImportResult> _importXtream(
    XtreamCredentials credentials,
    int sourceId,
    int generation,
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  ) async {
    final result = await _xtreamImporter.run(
      client: _xtreamClientFactory(credentials),
      cancel: cancel,
      onProgress: onProgress,
      liveSink: (batch, start) =>
          _db.channelDao.insertEntries(sourceId, generation, start, batch),
      vodSink: (batch, start, names) =>
          _db.vodDao.insertVod(sourceId, generation, start, batch, names),
      seriesSink: (batch, start, names) =>
          _db.vodDao.insertSeries(sourceId, generation, start, batch, names),
    );
    return result.toImportResult();
  }

  Future<ImportResult> refresh(
    PlaylistSource source, {
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) => importSource(source, cancel: cancel, onProgress: onProgress);

  Future<bool> toggleFavorite(Channel channel) =>
      _db.channelDao.toggleFavorite(channel.sourceId, channel.channelKey);

  /// Endpoint de-facto `xmltv.php` do Xtream, com as mesmas credenciais.
  String? _xtreamEpgUrl(PlaylistSource source) {
    final creds = source.xtream;
    if (source.kind != SourceKind.xtream || creds == null) return null;
    try {
      final base = creds.baseUri;
      return base
          .replace(
            path: '${base.path}/xmltv.php',
            queryParameters: <String, String>{
              'username': creds.username,
              'password': creds.password,
            },
          )
          .toString();
    } on SourceException {
      return null;
    }
  }

  SourceException _normalize(
    Object error,
    SourceKind kind,
    ImportCancelToken? cancel,
  ) {
    if (cancel != null && cancel.isCancelled) {
      return const SourceException(SourceError.cancelled);
    }
    if (error is SourceException) {
      if (kind == SourceKind.xtream &&
          error.error == SourceError.invalidContent) {
        return SourceException(
          SourceError.credentials,
          statusCode: error.statusCode,
          detail: error.detail,
        );
      }
      return error;
    }
    if (error is FileSystemException) {
      return SourceException(SourceError.notFound, detail: error.message);
    }
    return SourceException(SourceError.network, detail: '$error');
  }

  PlaylistSource _toModel(SourceRow row) {
    final host = row.xtreamHost;
    return PlaylistSource(
      id: row.id,
      name: row.name,
      kind: row.kind,
      location: row.location,
      xtream: row.kind == SourceKind.xtream && host != null
          ? XtreamCredentials(
              host: host,
              port: row.xtreamPort,
              username: row.xtreamUser ?? '',
              password: row.xtreamPass ?? '',
            )
          : null,
      activeGeneration: row.activeGeneration,
      lastRefresh: row.lastRefresh,
    );
  }

  SourcesCompanion _insertCompanion(PlaylistSource s) {
    return SourcesCompanion.insert(
      name: s.name,
      kind: s.kind,
      location: s.location,
      xtreamHost: Value(s.xtream?.host),
      xtreamPort: Value(s.xtream?.port),
      xtreamUser: Value(s.xtream?.username),
      xtreamPass: Value(s.xtream?.password),
    );
  }

  SourcesCompanion _updateCompanion(PlaylistSource s) {
    return SourcesCompanion(
      name: Value(s.name),
      kind: Value(s.kind),
      location: Value(s.location),
      xtreamHost: Value(s.xtream?.host),
      xtreamPort: Value(s.xtream?.port),
      xtreamUser: Value(s.xtream?.username),
      xtreamPass: Value(s.xtream?.password),
    );
  }
}
