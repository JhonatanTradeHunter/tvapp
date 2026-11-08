import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tvapp/core/data/db/daos/channel_dao.dart';
import 'package:tvapp/core/data/db/daos/epg_dao.dart';
import 'package:tvapp/core/data/db/daos/source_dao.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/models/playlist_source.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Sources, Channels, Favorites, EpgChannels, Programmes],
  daos: [ChannelDao, SourceDao, EpgDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

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
        // VERIFICAR: nome do getter que o drift gera para o @TableIndex
        // 'idx_programmes_lookup' (camelCase do nome do índice).
        await m.createIndex(idxProgrammesLookup);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'tvapp.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
