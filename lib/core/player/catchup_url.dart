import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tvapp/core/models/channel.dart';

/// Monta a URL de catch-up a partir dos atributos M3U do canal (`catchup`,
/// `catchup-source`, `catchup-days`). Modos: `default` (template completo),
/// `append` (template somado à URL ao vivo), `shift` (`utc`/`lutc` na query),
/// `flussonic`/`fs` (reescreve o caminho) e `xc` (endpoint `timeshift` do
/// Xtream Codes). Placeholders no estilo do pvr.iptvsimple: `{utc}`,
/// `{start}`, `{utcend}`, `{end}`, `{lutc}`, `{now}`, `{timestamp}`,
/// `{offset}`, `{duration}`, `{duration:60}`, `{Y}` `{m}` `{d}` `{H}` `{M}`
/// `{S}` e formatos como `{utc:Y-m-d-H-M-S}`, com ou sem `$` na frente.
class CatchupUrlBuilder {
  CatchupUrlBuilder._();

  /// Dias de arquivo quando a lista declara catch-up mas não `catchup-days`.
  static const int defaultDays = 7;

  static final RegExp _placeholder = RegExp(r'\$?\{([a-zA-Z]+)(?::([^}]*))?\}');
  static final RegExp _hlsFile = RegExp(r'/([^/]+)\.m3u8$');

  static bool supports(Channel channel) =>
      (channel.catchup ?? '').trim().isNotEmpty ||
      (channel.catchupSource ?? '').trim().isNotEmpty;

  /// O programa já começou e está dentro dos dias de arquivo do canal.
  static bool isAvailable(Channel channel, DateTime start, DateTime now) {
    if (!supports(channel)) return false;
    final days = channel.catchupDays ?? defaultDays;
    if (days <= 0) return false;
    if (!start.isBefore(now)) return false;
    return !start.isBefore(now.subtract(Duration(days: days)));
  }

  static Uri? build(
    Channel channel, {
    required DateTime start,
    required DateTime end,
    DateTime? now,
    String? timezone,
  }) {
    final mode = (channel.catchup ?? '').trim().toLowerCase();
    final source = _nonEmpty(channel.catchupSource);
    final live = channel.playbackUrl;
    final s = start.toUtc();
    final e = end.toUtc();
    final n = (now ?? DateTime.now()).toUtc();

    String? template;
    switch (mode) {
      case 'default':
        template = source;
      case 'append':
        template = source == null ? null : _append(live, source);
      case 'shift':
        template = _append(live, '?utc={utc}&lutc={lutc}');
      case 'flussonic':
      case 'flussonic-hls':
      case 'flussonic-ts':
      case 'fs':
        return _flussonic(live, s, e);
      case 'xc':
        return _xtream(live, s, e, timezone);
      default:
        if (source == null) return null;
        template = _hasScheme(source) ? source : _append(live, source);
    }
    if (template == null) return null;
    return Uri.tryParse(fill(template, start: s, end: e, now: n));
  }

  static String fill(
    String template, {
    required DateTime start,
    required DateTime end,
    required DateTime now,
  }) {
    final s = start.toUtc();
    final e = end.toUtc();
    final n = now.toUtc();
    return template.replaceAllMapped(_placeholder, (m) {
      final name = m.group(1)!.toLowerCase();
      final arg = m.group(2);
      switch (m.group(1)!) {
        case 'Y':
          return _pad(s.year, 4);
        case 'm':
          return _pad(s.month, 2);
        case 'd':
          return _pad(s.day, 2);
        case 'H':
          return _pad(s.hour, 2);
        case 'M':
          return _pad(s.minute, 2);
        case 'S':
          return _pad(s.second, 2);
      }
      switch (name) {
        case 'utc':
        case 'start':
          return arg == null ? '${_epoch(s)}' : _format(arg, s);
        case 'utcend':
        case 'end':
          return arg == null ? '${_epoch(e)}' : _format(arg, e);
        case 'lutc':
        case 'now':
        case 'timestamp':
          return arg == null ? '${_epoch(n)}' : _format(arg, n);
        case 'offset':
          return '${n.difference(s).inSeconds}';
        case 'duration':
          final seconds = e.difference(s).inSeconds;
          final divider = int.tryParse(arg ?? '');
          if (divider == null || divider <= 0) return '$seconds';
          return '${seconds ~/ divider}';
      }
      return m.group(0)!;
    });
  }

  /// Flussonic: `.../index.m3u8` vira `.../index-{início}-{duração}.m3u8` e
  /// `.../mpegts` vira `.../timeshift_abs/{início}`.
  static Uri? _flussonic(String live, DateTime s, DateTime e) {
    final uri = Uri.tryParse(live);
    if (uri == null) return null;
    final start = _epoch(s);
    final duration = e.difference(s).inSeconds;
    final path = uri.path;
    if (path.endsWith('/mpegts')) {
      return uri.replace(
        path: '${path.substring(0, path.length - 7)}/timeshift_abs/$start',
      );
    }
    final hls = _hlsFile.firstMatch(path);
    if (hls != null) {
      return uri.replace(
        path: path.replaceRange(
          hls.start,
          hls.end,
          '/${hls.group(1)}-$start-$duration.m3u8',
        ),
      );
    }
    return null;
  }

  /// Xtream Codes: a live `/{user}/{pass}/{id}` ou `/live/{user}/{pass}/{id}.ext`
  /// vira `/timeshift/{user}/{pass}/{minutos}/{Y-m-d:H-M}/{id}.ext`.
  /// O início vai no fuso do painel ([timezone], de `server_info.timezone`);
  /// sem fuso informado ou com nome desconhecido, vai em UTC.
  static Uri? _xtream(String live, DateTime s, DateTime e, String? timezone) {
    final uri = Uri.tryParse(live);
    if (uri == null || uri.host.isEmpty) return null;
    final segments = uri.pathSegments.where((x) => x.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.first == 'live') segments.removeAt(0);
    if (segments.length < 3) return null;
    final user = segments[segments.length - 3];
    final pass = segments[segments.length - 2];
    final file = segments.last;
    final dot = file.lastIndexOf('.');
    final id = dot > 0 ? file.substring(0, dot) : file;
    final ext = dot > 0 ? file.substring(dot + 1) : 'ts';
    final minutes = (e.difference(s).inSeconds / 60).ceil();
    final local = inZone(s, timezone);
    final stamp =
        '${_pad(local.year, 4)}-${_pad(local.month, 2)}-${_pad(local.day, 2)}:'
        '${_pad(local.hour, 2)}-${_pad(local.minute, 2)}';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: <String>[
        'timeshift',
        user,
        pass,
        '$minutes',
        stamp,
        '$id.$ext',
      ],
    );
  }

  static bool _zonesLoaded = false;

  /// [utc] no fuso IANA [zone]. Carrega a base de fusos na primeira chamada.
  static DateTime inZone(DateTime utc, String? zone) {
    final name = zone?.trim();
    if (name == null || name.isEmpty) return utc.toUtc();
    try {
      if (!_zonesLoaded) {
        tzdata.initializeTimeZones();
        _zonesLoaded = true;
      }
      return tz.TZDateTime.from(utc, tz.getLocation(name));
    } catch (_) {
      return utc.toUtc();
    }
  }

  static String _append(String live, String suffix) {
    if (live.contains('?') && suffix.startsWith('?')) {
      return '$live&${suffix.substring(1)}';
    }
    if (!live.contains('?') && suffix.startsWith('&')) {
      return '$live?${suffix.substring(1)}';
    }
    return '$live$suffix';
  }

  static String _format(String pattern, DateTime t) {
    final out = StringBuffer();
    for (final unit in pattern.split('')) {
      switch (unit) {
        case 'Y':
          out.write(_pad(t.year, 4));
        case 'm':
          out.write(_pad(t.month, 2));
        case 'd':
          out.write(_pad(t.day, 2));
        case 'H':
          out.write(_pad(t.hour, 2));
        case 'M':
          out.write(_pad(t.minute, 2));
        case 'S':
          out.write(_pad(t.second, 2));
        default:
          out.write(unit);
      }
    }
    return out.toString();
  }

  static int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  static bool _hasScheme(String value) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(value);

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
