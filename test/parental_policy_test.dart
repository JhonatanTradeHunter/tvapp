import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/profiles/parental_policy.dart';
import 'package:tvapp/core/models/channel.dart';

Channel _channel(String name, String group) => Channel(
  id: 1,
  sourceId: 1,
  channelKey: 'k',
  position: 0,
  name: name,
  group: group,
  streamUrl: 'http://x/1',
);

void main() {
  test('heurística de adulto pega variações e poupa nomes comuns', () {
    for (final name in [
      'Adultos',
      'XXX Premium',
      'BR | Adult 24h',
      'Canal +18',
      'Eróticos',
    ]) {
      expect(ParentalPolicy.looksAdult(name), isTrue, reason: name);
    }
    for (final name in [
      'Globo',
      'Hotelaria TV',
      'Discovery Kids',
      'Shotgun News',
    ]) {
      expect(ParentalPolicy.looksAdult(name), isFalse, reason: name);
    }
  });

  test('perfil adulto vê tudo, menos os grupos que escondeu', () {
    const policy = ParentalPolicy(blockedLive: {'Esportes'});
    expect(policy.allowsChannel(_channel('XXX', 'Adultos')), isTrue);
    expect(policy.allowsChannel(_channel('ESPN', 'Esportes')), isFalse);
    expect(policy.allowsGroup(BlockedKind.vod, 'Esportes'), isTrue);
    expect(policy.allowsProgramme(18), isTrue);
  });

  test('infantil esconde adulto por grupo ou nome e limita idade', () {
    const policy = ParentalPolicy(isKids: true, maxAge: 12);
    expect(policy.allowsChannel(_channel('Gloob', 'Infantil')), isTrue);
    expect(policy.allowsChannel(_channel('Canal', 'Adultos')), isFalse);
    expect(policy.allowsChannel(_channel('Hot Night', 'Variedades')), isFalse);
    expect(policy.allowsProgramme(10), isTrue);
    expect(policy.allowsProgramme(12), isTrue);
    expect(policy.allowsProgramme(14), isFalse);
    expect(policy.allowsProgramme(null), isTrue);
  });

  test('infantil sem limite de idade só usa a heurística e os grupos', () {
    const policy = ParentalPolicy(isKids: true);
    expect(policy.allowsProgramme(18), isTrue);
    expect(
      policy.allowsItem(BlockedKind.series, 'Séries', 'Série Adulta'),
      isFalse,
    );
  });
}
