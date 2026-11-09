import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:tvapp/core/data/db/daos/history_dao.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
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
/// O que entra no histórico do perfil ao começar a tocar.
class HistoryMark {
  const HistoryMark({
    required this.kind,
    required this.itemKey,
    required this.title,
    this.image,
  });

  final HistoryKind kind;
  final String itemKey;
  final String title;
  final String? image;
}

class PlaybackController extends Notifier<PlayerViewState> {
  static const Duration bufferingLimit = Duration(seconds: 15);
  static const Duration positionInterval = Duration(seconds: 5);

  final StreamController<PlayerEvent> _events =
      StreamController<PlayerEvent>.broadcast();
  final Map<int, int> _failures = <int, int>{};

  PlaybackEngine? _engine;
  List<Channel> _playlist = const <Channel>[];
  List<EngineDescriptor> _candidates = const <EngineDescriptor>[];
  int _candidateIndex = 0;
  MediaRequest? _request;
  Uri? _catchupUri;
  String? _positionKey;
  Timer? _positionTimer;
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
      _positionTimer?.cancel();
      _engine?.state.removeListener(_onEngineState);
      unawaited(_engine?.dispose());
      unawaited(_events.close());
      unawaited(WakelockPlus.disable());
    });
    return const PlayerViewState();
  }

  Future<void> playChannel(Channel channel, {List<Channel>? playlist}) async {
    if (playlist != null) _playlist = List<Channel>.unmodifiable(playlist);
    await _flushPosition();
    _catchupUri = null;
    _positionKey = null;
    final seq = ++_seq;
    final Uri uri;
    try {
      uri = Uri.parse(channel.playbackUrl);
    } on FormatException {
      _resetAttempt();
      state = PlayerViewState(channel: channel, engine: _engine);
      _onChannelExhausted(seq, channel, PlaybackError.FonteInvalida);
      return;
    }
    unawaited(ref.read(appPrefsProvider).setLastChannelKey(channel.channelKey));
    _recordHistory(
      channel.sourceId,
      HistoryMark(
        kind: HistoryKind.live,
        itemKey: channel.channelKey,
        title: channel.name,
        image: channel.logo,
      ),
    );
    await _start(seq, channel, uri, isLive: true);
  }

  /// Reproduz um programa passado (catch-up) do canal. É tratado como VOD:
  /// tem seekbar e, se falhar, mostra o erro sem pular para outro canal.
  Future<void> playCatchup(
    Channel channel,
    Uri uri, {
    List<Channel>? playlist,
  }) async {
    if (playlist != null) _playlist = List<Channel>.unmodifiable(playlist);
    await _flushPosition();
    _catchupUri = uri;
    _positionKey = null;
    final seq = ++_seq;
    await _start(seq, channel, uri, isLive: false);
  }

  /// Filme ou episódio. A posição vai para o banco a cada
  /// [positionInterval] e ao sair, sob `item.channelKey`. Filmes entram no
  /// histórico sozinhos; episódios passam a série em [history].
  Future<void> playVod(
    Channel item,
    Uri uri, {
    Duration? resumeAt,
    HistoryMark? history,
  }) async {
    final mark =
        history ??
        (item.channelKey.startsWith('movie|')
            ? HistoryMark(
                kind: HistoryKind.movie,
                itemKey: item.channelKey,
                title: item.name,
                image: item.logo,
              )
            : null);
    if (mark != null) _recordHistory(item.sourceId, mark);
    await _flushPosition();
    _playlist = const <Channel>[];
    _catchupUri = uri;
    _positionKey = item.channelKey;
    final seq = ++_seq;
    await _start(seq, item, uri, isLive: false, startAt: resumeAt);
  }

  void _recordHistory(int sourceId, HistoryMark mark) {
    final profileId = ref.read(activeProfileIdProvider);
    if (profileId == null) return;
    unawaited(
      ref
          .read(databaseProvider)
          .historyDao
          .record(
            profileId: profileId,
            sourceId: sourceId,
            kind: mark.kind,
            itemKey: mark.itemKey,
            title: mark.title,
            image: mark.image,
          )
          .catchError((Object e) => debugPrint('histórico: $e')),
    );
  }

  Future<void> _flushPosition() async {
    final key = _positionKey;
    final channel = state.channel;
    if (key == null || channel == null) return;
    if (state.duration <= Duration.zero) return;
    await ref
        .read(databaseProvider)
        .positionDao
        .save(channel.sourceId, key, state.position, state.duration);
  }

  void _startPositionTimer(int seq) {
    _positionTimer?.cancel();
    if (_positionKey == null) return;
    _positionTimer = Timer.periodic(positionInterval, (_) {
      if (seq != _seq) return;
      if (state.status == PlaybackStatus.playing) unawaited(_flushPosition());
    });
  }

  void _resetAttempt() {
    _opened = false;
    _watchdog?.cancel();
    _lastError = null;
  }

  Future<void> _start(
    int seq,
    Channel channel,
    Uri uri, {
    required bool isLive,
    Duration? startAt,
  }) async {
    _resetAttempt();
    _request = MediaRequest(
      uri: uri,
      headers: channel.httpHeaders,
      isLive: isLive,
    );
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
      isLive: isLive,
    );
    _startPositionTimer(seq);
    await _tryCandidates(seq, channel, startAt);
  }

  Future<void> retry() async {
    final channel = state.channel;
    if (channel == null) return;
    final catchup = _catchupUri;
    if (catchup != null && _positionKey != null) {
      await playVod(channel, catchup, resumeAt: state.position);
    } else if (catchup != null) {
      await playCatchup(channel, catchup);
    } else {
      await playChannel(channel);
    }
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

  /// Para a reprodução mas mantém o canal na tela, para o bloqueio por
  /// classificação: [retry] volta a tocar o mesmo canal depois do PIN.
  Future<void> halt() async {
    _seq++;
    _opened = false;
    _watchdog?.cancel();
    unawaited(WakelockPlus.disable());
    final engine = _engine;
    _engine = null;
    engine?.state.removeListener(_onEngineState);
    state = PlayerViewState(channel: state.channel, isLive: state.isLive);
    await engine?.dispose();
  }

  Future<void> stop() async {
    await _flushPosition();
    _positionTimer?.cancel();
    _positionTimer = null;
    _positionKey = null;
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

    if (count >= 2 && state.isLive) {
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
      isLive: state.isLive,
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
