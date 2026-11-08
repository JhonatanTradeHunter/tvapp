import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';

enum EngineKind { exoPlayer, avPlayer, mpv, web }

enum PlaybackStatus { idle, opening, buffering, playing, paused, ended, failed }

class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
    this.errorDetail,
  });

  static const PlaybackState idle = PlaybackState();

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final PlaybackError? error;
  final String? errorDetail;
}

class MediaRequest {
  const MediaRequest({
    required this.uri,
    this.headers = const <String, String>{},
    this.isLive = true,
    this.startAt,
  });

  final Uri uri;
  final Map<String, String> headers;
  final bool isLive;
  final Duration? startAt;

  MediaRequest withStart(Duration? start) =>
      MediaRequest(uri: uri, headers: headers, isLive: isLive, startAt: start);
}

class AudioTrack {
  const AudioTrack({required this.id, required this.label, this.language});

  final String id;
  final String label;
  final String? language;
}

abstract class PlaybackEngine {
  EngineKind get kind;

  EngineCapabilities get capabilities;

  ValueListenable<PlaybackState> get state;

  /// Abre e inicia a mídia. Lança [PlaybackException] em falha,
  /// inclusive no estouro do timeout de conexão.
  Future<void> open(MediaRequest request);

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<List<AudioTrack>> audioTracks();

  Future<void> selectAudioTrack(String id);

  Future<void> setAudioDelay(Duration delay);

  Future<void> stop();

  Widget buildView(BuildContext context);

  Future<void> dispose();
}
