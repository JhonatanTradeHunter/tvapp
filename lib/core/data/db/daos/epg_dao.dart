import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/data/epg/xmltv_parser.dart';

part 'epg_dao.g.dart';

@DriftAccessor(tables: [EpgChannels, Programmes])
class EpgDao extends DatabaseAccessor<AppDatabase> with _$EpgDaoMixin {
  EpgDao(super.attachedDatabase);

  /// XMLTV repete `<channel>` com o mesmo id com frequência; o primeiro vence.
  Future<void> insertChannels(
    int sourceId,
    int generation,
    List<XmltvChannel> items,
  ) {
    return batch((b) {
      b.insertAll(epgChannels, <EpgChannelsCompanion>[
        for (final c in items)
          EpgChannelsCompanion.insert(
            sourceId: sourceId,
            generation: generation,
            xmltvId: c.id,
            displayName: c.displayName,
            nameNormalized: c.normalizedName,
            icon: Value(c.icon),
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  Future<void> insertProgrammes(
    int sourceId,
    int generation,
    List<XmltvProgramme> items,
  ) {
    return batch((b) {
      b.insertAll(programmes, <ProgrammesCompanion>[
        for (final p in items)
          ProgrammesCompanion.insert(
            sourceId: sourceId,
            generation: generation,
            channelId: p.channelId,
            startUtc: p.start,
            stopUtc: p.stop!,
            title: p.title,
            subtitle: Value(p.subtitle),
            description: Value(p.description),
            category: Value(p.category),
          ),
      ]);
    });
  }

  Future<void> deleteGeneration(int sourceId, int generation) async {
    await (delete(epgChannels)..where(
          (t) => t.sourceId.equals(sourceId) & t.generation.equals(generation),
        ))
        .go();
    await (delete(programmes)..where(
          (t) => t.sourceId.equals(sourceId) & t.generation.equals(generation),
        ))
        .go();
  }

  Future<void> deleteOtherGenerations(int sourceId, int generation) async {
    await (delete(epgChannels)..where(
          (t) =>
              t.sourceId.equals(sourceId) &
              t.generation.equals(generation).not(),
        ))
        .go();
    await (delete(programmes)..where(
          (t) =>
              t.sourceId.equals(sourceId) &
              t.generation.equals(generation).not(),
        ))
        .go();
  }

  /// Programas que cruzam o intervalo [from, to), por canal e início.
  /// `channelIds` já em minúsculas; mantenha a lista curta (canais visíveis).
  Future<List<ProgrammeRow>> programmesInRange({
    required int sourceId,
    required int generation,
    required List<String> channelIds,
    required DateTime from,
    required DateTime to,
  }) {
    if (channelIds.isEmpty) return Future.value(const <ProgrammeRow>[]);
    return (select(programmes)
          ..where(
            (p) =>
                p.sourceId.equals(sourceId) &
                p.generation.equals(generation) &
                p.channelId.isIn(channelIds) &
                p.stopUtc.isBiggerThanValue(from.toUtc()) &
                p.startUtc.isSmallerThanValue(to.toUtc()),
          )
          ..orderBy([
            (p) => OrderingTerm.asc(p.channelId),
            (p) => OrderingTerm.asc(p.startUtc),
          ]))
        .get();
  }

  Future<List<EpgChannelRow>> channels(int sourceId, int generation) {
    return (select(epgChannels)..where(
          (t) => t.sourceId.equals(sourceId) & t.generation.equals(generation),
        ))
        .get();
  }

  Future<int> countProgrammes(int sourceId, int generation) async {
    final count = programmes.id.count();
    final query = selectOnly(programmes)
      ..addColumns([count])
      ..where(
        programmes.sourceId.equals(sourceId) &
            programmes.generation.equals(generation),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
