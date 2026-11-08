import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/epg/xmltv_parser.dart';
import 'package:tvapp/core/models/playlist_source.dart';

const String _sample = '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="x">
  <channel id="Globo.BR">
    <display-name lang="en">Globo</display-name>
    <display-name lang="pt">Globo SP</display-name>
    <icon src="http://img.example/globo.png"/>
  </channel>
  <programme start="20261108200000 -0300" stop="20261108210000 -0300" channel="globo.br">
    <title lang="en">News</title>
    <title lang="pt">Jornal &amp; Notícias</title>
    <desc><![CDATA[Edição <ao vivo> & completa]]></desc>
    <category>Notícias</category>
  </programme>
  <programme start="20261108210000 -0300" stop="20261108200000 -0300" channel="globo.br">
    <title>Duração negativa</title>
  </programme>
  <programme start="20261108210000 -0300" stop="20261110210000 -0300" channel="globo.br">
    <title>Duração absurda</title>
  </programme>
</tv>
''';

Stream<List<int>> _chunks(List<int> bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

XmltvImporter _importer() => XmltvImporter(
  useIsolate: false,
  clock: () => DateTime.utc(2026, 11, 8, 23),
);

void main() {
  group('parseTime', () {
    test('converte fuso para UTC', () {
      expect(
        XmltvParser.parseTime('20261108200000 -0300'),
        DateTime.utc(2026, 11, 8, 23),
      );
      expect(
        XmltvParser.parseTime('20261108200000 +01:00'),
        DateTime.utc(2026, 11, 8, 19),
      );
    });

    test('sem fuso assume UTC e aceita sem segundos', () {
      expect(
        XmltvParser.parseTime('202611082000'),
        DateTime.utc(2026, 11, 8, 20),
      );
    });

    test('lixo vira null', () {
      expect(XmltvParser.parseTime('ontem'), isNull);
      expect(XmltvParser.parseTime('20261399200000'), isNull);
    });
  });

  group('XmltvChunker', () {
    test('recorta elementos que chegam quebrados em qualquer ponto', () {
      final chunker = XmltvChunker();
      final out = <String>[];
      for (var i = 0; i < _sample.length; i += 7) {
        final end = i + 7 > _sample.length ? _sample.length : i + 7;
        out.addAll(chunker.feed(_sample.substring(i, end)));
      }
      expect(out, hasLength(4));
      expect(out.first, startsWith('<channel'));
      expect(
        out.every(
          (e) => e.endsWith('</channel>') || e.endsWith('</programme>'),
        ),
        isTrue,
      );
    });

    test('programa sem fechamento é pulado quando o próximo começa', () {
      final chunker = XmltvChunker();
      final out = chunker.feed(
        '<programme start="1" channel="a"><title>quebrado'
        '<programme start="2" channel="a"><title>ok</title></programme>',
      );
      expect(out, hasLength(1));
      expect(out.single, contains('ok'));
      expect(chunker.skipped, 1);
    });
  });

  group('parseProgramme', () {
    test('prefere pt, decodifica entidades e CDATA, canal em minúsculas', () {
      final elements = XmltvChunker().feed(_sample);
      final parsed = XmltvParser.parseElements(elements);
      expect(parsed.channels.single.id, 'globo.br');
      expect(parsed.channels.single.displayName, 'Globo SP');
      expect(parsed.channels.single.icon, 'http://img.example/globo.png');

      final p = parsed.programmes.single;
      expect(p.channelId, 'globo.br');
      expect(p.title, 'Jornal & Notícias');
      expect(p.description, 'Edição <ao vivo> & completa');
      expect(p.category, 'Notícias');
      expect(p.start, DateTime.utc(2026, 11, 8, 23));
      expect(p.stop, DateTime.utc(2026, 11, 9));
    });

    test('duração negativa e acima de 24h são descartadas', () {
      final parsed = XmltvParser.parseElements(XmltvChunker().feed(_sample));
      expect(parsed.discarded, 2);
    });
  });

  group('XmltvImporter', () {
    test('infere stop pelo próximo programa do canal', () async {
      const xml = '''<tv>
<channel id="a"><display-name>A</display-name></channel>
<programme start="20261108220000 +0000" channel="a"><title>Um</title></programme>
<programme start="20261108230000 +0000" channel="a"><title>Dois</title></programme>
<programme start="20261109000000 +0000" stop="20261109010000 +0000" channel="a"><title>Três</title></programme>
</tv>''';
      final programmes = <XmltvProgramme>[];
      final result = await _importer().run(
        bytes: _chunks(utf8.encode(xml), 32),
        channelSink: (batch) async {},
        programmeSink: (batch) async => programmes.addAll(batch),
      );
      expect(result.channels, 1);
      expect(programmes.map((p) => p.title), ['Um', 'Dois', 'Três']);
      expect(programmes[0].stop, DateTime.utc(2026, 11, 8, 23));
      expect(programmes[1].stop, DateTime.utc(2026, 11, 9));
    });

    test('lê gzip e prólogo ISO-8859-1', () async {
      const xml =
          '<?xml version="1.0" encoding="ISO-8859-1"?><tv>'
          '<programme start="20261108230000 +0000" stop="20261109000000 +0000" channel="a">'
          '<title>Programação</title></programme></tv>';
      final programmes = <XmltvProgramme>[];
      await _importer().run(
        bytes: _chunks(gzip.encode(latin1.encode(xml)), 16),
        channelSink: (batch) async {},
        programmeSink: (batch) async => programmes.addAll(batch),
      );
      expect(programmes.single.title, 'Programação');
    });

    test('descarta programas fora da janela', () async {
      const xml = '''<tv>
<programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="a"><title>Velho</title></programme>
<programme start="20261108230000 +0000" stop="20261109000000 +0000" channel="a"><title>Agora</title></programme>
<programme start="20270101000000 +0000" stop="20270101010000 +0000" channel="a"><title>Longe</title></programme>
</tv>''';
      final programmes = <XmltvProgramme>[];
      final result = await _importer().run(
        bytes: Stream<List<int>>.value(utf8.encode(xml)),
        channelSink: (batch) async {},
        programmeSink: (batch) async => programmes.addAll(batch),
      );
      expect(programmes.map((p) => p.title), ['Agora']);
      expect(result.discarded, 2);
    });

    test('HTML no lugar do XMLTV vira invalidContent', () async {
      await expectLater(
        _importer().run(
          bytes: Stream<List<int>>.value(
            utf8.encode('<!DOCTYPE html><html></html>'),
          ),
          channelSink: (batch) async {},
          programmeSink: (batch) async {},
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
  });
}
