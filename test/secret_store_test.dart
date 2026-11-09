import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/secure/secret_store.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/source/source_repository.dart';
import 'package:tvapp/core/models/playlist_source.dart';

class _FailingStore extends MemorySecretStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keystore indisponível');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertXtream(String? password) => db
      .into(db.sources)
      .insert(
        SourcesCompanion.insert(
          name: 'painel',
          kind: SourceKind.xtream,
          location: 'http://painel.example:8080',
          xtreamHost: const Value('http://painel.example'),
          xtreamPort: const Value(8080),
          xtreamUser: const Value('u'),
          xtreamPass: Value(password),
          isActive: const Value(true),
        ),
      );

  test('move a senha para o cofre e apaga do banco', () async {
    final id = await insertXtream('segredo');
    final store = MemorySecretStore();

    expect(await moveXtreamPasswords(db, store), 1);
    expect(store.values[SecretStore.xtreamPasswordKey(id)], 'segredo');
    expect((await db.sourceDao.byId(id))!.xtreamPass, isNull);
    expect(await moveXtreamPasswords(db, store), 0);
  });

  test('se o cofre falhar, a senha continua no banco', () async {
    final id = await insertXtream('segredo');

    expect(await moveXtreamPasswords(db, _FailingStore()), 0);
    expect((await db.sourceDao.byId(id))!.xtreamPass, 'segredo');
  });

  test('fonte ativa lê a senha do cofre depois de migrar', () async {
    await insertXtream('segredo');
    final store = MemorySecretStore();
    final repo = SourceRepository(
      db: db,
      loader: PlaylistLoader(),
      secrets: store,
    );

    final active = await repo.watchActive().firstWhere((s) => s != null);
    expect(active!.xtream!.password, 'segredo');
    expect((await db.sourceDao.byId(active.id!))!.xtreamPass, isNull);
  });

  test('salvar fonte Xtream não grava a senha no SQLite', () async {
    final store = MemorySecretStore();
    final repo = SourceRepository(
      db: db,
      loader: PlaylistLoader(),
      secrets: store,
    );
    final saved = await repo.save(
      const PlaylistSource(
        name: 'painel',
        kind: SourceKind.xtream,
        location: 'http://painel.example:8080',
        xtream: XtreamCredentials(
          host: 'http://painel.example',
          port: 8080,
          username: 'u',
          password: 'nova',
        ),
      ),
    );

    final row = await db.sourceDao.byId(saved.id!);
    expect(row!.xtreamPass, isNull);
    expect(store.values[SecretStore.xtreamPasswordKey(saved.id!)], 'nova');
  });
}
