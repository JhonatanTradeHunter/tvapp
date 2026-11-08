import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/util/normalize.dart';

void main() {
  group('foldName', () {
    test('remove acentos, baixa caixa e colapsa espaços', () {
      expect(foldName('  São   Paulo HD '), 'sao paulo hd');
      expect(foldName('AÇÃO\tÉPICA'), 'acao epica');
    });

    test(
      'mantém marcadores de qualidade para não fundir streams distintos',
      () {
        expect(foldName('Globo HD'), isNot(foldName('Globo SD')));
      },
    );
  });

  group('normalizeForMatch', () {
    test('remove prefixo de país, colchetes e qualidade', () {
      expect(normalizeForMatch('BR: Globo SP FHD [Alt]'), 'globo sp');
      expect(normalizeForMatch('ESPN 2 (H265)'), 'espn 2');
      expect(normalizeForMatch('PT | RTP 1 HD'), 'rtp 1');
    });

    test('pontuação vira separador', () {
      expect(normalizeForMatch('Canal+ Séries'), 'canal series');
    });
  });

  group('channelKey', () {
    test('combina tvg-id e nome dobrado', () {
      expect(channelKey(null, 'Ação'), '|acao');
      expect(channelKey(' Globo.br ', 'Globo'), 'globo.br|globo');
    });
  });
}
