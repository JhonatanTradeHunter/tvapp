import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/util/pin.dart';

void main() {
  test('só aceita quatro dígitos', () {
    expect(PinHasher.isValid('1234'), isTrue);
    expect(PinHasher.isValid('123'), isFalse);
    expect(PinHasher.isValid('12a4'), isFalse);
    expect(PinHasher.isValid('12345'), isFalse);
  });

  test('hash com sal verifica o PIN certo e recusa o errado', () {
    final salt = PinHasher.newSalt(Random(1));
    final hash = PinHasher.hash('2468', salt);
    expect(PinHasher.verify('2468', salt, hash), isTrue);
    expect(PinHasher.verify('2469', salt, hash), isFalse);
    expect(PinHasher.verify('abcd', salt, hash), isFalse);
  });

  test('sais diferentes geram hashes diferentes para o mesmo PIN', () {
    final a = PinHasher.hash('0000', PinHasher.newSalt(Random(1)));
    final b = PinHasher.hash('0000', PinHasher.newSalt(Random(2)));
    expect(a, isNot(b));
  });
}
