import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/secure/secret_store.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_importer.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/platform/local_io.dart' as local_io;

class SourceRepository {
  SourceRepository({
    required AppDatabase db,
    required PlaylistLoader loader,
    M3uImporter? importer,
    XtreamImporter? xtreamImporter,
    XtreamClient Function(XtreamCredentials credentials)? xtreamClientFactory,
    SecretStore? secrets,
  }) : _db = db,
       _secrets = secrets ?? SecureSecretStore(),
       _loader = loader,
       _importer = importer ?? M3uImporter(),
       _xtreamImporter = xtreamImporter ?? XtreamImporter(),
       _xtreamClientFactory = xtreamClientFactory ?? XtreamClient.new;

  final AppDatabase _db;
  final SecretStore _secrets;
  final PlaylistLoader _loader;
  final M3uImporter _importer;
  final XtreamImporter _xtreamImporter;
  final XtreamClient Function(XtreamCredentials credentials)
  _xtreamClientFactory;

  Future<void>? _passwordsMoved;

  /// Na primeira assinatura, tira do SQLite as senhas gravadas por versões
  /// antigas antes de emitir qualquer fonte.
  Stream<PlaylistSource?> watchActive() async* {
    await (_passwordsMoved ??= moveXtreamPasswords(
      _db,
      _secrets,
    ).then((_) {}, onError: (Object e) => debugPrint('mover senhas: $e')));
    yield* _db.sourceDao.watchActive().asyncMap(
      (row) async => row == null ? null : _toModel(row),
    );
  }

  /// A senha Xtream vai para o [SecretStore]; a coluna fica nula.
  Future<PlaylistSource> save(PlaylistSource source) async {
    final id = source.id;
    final password = source.xtream?.password;
    if (id == null) {
      final newId = await _db.sourceDao.insertSource(_insertCompanion(source));
      await _storePassword(newId, password);
      return source.copyWith(id: newId);
    }
    await _storePassword(id, password);
    await _db.sourceDao.updateSource(id, _updateCompanion(source));
    return source;
  }

  Future<void> _storePassword(int sourceId, String? password) {
    final key = SecretStore.xtreamPasswordKey(sourceId);
    return password == null
        ? _secrets.delete(key)
        : _secrets.write(key, password);
  }

  /// Grava o arquivo escolhido na pasta do app, por stream. No Android o
  /// seletor devolve URI de SAF sem caminho, então a cópia é a única forma
  /// de a fonte continuar válida para refresh. Indisponível na web.
  Future<String> persistPickedFile(String name, Stream<List<int>> bytes) =>
      local_io.persistPickedFile(name, bytes);

  /// Copia um caminho local para a pasta do app, se ainda não estiver lá.
  Future<String> persistLocalFile(String path) =>
      local_io.persistLocalFile(path);

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
      if (isNew) {
        await _db.sourceDao.deleteSource(sourceId);
        await _secrets.delete(SecretStore.xtreamPasswordKey(sourceId));
      }
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
    final run = await _xtreamImporter.run(
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
    await _db.sourceDao.updateSource(
      sourceId,
      SourcesCompanion(serverTimezone: Value(run.account.serverTimezone)),
    );
    return run.toImportResult();
  }

  Future<ImportResult> refresh(
    PlaylistSource source, {
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) => importSource(source, cancel: cancel, onProgress: onProgress);

  Future<bool> toggleFavorite(int profileId, Channel channel) => _db.channelDao
      .toggleFavorite(profileId, channel.sourceId, channel.channelKey);

  String? _xtreamEpgUrl(PlaylistSource source) {
    final creds = source.xtream;
    if (source.kind != SourceKind.xtream || creds == null) return null;
    try {
      return creds.xmltvUri().toString();
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
    final fileError = local_io.fileSystemErrorMessage(error);
    if (fileError != null) {
      return SourceException(SourceError.notFound, detail: fileError);
    }
    return SourceException(SourceError.network, detail: '$error');
  }

  Future<PlaylistSource> _toModel(SourceRow row) async {
    return PlaylistSource(
      id: row.id,
      name: row.name,
      kind: row.kind,
      location: row.location,
      xtream: await xtreamCredentialsFor(row, _secrets),
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
      xtreamPass: const Value(null),
    );
  }
}
