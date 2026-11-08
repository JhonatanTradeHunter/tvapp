import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/models/playlist_source.dart';

const int _entries = 2500;

/// 1 cabeçalho + 2 linhas por entrada = 5.001 linhas.
/// A cada 100 entradas uma repete a anterior (duplicada) e a cada 250
/// uma tem URL inválida (descartada). Cinco entradas caem nos dois casos
/// (499, 999, ...) e contam só como descartadas, porque a URL é validada
/// antes da deduplicação: 20 duplicadas, 10 descartadas, 2.470 importadas.
String _fixture() {
  final b = StringBuffer('#EXTM3U\n');
  for (var i = 0; i < _entries; i++) {
    final duplicate = i % 100 == 99;
    final invalid = i % 250 == 249;
    final id = duplicate ? i - 1 : i;
    b
      ..write(
        '#EXTINF:-1 tvg-id="ch$id" tvg-logo="http://logo.example/$id.png" ',
      )
      ..write('group-title="Grupo ${id % 20}",Canal $id\n')
      ..write(invalid ? 'sem-url\n' : 'http://stream.example/live/$i.m3u8\n');
  }
  return b.toString();
}

Stream<List<int>> _chunked(List<int> bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    final end = i + size > bytes.length ? bytes.length : i + size;
    yield bytes.sublist(i, end);
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('importa M3U de 5.000 linhas em menos de 2s', () async {
    final sourceId = await db.sourceDao.insertSource(
      SourcesCompanion.insert(
        name: 'teste',
        kind: SourceKind.url,
        location: 'http://example.com/lista.m3u',
        xtreamHost: const Value(null),
      ),
    );
    final text = _fixture();
    expect(const LineSplitter().convert(text).length, 5001);

    final clock = Stopwatch()..start();
    final result = await M3uImporter().run(
      bytes: _chunked(utf8.encode(text), 64 * 1024),
      sink: (batch, start) =>
          db.channelDao.insertEntries(sourceId, 1, start, batch),
    );
    clock.stop();

    expect(result.duplicates, 20);
    expect(result.discarded, 10);
    expect(result.imported, _entries - 20 - 10);
    expect(await db.channelDao.countChannels(sourceId, 1), result.imported);
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('HTML no lugar da lista vira invalidContent', () async {
    final html = utf8.encode('<!DOCTYPE html><html><body>login</body></html>');
    await expectLater(
      M3uImporter().run(
        bytes: Stream<List<int>>.value(html),
        sink: (batch, start) async {},
      ),
      throwsA(
        isA<SourceException>().having(
          (e) => e.error,
          'error',
          SourceError.invalidContent,
        ),
      ),
    );
  });

  test('respeita o limite máximo de entradas', () async {
    final result = await M3uImporter(maxEntries: 100, parseChunkRecords: 64)
        .run(
          bytes: _chunked(utf8.encode(_fixture()), 4096),
          sink: (batch, start) async {},
        );
    expect(result.imported, 100);
    expect(result.truncated, isTrue);
  });
}
