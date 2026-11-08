import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';

part 'source_dao.g.dart';

@DriftAccessor(tables: [Sources])
class SourceDao extends DatabaseAccessor<AppDatabase> with _$SourceDaoMixin {
  SourceDao(super.attachedDatabase);

  Future<int> insertSource(SourcesCompanion row) => into(sources).insert(row);

  Future<void> updateSource(int id, SourcesCompanion row) =>
      (update(sources)..where((s) => s.id.equals(id))).write(row);

  Future<SourceRow?> byId(int id) =>
      (select(sources)..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<SourceRow?> watchActive() =>
      (select(sources)
            ..where((s) => s.isActive.equals(true))
            ..limit(1))
          .watchSingleOrNull();

  /// Sem transação própria: quem chama decide o escopo transacional.
  Future<void> setActive(int id) async {
    await update(sources).write(const SourcesCompanion(isActive: Value(false)));
    await (update(sources)..where((s) => s.id.equals(id))).write(
      const SourcesCompanion(isActive: Value(true)),
    );
  }

  Future<void> markRefreshed(int id, int generation, DateTime at) =>
      (update(sources)..where((s) => s.id.equals(id))).write(
        SourcesCompanion(
          activeGeneration: Value(generation),
          lastRefresh: Value(at),
        ),
      );

  Future<void> deleteSource(int id) =>
      (delete(sources)..where((s) => s.id.equals(id))).go();
}
