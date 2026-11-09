import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';

part 'history_dao.g.dart';

enum HistoryKind { live, movie, series }

@DriftAccessor(tables: [WatchHistory])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.attachedDatabase);

  /// Itens guardados por perfil e tipo; os mais antigos saem.
  static const int keepPerKind = 40;

  Future<void> record({
    required int profileId,
    required int sourceId,
    required HistoryKind kind,
    required String itemKey,
    required String title,
    String? image,
    DateTime? at,
  }) {
    return transaction(() async {
      await into(watchHistory).insertOnConflictUpdate(
        WatchHistoryCompanion.insert(
          profileId: profileId,
          sourceId: sourceId,
          kind: kind.name,
          itemKey: itemKey,
          title: title,
          image: Value(image),
          watchedAt: at ?? DateTime.now(),
        ),
      );
      final keep = await _recentQuery(
        profileId,
        sourceId,
        kind,
        keepPerKind,
      ).get();
      if (keep.length < keepPerKind) return;
      final oldest = keep.last.watchedAt;
      await (delete(watchHistory)..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.sourceId.equals(sourceId) &
                t.kind.equals(kind.name) &
                t.watchedAt.isSmallerThanValue(oldest),
          ))
          .go();
    });
  }

  Stream<List<WatchHistoryRow>> watchRecent({
    required int profileId,
    required int sourceId,
    required HistoryKind kind,
    int limit = keepPerKind,
  }) => _recentQuery(profileId, sourceId, kind, limit).watch();

  Future<void> clear(int profileId) =>
      (delete(watchHistory)..where((t) => t.profileId.equals(profileId))).go();

  Future<void> remove({
    required int profileId,
    required int sourceId,
    required HistoryKind kind,
    required String itemKey,
  }) =>
      (delete(watchHistory)..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.sourceId.equals(sourceId) &
                t.kind.equals(kind.name) &
                t.itemKey.equals(itemKey),
          ))
          .go();

  SimpleSelectStatement<$WatchHistoryTable, WatchHistoryRow> _recentQuery(
    int profileId,
    int sourceId,
    HistoryKind kind,
    int limit,
  ) => select(watchHistory)
    ..where(
      (t) =>
          t.profileId.equals(profileId) &
          t.sourceId.equals(sourceId) &
          t.kind.equals(kind.name),
    )
    ..orderBy([(t) => OrderingTerm.desc(t.watchedAt)])
    ..limit(limit);
}
