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

/// Quanto a engine guarda à frente. Só vale para engines com
/// `supportsBufferTuning`; as outras usam o padrão da plataforma.
enum BufferProfile {
  compact(seconds: 5, megabytes: 8),
  normal(seconds: 15, megabytes: 32),
  large(seconds: 45, megabytes: 96);

  const BufferProfile({required this.seconds, required this.megabytes});

  final int seconds;
  final int megabytes;
}

class MediaRequest {
  const MediaRequest({
    required this.uri,
    this.headers = const <String, String>{},
    this.isLive = true,
    this.startAt,
    this.buffer = BufferProfile.normal,
  });

  final Uri uri;
  final Map<String, String> headers;
  final bool isLive;
  final Duration? startAt;
  final BufferProfile buffer;

  MediaRequest withStart(Duration? start) => MediaRequest(
    uri: uri,
    headers: headers,
    isLive: isLive,
    startAt: start,
    buffer: buffer,
  );
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
