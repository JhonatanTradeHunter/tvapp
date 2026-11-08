enum SourceKind { localFile, url, xtream }

enum SourceError {
  network,
  timeout,
  notFound,
  http4xx,
  http5xx,
  credentials,
  invalidContent,
  empty,
  cancelled,
  unknown,
}

class SourceException implements Exception {
  const SourceException(this.error, {this.statusCode, this.detail});

  final SourceError error;
  final int? statusCode;
  final String? detail;

  @override
  String toString() =>
      'SourceException(${error.name}, status: $statusCode, detail: $detail)';
}

class XtreamCredentials {
  const XtreamCredentials({
    required this.host,
    required this.username,
    required this.password,
    this.port,
  });

  final String host;
  final int? port;
  final String username;
  final String password;

  static const String defaultOutput = 'm3u8';

  static Uri? tryParseHost(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Uri get baseUri {
    final parsed = tryParseHost(host);
    if (parsed == null) {
      throw const SourceException(SourceError.invalidContent, detail: 'host');
    }
    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: port ?? (parsed.hasPort ? parsed.port : null),
      path: path,
    );
  }

  /// Endpoint de-facto `xmltv.php` do Xtream, com as mesmas credenciais.
  Uri xmltvUri() {
    final base = baseUri;
    return base.replace(
      path: '${base.path}/xmltv.php',
      queryParameters: <String, String>{
        'username': username,
        'password': password,
      },
    );
  }

  Uri m3uUri({String output = defaultOutput}) {
    final base = baseUri;
    return base.replace(
      path: '${base.path}/get.php',
      queryParameters: <String, String>{
        'username': username,
        'password': password,
        'type': 'm3u_plus',
        'output': output,
      },
    );
  }
}

class PlaylistSource {
  const PlaylistSource({
    required this.name,
    required this.kind,
    required this.location,
    this.id,
    this.xtream,
    this.activeGeneration = 0,
    this.lastRefresh,
  });

  final int? id;
  final String name;
  final SourceKind kind;
  final String location;
  final XtreamCredentials? xtream;
  final int activeGeneration;
  final DateTime? lastRefresh;

  Uri? get remoteUri {
    switch (kind) {
      case SourceKind.localFile:
        return null;
      case SourceKind.url:
        return Uri.tryParse(location);
      case SourceKind.xtream:
        final creds = xtream;
        return creds == null ? Uri.tryParse(location) : creds.m3uUri();
    }
  }

  PlaylistSource copyWith({
    int? id,
    String? location,
    int? activeGeneration,
    DateTime? lastRefresh,
  }) {
    return PlaylistSource(
      id: id ?? this.id,
      name: name,
      kind: kind,
      location: location ?? this.location,
      xtream: xtream,
      activeGeneration: activeGeneration ?? this.activeGeneration,
      lastRefresh: lastRefresh ?? this.lastRefresh,
    );
  }
}
