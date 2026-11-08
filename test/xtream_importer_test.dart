import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvapp/core/data/m3u/m3u_entry.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_importer.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/playlist_source.dart';

const XtreamCredentials _creds = XtreamCredentials(
  host: 'http://painel.example',
  port: 8080,
  username: 'u',
  password: 'p',
);

XtreamClient _client(Map<String?, http.Response Function()> routes) =>
    XtreamClient(
      _creds,
      clientFactory: () => MockClient((request) async {
        final action = request.url.queryParameters['action'];
        final route = routes[action];
        return route == null ? http.Response('', 404) : route();
      }),
    );

http.Response _json(String body) => http.Response(body, 200);

final Map<String?, http.Response Function()> _full = {
  null: () => _json(
    '{"user_info": {"auth": 1, "status": "Active", "allowed_output_formats": ["m3u8", "ts"]}}',
  ),
  'get_live_categories': () =>
      _json('[{"category_id": "1", "category_name": "Abertos"}]'),
  'get_live_streams': () => _json('''[
    {"num": 1, "name": "Globo", "stream_id": 10, "epg_channel_id": "globo.br",
     "category_id": "1", "tv_archive": 1, "tv_archive_duration": "3"},
    {"num": 2, "name": "Globo", "stream_id": 11, "epg_channel_id": "globo.br", "category_id": "1"},
    {"num": 3, "name": "Band", "stream_id": 12, "category_id": "9"}
  ]'''),
  'get_vod_categories': () =>
      _json('[{"category_id": "5", "category_name": "Filmes"}]'),
  'get_vod_streams': () => _json(
    '[{"stream_id": 100, "name": "Filme", "category_id": "5", "container_extension": "mkv"}]',
  ),
  'get_series_categories': () => _json('[]'),
  'get_series': () => _json('[{"series_id": 7, "name": "Série"}]'),
};

class _Sinks {
  final live = <KeyedEntry>[];
  final vod = <XtreamVodStream>[];
  final series = <XtreamSeries>[];
  Map<String, String> vodNames = const {};
}

Future<XtreamImportResult> _run(XtreamClient client, _Sinks sinks) {
  return XtreamImporter().run(
    client: client,
    liveSink: (batch, start) async => sinks.live.addAll(batch),
    vodSink: (batch, start, names) async {
      sinks.vod.addAll(batch);
      sinks.vodNames = names;
    },
    seriesSink: (batch, start, names) async => sinks.series.addAll(batch),
  );
}

void main() {
  test('canais viram entradas M3U com grupo, EPG e catch-up xc', () async {
    final sinks = _Sinks();
    final result = await _run(_client(_full), sinks);

    expect(result.live, 2);
    expect(result.duplicates, 1);
    final globo = sinks.live.first.entry;
    expect(globo.url, 'http://painel.example:8080/live/u/p/10.m3u8');
    expect(globo.tvgId, 'globo.br');
    expect(globo.group, 'Abertos');
    expect(globo.catchup, 'xc');
    expect(globo.catchupDays, 3);
    expect(sinks.live.last.entry.group, isNull);
    expect(sinks.live.last.entry.catchup, isNull);

    expect(result.vod, 1);
    expect(sinks.vodNames['5'], 'Filmes');
    expect(result.series, 1);
    expect(result.toImportResult().imported, 2);
  });

  test('VOD indisponível não derruba a importação', () async {
    final routes = Map<String?, http.Response Function()>.of(_full)
      ..remove('get_vod_streams');
    final sinks = _Sinks();
    final result = await _run(_client(routes), sinks);
    expect(result.live, 2);
    expect(result.vodAvailable, isFalse);
    expect(result.seriesAvailable, isTrue);
  });

  test('conta expirada vira erro de credencial', () async {
    final routes = Map<String?, http.Response Function()>.of(_full)
      ..[null] = () => _json('{"user_info": {"auth": 1, "status": "Expired"}}');
    await expectLater(
      _run(_client(routes), _Sinks()),
      throwsA(
        isA<SourceException>().having(
          (e) => e.error,
          'error',
          SourceError.credentials,
        ),
      ),
    );
  });
}
