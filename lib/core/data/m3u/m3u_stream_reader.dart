import 'dart:convert';

class ImportCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final pending = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in pending) {
      listener();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// Converte bytes em linhas sem nunca materializar o arquivo inteiro.
/// O `await for` de quem consome pausa a assinatura, o que dá backpressure.
class M3uStreamReader {
  M3uStreamReader._();

  static Stream<String> lines(
    Stream<List<int>> bytes, {
    void Function(int bytesRead)? onBytes,
  }) {
    Stream<List<int>> source = bytes;
    if (onBytes != null) {
      var read = 0;
      source = bytes.map((chunk) {
        read += chunk.length;
        onBytes(read);
        return chunk;
      });
    }
    return source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }
}
