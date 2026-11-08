import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN de 4 dígitos guardado como SHA-256 de `sal:pin`, com sal aleatório
/// por perfil. Não protege contra quem tem o banco nas mãos (são só 10 mil
/// combinações); serve para controle parental na tela.
class PinHasher {
  PinHasher._();

  static final RegExp _pattern = RegExp(r'^\d{4}$');

  static bool isValid(String pin) => _pattern.hasMatch(pin);

  static String newSalt([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Comparação em tempo constante.
  static bool verify(String pin, String salt, String expectedHash) {
    if (!isValid(pin)) return false;
    final actual = hash(pin, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
