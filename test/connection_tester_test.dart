import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvapp/core/data/source/connection_tester.dart';
import 'package:tvapp/core/models/playlist_source.dart';

PlaylistSource _xtream() {
  const creds = XtreamCredentials(
    host: 'http://painel.example',
    username: 'u',
    password: 'p',
  );
  return PlaylistSource(
    name: 'painel',
    kind: SourceKind.xtream,
    location: creds.m3uUri().toString(),
    xtream: creds,
  );
}

ConnectionTester _tester(MockClientHandler handler) =>
    ConnectionTester(clientFactory: () => MockClient(handler));

void main() {
  test('Xtream testa pelo player_api e aceita conta ativa', () async {
    final report = await _tester((request) async {
      expect(request.url.path, '/player_api.php');
      return http.Response(
        '{"user_info": {"auth": 1, "status": "Active"}}',
        200,
      );
    }).test(_xtream());
    expect(report.ok, isTrue);
    expect(report.error, isNull);
  });

  test('Xtream com conta expirada falha como credencial', () async {
    final report = await _tester(
      (request) async =>
          http.Response('{"user_info": {"auth": 1, "status": "Expired"}}', 200),
    ).test(_xtream());
    expect(report.ok, isFalse);
    expect(report.error, SourceError.credentials);
  });

  test('Xtream com auth=0 falha como credencial', () async {
    final report = await _tester(
      (request) async => http.Response('{"user_info": {"auth": 0}}', 200),
    ).test(_xtream());
    expect(report.error, SourceError.credentials);
  });

  test('URL de playlist detecta M3U pelo começo do conteúdo', () async {
    final report =
        await _tester((request) async {
          if (request.method == 'HEAD') return http.Response('', 200);
          return http.Response('#EXTM3U\n#EXTINF:-1,A\nhttp://x/1', 206);
        }).test(
          const PlaylistSource(
            name: 'lista',
            kind: SourceKind.url,
            location: 'http://lista.example/a.m3u',
          ),
        );
    expect(report.ok, isTrue);
    expect(report.looksLikePlaylist, isTrue);
  });
}
