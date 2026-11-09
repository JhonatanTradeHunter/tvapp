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

  /// Fuso IANA declarado pelo painel Xtream (`server_info.timezone`).
  /// O timeshift recebe o horário de início nesse fuso.
  TextColumn get serverTimezone => text().nullable()();
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

/// Canais favoritos de cada perfil. `profileId` 0 marca favoritos vindos de
/// antes dos perfis, adotados pelo primeiro perfil criado.
@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get profileId => integer().withDefault(const Constant(0))();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get channelKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {profileId, sourceId, channelKey};
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
  IntColumn get ageRating => integer().nullable()();
}

/// Filmes do catálogo (hoje via Xtream). Mesma geração dos canais da fonte,
/// então trocam juntos no fim de cada importação.
@DataClassName('VodItemRow')
@TableIndex(
  name: 'idx_vod_listing',
  columns: {#sourceId, #generation, #categoryName, #position},
)
class VodItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  IntColumn get position => integer()();
  IntColumn get streamId => integer()();
  TextColumn get name => text()();
  TextColumn get nameFolded => text()();
  TextColumn get icon => text().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get categoryName => text()();
  TextColumn get extension => text().nullable()();
  DateTimeColumn get added => dateTime().nullable()();
}

/// Séries do catálogo. Temporadas e episódios vêm sob demanda da API.
@DataClassName('SeriesItemRow')
@TableIndex(
  name: 'idx_series_listing',
  columns: {#sourceId, #generation, #categoryName, #position},
)
class SeriesItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  IntColumn get generation => integer()();
  IntColumn get position => integer()();
  IntColumn get seriesId => integer()();
  TextColumn get name => text()();
  TextColumn get nameFolded => text()();
  TextColumn get cover => text().nullable()();
  TextColumn get plot => text().nullable()();
  TextColumn get genre => text().nullable()();
  TextColumn get releaseDate => text().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get categoryName => text()();
  DateTimeColumn get lastModified => dateTime().nullable()();
}

/// Onde cada perfil parou em filmes e episódios. `itemKey` é `movie|id` ou
/// `episode|id`. `profileId` 0 marca posições de antes da separação por
/// perfil, adotadas pelo primeiro perfil criado.
@DataClassName('PlaybackPositionRow')
class PlaybackPositions extends Table {
  IntColumn get profileId => integer().withDefault(const Constant(0))();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemKey => text()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {profileId, sourceId, itemKey};
}

/// Perfis de quem usa o app. PIN de 4 dígitos guardado como hash com sal.
/// `maxAge` só vale para perfil infantil; null = sem limite de idade.
@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  BoolColumn get isKids => boolean().withDefault(const Constant(false))();
  IntColumn get maxAge => integer().nullable()();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinSalt => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Grupos escondidos para um perfil. `kind`: live, vod ou series.
@DataClassName('ProfileBlockedGroupRow')
class ProfileBlockedGroups extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get groupName => text()();

  @override
  Set<Column> get primaryKey => {profileId, kind, groupName};
}

/// O que cada perfil abriu por último. `kind`: live, movie ou series;
/// `itemKey` é a chave do canal, `movie|id` ou `series|id`.
@DataClassName('WatchHistoryRow')
@TableIndex(name: 'idx_history_recent', columns: {#profileId, #watchedAt})
class WatchHistory extends Table {
  IntColumn get profileId => integer()();
  IntColumn get sourceId =>
      integer().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get itemKey => text()();
  TextColumn get title => text()();
  TextColumn get image => text().nullable()();
  DateTimeColumn get watchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {profileId, sourceId, kind, itemKey};
}
