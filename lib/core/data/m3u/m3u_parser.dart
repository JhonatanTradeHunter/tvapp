import 'package:tvapp/core/data/m3u/m3u_entry.dart';

class AttributeLine {
  const AttributeLine(this.attributes, this.trailing);

  final Map<String, String> attributes;
  final String trailing;
}

/// Parser puro e sem estado global. Recebe registros completos
/// (linhas `#...` seguidas da URL) e pode rodar dentro de um isolate.
class M3uParser {
  M3uParser._();

  static const Set<String> _validSchemes = <String>{
    'http',
    'https',
    'rtmp',
    'rtmps',
    'rtsp',
    'udp',
    'rtp',
    'mms',
  };

  static const int _hash = 0x23;
  static const int _space = 0x20;
  static const int _tab = 0x09;
  static const int _comma = 0x2C;
  static const int _equals = 0x3D;
  static const int _doubleQuote = 0x22;
  static const int _singleQuote = 0x27;

  static M3uHeader parseHeader(String line) {
    final start = line.startsWith('#EXTM3U') ? 7 : 0;
    final attrs = parseAttributeLine(
      line,
      start,
      skipDuration: false,
    ).attributes;
    return M3uHeader(
      catchup: _nonEmpty(attrs['catchup']),
      catchupSource: _nonEmpty(attrs['catchup-source']),
      catchupDays: _toInt(attrs['catchup-days']),
      urlTvg: _nonEmpty(attrs['url-tvg']) ?? _nonEmpty(attrs['x-tvg-url']),
    );
  }

  static ParsedChunk parseRecords(List<String> lines, M3uHeader header) {
    final entries = <M3uEntry>[];
    var discarded = 0;
    Map<String, String>? attrs;
    String? title;
    String? extGroup;
    String? userAgent;
    String? referrer;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.codeUnitAt(0) == _hash) {
        if (line.startsWith('#EXTINF')) {
          final start = line.length > 7 && line.codeUnitAt(7) == 0x3A ? 8 : 7;
          final parsed = parseAttributeLine(line, start, skipDuration: true);
          attrs = parsed.attributes;
          title = parsed.trailing;
        } else if (line.startsWith('#EXTGRP:')) {
          extGroup = _nonEmpty(line.substring(8).trim());
        } else if (line.startsWith('#EXTVLCOPT:')) {
          final option = line.substring(11);
          final eq = option.indexOf('=');
          if (eq > 0) {
            final key = option.substring(0, eq).trim().toLowerCase();
            final value = _nonEmpty(option.substring(eq + 1).trim());
            if (key == 'http-user-agent') {
              userAgent = value;
            } else if (key == 'http-referrer' || key == 'http-referer') {
              referrer = value;
            }
          }
        }
        continue;
      }

      if (isValidUrl(line)) {
        final a = attrs ?? const <String, String>{};
        var name = (title ?? '').trim();
        if (name.isEmpty) name = (a['tvg-name'] ?? '').trim();
        if (name.isEmpty) name = nameFromUrl(line);
        entries.add(
          M3uEntry(
            name: name,
            url: line,
            tvgId: _nonEmpty(a['tvg-id']),
            tvgName: _nonEmpty(a['tvg-name']),
            logo: _nonEmpty(a['tvg-logo']),
            group: _nonEmpty(a['group-title']) ?? extGroup,
            tvgChno: _toInt(a['tvg-chno']) ?? _toInt(a['tvg-num']),
            catchup: _nonEmpty(a['catchup']) ?? header.catchup,
            catchupSource:
                _nonEmpty(a['catchup-source']) ?? header.catchupSource,
            catchupDays: _toInt(a['catchup-days']) ?? header.catchupDays,
            userAgent: _nonEmpty(a['user-agent']) ?? userAgent,
            referrer: referrer,
          ),
        );
      } else {
        discarded++;
      }

      attrs = null;
      title = null;
      extGroup = null;
      userAgent = null;
      referrer = null;
    }

    return ParsedChunk(entries, discarded);
  }

  static AttributeLine parseAttributeLine(
    String line,
    int start, {
    required bool skipDuration,
  }) {
    final n = line.length;
    var i = start;

    if (skipDuration) {
      while (i < n) {
        final c = line.codeUnitAt(i);
        if (c == _space || c == _tab || c == _comma) break;
        i++;
      }
    }

    final attrs = <String, String>{};
    String? trailing;

    while (i < n) {
      final c = line.codeUnitAt(i);
      if (c == _comma) {
        trailing = line.substring(i + 1);
        break;
      }
      if (c == _space || c == _tab) {
        i++;
        continue;
      }

      final keyStart = i;
      while (i < n) {
        final k = line.codeUnitAt(i);
        if (k == _equals || k == _space || k == _tab || k == _comma) break;
        i++;
      }
      final key = line.substring(keyStart, i).toLowerCase();

      if (i < n && line.codeUnitAt(i) == _equals) {
        i++;
        String value;
        if (i < n &&
            (line.codeUnitAt(i) == _doubleQuote ||
                line.codeUnitAt(i) == _singleQuote)) {
          final quote = line[i];
          final valueStart = i + 1;
          final end = line.indexOf(quote, valueStart);
          if (end < 0) {
            value = line.substring(valueStart);
            i = n;
          } else {
            value = line.substring(valueStart, end);
            i = end + 1;
          }
        } else {
          final valueStart = i;
          while (i < n) {
            final k = line.codeUnitAt(i);
            if (k == _space || k == _tab || k == _comma) break;
            i++;
          }
          value = line.substring(valueStart, i);
        }
        if (key.isNotEmpty) attrs[key] = value;
      }
    }

    return AttributeLine(attrs, (trailing ?? '').trim());
  }

  static bool isValidUrl(String candidate) {
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme) return false;
    if (!_validSchemes.contains(uri.scheme.toLowerCase())) return false;
    return uri.host.isNotEmpty;
  }

  static String nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? uri.host : segments.last;
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _toInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value.trim());
  }
}
