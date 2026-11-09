import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/core/background/epg_background.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_repository.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/prefs/app_prefs.dart';
import 'package:tvapp/core/data/secure/secret_store.dart';
import 'package:tvapp/core/models/playlist_source.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 11, 9, 3);
  late AppDatabase db;
  late AppPrefs prefs;
  var requests = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = AppPrefs(await SharedPreferences.getInstance());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    requests = 0;
  });
  tearDown(() => db.close());

  EpgRepository repository() => EpgRepository(
    db: db,
    secrets: MemorySecretStore(),
    importer: XmltvImporter(useIsolate: false),
    clientFactory: () => MockClient((request) async {
      requests++;
      return http.Response(
        '<?xml version="1.0"?><tv><channel id="a"><display-name>A'
        '</display-name></channel></tv>',
        200,
        headers: <String, String>{'content-type': 'application/xml'},
      );
    }),
  );

  Future<int> insertSource({DateTime? epgRefresh}) => db.sourceDao.insertSource(
    SourcesCompanion.insert(
      name: 'lista',
      kind: SourceKind.url,
      location: 'http://lista.example/a.m3u',
      isActive: const Value(true),
      epgUrl: const Value('http://epg.example/guia.xml'),
      epgRefresh: Value(epgRefresh),
    ),
  );

  Future<EpgTaskOutcome> run() =>
      runEpgTask(db: db, repository: repository(), prefs: prefs, now: now);

  test('com o app aberto, não faz nada', () async {
    await insertSource();
    await prefs.markAppInUse(now.subtract(const Duration(minutes: 1)));
    expect(await run(), EpgTaskOutcome.appInUse);
    expect(requests, 0);
  });

  test('heartbeat antigo não impede a rodada', () async {
    await insertSource();
    await prefs.markAppInUse(now.subtract(const Duration(minutes: 10)));
    expect(await run(), EpgTaskOutcome.refreshed);
    expect(requests, 1);
  });

  test('guia recente não é baixado de novo', () async {
    await insertSource(epgRefresh: now.subtract(const Duration(hours: 2)));
    expect(await run(), EpgTaskOutcome.fresh);
    expect(requests, 0);
  });

  test('sem fonte ativa, termina sem erro', () async {
    expect(await run(), EpgTaskOutcome.noSource);
  });
}
