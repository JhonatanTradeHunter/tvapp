import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';

const List<String> _v1 = <String>[
  'CREATE TABLE sources (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'name TEXT NOT NULL, kind TEXT NOT NULL, location TEXT NOT NULL, '
      'xtream_host TEXT NULL, xtream_port INTEGER NULL, xtream_user TEXT NULL, '
      'xtream_pass TEXT NULL, active_generation INTEGER NOT NULL DEFAULT 0, '
      'last_refresh INTEGER NULL, is_active INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE channels (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'source_id INTEGER NOT NULL REFERENCES sources (id) ON DELETE CASCADE, '
      'generation INTEGER NOT NULL, position INTEGER NOT NULL, '
      'channel_key TEXT NOT NULL, name TEXT NOT NULL, name_folded TEXT NOT NULL, '
      'tvg_id TEXT NULL, tvg_name TEXT NULL, logo TEXT NULL, '
      'group_title TEXT NOT NULL, number INTEGER NULL, stream_url TEXT NOT NULL, '
      'stream_url_resolved TEXT NULL, user_agent TEXT NULL, referrer TEXT NULL, '
      'catchup TEXT NULL, catchup_source TEXT NULL, catchup_days INTEGER NULL)',
  'CREATE TABLE favorites (source_id INTEGER NOT NULL REFERENCES sources (id) '
      'ON DELETE CASCADE, channel_key TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, PRIMARY KEY (source_id, channel_key))',
  "INSERT INTO sources (name, kind, location, active_generation, is_active) "
      "VALUES ('lista', 'url', 'http://x/a.m3u', 1, 1)",
  'INSERT INTO favorites (source_id, channel_key, created_at) '
      "VALUES (1, 'globo|globo', 0)",
];

const List<String> _v6Extra = <String>[
  'CREATE TABLE programmes (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'source_id INTEGER NOT NULL, generation INTEGER NOT NULL, '
      'channel_id TEXT NOT NULL, start_utc INTEGER NOT NULL, '
      'stop_utc INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT NULL, '
      'description TEXT NULL, category TEXT NULL, age_rating INTEGER NULL)',
  'CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'name TEXT NOT NULL, color_index INTEGER NOT NULL DEFAULT 0, '
      'is_kids INTEGER NOT NULL DEFAULT 0, max_age INTEGER NULL, '
      'pin_hash TEXT NULL, pin_salt TEXT NULL, '
      'position INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE profile_blocked_groups (profile_id INTEGER NOT NULL, '
      'kind TEXT NOT NULL, group_name TEXT NOT NULL, '
      'PRIMARY KEY (profile_id, kind, group_name))',
  "INSERT INTO profiles (id, name) VALUES (3, 'Ana'), (5, 'Beto')",
];

const String _v2Programmes =
    'CREATE TABLE programmes (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'source_id INTEGER NOT NULL, generation INTEGER NOT NULL, '
    'channel_id TEXT NOT NULL, start_utc INTEGER NOT NULL, '
    'stop_utc INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT NULL, '
    'description TEXT NULL, category TEXT NULL)';

const String _v4Positions =
    'CREATE TABLE playback_positions (source_id INTEGER NOT NULL, '
    'item_key TEXT NOT NULL, position_ms INTEGER NOT NULL, '
    'duration_ms INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
    'PRIMARY KEY (source_id, item_key))';

const List<String> _v7Extra = <String>[
  'CREATE TABLE watch_history (profile_id INTEGER NOT NULL, '
      'source_id INTEGER NOT NULL, kind TEXT NOT NULL, '
      'item_key TEXT NOT NULL, title TEXT NOT NULL, image TEXT NULL, '
      'watched_at INTEGER NOT NULL, '
      'PRIMARY KEY (profile_id, source_id, kind, item_key))',
  _v4Positions,
  'INSERT INTO playback_positions VALUES '
      "(1, 'movie|7', 600000, 5400000, 0)",
];

Future<List<int>> _positionProfiles(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT profile_id FROM playback_positions',
        variables: <Variable>[],
      )
      .get();
  return <int>[for (final r in rows) r.read<int>('profile_id')];
}

Future<List<int>> _favoriteProfiles(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT profile_id FROM favorites', variables: <Variable>[])
      .get();
  return <int>[for (final r in rows) r.read<int>('profile_id')];
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db
      .customSelect('PRAGMA table_info($table)', variables: <Variable>[])
      .get();
  return <String>[for (final r in rows) r.read<String>('name')];
}

void main() {
  test('migra de v1 até a versão atual sem coluna duplicada', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1) {
            raw.execute(sql);
          }
          raw.userVersion = 1;
        },
      ),
    );
    addTearDown(db.close);

    final source = await db.sourceDao.watchActive().first;
    expect(source?.name, 'lista');
    expect(await _columns(db, 'programmes'), contains('age_rating'));
    expect(await _columns(db, 'sources'), contains('server_timezone'));
    expect(await _columns(db, 'playback_positions'), contains('profile_id'));
    expect(await db.profileDao.all(), isEmpty);
    expect(await _favoriteProfiles(db), <int>[0]);

    final profile = await db.profileDao.ensureDefault('Principal');
    expect(await _favoriteProfiles(db), <int>[profile.id]);
  });

  test('migra de v6 dando os favoritos ao primeiro perfil', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1) {
            raw.execute(sql);
          }
          for (final sql in _v6Extra) {
            raw.execute(sql);
          }
          raw.execute(_v4Positions);
          raw.userVersion = 6;
        },
      ),
    );
    addTearDown(db.close);

    expect(await _favoriteProfiles(db), <int>[3]);
    expect(await _columns(db, 'watch_history'), contains('item_key'));
  });

  test('migra de v7 dando as posições ao primeiro perfil', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1.take(2)) {
            raw.execute(sql);
          }
          raw.execute(
            'CREATE TABLE favorites (profile_id INTEGER NOT NULL DEFAULT 0, '
            'source_id INTEGER NOT NULL, channel_key TEXT NOT NULL, '
            'created_at INTEGER NOT NULL, '
            'PRIMARY KEY (profile_id, source_id, channel_key))',
          );
          for (final sql in _v6Extra) {
            raw.execute(sql);
          }
          for (final sql in _v7Extra) {
            raw.execute(sql);
          }
          raw.execute(_v1[3]);
          raw.userVersion = 7;
        },
      ),
    );
    addTearDown(db.close);

    expect(await _positionProfiles(db), <int>[3]);
    expect(
      await db.positionDao.resumePoint(3, 1, 'movie|7'),
      const Duration(minutes: 10),
    );
    expect(await db.positionDao.resumePoint(5, 1, 'movie|7'), isNull);
  });

  test(
    'posição sem perfil vai para o perfil padrão quando ele nasce',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            for (final sql in _v1) {
              raw.execute(sql);
            }
            raw.execute(_v2Programmes);
            raw.execute(_v4Positions);
            raw.execute(
              'INSERT INTO playback_positions VALUES '
              "(1, 'movie|7', 600000, 5400000, 0)",
            );
            raw.userVersion = 4;
          },
        ),
      );
      addTearDown(db.close);

      expect(await _positionProfiles(db), <int>[0]);
      final profile = await db.profileDao.ensureDefault('Principal');
      expect(await _positionProfiles(db), <int>[profile.id]);
    },
  );

  test('migra de v5 adicionando age_rating à tabela que já existia', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1.take(3)) {
            raw.execute(sql);
          }
          raw.execute(_v2Programmes);
          raw.execute(_v4Positions);
          raw.userVersion = 5;
        },
      ),
    );
    addTearDown(db.close);

    expect(await db.profileDao.all(), isEmpty);
    expect(await _columns(db, 'programmes'), contains('age_rating'));
  });
}
