const Map<String, String> _foldGroups = <String, String>{
  'a': 'àáâãäåāăą',
  'c': 'çćč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'i': 'ìíîïĩīĭį',
  'n': 'ñńň',
  'o': 'òóôõöøōŏő',
  'r': 'ŕř',
  's': 'śšş',
  't': 'ť',
  'u': 'ùúûüũūŭůűų',
  'y': 'ýÿ',
  'z': 'źżž',
  'ss': 'ß',
  'ae': 'æ',
  'oe': 'œ',
};

final Map<int, String> _foldMap = <int, String>{
  for (final entry in _foldGroups.entries)
    for (final rune in entry.value.runes) rune: entry.key,
};

const Set<String> _qualityTokens = <String>{
  'hd',
  'fhd',
  'uhd',
  'sd',
  'hq',
  'lq',
  '4k',
  '8k',
  'hevc',
  'h264',
  'h265',
  'x264',
  'x265',
  '480p',
  '720p',
  '1080p',
  '1080i',
  '2160p',
  '50fps',
  '60fps',
  'backup',
};

final RegExp _bracketed = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
final RegExp _countryPrefix = RegExp(r'^\s*[a-z]{2,3}\s*[:|]\s*');
final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');

bool _isSpace(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0D ||
    rune == 0xA0;

/// Minúsculas, sem acento e com espaços colapsados. Base da chave de deduplicação.
String foldName(String input) {
  final buffer = StringBuffer();
  var lastWasSpace = true;
  for (final rune in input.toLowerCase().runes) {
    final mapped = _foldMap[rune];
    if (mapped != null) {
      buffer.write(mapped);
      lastWasSpace = false;
    } else if (_isSpace(rune)) {
      if (!lastWasSpace) {
        buffer.write(' ');
        lastWasSpace = true;
      }
    } else {
      buffer.writeCharCode(rune);
      lastWasSpace = false;
    }
  }
  return buffer.toString().trim();
}

/// Forma agressiva para casar nomes com o EPG: remove prefixo de país,
/// trechos entre colchetes/parênteses, pontuação e marcadores de qualidade.
String normalizeForMatch(String input) {
  var text = foldName(input);
  text = text.replaceAll(_bracketed, ' ');
  text = text.replaceFirst(_countryPrefix, '');
  final tokens = text
      .split(_nonAlnum)
      .where((t) => t.isNotEmpty && !_qualityTokens.contains(t));
  return tokens.join(' ');
}

String channelKeyFrom(String? tvgId, String foldedName) {
  final id = (tvgId ?? '').trim().toLowerCase();
  return '$id|$foldedName';
}

String channelKey(String? tvgId, String name) =>
    channelKeyFrom(tvgId, foldName(name));
