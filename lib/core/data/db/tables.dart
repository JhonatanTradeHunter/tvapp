import 'package:drift/drift.dart';
import 'package:tvapp/core/models/playlist_source.dart';

@DataClassName('SourceRow')
class Sources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<SourceKind>()();
  TextColumn get location => text()();
  TextColumn get xtreamHost => text().nullable()();
  IntColumn get xtreamPort => integer().nullable()();
  TextColumn get xtreamUser => text().nullable()();
  TextColumn get xtreamPass => text().nullable()();
  IntColumn get activeGeneration => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastRefresh => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  TextColumn get epgUrl => text().nullable()();
  IntColumn get epgGeneration => integer().withDefault(const Constant(0))();
  DateTimeColumn get epgRefresh => dateTime().nullable()();
}

@DataClassName('ChannelRow')
@TableIndex(
  name: 'idx_channels_listing',
  columns: {#sourceId, #generation, #groupTitle, #position},
)
@TableIndex(name: 'idx_channels_key', columns: {#sourceId, #channelKey})
class Channels extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  IntColumn get position => integer()();
  TextColumn get channelKey => text()();
  TextColumn get name => text()();
  TextColumn get nameFolded => text()();
  TextColumn get tvgId => text().nullable()();
  TextColumn get tvgName => text().nullable()();
  TextColumn get logo => text().nullable()();
  TextColumn get groupTitle => text()();
  IntColumn get number => integer().nullable()();
  TextColumn get streamUrl => text()();
  TextColumn get streamUrlResolved => text().nullable()();
  TextColumn get userAgent => text().nullable()();
  TextColumn get referrer => text().nullable()();
  TextColumn get catchup => text().nullable()();
  TextColumn get catchupSource => text().nullable()();
  IntColumn get catchupDays => integer().nullable()();
}

@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get channelKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId, channelKey};
}

/// Canais declarados no XMLTV. `xmltvId` em minúsculas, para casar com
/// `tvg-id`; `nameNormalized` serve só ao fallback por nome.
@DataClassName('EpgChannelRow')
class EpgChannels extends Table {
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  TextColumn get xmltvId => text()();
  TextColumn get displayName => text()();
  TextColumn get nameNormalized => text()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {sourceId, generation, xmltvId};
}

/// Horários sempre em UTC.
@DataClassName('ProgrammeRow')
@TableIndex(
  name: 'idx_programmes_lookup',
  columns: {#sourceId, #generation, #channelId, #startUtc},
)
class Programmes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  TextColumn get channelId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get stopUtc => dateTime()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().nullable()();
}
