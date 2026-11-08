import 'package:tvapp/core/data/xtream/json_read.dart';

class XtreamAccount {
  const XtreamAccount({
    required this.authenticated,
    this.username,
    this.status,
    this.expiresAt,
    this.isTrial = false,
    this.maxConnections,
    this.activeConnections,
    this.allowedFormats = const <String>[],
    this.serverTimezone,
    this.serverNow,
  });

  factory XtreamAccount.fromJson(Object? json) {
    final root = JsonRead.map(json);
    final user = JsonRead.map(root['user_info']);
    final server = JsonRead.map(root['server_info']);
    return XtreamAccount(
      authenticated: JsonRead.flag(user['auth']),
      username: JsonRead.string(user['username']),
      status: JsonRead.string(user['status']),
      expiresAt: JsonRead.epoch(user['exp_date']),
      isTrial: JsonRead.flag(user['is_trial']),
      maxConnections: JsonRead.integer(user['max_connections']),
      activeConnections: JsonRead.integer(user['active_cons']),
      allowedFormats: JsonRead.strings(user['allowed_output_formats']),
      serverTimezone: JsonRead.string(server['timezone']),
      serverNow: JsonRead.epoch(server['timestamp_now']),
    );
  }

  final bool authenticated;
  final String? username;
  final String? status;
  final DateTime? expiresAt;
  final bool isTrial;
  final int? maxConnections;
  final int? activeConnections;
  final List<String> allowedFormats;
  final String? serverTimezone;
  final DateTime? serverNow;

  bool get isActive =>
      authenticated && (status == null || status!.toLowerCase() == 'active');

  /// HLS quando o painel permite; senão TS (que o mpv abre).
  String get preferredLiveExtension {
    if (allowedFormats.isEmpty || allowedFormats.contains('m3u8')) {
      return 'm3u8';
    }
    return allowedFormats.contains('ts') ? 'ts' : allowedFormats.first;
  }
}

class XtreamCategory {
  const XtreamCategory({required this.id, required this.name, this.parentId});

  static XtreamCategory? fromJson(Object? json) {
    final m = JsonRead.map(json);
    final id = JsonRead.string(m['category_id']);
    if (id == null) return null;
    return XtreamCategory(
      id: id,
      name: JsonRead.string(m['category_name']) ?? id,
      parentId: JsonRead.string(m['parent_id']),
    );
  }

  final String id;
  final String name;
  final String? parentId;
}

class XtreamLiveStream {
  const XtreamLiveStream({
    required this.streamId,
    required this.name,
    this.num,
    this.icon,
    this.epgChannelId,
    this.categoryId,
    this.tvArchive = false,
    this.archiveDays,
    this.added,
  });

  static XtreamLiveStream? fromJson(Object? json) {
    final m = JsonRead.map(json);
    final id = JsonRead.integer(m['stream_id']);
    if (id == null) return null;
    return XtreamLiveStream(
      streamId: id,
      name: JsonRead.string(m['name']) ?? '$id',
      num: JsonRead.integer(m['num']),
      icon: JsonRead.string(m['stream_icon']),
      epgChannelId: JsonRead.string(m['epg_channel_id']),
      categoryId: JsonRead.string(m['category_id']),
      tvArchive: JsonRead.flag(m['tv_archive']),
      archiveDays: JsonRead.integer(m['tv_archive_duration']),
      added: JsonRead.epoch(m['added']),
    );
  }

  final int streamId;
  final String name;
  final int? num;
  final String? icon;
  final String? epgChannelId;
  final String? categoryId;
  final bool tvArchive;
  final int? archiveDays;
  final DateTime? added;
}

class XtreamVodStream {
  const XtreamVodStream({
    required this.streamId,
    required this.name,
    this.num,
    this.icon,
    this.rating,
    this.categoryId,
    this.containerExtension,
    this.added,
  });

  static XtreamVodStream? fromJson(Object? json) {
    final m = JsonRead.map(json);
    final id = JsonRead.integer(m['stream_id']);
    if (id == null) return null;
    return XtreamVodStream(
      streamId: id,
      name: JsonRead.string(m['name']) ?? '$id',
      num: JsonRead.integer(m['num']),
      icon: JsonRead.string(m['stream_icon']),
      rating:
          JsonRead.number(m['rating_5based']) ??
          _tenToFive(JsonRead.number(m['rating'])),
      categoryId: JsonRead.string(m['category_id']),
      containerExtension: JsonRead.string(m['container_extension']),
      added: JsonRead.epoch(m['added']),
    );
  }

  final int streamId;
  final String name;
  final int? num;
  final String? icon;

  /// Nota de 0 a 5.
  final double? rating;
  final String? categoryId;
  final String? containerExtension;
  final DateTime? added;
}

class XtreamSeries {
  const XtreamSeries({
    required this.seriesId,
    required this.name,
    this.num,
    this.cover,
    this.plot,
    this.genre,
    this.releaseDate,
    this.rating,
    this.categoryId,
    this.lastModified,
  });

  static XtreamSeries? fromJson(Object? json) {
    final m = JsonRead.map(json);
    final id = JsonRead.integer(m['series_id']);
    if (id == null) return null;
    return XtreamSeries(
      seriesId: id,
      name: JsonRead.string(m['name']) ?? '$id',
      num: JsonRead.integer(m['num']),
      cover: JsonRead.string(m['cover']),
      plot: JsonRead.string(m['plot']),
      genre: JsonRead.string(m['genre']),
      releaseDate:
          JsonRead.string(m['releaseDate']) ??
          JsonRead.string(m['release_date']),
      rating:
          JsonRead.number(m['rating_5based']) ??
          _tenToFive(JsonRead.number(m['rating'])),
      categoryId: JsonRead.string(m['category_id']),
      lastModified: JsonRead.epoch(m['last_modified']),
    );
  }

  final int seriesId;
  final String name;
  final int? num;
  final String? cover;
  final String? plot;
  final String? genre;
  final String? releaseDate;
  final double? rating;
  final String? categoryId;
  final DateTime? lastModified;
}

class XtreamSeason {
  const XtreamSeason({
    required this.number,
    this.name,
    this.cover,
    this.episodeCount,
  });

  static XtreamSeason? fromJson(Object? json) {
    final m = JsonRead.map(json);
    final number = JsonRead.integer(m['season_number']);
    if (number == null) return null;
    return XtreamSeason(
      number: number,
      name: JsonRead.string(m['name']),
      cover: JsonRead.string(m['cover']) ?? JsonRead.string(m['cover_big']),
      episodeCount: JsonRead.integer(m['episode_count']),
    );
  }

  final int number;
  final String? name;
  final String? cover;
  final int? episodeCount;
}

class XtreamEpisode {
  const XtreamEpisode({
    required this.id,
    required this.season,
    required this.episodeNum,
    required this.title,
    this.containerExtension,
    this.durationSecs,
    this.plot,
    this.image,
  });

  static XtreamEpisode? fromJson(Object? json, {int? fallbackSeason}) {
    final m = JsonRead.map(json);
    final id = JsonRead.integer(m['id']);
    if (id == null) return null;
    final info = JsonRead.map(m['info']);
    final number = JsonRead.integer(m['episode_num']) ?? 0;
    return XtreamEpisode(
      id: id,
      season: JsonRead.integer(m['season']) ?? fallbackSeason ?? 0,
      episodeNum: number,
      title: JsonRead.string(m['title']) ?? '$number',
      containerExtension: JsonRead.string(m['container_extension']),
      durationSecs: JsonRead.integer(info['duration_secs']),
      plot: JsonRead.string(info['plot']),
      image: JsonRead.string(info['movie_image']),
    );
  }

  final int id;
  final int season;
  final int episodeNum;
  final String title;
  final String? containerExtension;
  final int? durationSecs;
  final String? plot;
  final String? image;
}

class XtreamSeriesInfo {
  const XtreamSeriesInfo({
    required this.seasons,
    required this.episodes,
    this.plot,
    this.cover,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
  });

  /// `episodes` chega como mapa `{"1": [...], "2": [...]}` ou como lista de
  /// listas; nos dois casos a temporada da chave vale quando o item não a traz.
  factory XtreamSeriesInfo.fromJson(Object? json) {
    final root = JsonRead.map(json);
    final info = JsonRead.map(root['info']);
    final episodes = <XtreamEpisode>[];
    final rawEpisodes = root['episodes'];
    if (rawEpisodes is Map) {
      for (final entry in rawEpisodes.entries) {
        final season = JsonRead.integer(entry.key);
        for (final item in JsonRead.list(entry.value)) {
          final e = XtreamEpisode.fromJson(item, fallbackSeason: season);
          if (e != null) episodes.add(e);
        }
      }
    } else {
      for (final group in JsonRead.list(rawEpisodes)) {
        final items = group is List ? group : <Object?>[group];
        for (final item in items) {
          final e = XtreamEpisode.fromJson(item);
          if (e != null) episodes.add(e);
        }
      }
    }
    episodes.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.episodeNum.compareTo(b.episodeNum);
    });

    final seasons = <XtreamSeason>[
      for (final s in JsonRead.list(root['seasons'])) ?XtreamSeason.fromJson(s),
    ];
    final known = {for (final s in seasons) s.number};
    for (final e in episodes) {
      if (known.add(e.season)) seasons.add(XtreamSeason(number: e.season));
    }
    seasons.sort((a, b) => a.number.compareTo(b.number));

    return XtreamSeriesInfo(
      seasons: seasons,
      episodes: episodes,
      plot: JsonRead.string(info['plot']),
      cover: JsonRead.string(info['cover']),
      genre: JsonRead.string(info['genre']),
      cast: JsonRead.string(info['cast']),
      director: JsonRead.string(info['director']),
      releaseDate:
          JsonRead.string(info['releaseDate']) ??
          JsonRead.string(info['release_date']),
    );
  }

  final List<XtreamSeason> seasons;
  final List<XtreamEpisode> episodes;
  final String? plot;
  final String? cover;
  final String? genre;
  final String? cast;
  final String? director;
  final String? releaseDate;

  List<XtreamEpisode> episodesOf(int season) =>
      episodes.where((e) => e.season == season).toList();
}

class XtreamVodInfo {
  const XtreamVodInfo({
    this.plot,
    this.durationSecs,
    this.cover,
    this.backdrop,
    this.releaseDate,
    this.genre,
    this.cast,
    this.director,
    this.rating,
    this.containerExtension,
  });

  factory XtreamVodInfo.fromJson(Object? json) {
    final root = JsonRead.map(json);
    final info = JsonRead.map(root['info']);
    final data = JsonRead.map(root['movie_data']);
    final backdrops = JsonRead.strings(info['backdrop_path']);
    return XtreamVodInfo(
      plot:
          JsonRead.string(info['plot']) ?? JsonRead.string(info['description']),
      durationSecs: JsonRead.integer(info['duration_secs']),
      cover:
          JsonRead.string(info['movie_image']) ??
          JsonRead.string(info['cover_big']),
      backdrop: backdrops.isEmpty ? null : backdrops.first,
      releaseDate:
          JsonRead.string(info['releasedate']) ??
          JsonRead.string(info['release_date']),
      genre: JsonRead.string(info['genre']),
      cast: JsonRead.string(info['cast']) ?? JsonRead.string(info['actors']),
      director: JsonRead.string(info['director']),
      rating:
          JsonRead.number(info['rating_5based']) ??
          _tenToFive(JsonRead.number(info['rating'])),
      containerExtension: JsonRead.string(data['container_extension']),
    );
  }

  final String? plot;
  final int? durationSecs;
  final String? cover;
  final String? backdrop;
  final String? releaseDate;
  final String? genre;
  final String? cast;
  final String? director;
  final double? rating;
  final String? containerExtension;
}

double? _tenToFive(double? rating) => rating == null ? null : rating / 2;
