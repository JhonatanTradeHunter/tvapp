import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/history_dao.dart';
import 'package:tvapp/core/models/playlist_source.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int sourceId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceId = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            name: 'lista',
            kind: SourceKind.url,
            location: 'http://x/a.m3u',
          ),
        );
  });
  tearDown(() => db.close());

  Future<List<String>> keys(int profileId, HistoryKind kind) async => <String>[
    for (final r
        in await db.historyDao
            .watchRecent(profileId: profileId, sourceId: sourceId, kind: kind)
            .first)
      r.itemKey,
  ];

  test('mais recente primeiro e sem repetir o mesmo item', () async {
    final t0 = DateTime(2026, 11, 8, 20);
    for (final (key, minutes) in <(String, int)>[
      ('a', 0),
      ('b', 1),
      ('a', 2),
    ]) {
      await db.historyDao.record(
        profileId: 1,
        sourceId: sourceId,
        kind: HistoryKind.live,
        itemKey: key,
        title: key,
        at: t0.add(Duration(minutes: minutes)),
      );
    }
    expect(await keys(1, HistoryKind.live), <String>['a', 'b']);
    expect(await keys(2, HistoryKind.live), isEmpty);
    expect(await keys(1, HistoryKind.movie), isEmpty);
  });

  test('guarda no máximo keepPerKind itens por tipo', () async {
    final t0 = DateTime(2026, 11, 8, 20);
    const total = HistoryDao.keepPerKind + 5;
    for (var i = 0; i < total; i++) {
      await db.historyDao.record(
        profileId: 1,
        sourceId: sourceId,
        kind: HistoryKind.movie,
        itemKey: 'movie|$i',
        title: 'Filme $i',
        at: t0.add(Duration(minutes: i)),
      );
    }
    final kept = await keys(1, HistoryKind.movie);
    expect(kept, hasLength(HistoryDao.keepPerKind));
    expect(kept.first, 'movie|${total - 1}');
    expect(kept, isNot(contains('movie|0')));
  });

  test('apagar o perfil leva junto o histórico e os favoritos', () async {
    final id = await db.profileDao.createProfile(
      name: 'Ana',
      colorIndex: 0,
      isKids: false,
    );
    await db.historyDao.record(
      profileId: id,
      sourceId: sourceId,
      kind: HistoryKind.live,
      itemKey: 'k',
      title: 'Canal',
    );
    await db.channelDao.toggleFavorite(id, sourceId, 'k');
    await db.profileDao.deleteProfile(id);
    expect(await keys(id, HistoryKind.live), isEmpty);
    expect(await db.select(db.favorites).get(), isEmpty);
  });
}
