import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/epg/epg_matcher.dart';
import 'package:tvapp/core/util/normalize.dart';

EpgChannelInfo _info(String id, String name) =>
    EpgChannelInfo(id: id, normalizedName: normalizeForMatch(name));

void main() {
  final matcher = EpgMatcher(<EpgChannelInfo>[
    _info('globo.br', 'Globo SP'),
    _info('espn.br', 'ESPN'),
    _info('band.sp', 'Band'),
    _info('band.rj', 'Band'),
  ]);

  test('tvg-id casa exato, sem diferenciar maiúsculas', () {
    final m = matcher.match(tvgId: ' Globo.BR ', name: 'Qualquer');
    expect(m?.xmltvId, 'globo.br');
    expect(m?.confidence, EpgMatchConfidence.exact);
    expect(m?.isApproximate, isFalse);
  });

  test('sem tvg-id conhecido cai no nome normalizado e marca aproximado', () {
    final m = matcher.match(tvgId: 'inexistente', name: 'BR: ESPN FHD');
    expect(m?.xmltvId, 'espn.br');
    expect(m?.isApproximate, isTrue);
  });

  test('nome ambíguo não casa', () {
    expect(matcher.match(tvgId: null, name: 'Band HD'), isNull);
  });

  test('sem nada parecido devolve null', () {
    expect(matcher.match(tvgId: '', name: 'Canal Novo'), isNull);
  });

  test('XMLTV sem <channel> aceita o tvg-id como está', () {
    final empty = EpgMatcher(const <EpgChannelInfo>[]);
    final m = empty.match(tvgId: 'x.y', name: 'X');
    expect(m?.xmltvId, 'x.y');
    expect(m?.confidence, EpgMatchConfidence.exact);
  });
}
