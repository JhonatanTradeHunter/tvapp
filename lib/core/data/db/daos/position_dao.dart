import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';

part 'position_dao.g.dart';

@DriftAccessor(tables: [PlaybackPositions])
class PositionDao extends DatabaseAccessor<AppDatabase>
    with _$PositionDaoMixin {
  PositionDao(super.attachedDatabase);

  /// Abaixo disso não vale oferecer "continuar".
  static const Duration minResume = Duration(seconds: 30);

  /// Acima de 95% da duração conta como assistido e a posição é apagada.
  static bool isFinished(Duration position, Duration duration) =>
      duration > Duration.zero &&
      position.inMilliseconds >= duration.inMilliseconds * 0.95;

  static bool worthKeeping(Duration position, Duration duration) =>
      position >= minResume && !isFinished(position, duration);

  Future<void> save(
    int profileId,
    int sourceId,
    String key,
    Duration position,
    Duration duration,
  ) async {
    if (!worthKeeping(position, duration)) {
      await clear(profileId, sourceId, key);
      return;
    }
    await into(playbackPositions).insertOnConflictUpdate(
      PlaybackPositionsCompanion.insert(
        profileId: Value(profileId),
        sourceId: sourceId,
        itemKey: key,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<Duration?> resumePoint(int profileId, int sourceId, String key) async {
    final row = await _query(profileId, sourceId, key).getSingleOrNull();
    return row == null ? null : Duration(milliseconds: row.positionMs);
  }

  Stream<Duration?> watchResumePoint(int profileId, int sourceId, String key) =>
      _query(profileId, sourceId, key).watchSingleOrNull().map(
        (row) => row == null ? null : Duration(milliseconds: row.positionMs),
      );

  Future<void> clear(int profileId, int sourceId, String key) =>
      (delete(playbackPositions)..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.sourceId.equals(sourceId) &
                t.itemKey.equals(key),
          ))
          .go();

  SimpleSelectStatement<$PlaybackPositionsTable, PlaybackPositionRow> _query(
    int profileId,
    int sourceId,
    String key,
  ) => select(playbackPositions)
    ..where(
      (t) =>
          t.profileId.equals(profileId) &
          t.sourceId.equals(sourceId) &
          t.itemKey.equals(key),
    );
}
