import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Converte exceções e mensagens de ExoPlayer, AVFoundation e mpv no
/// [PlaybackError] da UI. Ordem: status HTTP, rede, codec, fonte.
class PlaybackErrorMapper {
  PlaybackErrorMapper._();

  /// Cobre "Response code: 404", "HTTP/1.1 503" e o formato do mpv,
  /// "http: HTTP error 404 Not Found".
  static final RegExp _statusCode = RegExp(
    r'(?:response code|status code|http error|http(?:/\d(?:\.\d)?)?)\D{0,3}(\d{3})',
    caseSensitive: false,
  );

  static const List<String> _networkHints = <String>[
    'unknownhost',
    'connectexception',
    'sockettimeout',
    'timed out',
    'timeout',
    'unable to connect',
    'connection refused',
    'connection reset',
    'network is unreachable',
    'failed to resolve hostname',
    'no route to host',
    'network',
    'nsurlerrordomain',
    '-1001',
    '-1004',
    '-1005',
    '-1009',
  ];

  static const List<String> _codecHints = <String>[
    'decoder',
    'codec',
    'mediacodec',
    'unsupported',
    'format not supported',
    'no video or audio streams',
    'could not open codec',
    '-11821',
    '-12906',
  ];

  static const List<String> _sourceHints = <String>[
    'unrecognizedinputformat',
    'failed to recognize file format',
    'invalid data found',
    'malformed',
    'parser',
    'cannot open',
    'failed to open',
    'loading failed',
    'invalid',
    'filenotfound',
    '-11800',
    '-11828',
    '-1100',
  ];

  static PlaybackError fromHttpStatus(int status) {
    if (status >= 500) return PlaybackError.Http5xx;
    if (status >= 400) return PlaybackError.Http4xx;
    return PlaybackError.Desconhecido;
  }

  static PlaybackError fromObject(Object error) {
    if (error is PlaybackException) return error.error;
    if (error is TimeoutException || error is SocketException) {
      return PlaybackError.Rede;
    }
    if (error is FormatException) return PlaybackError.FonteInvalida;
    if (error is PlatformException) {
      return fromDescription(
        '${error.code} ${error.message ?? ''} ${error.details ?? ''}',
      );
    }
    return fromDescription(error.toString());
  }

  static PlaybackError fromDescription(String? description) {
    if (description == null || description.isEmpty) {
      return PlaybackError.Desconhecido;
    }
    final text = description.toLowerCase();
    // allMatches: a URL na mensagem ("http://187.4...") casa antes do status
    // real ("HTTP error 404") e não pode esconder o código.
    for (final match in _statusCode.allMatches(text)) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code != null && code >= 400 && code < 600) {
        return fromHttpStatus(code);
      }
    }
    if (_containsAny(text, _networkHints)) return PlaybackError.Rede;
    if (_containsAny(text, _codecHints)) return PlaybackError.Codec;
    if (_containsAny(text, _sourceHints)) return PlaybackError.FonteInvalida;
    return PlaybackError.Desconhecido;
  }

  static bool _containsAny(String text, List<String> hints) {
    for (final hint in hints) {
      if (text.contains(hint)) return true;
    }
    return false;
  }
}

String describePlaybackError(PlaybackError error, AppLocalizations l) {
  switch (error) {
    case PlaybackError.Rede:
      return l.errRede;
    case PlaybackError.Http4xx:
      return l.errHttp4xx;
    case PlaybackError.Http5xx:
      return l.errHttp5xx;
    case PlaybackError.Codec:
      return l.errCodec;
    case PlaybackError.FonteInvalida:
      return l.errFonteInvalida;
    case PlaybackError.Desconhecido:
      return l.errDesconhecido;
  }
}
