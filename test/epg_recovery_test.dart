import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_repository.dart';
import 'package:tvapp/core/models/playlist_source.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  EpgRepository repository(MockClientHandler handler) =>
      EpgRepository(db: db, clientFactory: () => MockClient(handler));

  test('M3U sem epgUrl recupera o url-tvg do cabeçalho', () async {
    final id = await db.sourceDao.insertSource(
      SourcesCompanion.insert(
        name: 'lista',
        kind: SourceKind.url,
        location: 'http://lista.example/a.m3u',
      ),
    );
    var requests = 0;
    await repository((request) async {
      requests++;
      return http.Response(
        '#EXTM3U url-tvg="http://epg.example/guia.xml, http://outro/e.xml"\n'
        '#EXTINF:-1,A\nhttp://x/1\n',
        200,
      );
    }).recoverMetadata(id);

    final row = await db.sourceDao.byId(id);
    expect(row!.epgUrl, 'http://epg.example/guia.xml');
    expect(requests, 1);
    expect(EpgRepository.needsMetadata(row), isFalse);
  });

  test('Xtream sem epgUrl e sem fuso monta xmltv.php e lê o fuso', () async {
    final id = await db.sourceDao.insertSource(
      SourcesCompanion.insert(
        name: 'painel',
        kind: SourceKind.xtream,
        location: 'http://painel.example/get.php',
        xtreamHost: const Value('http://painel.example'),
        xtreamPort: const Value(8080),
        xtreamUser: const Value('u'),
        xtreamPass: const Value('p'),
      ),
    );
    await repository((request) async {
      expect(request.url.path, '/player_api.php');
      return http.Response(
        '{"user_info": {"auth": 1, "status": "Active"},'
        ' "server_info": {"timezone": "America/Sao_Paulo"}}',
        200,
      );
    }).recoverMetadata(id);

    final row = await db.sourceDao.byId(id);
    expect(
      row!.epgUrl,
      'http://painel.example:8080/xmltv.php?username=u&password=p',
    );
    expect(row.serverTimezone, 'America/Sao_Paulo');
    expect(EpgRepository.needsMetadata(row), isFalse);
  });

  test('lista sem cabeçalho #EXTM3U continua sem URL, sem erro', () async {
    final id = await db.sourceDao.insertSource(
      SourcesCompanion.insert(
        name: 'lista',
        kind: SourceKind.url,
        location: 'http://lista.example/a.m3u',
      ),
    );
    await repository(
      (request) async => http.Response('#EXTINF:-1,A\nhttp://x/1\n', 200),
    ).recoverMetadata(id);
    expect((await db.sourceDao.byId(id))!.epgUrl, isNull);
  });

  test('firstEpgUrl ignora entradas sem host', () {
    expect(EpgRepository.firstEpgUrl(' , http://a/e.xml'), 'http://a/e.xml');
    expect(EpgRepository.firstEpgUrl('nada'), isNull);
    expect(EpgRepository.firstEpgUrl(null), isNull);
  });
}
