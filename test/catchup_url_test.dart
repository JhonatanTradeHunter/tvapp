import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/player/catchup_url.dart';

Channel _channel(String url, {String? catchup, String? source, int? days}) =>
    Channel(
      id: 1,
      sourceId: 1,
      channelKey: 'k',
      position: 0,
      name: 'Canal',
      group: '',
      streamUrl: url,
      catchup: catchup,
      catchupSource: source,
      catchupDays: days,
    );

void main() {
  final start = DateTime.utc(2026, 11, 8, 20, 5, 9);
  final end = DateTime.utc(2026, 11, 8, 21, 5, 9);
  final now = DateTime.utc(2026, 11, 8, 22);
  final s = start.millisecondsSinceEpoch ~/ 1000;
  final e = end.millisecondsSinceEpoch ~/ 1000;
  final n = now.millisecondsSinceEpoch ~/ 1000;

  String? build(Channel c) =>
      CatchupUrlBuilder.build(c, start: start, end: end, now: now)?.toString();

  test('default usa o template completo', () {
    final c = _channel(
      'http://h/live/1.m3u8',
      catchup: 'default',
      source: 'http://h/arch/1.m3u8?start={utc}&end={utcend}&d={duration:60}',
    );
    expect(build(c), 'http://h/arch/1.m3u8?start=$s&end=$e&d=60');
  });

  test('append soma à URL ao vivo e ajusta ? para &', () {
    final c = _channel(
      'http://h/live/1.m3u8?token=x',
      catchup: 'append',
      source: '?utc={utc}&lutc={lutc}',
    );
    expect(build(c), 'http://h/live/1.m3u8?token=x&utc=$s&lutc=$n');
  });

  test('shift põe utc e lutc na query', () {
    final c = _channel('http://h/live/1.ts', catchup: 'shift');
    expect(build(c), 'http://h/live/1.ts?utc=$s&lutc=$n');
  });

  test('flussonic reescreve HLS e mpegts', () {
    expect(
      build(_channel('http://h/canal/index.m3u8', catchup: 'flussonic')),
      'http://h/canal/index-$s-3600.m3u8',
    );
    expect(
      build(_channel('http://h/canal/mpegts', catchup: 'fs')),
      'http://h/canal/timeshift_abs/$s',
    );
  });

  test('xc monta o endpoint timeshift do Xtream', () {
    expect(
      build(_channel('http://srv:8080/live/user/pass/123.m3u8', catchup: 'xc')),
      'http://srv:8080/timeshift/user/pass/60/2026-11-08:20-05/123.m3u8',
    );
    expect(
      build(_channel('http://srv:8080/user/pass/123', catchup: 'xc')),
      'http://srv:8080/timeshift/user/pass/60/2026-11-08:20-05/123.ts',
    );
  });

  test('xc formata o início no fuso do painel', () {
    final c = _channel('http://srv:8080/live/user/pass/123.ts', catchup: 'xc');
    String? at(String? zone) => CatchupUrlBuilder.build(
      c,
      start: start,
      end: end,
      now: now,
      timezone: zone,
    )?.toString();
    expect(
      at('America/Sao_Paulo'),
      'http://srv:8080/timeshift/user/pass/60/2026-11-08:17-05/123.ts',
    );
    expect(
      at('Europe/Lisbon'),
      'http://srv:8080/timeshift/user/pass/60/2026-11-08:20-05/123.ts',
    );
    expect(at('Zona/Inexistente'), contains('2026-11-08:20-05'));
    expect(at(null), contains('2026-11-08:20-05'));
  });

  test('placeholders de data, offset e formato com \$', () {
    final out = CatchupUrlBuilder.fill(
      '/{Y}/{m}/{d}/{H}{M}{S}?o={offset}&t=\${start:Y-m-d_H-M}',
      start: start,
      end: end,
      now: now,
    );
    expect(out, '/2026/11/08/200509?o=${n - s}&t=2026-11-08_20-05');
  });

  test('sem atributos de catch-up não há URL nem disponibilidade', () {
    final c = _channel('http://h/live/1.m3u8');
    expect(build(c), isNull);
    expect(CatchupUrlBuilder.isAvailable(c, start, now), isFalse);
  });

  test('disponibilidade respeita catchup-days e não vale para o futuro', () {
    final c = _channel('http://h/1.ts', catchup: 'shift', days: 1);
    expect(CatchupUrlBuilder.isAvailable(c, start, now), isTrue);
    expect(
      CatchupUrlBuilder.isAvailable(
        c,
        now.subtract(const Duration(days: 2)),
        now,
      ),
      isFalse,
    );
    expect(
      CatchupUrlBuilder.isAvailable(c, now.add(const Duration(hours: 1)), now),
      isFalse,
    );
  });
}
