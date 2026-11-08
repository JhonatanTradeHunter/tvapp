import 'package:tvapp/core/util/normalize.dart';

class XmltvChannel {
  const XmltvChannel({
    required this.id,
    required this.displayName,
    required this.normalizedName,
    this.icon,
  });

  /// Já em minúsculas e sem espaços nas pontas.
  final String id;
  final String displayName;
  final String normalizedName;
  final String? icon;
}

class XmltvProgramme {
  const XmltvProgramme({
    required this.channelId,
    required this.start,
    required this.title,
    this.stop,
    this.subtitle,
    this.description,
    this.category,
  });

  /// Já em minúsculas e sem espaços nas pontas.
  final String channelId;
  final DateTime start;
  final DateTime? stop;
  final String title;
  final String? subtitle;
  final String? description;
  final String? category;

  XmltvProgramme withStop(DateTime value) => XmltvProgramme(
    channelId: channelId,
    start: start,
    stop: value,
    title: title,
    subtitle: subtitle,
    description: description,
    category: category,
  );
}

class ParsedXmltv {
  const ParsedXmltv(this.channels, this.programmes, this.discarded);

  final List<XmltvChannel> channels;
  final List<XmltvProgramme> programmes;
  final int discarded;
}

/// Recorta elementos `<channel>` e `<programme>` de um texto que chega em
/// pedaços. Não monta árvore e não exige XML válido: elemento sem fechamento
/// é pulado quando o próximo começa, e lixo maior que [maxElementLength] é
/// descartado em vez de acumular memória.
class XmltvChunker {
  XmltvChunker({this.maxElementLength = 256 * 1024});

  final int maxElementLength;
  int skipped = 0;
  String _pending = '';

  static const int _tailKeep = 16;

  List<String> feed(String chunk) {
    final text = _pending.isEmpty ? chunk : '$_pending$chunk';
    final out = <String>[];
    var pos = 0;
    var nextProgramme = _findTag(text, '<programme', 0);
    var nextChannel = _findTag(text, '<channel', 0);

    while (true) {
      if (nextProgramme >= 0 && nextProgramme < pos) {
        nextProgramme = _findTag(text, '<programme', pos);
      }
      if (nextChannel >= 0 && nextChannel < pos) {
        nextChannel = _findTag(text, '<channel', pos);
      }
      final start = _earliest(nextProgramme, nextChannel);
      if (start < 0) {
        final keep = text.length - _tailKeep;
        if (keep > pos) pos = keep;
        break;
      }

      final isProgramme = start == nextProgramme;
      final tagEnd = text.indexOf('>', start);
      if (tagEnd < 0) {
        if (text.length - start > maxElementLength) {
          skipped++;
          pos = start + 1;
          continue;
        }
        pos = start;
        break;
      }

      int end;
      if (text.codeUnitAt(tagEnd - 1) == 0x2F) {
        end = tagEnd + 1;
      } else {
        final close = isProgramme ? '</programme>' : '</channel>';
        final closeAt = text.indexOf(close, tagEnd);
        final sibling = _findTag(
          text,
          isProgramme ? '<programme' : '<channel',
          tagEnd,
        );
        if (sibling >= 0 && (closeAt < 0 || sibling < closeAt)) {
          skipped++;
          pos = sibling;
          continue;
        }
        if (closeAt < 0) {
          if (text.length - start > maxElementLength) {
            skipped++;
            pos = start + 1;
            continue;
          }
          pos = start;
          break;
        }
        end = closeAt + close.length;
      }

      out.add(text.substring(start, end));
      pos = end;
    }

    _pending = text.substring(pos);
    return out;
  }

  static int _earliest(int a, int b) {
    if (a < 0) return b;
    if (b < 0) return a;
    return a < b ? a : b;
  }

  /// Exige que o nome termine ali (`<channel ` ou `<channel>`), para não
  /// confundir com `<channels>` ou similares.
  static int _findTag(String text, String tag, int from) {
    var at = text.indexOf(tag, from);
    while (at >= 0) {
      final after = at + tag.length;
      if (after >= text.length) return at;
      final c = text.codeUnitAt(after);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x3E ||
          c == 0x2F) {
        return at;
      }
      at = text.indexOf(tag, after);
    }
    return -1;
  }
}

/// Parser puro de elementos já recortados. Roda dentro de isolate.
class XmltvParser {
  XmltvParser._();

  static const Duration maxDuration = Duration(hours: 24);

  static final RegExp _attribute = RegExp(
    r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final RegExp _time = RegExp(
    r'^\s*(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*(Z|[+-]\d{2}:?\d{2})?',
  );
  static final RegExp _cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');
  static final RegExp _entity = RegExp(
    r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);',
  );
  static final RegExp _icon = RegExp(
    r'''<icon\s[^>]*?src\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final Map<String, RegExp> _children = <String, RegExp>{
    for (final tag in <String>[
      'title',
      'sub-title',
      'desc',
      'category',
      'display-name',
    ])
      tag: RegExp('<$tag(\\s[^>]*)?>([\\s\\S]*?)</$tag>'),
  };

  /// [minStopMs] e [maxStartMs] limitam a janela guardada (epoch UTC).
  static ParsedXmltv parseElements(
    List<String> elements, {
    int? minStopMs,
    int? maxStartMs,
  }) {
    final channels = <XmltvChannel>[];
    final programmes = <XmltvProgramme>[];
    var discarded = 0;

    for (final element in elements) {
      if (element.startsWith('<channel')) {
        final channel = parseChannel(element);
        if (channel == null) {
          discarded++;
        } else {
          channels.add(channel);
        }
        continue;
      }
      final programme = parseProgramme(element);
      if (programme == null) {
        discarded++;
        continue;
      }
      final startMs = programme.start.millisecondsSinceEpoch;
      final stopMs = programme.stop?.millisecondsSinceEpoch;
      if (maxStartMs != null && startMs > maxStartMs) {
        discarded++;
        continue;
      }
      if (minStopMs != null && stopMs != null && stopMs < minStopMs) {
        discarded++;
        continue;
      }
      programmes.add(programme);
    }
    return ParsedXmltv(channels, programmes, discarded);
  }

  static XmltvChannel? parseChannel(String element) {
    final attrs = _openingAttributes(element);
    final id = (attrs['id'] ?? '').trim().toLowerCase();
    if (id.isEmpty) return null;
    final name = _preferred(element, 'display-name') ?? id;
    return XmltvChannel(
      id: id,
      displayName: name,
      normalizedName: normalizeForMatch(name),
      icon: _iconSrc(element),
    );
  }

  /// Descarta sem canal, sem início válido ou com duração <= 0 ou > 24h.
  /// Sem `stop`, o programa volta com `stop` nulo e o importador infere pelo
  /// início do próximo programa do mesmo canal.
  static XmltvProgramme? parseProgramme(String element) {
    final attrs = _openingAttributes(element);
    final channelId = (attrs['channel'] ?? '').trim().toLowerCase();
    if (channelId.isEmpty) return null;
    final start = parseTime(attrs['start']);
    if (start == null) return null;
    final stop = parseTime(attrs['stop']);
    if (stop != null && !isSaneDuration(start, stop)) return null;
    return XmltvProgramme(
      channelId: channelId,
      start: start,
      stop: stop,
      title: _preferred(element, 'title') ?? '',
      subtitle: _preferred(element, 'sub-title'),
      description: _preferred(element, 'desc'),
      category: _preferred(element, 'category'),
    );
  }

  static bool isSaneDuration(DateTime start, DateTime stop) {
    final duration = stop.difference(start);
    return duration > Duration.zero && duration <= maxDuration;
  }

  /// `YYYYMMDDHHmm[ss] [±HHMM|Z]`. Sem fuso, o XMLTV assume UTC.
  static DateTime? parseTime(String? raw) {
    if (raw == null) return null;
    final m = _time.firstMatch(raw);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.parse(m.group(6) ?? '0');
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59) {
      return null;
    }
    var utc = DateTime.utc(year, month, day, hour, minute, second);
    final zone = m.group(7);
    if (zone != null && zone != 'Z') {
      final digits = zone.replaceAll(':', '');
      final sign = digits.startsWith('-') ? -1 : 1;
      final hours = int.parse(digits.substring(1, 3));
      final minutes = int.parse(digits.substring(3, 5));
      utc = utc.subtract(Duration(hours: hours, minutes: minutes) * sign);
    }
    return utc;
  }

  static String decodeText(String raw) {
    final parts = <String>[];
    var last = 0;
    for (final m in _cdata.allMatches(raw)) {
      parts.add(_decodeEntities(raw.substring(last, m.start)));
      parts.add(m.group(1) ?? '');
      last = m.end;
    }
    parts.add(_decodeEntities(raw.substring(last)));
    return parts.join().trim();
  }

  static String _decodeEntities(String text) {
    if (!text.contains('&')) return text;
    return text.replaceAllMapped(_entity, (m) {
      final name = m.group(1)!;
      switch (name) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = name.startsWith('#x')
          ? int.tryParse(name.substring(2), radix: 16)
          : int.tryParse(name.substring(1));
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
  }

  static Map<String, String> _openingAttributes(String element) {
    final tagEnd = element.indexOf('>');
    final opening = tagEnd < 0 ? element : element.substring(0, tagEnd);
    final attrs = <String, String>{};
    for (final m in _attribute.allMatches(opening)) {
      attrs[m.group(1)!.toLowerCase()] = _decodeEntities(
        m.group(2) ?? m.group(3) ?? '',
      );
    }
    return attrs;
  }

  /// Entre vários filhos com `lang`, prefere português; senão o primeiro.
  static String? _preferred(String element, String tag) {
    final pattern = _children[tag];
    if (pattern == null) return null;
    String? first;
    for (final m in pattern.allMatches(element)) {
      final text = decodeText(m.group(2) ?? '');
      if (text.isEmpty) continue;
      first ??= text;
      final lang = _attribute
          .allMatches(m.group(1) ?? '')
          .where((a) => a.group(1)!.toLowerCase() == 'lang')
          .map((a) => (a.group(2) ?? a.group(3) ?? '').toLowerCase())
          .firstOrNull;
      if (lang != null && lang.startsWith('pt')) return text;
    }
    return first;
  }

  static String? _iconSrc(String element) {
    final m = _icon.firstMatch(element);
    if (m == null) return null;
    final src = _decodeEntities(m.group(1) ?? m.group(2) ?? '').trim();
    return src.isEmpty ? null : src;
  }
}
