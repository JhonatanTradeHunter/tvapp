import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/models/playlist_source.dart';

const XtreamCredentials _creds = XtreamCredentials(
  host: 'http://painel.example',
  port: 8080,
  username: 'joao',
  password: 'p@ss',
);

XtreamClient _client(MockClientHandler handler) =>
    XtreamClient(_creds, clientFactory: () => MockClient(handler));

Matcher _sourceError(SourceError error) =>
    throwsA(isA<SourceException>().having((e) => e.error, 'error', error));

void main() {
  test('monta player_api e URLs de mídia com credenciais codificadas', () {
    final client = XtreamClient(_creds);
    final api = client.apiUri('get_series_info', {'series_id': '7'});
    expect(api.path, '/player_api.php');
    expect(api.queryParameters, {
      'username': 'joao',
      'password': 'p@ss',
      'action': 'get_series_info',
      'series_id': '7',
    });
    expect(
      client.liveUrl(101, extension: 'ts').toString(),
      'http://painel.example:8080/live/joao/p@ss/101.ts',
    );
    expect(
      client.movieUrl(5, extension: 'mkv').toString(),
      'http://painel.example:8080/movie/joao/p@ss/5.mkv',
    );
    expect(
      client.episodeUrl(9).toString(),
      'http://painel.example:8080/series/joao/p@ss/9.mp4',
    );
  });

  test('authenticate devolve a conta quando auth=1', () async {
    final client = _client((request) async {
      expect(request.url.queryParameters.containsKey('action'), isFalse);
      return http.Response(
        '{"user_info": {"auth": 1, "status": "Active"}, "server_info": {}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final account = await client.authenticate();
    expect(account.isActive, isTrue);
  });

  test('auth=0 vira erro de credencial', () async {
    final client = _client(
      (request) async => http.Response('{"user_info": {"auth": 0}}', 200),
    );
    await expectLater(
      client.authenticate(),
      _sourceError(SourceError.credentials),
    );
  });

  test('HTML com status 200 vira erro de credencial', () async {
    final client = _client(
      (request) async => http.Response(
        '<html>login</html>',
        200,
        headers: {'content-type': 'text/html'},
      ),
    );
    await expectLater(
      client.liveStreams(),
      _sourceError(SourceError.credentials),
    );
  });

  test('corpo que não é JSON vira erro de credencial', () async {
    final client = _client(
      (request) async => http.Response('Access denied', 200),
    );
    await expectLater(
      client.vodStreams(),
      _sourceError(SourceError.credentials),
    );
  });

  test('404 vira credencial e 503 vira erro do servidor', () async {
    await expectLater(
      _client((r) async => http.Response('', 404)).series(),
      _sourceError(SourceError.credentials),
    );
    await expectLater(
      _client((r) async => http.Response('', 503)).series(),
      _sourceError(SourceError.http5xx),
    );
  });

  test(
    'listas descartam itens sem id e aceitam mapa no lugar de lista',
    () async {
      final client = _client((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'get_live_streams') {
          return http.Response(
            '[{"stream_id": 1, "name": "A"}, {"name": "sem id"}, {"stream_id": "2", "name": "B"}]',
            200,
          );
        }
        return http.Response(
          '{"0": {"category_id": "1", "category_name": "Abertos"}}',
          200,
        );
      });
      final streams = await client.liveStreams();
      expect(streams.map((s) => s.streamId), [1, 2]);
      final categories = await client.liveCategories();
      expect(categories.single.name, 'Abertos');
    },
  );
}
