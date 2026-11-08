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
];

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
    expect(await db.profileDao.all(), isEmpty);
  });

  test('migra de v5 adicionando age_rating à tabela que já existia', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in _v1.take(3)) {
            raw.execute(sql);
          }
          raw.execute(
            'CREATE TABLE programmes (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, source_id INTEGER NOT NULL, generation INTEGER NOT '
            'NULL, channel_id TEXT NOT NULL, start_utc INTEGER NOT NULL, '
            'stop_utc INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT '
            'NULL, description TEXT NULL, category TEXT NULL)',
          );
          raw.userVersion = 5;
        },
      ),
    );
    addTearDown(db.close);

    expect(await db.profileDao.all(), isEmpty);
    expect(await _columns(db, 'programmes'), contains('age_rating'));
  });
}
