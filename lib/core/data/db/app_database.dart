import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/connection/connection.dart';
import 'package:tvapp/core/data/db/daos/channel_dao.dart';
import 'package:tvapp/core/data/db/daos/epg_dao.dart';
import 'package:tvapp/core/data/db/daos/history_dao.dart';
import 'package:tvapp/core/data/db/daos/position_dao.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/db/daos/source_dao.dart';
import 'package:tvapp/core/data/db/daos/vod_dao.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/models/playlist_source.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Sources,
    Channels,
    Favorites,
    EpgChannels,
    Programmes,
    VodItems,
    SeriesItems,
    PlaybackPositions,
    Profiles,
    ProfileBlockedGroups,
    WatchHistory,
  ],
  daos: [
    ChannelDao,
    SourceDao,
    EpgDao,
    VodDao,
    PositionDao,
    ProfileDao,
    HistoryDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(sources, sources.epgUrl);
        await m.addColumn(sources, sources.epgGeneration);
        await m.addColumn(sources, sources.epgRefresh);
        await m.createTable(epgChannels);
        await m.createTable(programmes);
        await m.createIndex(idxProgrammesLookup);
      }
      if (from < 3) {
        await m.createTable(vodItems);
        await m.createTable(seriesItems);
        await m.createIndex(idxVodListing);
        await m.createIndex(idxSeriesListing);
      }
      if (from < 4) {
        await m.createTable(playbackPositions);
      }
      if (from < 5) {
        await m.addColumn(sources, sources.serverTimezone);
      }
      if (from < 6) {
        // createTable usa o formato atual da tabela. Se programmes nasceu no
        // passo de v2 desta mesma migração, já veio com age_rating.
        if (from >= 2) await m.addColumn(programmes, programmes.ageRating);
        await m.createTable(profiles);
        await m.createTable(profileBlockedGroups);
      }
      if (from < 7) {
        // Favoritos passam a ser por perfil: ficam com o primeiro perfil, ou
        // com 0 até o perfil padrão ser criado.
        await m.alterTable(
          TableMigration(
            favorites,
            newColumns: [favorites.profileId],
            columnTransformer: {
              favorites.profileId: const CustomExpression<int>(
                'COALESCE((SELECT MIN(id) FROM profiles), 0)',
              ),
            },
          ),
        );
        await m.createTable(watchHistory);
        await m.createIndex(idxHistoryRecent);
      }
      if (from < 8) {
        // Posições passam a ser por perfil, com a mesma regra dos favoritos.
        // Se playback_positions nasceu no passo de v4 desta migração, já veio
        // com profile_id e não há o que copiar.
        if (from >= 4) {
          await m.alterTable(
            TableMigration(
              playbackPositions,
              newColumns: [playbackPositions.profileId],
              columnTransformer: {
                playbackPositions.profileId: const CustomExpression<int>(
                  'COALESCE((SELECT MIN(id) FROM profiles), 0)',
                ),
              },
            ),
          );
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
