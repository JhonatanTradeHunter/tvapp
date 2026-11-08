import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/engine_selector.dart';
import 'package:tvapp/core/player/playback_engine.dart';

class PlayerViewState {
  const PlayerViewState({
    this.channel,
    this.engine,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
    this.isLive = true,
  });

  final Channel? channel;
  final PlaybackEngine? engine;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final PlaybackError? error;
  final bool isLive;

  EngineCapabilities get capabilities =>
      engine?.capabilities ?? EngineCapabilities.none;

  bool get canSeek => !isLive && capabilities.supportsSeek;

  bool get isBusy =>
      status == PlaybackStatus.opening || status == PlaybackStatus.buffering;

  PlayerViewState copyWith({
    Channel? channel,
    PlaybackEngine? engine,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    PlaybackError? error,
    bool clearError = false,
  }) {
    return PlayerViewState(
      channel: channel ?? this.channel,
      engine: engine ?? this.engine,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: clearError ? null : (error ?? this.error),
      isLive: isLive,
    );
  }
}

class PlayerEvent {
  const PlayerEvent({
    required this.reason,
    required this.from,
    required this.to,
  });

  final PlaybackError reason;
  final Channel from;
  final Channel to;
}

final engineSelectorProvider = Provider<EngineSelector>(
  (ref) => EngineSelector.forPlatform(defaultTargetPlatform),
);

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlayerViewState>(
      PlaybackController.new,
    );

/// Regras: timeout de conexão 8s (na engine), buffering acima de 15s conta
/// como falha, falha troca de engine preservando canal e posição, engines
/// esgotadas geram erro acionável e a segunda falha seguida no mesmo canal
/// pula para o próximo da lista com um evento para o toast.
class PlaybackController extends Notifier<PlayerViewState> {
  static const Duration bufferingLimit = Duration(seconds: 15);

  final StreamController<PlayerEvent> _events =
      StreamController<PlayerEvent>.broadcast();
  final Map<int, int> _failures = <int, int>{};

  PlaybackEngine? _engine;
  List<Channel> _playlist = const <Channel>[];
  List<EngineDescriptor> _candidates = const <EngineDescriptor>[];
  int _candidateIndex = 0;
  MediaRequest? _request;
  PlaybackError? _lastError;
  Timer? _watchdog;
  DateTime? _stalledSince;
  int _seq = 0;
  bool _opened = false;

  Stream<PlayerEvent> get events => _events.stream;

  @override
  PlayerViewState build() {
    ref.onDispose(() {
      _watchdog?.cancel();
      _engine?.state.removeListener(_onEngineState);
      unawaited(_engine?.dispose());
      unawaited(_events.close());
      unawaited(WakelockPlus.disable());
    });
    return const PlayerViewState();
  }

  Future<void> playChannel(Channel channel, {List<Channel>? playlist}) async {
    if (playlist != null) _playlist = List<Channel>.unmodifiable(playlist);
    final seq = ++_seq;
    _opened = false;
    _watchdog?.cancel();
    _lastError = null;

    final Uri uri;
    try {
      uri = Uri.parse(channel.playbackUrl);
    } on FormatException {
      _onChannelExhausted(seq, channel, PlaybackError.FonteInvalida);
      return;
    }

    _request = MediaRequest(uri: uri, headers: channel.httpHeaders);
    _candidates = ref
        .read(engineSelectorProvider)
        .candidatesFor(
          _request!,
          preferred: ref.read(appPrefsProvider).preferredEngine,
        );
    _candidateIndex = 0;
    state = PlayerViewState(
      channel: channel,
      engine: _engine,
      status: PlaybackStatus.opening,
    );
    unawaited(ref.read(appPrefsProvider).setLastChannelKey(channel.channelKey));
    await _tryCandidates(seq, channel, null);
  }

  Future<void> retry() async {
    final channel = state.channel;
    if (channel != null) await playChannel(channel);
  }

  Future<void> zap(int delta) async {
    final current = state.channel;
    if (current == null) return;
    final next = _neighbor(current, delta);
    if (next != null && next.id != current.id) await playChannel(next);
  }

  Future<void> togglePause() async {
    final engine = _engine;
    if (engine == null) return;
    if (state.status == PlaybackStatus.playing) {
      await engine.pause();
    } else if (state.status == PlaybackStatus.paused) {
      await engine.play();
    }
  }

  Future<void> seekBy(Duration delta) async {
    final engine = _engine;
    if (engine == null || !state.canSeek) return;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    await engine.seekTo(target);
  }

  Future<void> seekTo(Duration position) async {
    if (!state.canSeek) return;
    await _engine?.seekTo(position);
  }

  Future<void> stop() async {
    _seq++;
    _opened = false;
    _watchdog?.cancel();
    _watchdog = null;
    unawaited(WakelockPlus.disable());
    final engine = _engine;
    _engine = null;
    engine?.state.removeListener(_onEngineState);
    state = const PlayerViewState();
    await engine?.dispose();
  }

  Future<void> _tryCandidates(
    int seq,
    Channel channel,
    Duration? startAt,
  ) async {
    while (_candidateIndex < _candidates.length) {
      if (seq != _seq) return;
      final descriptor = _candidates[_candidateIndex];
      final engine = await _engineFor(descriptor);
      if (seq != _seq) return;
      state = state.copyWith(
        engine: engine,
        status: PlaybackStatus.opening,
        clearError: true,
      );
      try {
        await engine.open(_request!.withStart(startAt));
        if (seq != _seq) return;
        _startWatchdog(seq);
        unawaited(WakelockPlus.enable());
        return;
      } on PlaybackException catch (e) {
        if (seq != _seq) return;
        _lastError = e.error;
        _candidateIndex++;
      }
    }
    _onChannelExhausted(seq, channel, _lastError ?? PlaybackError.Desconhecido);
  }

  Future<PlaybackEngine> _engineFor(EngineDescriptor descriptor) async {
    final current = _engine;
    if (current != null && current.kind == descriptor.kind) return current;
    final next = descriptor.create();
    next.state.addListener(_onEngineState);
    _engine = next;
    if (current != null) {
      current.state.removeListener(_onEngineState);
      await current.dispose();
    }
    return next;
  }

  void _onEngineState() {
    final engine = _engine;
    if (engine == null) return;
    final s = engine.state.value;

    if (s.status == PlaybackStatus.playing) {
      _stalledSince = null;
      final id = state.channel?.id;
      if (id != null) _failures.remove(id);
    } else if (s.status == PlaybackStatus.buffering ||
        s.status == PlaybackStatus.opening) {
      _stalledSince ??= DateTime.now();
    } else {
      _stalledSince = null;
    }

    if (s.status == PlaybackStatus.failed) {
      if (_opened) _onRuntimeFailure(s.error ?? PlaybackError.Desconhecido);
      return;
    }
    state = state.copyWith(
      status: s.status,
      position: s.position,
      duration: s.duration,
    );
  }

  void _startWatchdog(int seq) {
    _opened = true;
    _stalledSince = null;
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (seq != _seq) return;
      final since = _stalledSince;
      if (since != null && DateTime.now().difference(since) > bufferingLimit) {
        _stalledSince = null;
        _onRuntimeFailure(PlaybackError.Rede);
      }
    });
  }

  void _onRuntimeFailure(PlaybackError error) {
    final channel = state.channel;
    if (channel == null || !_opened) return;
    _opened = false;
    _watchdog?.cancel();
    _lastError = error;
    _candidateIndex++;
    final resumeAt = state.isLive ? null : state.position;
    unawaited(_tryCandidates(_seq, channel, resumeAt));
  }

  void _onChannelExhausted(int seq, Channel channel, PlaybackError error) {
    if (seq != _seq) return;
    _opened = false;
    _watchdog?.cancel();

    final count = (_failures[channel.id] ?? 0) + 1;
    _failures[channel.id] = count;

    if (count >= 2) {
      final next = _neighbor(channel, 1);
      if (next != null && next.id != channel.id) {
        _failures.remove(channel.id);
        if (!_events.isClosed) {
          _events.add(PlayerEvent(reason: error, from: channel, to: next));
        }
        unawaited(playChannel(next));
        return;
      }
    }

    unawaited(WakelockPlus.disable());
    state = PlayerViewState(
      channel: channel,
      engine: _engine,
      status: PlaybackStatus.failed,
      error: error,
    );
  }

  Channel? _neighbor(Channel channel, int delta) {
    if (_playlist.isEmpty) return null;
    var index = -1;
    for (var i = 0; i < _playlist.length; i++) {
      if (_playlist[i].id == channel.id) {
        index = i;
        break;
      }
    }
    if (index < 0) return _playlist.first;
    final length = _playlist.length;
    return _playlist[((index + delta) % length + length) % length];
  }
}
