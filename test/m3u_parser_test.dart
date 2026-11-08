import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/m3u/m3u_entry.dart';
import 'package:tvapp/core/data/m3u/m3u_parser.dart';

void main() {
  test('lê atributos com e sem aspas e nome com vírgula', () {
    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:-1 tvg-id="globo.br" tvg-logo="http://l/g.png" group-title="Abertos, BR",Globo, São Paulo',
      'http://example.com/live/1.m3u8',
    ], M3uHeader.empty);

    expect(chunk.discarded, 0);
    final e = chunk.entries.single;
    expect(e.name, 'Globo, São Paulo');
    expect(e.tvgId, 'globo.br');
    expect(e.logo, 'http://l/g.png');
    expect(e.group, 'Abertos, BR');
    expect(e.url, 'http://example.com/live/1.m3u8');
  });

  test('EXTGRP, EXTVLCOPT e catchup por entrada', () {
    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:0 catchup="shift" catchup-days=3 catchup-source="?utc={utc}",Canal A',
      '#EXTGRP:Notícias',
      '#EXTVLCOPT:http-user-agent=MeuPlayer/1.0',
      '#EXTVLCOPT:http-referrer=http://ref.example/',
      'https://cdn.example.com/a.ts',
      '#EXTINF:-1,Canal B',
      'https://cdn.example.com/b.ts',
    ], M3uHeader.empty);

    expect(chunk.entries, hasLength(2));
    final a = chunk.entries[0];
    expect(a.group, 'Notícias');
    expect(a.catchup, 'shift');
    expect(a.catchupDays, 3);
    expect(a.catchupSource, '?utc={utc}');
    expect(a.userAgent, 'MeuPlayer/1.0');
    expect(a.referrer, 'http://ref.example/');

    final b = chunk.entries[1];
    expect(b.group, isNull);
    expect(b.userAgent, isNull);
  });

  test('cabeçalho fornece catchup padrão', () {
    final header = M3uParser.parseHeader(
      '#EXTM3U url-tvg="http://epg.example/guide.xml" catchup="append" catchup-days="7"',
    );
    expect(header.urlTvg, 'http://epg.example/guide.xml');

    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:-1,Canal',
      'http://example.com/c',
    ], header);
    expect(chunk.entries.single.catchup, 'append');
    expect(chunk.entries.single.catchupDays, 7);
  });

  test('descarta entrada sem URL válida e não vaza atributos', () {
    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:-1 tvg-id="x",Quebrado',
      'isto não é url',
      '#EXTINF:-1,Sem host',
      'http://',
      'http://example.com/ok',
    ], M3uHeader.empty);

    expect(chunk.discarded, 2);
    final ok = chunk.entries.single;
    expect(ok.tvgId, isNull);
    expect(ok.name, 'ok');
  });

  test('nome vazio usa tvg-name e depois o fim da URL', () {
    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:-1 tvg-name="Nome TVG",',
      'http://example.com/live/1',
      'http://example.com/live/canal-2.m3u8',
    ], M3uHeader.empty);
    expect(chunk.entries[0].name, 'Nome TVG');
    expect(chunk.entries[1].name, 'canal-2.m3u8');
  });

  test('aceita esquemas de streaming e recusa os demais', () {
    expect(M3uParser.isValidUrl('rtmp://host/app/stream'), isTrue);
    expect(M3uParser.isValidUrl('udp://@239.0.0.1:1234'), isTrue);
    expect(M3uParser.isValidUrl('file:///sdcard/a.ts'), isFalse);
    expect(M3uParser.isValidUrl('javascript:alert(1)'), isFalse);
  });

  test('tvg-chno vira número do canal', () {
    final chunk = M3uParser.parseRecords(<String>[
      '#EXTINF:-1 tvg-chno="105",Canal',
      'http://example.com/c',
    ], M3uHeader.empty);
    expect(chunk.entries.single.tvgChno, 105);
  });
}
