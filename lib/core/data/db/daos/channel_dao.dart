import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/data/m3u/m3u_entry.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/channel_group.dart';

part 'channel_dao.g.dart';

@DriftAccessor(tables: [Channels, Favorites])
class ChannelDao extends DatabaseAccessor<AppDatabase> with _$ChannelDaoMixin {
  ChannelDao(super.attachedDatabase);

  /// Um lote vira um `batch`, que o Drift executa numa única transação.
  Future<void> insertEntries(
    int sourceId,
    int generation,
    int startPosition,
    List<KeyedEntry> entries,
  ) {
    return batch((b) {
      b.insertAll(channels, <ChannelsCompanion>[
        for (var i = 0; i < entries.length; i++)
          _companion(sourceId, generation, startPosition + i, entries[i]),
      ]);
    });
  }

  ChannelsCompanion _companion(
    int sourceId,
    int generation,
    int position,
    KeyedEntry keyed,
  ) {
    final e = keyed.entry;
    return ChannelsCompanion.insert(
      sourceId: sourceId,
      generation: generation,
      position: position,
      channelKey: keyed.key,
      name: e.name,
      nameFolded: keyed.foldedName,
      groupTitle: e.group ?? '',
      streamUrl: e.url,
      tvgId: Value(e.tvgId),
      tvgName: Value(e.tvgName),
      logo: Value(e.logo),
      number: Value(e.tvgChno),
      userAgent: Value(e.userAgent),
      referrer: Value(e.referrer),
      catchup: Value(e.catchup),
      catchupSource: Value(e.catchupSource),
      catchupDays: Value(e.catchupDays),
    );
  }

  Future<void> deleteGeneration(int sourceId, int generation) =>
      (delete(channels)..where(
            (c) =>
                c.sourceId.equals(sourceId) & c.generation.equals(generation),
          ))
          .go();

  Future<void> deleteOtherGenerations(int sourceId, int generation) =>
      (delete(channels)..where(
            (c) =>
                c.sourceId.equals(sourceId) &
                c.generation.equals(generation).not(),
          ))
          .go();

  Future<int> countChannels(int sourceId, int generation) async {
    final count = channels.id.count();
    final query = selectOnly(channels)
      ..addColumns([count])
      ..where(
        channels.sourceId.equals(sourceId) &
            channels.generation.equals(generation),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Stream<List<ChannelGroup>> watchGroups(int sourceId, int generation) {
    final count = channels.id.count();
    final firstPosition = channels.position.min();
    final query = selectOnly(channels)
      ..addColumns([channels.groupTitle, count, firstPosition])
      ..where(
        channels.sourceId.equals(sourceId) &
            channels.generation.equals(generation),
      )
      ..groupBy([channels.groupTitle])
      ..orderBy([OrderingTerm(expression: firstPosition)]);
    return query.watch().map(
      (rows) => <ChannelGroup>[
        for (final row in rows)
          ChannelGroup(
            name: row.read(channels.groupTitle) ?? '',
            count: row.read(count) ?? 0,
          ),
      ],
    );
  }

  Stream<List<Channel>> watchChannels({
    required int sourceId,
    required int generation,
    required GroupFilter filter,
    required LiveSort sort,
  }) {
    final query = select(channels).join([
      leftOuterJoin(
        favorites,
        favorites.sourceId.equalsExp(channels.sourceId) &
            favorites.channelKey.equalsExp(channels.channelKey),
      ),
    ]);

    Expression<bool> where =
        channels.sourceId.equals(sourceId) &
        channels.generation.equals(generation);
    final group = filter.name;
    if (group != null) where = where & channels.groupTitle.equals(group);
    if (filter.favoritesOnly) where = where & favorites.channelKey.isNotNull();
    query.where(where);
    query.orderBy(_ordering(sort));

    return query.watch().map(
      (rows) => <Channel>[
        for (final row in rows)
          _toChannel(
            row.readTable(channels),
            row.readTableOrNull(favorites) != null,
          ),
      ],
    );
  }

  List<OrderingTerm> _ordering(LiveSort sort) {
    switch (sort) {
      case LiveSort.number:
        return [
          OrderingTerm.asc(channels.number.isNull()),
          OrderingTerm.asc(channels.number),
          OrderingTerm.asc(channels.position),
        ];
      case LiveSort.alpha:
        return [
          OrderingTerm.asc(channels.nameFolded),
          OrderingTerm.asc(channels.position),
        ];
      case LiveSort.favorites:
        return [
          OrderingTerm.asc(favorites.channelKey.isNull()),
          OrderingTerm.asc(channels.position),
        ];
    }
  }

  Future<bool> toggleFavorite(int sourceId, String key) async {
    final existing =
        await (select(favorites)..where(
              (f) => f.sourceId.equals(sourceId) & f.channelKey.equals(key),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (delete(favorites)..where(
            (f) => f.sourceId.equals(sourceId) & f.channelKey.equals(key),
          ))
          .go();
      return false;
    }
    await into(
      favorites,
    ).insert(FavoritesCompanion.insert(sourceId: sourceId, channelKey: key));
    return true;
  }

  Channel _toChannel(ChannelRow r, bool favorite) {
    return Channel(
      id: r.id,
      sourceId: r.sourceId,
      channelKey: r.channelKey,
      position: r.position,
      name: r.name,
      group: r.groupTitle,
      streamUrl: r.streamUrl,
      tvgId: r.tvgId,
      logo: r.logo,
      number: r.number,
      streamUrlResolved: r.streamUrlResolved,
      userAgent: r.userAgent,
      referrer: r.referrer,
      catchup: r.catchup,
      catchupSource: r.catchupSource,
      catchupDays: r.catchupDays,
      isFavorite: favorite,
    );
  }
}
