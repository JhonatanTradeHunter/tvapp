import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/platform/local_io.dart';

class PlaylistStream {
  PlaylistStream({
    required this.bytes,
    required Future<void> Function() close,
    this.length,
  }) : _close = close;

  final Stream<List<int>> bytes;
  final int? length;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

class PlaylistLoader {
  PlaylistLoader({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const Duration responseTimeout = Duration(seconds: 15);

  static const Map<String, String> defaultHeaders = <String, String>{
    'User-Agent': 'tvapp/0.1',
    'Accept': '*/*',
  };

  Future<PlaylistStream> open(
    PlaylistSource source, {
    ImportCancelToken? cancel,
  }) async {
    switch (source.kind) {
      case SourceKind.localFile:
        return _openFile(source.location);
      case SourceKind.url:
        final uri = Uri.tryParse(source.location);
        if (uri == null) {
          throw const SourceException(
            SourceError.invalidContent,
            detail: 'url',
          );
        }
        return _openHttp(uri, credentialsMode: false, cancel: cancel);
      case SourceKind.xtream:
        final uri = source.remoteUri;
        if (uri == null) {
          throw const SourceException(SourceError.credentials, detail: 'host');
        }
        return _openHttp(uri, credentialsMode: true, cancel: cancel);
    }
  }

  Future<PlaylistStream> _openFile(String path) async {
    final (bytes, length) = await openLocalFile(path);
    return PlaylistStream(bytes: bytes, length: length, close: () async {});
  }

  Future<PlaylistStream> _openHttp(
    Uri uri, {
    required bool credentialsMode,
    ImportCancelToken? cancel,
  }) async {
    final client = _clientFactory();
    cancel?.onCancel(client.close);
    final request = http.Request('GET', uri)..headers.addAll(defaultHeaders);

    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(responseTimeout);
    } on TimeoutException {
      client.close();
      throw const SourceException(SourceError.timeout);
    } catch (error) {
      client.close();
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
      throw SourceException(SourceError.network, detail: '$error');
    }

    final failure = classifyResponse(
      response.statusCode,
      response.headers['content-type'],
      credentialsMode: credentialsMode,
    );
    if (failure != null) {
      client.close();
      throw failure;
    }

    return PlaylistStream(
      bytes: response.stream,
      length: response.contentLength,
      close: () async => client.close(),
    );
  }

  /// No modo credencial (Xtream), 401/403/404 e HTML indicam usuário,
  /// senha ou host errados, nunca uma lista vazia.
  static SourceException? classifyResponse(
    int status,
    String? contentType, {
    required bool credentialsMode,
  }) {
    if (credentialsMode && (status == 401 || status == 403 || status == 404)) {
      return SourceException(SourceError.credentials, statusCode: status);
    }
    if (status >= 500) {
      return SourceException(SourceError.http5xx, statusCode: status);
    }
    if (status >= 400) {
      return SourceException(SourceError.http4xx, statusCode: status);
    }
    if (status < 200 || status >= 300) {
      return SourceException(SourceError.unknown, statusCode: status);
    }
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('text/html')) {
      return SourceException(
        credentialsMode ? SourceError.credentials : SourceError.invalidContent,
        statusCode: status,
        detail: 'html',
      );
    }
    return null;
  }
}
