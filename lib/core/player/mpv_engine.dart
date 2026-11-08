import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/playback_error_mapper.dart';

/// mpv via `media_kit`. Abre MPEG-TS cru, permite escolher faixa de áudio e
/// ajustar o atraso. O timeout de rede é nativo (`network-timeout`), e há
/// também um limite de 8s até o primeiro quadro ou avanço de posição.
class MpvEngine implements PlaybackEngine {
  static const EngineCapabilities caps = EngineCapabilities(
    supportsSeek: true,
    supportsTrackSelection: true,
    supportsAudioDelay: true,
    supportsRawTs: true,
    supportsBufferTuning: true,
  );

  static const Duration connectTimeout = Duration(seconds: 8);
  static const int _cacheBytes = 32 * 1024 * 1024;

  static bool isSupportedOn(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );
  final ValueNotifier<mkv.VideoController?> _video =
      ValueNotifier<mkv.VideoController?>(null);
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  mk.Player? _player;
  int _openSeq = 0;
  bool _opened = false;
  bool _disposed = false;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _audioDelay = Duration.zero;

  @override
  EngineKind get kind => EngineKind.mpv;

  @override
  EngineCapabilities get capabilities => caps;

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Future<void> open(MediaRequest request) async {
    final seq = ++_openSeq;
    final player = await _ensurePlayer();
    _opened = false;
    _playing = false;
    _buffering = false;
    _completed = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _emit(const PlaybackState(status: PlaybackStatus.opening));

    final ready = Completer<void>();
    // O erro pode chegar enquanto player.open ainda roda, antes de alguém
    // escutar ready.future. Sem isso ele vira erro não tratado na zona.
    ready.future.ignore();
    void succeed() {
      if (!ready.isCompleted) ready.complete();
    }

    final watchers = <StreamSubscription<Object?>>[
      player.stream.position.listen((p) {
        if (p > Duration.zero) succeed();
      }),
      player.stream.width.listen((w) {
        if (w != null && w > 0) succeed();
      }),
      player.stream.error.listen((message) {
        if (!ready.isCompleted) {
          ready.completeError(
            PlaybackException(
              PlaybackErrorMapper.fromDescription(message),
              message,
            ),
          );
        }
      }),
    ];

    try {
      await player.open(
        mk.Media(request.uri.toString(), httpHeaders: request.headers),
        play: true,
      );
      await ready.future.timeout(connectTimeout);
    } on TimeoutException {
      await player.stop();
      throw const PlaybackException(PlaybackError.Rede, 'connect timeout 8s');
    } on PlaybackException {
      await player.stop();
      rethrow;
    } catch (error) {
      await player.stop();
      throw PlaybackException(PlaybackErrorMapper.fromObject(error), '$error');
    } finally {
      for (final watcher in watchers) {
        await watcher.cancel();
      }
    }

    if (seq != _openSeq || _disposed) return;
    _opened = true;

    final start = request.startAt;
    if (!request.isLive && start != null && start > Duration.zero) {
      await player.seek(start);
    }
    if (_audioDelay != Duration.zero) await _applyAudioDelay(player);
    _emitCurrent();
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seekTo(Duration position) async => _player?.seek(position);

  @override
  Future<List<AudioTrack>> audioTracks() async {
    final player = _player;
    if (player == null) return const <AudioTrack>[];
    return <AudioTrack>[
      for (final t in player.state.tracks.audio)
        if (t.id != 'auto' && t.id != 'no')
          AudioTrack(
            id: t.id,
            label: t.title ?? t.language ?? t.id,
            language: t.language,
          ),
    ];
  }

  @override
  Future<void> selectAudioTrack(String id) async {
    final player = _player;
    if (player == null) return;
    for (final t in player.state.tracks.audio) {
      if (t.id == id) {
        await player.setAudioTrack(t);
        return;
      }
    }
  }

  @override
  Future<void> setAudioDelay(Duration delay) async {
    _audioDelay = delay;
    final player = _player;
    if (player != null) await _applyAudioDelay(player);
  }

  @override
  Future<void> stop() async {
    _openSeq++;
    _opened = false;
    await _player?.stop();
    _emit(PlaybackState.idle);
  }

  @override
  Widget buildView(BuildContext context) {
    return ValueListenableBuilder<mkv.VideoController?>(
      valueListenable: _video,
      builder: (context, controller, _) {
        if (controller == null) return const SizedBox.expand();
        return mkv.Video(
          controller: controller,
          // NoVideoControls é declarado como `const = null` (tipo dynamic);
          // null direto desliga os controles e passa no tipo.
          controls: null,
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _openSeq++;
    _opened = false;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _video.value = null;
    await player?.dispose();
  }

  Future<mk.Player> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;

    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(bufferSize: _cacheBytes),
    );
    _player = player;
    await _setProperty(player, 'network-timeout', '${connectTimeout.inSeconds}');
    await _setProperty(player, 'cache', 'yes');
    await _setProperty(player, 'cache-secs', '15');
    await _setProperty(player, 'demuxer-readahead-secs', '15');
    _video.value = mkv.VideoController(player);

    _subscriptions.addAll(<StreamSubscription<Object?>>[
      player.stream.playing.listen((v) {
        _playing = v;
        if (v) _completed = false;
        _emitCurrent();
      }),
      player.stream.buffering.listen((v) {
        _buffering = v;
        _emitCurrent();
      }),
      player.stream.position.listen((v) {
        _position = v;
        _emitCurrent();
      }),
      player.stream.duration.listen((v) {
        _duration = v;
        _emitCurrent();
      }),
      player.stream.completed.listen((v) {
        _completed = v;
        _emitCurrent();
      }),
      player.stream.error.listen((message) {
        if (!_opened) return;
        _emit(PlaybackState(
          status: PlaybackStatus.failed,
          position: _position,
          duration: _duration,
          error: PlaybackErrorMapper.fromDescription(message),
          errorDetail: message,
        ));
      }),
    ]);
    return player;
  }

  Future<void> _applyAudioDelay(mk.Player player) {
    final seconds = (_audioDelay.inMilliseconds / 1000).toStringAsFixed(3);
    return _setProperty(player, 'audio-delay', seconds);
  }

  static Future<void> _setProperty(
    mk.Player player,
    String name,
    String value,
  ) async {
    // VERIFICAR: NativePlayer exportado por package:media_kit/media_kit.dart
    // e setProperty(String, String) disponível na versão resolvida.
    final platform = player.platform;
    if (platform is mk.NativePlayer) await platform.setProperty(name, value);
  }

  void _emitCurrent() {
    if (!_opened) return;
    final PlaybackStatus status;
    if (_completed) {
      status = PlaybackStatus.ended;
    } else if (_buffering) {
      status = PlaybackStatus.buffering;
    } else if (_playing) {
      status = PlaybackStatus.playing;
    } else {
      status = PlaybackStatus.paused;
    }
    _emit(PlaybackState(
      status: status,
      position: _position,
      duration: _duration,
    ));
  }

  void _emit(PlaybackState next) {
    if (_disposed) return;
    _state.value = next;
  }
}
