import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/core/util/normalize.dart';

part 'vod_dao.g.dart';

@DriftAccessor(tables: [VodItems, SeriesItems])
class VodDao extends DatabaseAccessor<AppDatabase> with _$VodDaoMixin {
  VodDao(super.attachedDatabase);

  Future<void> insertVod(
    int sourceId,
    int generation,
    int startPosition,
    List<XtreamVodStream> items,
    Map<String, String> categoryNames,
  ) {
    return batch((b) {
      b.insertAll(vodItems, <VodItemsCompanion>[
        for (var i = 0; i < items.length; i++)
          VodItemsCompanion.insert(
            sourceId: sourceId,
            generation: generation,
            position: startPosition + i,
            streamId: items[i].streamId,
            name: items[i].name,
            nameFolded: foldName(items[i].name),
            icon: Value(items[i].icon),
            rating: Value(items[i].rating),
            categoryName: categoryNames[items[i].categoryId] ?? '',
            extension: Value(items[i].containerExtension),
            added: Value(items[i].added),
          ),
      ]);
    });
  }

  Future<void> insertSeries(
    int sourceId,
    int generation,
    int startPosition,
    List<XtreamSeries> items,
    Map<String, String> categoryNames,
  ) {
    return batch((b) {
      b.insertAll(seriesItems, <SeriesItemsCompanion>[
        for (var i = 0; i < items.length; i++)
          SeriesItemsCompanion.insert(
            sourceId: sourceId,
            generation: generation,
            position: startPosition + i,
            seriesId: items[i].seriesId,
            name: items[i].name,
            nameFolded: foldName(items[i].name),
            cover: Value(items[i].cover),
            plot: Value(items[i].plot),
            genre: Value(items[i].genre),
            releaseDate: Value(items[i].releaseDate),
            rating: Value(items[i].rating),
            categoryName: categoryNames[items[i].categoryId] ?? '',
            lastModified: Value(items[i].lastModified),
          ),
      ]);
    });
  }

  Future<void> deleteGeneration(int sourceId, int generation) async {
    await (delete(vodItems)..where(
          (t) => t.sourceId.equals(sourceId) & t.generation.equals(generation),
        ))
        .go();
    await (delete(seriesItems)..where(
          (t) => t.sourceId.equals(sourceId) & t.generation.equals(generation),
        ))
        .go();
  }

  Future<void> deleteOtherGenerations(int sourceId, int generation) async {
    await (delete(vodItems)..where(
          (t) =>
              t.sourceId.equals(sourceId) &
              t.generation.equals(generation).not(),
        ))
        .go();
    await (delete(seriesItems)..where(
          (t) =>
              t.sourceId.equals(sourceId) &
              t.generation.equals(generation).not(),
        ))
        .go();
  }

  Stream<List<ChannelGroup>> watchVodCategories(int sourceId, int generation) {
    final count = vodItems.id.count();
    final first = vodItems.position.min();
    final query = selectOnly(vodItems)
      ..addColumns([vodItems.categoryName, count, first])
      ..where(
        vodItems.sourceId.equals(sourceId) &
            vodItems.generation.equals(generation),
      )
      ..groupBy([vodItems.categoryName])
      ..orderBy([OrderingTerm(expression: first)]);
    return query.watch().map(
      (rows) => <ChannelGroup>[
        for (final row in rows)
          ChannelGroup(
            name: row.read(vodItems.categoryName) ?? '',
            count: row.read(count) ?? 0,
          ),
      ],
    );
  }

  Stream<List<ChannelGroup>> watchSeriesCategories(
    int sourceId,
    int generation,
  ) {
    final count = seriesItems.id.count();
    final first = seriesItems.position.min();
    final query = selectOnly(seriesItems)
      ..addColumns([seriesItems.categoryName, count, first])
      ..where(
        seriesItems.sourceId.equals(sourceId) &
            seriesItems.generation.equals(generation),
      )
      ..groupBy([seriesItems.categoryName])
      ..orderBy([OrderingTerm(expression: first)]);
    return query.watch().map(
      (rows) => <ChannelGroup>[
        for (final row in rows)
          ChannelGroup(
            name: row.read(seriesItems.categoryName) ?? '',
            count: row.read(count) ?? 0,
          ),
      ],
    );
  }

  /// [search] já dobrado com `foldName`; casa por trecho do nome.
  Stream<List<VodItemRow>> watchVod({
    required int sourceId,
    required int generation,
    String? category,
    String? search,
  }) {
    final query = select(vodItems)
      ..where((t) {
        Expression<bool> where =
            t.sourceId.equals(sourceId) & t.generation.equals(generation);
        if (category != null) where = where & t.categoryName.equals(category);
        if (search != null && search.isNotEmpty) {
          where = where & t.nameFolded.like('%${_escapeLike(search)}%');
        }
        return where;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    return query.watch();
  }

  Stream<List<SeriesItemRow>> watchSeries({
    required int sourceId,
    required int generation,
    String? category,
    String? search,
  }) {
    final query = select(seriesItems)
      ..where((t) {
        Expression<bool> where =
            t.sourceId.equals(sourceId) & t.generation.equals(generation);
        if (category != null) where = where & t.categoryName.equals(category);
        if (search != null && search.isNotEmpty) {
          where = where & t.nameFolded.like('%${_escapeLike(search)}%');
        }
        return where;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    return query.watch();
  }

  /// Filmes da geração atual com estes ids, na ordem pedida.
  Future<List<VodItemRow>> vodByStreamIds(
    int sourceId,
    int generation,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return const <VodItemRow>[];
    final rows =
        await (select(vodItems)..where(
              (t) =>
                  t.sourceId.equals(sourceId) &
                  t.generation.equals(generation) &
                  t.streamId.isIn(ids),
            ))
            .get();
    final byId = <int, VodItemRow>{for (final r in rows) r.streamId: r};
    return <VodItemRow>[for (final id in ids) ?byId[id]];
  }

  /// Séries da geração atual com estes ids, na ordem pedida.
  Future<List<SeriesItemRow>> seriesByIds(
    int sourceId,
    int generation,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return const <SeriesItemRow>[];
    final rows =
        await (select(seriesItems)..where(
              (t) =>
                  t.sourceId.equals(sourceId) &
                  t.generation.equals(generation) &
                  t.seriesId.isIn(ids),
            ))
            .get();
    final byId = <int, SeriesItemRow>{for (final r in rows) r.seriesId: r};
    return <SeriesItemRow>[for (final id in ids) ?byId[id]];
  }

  Future<int> countVod(int sourceId, int generation) async {
    final count = vodItems.id.count();
    final query = selectOnly(vodItems)
      ..addColumns([count])
      ..where(
        vodItems.sourceId.equals(sourceId) &
            vodItems.generation.equals(generation),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  static String _escapeLike(String value) =>
      value.replaceAll('%', '').replaceAll('_', ' ');
}
