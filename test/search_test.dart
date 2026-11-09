import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/profiles/parental_policy.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/util/normalize.dart';
import 'package:tvapp/features/search/search_controller.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int sourceId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceId = await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            name: 'lista',
            kind: SourceKind.url,
            location: 'http://x/a.m3u',
          ),
        );
    final channels = <(String, String)>[
      ('Rede Esporte', 'Esportes'),
      ('ESPORTE Total', 'Esportes'),
      ('Notícias 24h', 'Notícias'),
      ('Hot Esporte Club', 'Adultos'),
    ];
    for (var i = 0; i < channels.length; i++) {
      final (name, group) = channels[i];
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              sourceId: sourceId,
              generation: 1,
              position: i,
              channelKey: channelKey(null, name),
              name: name,
              nameFolded: foldName(name),
              groupTitle: group,
              streamUrl: 'http://x/$i.ts',
            ),
          );
    }
    await db
        .into(db.vodItems)
        .insert(
          VodItemsCompanion.insert(
            sourceId: sourceId,
            generation: 1,
            position: 0,
            streamId: 7,
            name: 'O Último Esporte',
            nameFolded: foldName('O Último Esporte'),
            categoryName: 'Drama',
          ),
        );
    await db
        .into(db.seriesItems)
        .insert(
          SeriesItemsCompanion.insert(
            sourceId: sourceId,
            generation: 2,
            position: 0,
            seriesId: 9,
            name: 'Esporte de Geração Velha',
            nameFolded: foldName('Esporte de Geração Velha'),
            categoryName: 'Drama',
          ),
        );
  });
  tearDown(() => db.close());

  Future<SearchResults> search(
    String query, {
    ParentalPolicy policy = ParentalPolicy.unrestricted,
  }) => runSearch(
    db: db,
    profileId: 1,
    sourceId: sourceId,
    generation: 1,
    query: query,
    policy: policy,
  );

  test('ignora acento e caixa; quem começa com o termo vem antes', () async {
    final r = await search('ÉSPORTE');
    expect(r.channels.map((c) => c.name), [
      'ESPORTE Total',
      'Rede Esporte',
      'Hot Esporte Club',
    ]);
    expect(r.movies.single.streamId, 7);
    expect(r.series, isEmpty, reason: 'série é de outra geração');
  });

  test('termo curto não busca', () async {
    expect((await search('e')).isEmpty, isTrue);
  });

  test('perfil infantil não vê o canal adulto', () async {
    final r = await search(
      'esporte',
      policy: const ParentalPolicy(isKids: true),
    );
    expect(r.channels.map((c) => c.name), isNot(contains('Hot Esporte Club')));
    expect(r.channels, hasLength(2));
  });

  test('busca com % e _ não vira curinga', () async {
    expect((await search('%%')).isEmpty, isTrue);
  });
}
