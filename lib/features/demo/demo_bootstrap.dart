import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/playlist_source.dart';

/// `--dart-define=DEMO=true`: abre com uma fonte de exemplo embutida.
const bool kDemo = bool.fromEnvironment('DEMO');

/// Pasta dos assets da demonstração como a página os serve. Na web,
/// `assets/demo/x` vira `<base>/assets/assets/demo/x`.
String demoAssetBase() => Uri.base.resolve('assets/assets/demo/').toString();

/// Monta a fonte de demonstração a cada abertura, para que o guia fique
/// sempre relativo ao horário atual: um programa encerrado (com catch-up),
/// um no ar e os seguintes. Sem rede: tudo vem dos assets.
class DemoBootstrap {
  DemoBootstrap._();

  static const String sourceName = 'Demonstração';
  static final RegExp _relative = RegExp(r'\{\{T([+-]\d+)\}\}');

  static Future<void> run(
    AppDatabase db, {
    AssetBundle? bundle,
    DateTime? now,
    String? assetBase,
  }) async {
    final assets = bundle ?? rootBundle;
    final clock = (now ?? DateTime.now()).toUtc();
    final base = assetBase ?? demoAssetBase();

    await db.delete(db.sources).go();
    final sourceId = await db.sourceDao.insertSource(
      SourcesCompanion.insert(
        name: sourceName,
        kind: SourceKind.url,
        location: 'demo:playlist',
        activeGeneration: const Value(1),
        isActive: const Value(true),
        epgUrl: const Value('demo:epg'),
        epgGeneration: const Value(1),
        epgRefresh: Value(clock),
      ),
    );

    final playlist = (await assets.loadString(
      'assets/demo/demo.m3u',
    )).replaceAll('{{BASE}}', base);
    await M3uImporter(useIsolate: false).run(
      bytes: Stream<List<int>>.value(utf8.encode(playlist)),
      sink: (batch, start) =>
          db.channelDao.insertEntries(sourceId, 1, start, batch),
    );

    final guide = fillRelativeTimes(
      await assets.loadString('assets/demo/epg.xml'),
      clock,
    );
    await XmltvImporter(useIsolate: false, clock: () => clock).run(
      bytes: Stream<List<int>>.value(utf8.encode(guide)),
      channelSink: (batch) => db.epgDao.insertChannels(sourceId, 1, batch),
      programmeSink: (batch) => db.epgDao.insertProgrammes(sourceId, 1, batch),
    );

    const categories = <String, String>{'demo': sourceName};
    await db.vodDao.insertVod(sourceId, 1, 0, const <XtreamVodStream>[
      XtreamVodStream(
        streamId: 1,
        name: 'Filme de demonstração',
        rating: 4.5,
        categoryId: 'demo',
        containerExtension: 'mp4',
      ),
    ], categories);
    await db.vodDao.insertSeries(sourceId, 1, 0, const <XtreamSeries>[
      XtreamSeries(
        seriesId: 1,
        name: 'Série de demonstração',
        plot: 'Uma temporada curta para testar episódios e retomada.',
        genre: sourceName,
        releaseDate: '2026',
        rating: 4,
        categoryId: 'demo',
      ),
    ], categories);
  }

  /// Troca `{{T-90}}` pelo horário XMLTV de agora menos 90 minutos (UTC),
  /// com agora arredondado para o minuto.
  static String fillRelativeTimes(String template, DateTime now) {
    final anchor = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    return template.replaceAllMapped(_relative, (m) {
      final t = anchor.add(Duration(minutes: int.parse(m.group(1)!)));
      String two(int v) => v.toString().padLeft(2, '0');
      return '${t.year}${two(t.month)}${two(t.day)}'
          '${two(t.hour)}${two(t.minute)}00 +0000';
    });
  }
}
