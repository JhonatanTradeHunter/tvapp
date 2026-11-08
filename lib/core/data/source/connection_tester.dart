import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/models/playlist_source.dart';

class ConnectionReport {
  const ConnectionReport({
    required this.ok,
    required this.elapsed,
    this.statusCode,
    this.contentType,
    this.contentLength,
    this.error,
    this.looksLikePlaylist,
    this.headRejected = false,
  });

  final bool ok;
  final Duration elapsed;
  final int? statusCode;
  final String? contentType;
  final int? contentLength;
  final SourceError? error;
  final bool? looksLikePlaylist;
  final bool headRejected;
}

class ConnectionTester {
  ConnectionTester({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const Duration timeout = Duration(seconds: 8);
  static const int sniffBytes = 2048;

  Future<ConnectionReport> test(PlaylistSource source) async {
    final clock = Stopwatch()..start();
    try {
      if (source.kind == SourceKind.localFile) {
        return await _testFile(source.location, clock);
      }
      final credentials = source.xtream;
      if (source.kind == SourceKind.xtream && credentials != null) {
        return await _testXtream(credentials, clock);
      }
      final uri = source.remoteUri;
      if (uri == null) {
        return ConnectionReport(
          ok: false,
          elapsed: clock.elapsed,
          error: SourceError.invalidContent,
        );
      }
      return await _testHttp(
        uri,
        credentialsMode: source.kind == SourceKind.xtream,
        clock: clock,
      );
    } on TimeoutException {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: SourceError.timeout,
      );
    } on SocketException {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: SourceError.network,
      );
    } on http.ClientException {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: SourceError.network,
      );
    } on SourceException catch (e) {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: e.error,
        statusCode: e.statusCode,
      );
    } catch (_) {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: SourceError.unknown,
      );
    }
  }

  /// Xtream é importado pelo `player_api.php`, então o teste usa a mesma
  /// porta de entrada: autentica e confere se a conta está ativa.
  Future<ConnectionReport> _testXtream(
    XtreamCredentials credentials,
    Stopwatch clock,
  ) async {
    final account = await XtreamClient(
      credentials,
      clientFactory: _clientFactory,
      timeout: timeout,
    ).authenticate();
    final active = account.isActive;
    return ConnectionReport(
      ok: active,
      elapsed: clock.elapsed,
      contentType: 'application/json',
      error: active ? null : SourceError.credentials,
    );
  }

  Future<ConnectionReport> _testFile(String path, Stopwatch clock) async {
    final file = File(path);
    if (!await file.exists()) {
      return ConnectionReport(
        ok: false,
        elapsed: clock.elapsed,
        error: SourceError.notFound,
      );
    }
    final length = await file.length();
    final head = await _collect(file.openRead(0, sniffBytes));
    final playlist = looksLikePlaylist(head);
    return ConnectionReport(
      ok: playlist,
      elapsed: clock.elapsed,
      contentLength: length,
      looksLikePlaylist: playlist,
      error: playlist ? null : SourceError.invalidContent,
    );
  }

  Future<ConnectionReport> _testHttp(
    Uri uri, {
    required bool credentialsMode,
    required Stopwatch clock,
  }) async {
    final client = _clientFactory();
    try {
      final headRequest = http.Request('HEAD', uri)
        ..headers.addAll(PlaylistLoader.defaultHeaders);
      final head = await client.send(headRequest).timeout(timeout);
      await head.stream.drain<void>();

      final headRejected =
          head.statusCode == 400 ||
          head.statusCode == 405 ||
          head.statusCode == 501;
      if (!headRejected) {
        final failure = PlaylistLoader.classifyResponse(
          head.statusCode,
          head.headers['content-type'],
          credentialsMode: credentialsMode,
        );
        if (failure != null) {
          return ConnectionReport(
            ok: false,
            elapsed: clock.elapsed,
            statusCode: head.statusCode,
            contentType: head.headers['content-type'],
            contentLength: head.contentLength,
            error: failure.error,
          );
        }
      }

      final getRequest = http.Request('GET', uri)
        ..headers.addAll(PlaylistLoader.defaultHeaders)
        ..headers['Range'] = 'bytes=0-${sniffBytes - 1}';
      final response = await client.send(getRequest).timeout(timeout);
      final contentType = response.headers['content-type'];
      final failure = PlaylistLoader.classifyResponse(
        response.statusCode,
        contentType,
        credentialsMode: credentialsMode,
      );
      if (failure != null) {
        return ConnectionReport(
          ok: false,
          elapsed: clock.elapsed,
          statusCode: response.statusCode,
          contentType: contentType,
          headRejected: headRejected,
          error: failure.error,
        );
      }

      final bytes = await _collect(response.stream).timeout(timeout);
      final playlist = looksLikePlaylist(bytes);
      SourceError? error;
      if (!playlist) {
        final suspicious = looksLikeHtml(bytes) || bytes.isEmpty;
        error = credentialsMode && suspicious
            ? SourceError.credentials
            : SourceError.invalidContent;
      }
      return ConnectionReport(
        ok: playlist,
        elapsed: clock.elapsed,
        statusCode: response.statusCode,
        contentType: contentType,
        contentLength: headRejected ? null : head.contentLength,
        looksLikePlaylist: playlist,
        headRejected: headRejected,
        error: error,
      );
    } finally {
      client.close();
    }
  }

  static Future<List<int>> _collect(Stream<List<int>> stream) async {
    final out = <int>[];
    await for (final chunk in stream) {
      out.addAll(chunk);
      if (out.length >= sniffBytes) break;
    }
    return out;
  }

  static String _prefix(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true).trimLeft();

  static bool looksLikePlaylist(List<int> bytes) {
    final text = _prefix(bytes);
    return text.startsWith('#EXTM3U') || text.startsWith('#EXTINF');
  }

  static bool looksLikeHtml(List<int> bytes) => _prefix(bytes).startsWith('<');
}
