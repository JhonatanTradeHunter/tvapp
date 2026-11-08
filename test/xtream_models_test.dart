import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/xtream/json_read.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';

void main() {
  group('JsonRead', () {
    test('aceita número como string, string como número e false como nulo', () {
      expect(JsonRead.integer('42'), 42);
      expect(JsonRead.integer('4.6'), 5);
      expect(JsonRead.integer(7.0), 7);
      expect(JsonRead.string(12), '12');
      expect(JsonRead.string(false), isNull);
      expect(JsonRead.string('  '), isNull);
      expect(JsonRead.flag('1'), isTrue);
      expect(JsonRead.flag(0), isFalse);
      expect(JsonRead.epoch('0'), isNull);
      expect(
        JsonRead.epoch('1700000000'),
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
    });
  });

  test('conta: auth, status, validade e formato preferido', () {
    final account = XtreamAccount.fromJson(
      jsonDecode('''
      {"user_info": {"username": "u", "auth": 1, "status": "Active",
        "exp_date": "1893456000", "is_trial": "0", "max_connections": "2",
        "allowed_output_formats": ["ts"]},
       "server_info": {"timezone": "America/Sao_Paulo", "timestamp_now": 1762632000}}
    '''),
    );
    expect(account.isActive, isTrue);
    expect(account.maxConnections, 2);
    expect(account.expiresAt, DateTime.utc(2030));
    expect(account.preferredLiveExtension, 'ts');
    expect(account.serverTimezone, 'America/Sao_Paulo');

    final denied = XtreamAccount.fromJson(
      jsonDecode('{"user_info": {"auth": 0}}'),
    );
    expect(denied.authenticated, isFalse);
    expect(denied.isActive, isFalse);
  });

  test('live stream com ids em string e arquivo ligado', () {
    final s = XtreamLiveStream.fromJson(
      jsonDecode('''
      {"num": "3", "name": "Globo SP", "stream_type": "live", "stream_id": "1001",
       "stream_icon": "", "epg_channel_id": "globo.br", "category_id": 5,
       "tv_archive": "1", "tv_archive_duration": "3", "added": "1700000000"}
    '''),
    )!;
    expect(s.streamId, 1001);
    expect(s.num, 3);
    expect(s.icon, isNull);
    expect(s.categoryId, '5');
    expect(s.tvArchive, isTrue);
    expect(s.archiveDays, 3);
    expect(XtreamLiveStream.fromJson(jsonDecode('{"name": "sem id"}')), isNull);
  });

  test('VOD usa rating_5based ou converte rating de 0 a 10', () {
    final a = XtreamVodStream.fromJson(
      jsonDecode('{"stream_id": 1, "name": "A", "rating_5based": 4.2}'),
    )!;
    final b = XtreamVodStream.fromJson(
      jsonDecode(
        '{"stream_id": 2, "name": "B", "rating": "7", "container_extension": "mkv"}',
      ),
    )!;
    expect(a.rating, 4.2);
    expect(b.rating, 3.5);
    expect(b.containerExtension, 'mkv');
  });

  test('series info com episódios em mapa por temporada', () {
    final info = XtreamSeriesInfo.fromJson(
      jsonDecode('''
      {"seasons": [{"season_number": 1, "name": "Temporada 1", "episode_count": "2"}],
       "info": {"plot": "Sinopse", "genre": "Drama"},
       "episodes": {
         "2": [{"id": "30", "episode_num": 1, "title": "S2E1", "container_extension": "mp4"}],
         "1": [{"id": "11", "episode_num": "2", "title": "S1E2", "info": {"duration_secs": "2700"}},
               {"id": "10", "episode_num": 1, "title": "S1E1", "season": 1}]
       }}
    '''),
    );
    expect(info.plot, 'Sinopse');
    expect(info.episodes.map((e) => e.id), [10, 11, 30]);
    expect(info.episodes[1].durationSecs, 2700);
    expect(info.seasons.map((s) => s.number), [1, 2]);
    expect(info.episodesOf(2).single.title, 'S2E1');
  });

  test('series info com episódios em lista de listas', () {
    final info = XtreamSeriesInfo.fromJson(
      jsonDecode('''
      {"episodes": [[{"id": 5, "season": 1, "episode_num": 1, "title": "Piloto"}]]}
    '''),
    );
    expect(info.episodes.single.title, 'Piloto');
    expect(info.seasons.single.number, 1);
  });

  test('vod info lê movie_data e backdrop', () {
    final info = XtreamVodInfo.fromJson(
      jsonDecode('''
      {"info": {"plot": "P", "duration_secs": 5400, "backdrop_path": ["http://b/1.jpg"],
                "releasedate": "2024-01-01", "rating": "8"},
       "movie_data": {"stream_id": 9, "container_extension": "mkv"}}
    '''),
    );
    expect(info.durationSecs, 5400);
    expect(info.backdrop, 'http://b/1.jpg');
    expect(info.rating, 4);
    expect(info.containerExtension, 'mkv');
  });
}
