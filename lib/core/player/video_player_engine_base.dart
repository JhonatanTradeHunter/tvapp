import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/playback_error_mapper.dart';

/// Base comum para as engines sobre `video_player`. O plugin não expõe
/// timeout, então o limite de 8s é aplicado aqui em volta de `initialize()`.
abstract class VideoPlayerEngineBase implements PlaybackEngine {
  static const Duration connectTimeout = Duration(seconds: 8);

  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );
  final ValueNotifier<VideoPlayerController?> _current =
      ValueNotifier<VideoPlayerController?>(null);

  VideoPlayerController? _controller;
  int _openSeq = 0;
  bool _disposed = false;

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Future<void> open(MediaRequest request) async {
    final seq = ++_openSeq;
    await _release();
    _emit(const PlaybackState(status: PlaybackStatus.opening));

    final controller = VideoPlayerController.networkUrl(
      request.uri,
      httpHeaders: request.headers,
      formatHint: _formatHint(request.uri),
    );

    try {
      await controller.initialize().timeout(connectTimeout);
    } on TimeoutException {
      unawaited(controller.dispose());
      throw const PlaybackException(PlaybackError.Rede, 'connect timeout 8s');
    } catch (error) {
      unawaited(controller.dispose());
      throw PlaybackException(PlaybackErrorMapper.fromObject(error), '$error');
    }

    if (seq != _openSeq || _disposed) {
      unawaited(controller.dispose());
      return;
    }

    _controller = controller;
    _current.value = controller;
    controller.addListener(_onControllerChanged);

    final start = request.startAt;
    if (!request.isLive && start != null && start > Duration.zero) {
      await controller.seekTo(start);
    }
    await controller.play();
    _onControllerChanged();
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async {
    if (!capabilities.supportsSeek) return;
    await _controller?.seekTo(position);
  }

  @override
  Future<List<AudioTrack>> audioTracks() async => const <AudioTrack>[];

  @override
  Future<void> selectAudioTrack(String id) async {}

  @override
  Future<void> setAudioDelay(Duration delay) async {}

  @override
  Future<void> stop() async {
    _openSeq++;
    await _release();
    _emit(PlaybackState.idle);
  }

  @override
  Widget buildView(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: _current,
      builder: (context, controller, _) {
        if (controller == null) return const SizedBox.expand();
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final ratio = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
            return Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: VideoPlayer(controller),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _openSeq++;
    await _release();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;

    if (value.hasError) {
      _emit(
        PlaybackState(
          status: PlaybackStatus.failed,
          position: value.position,
          duration: value.duration,
          error: PlaybackErrorMapper.fromDescription(value.errorDescription),
          errorDetail: value.errorDescription,
        ),
      );
      return;
    }

    final PlaybackStatus status;
    if (!value.isInitialized) {
      status = PlaybackStatus.opening;
    } else if (value.isBuffering) {
      status = PlaybackStatus.buffering;
    } else if (value.isPlaying) {
      status = PlaybackStatus.playing;
    } else if (value.duration > Duration.zero &&
        value.position >= value.duration) {
      status = PlaybackStatus.ended;
    } else {
      status = PlaybackStatus.paused;
    }

    _emit(
      PlaybackState(
        status: status,
        position: value.position,
        duration: value.duration,
      ),
    );
  }

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    _current.value = null;
    if (controller == null) return;
    controller.removeListener(_onControllerChanged);
    await controller.dispose();
  }

  void _emit(PlaybackState next) {
    if (_disposed) return;
    _state.value = next;
  }

  static VideoFormat? _formatHint(Uri uri) {
    final path = uri.path.toLowerCase();
    final output = (uri.queryParameters['output'] ?? '').toLowerCase();
    if (path.endsWith('.m3u8') || output == 'm3u8' || output == 'hls') {
      return VideoFormat.hls;
    }
    return null;
  }
}
