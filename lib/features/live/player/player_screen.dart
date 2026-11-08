import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/models/playback_error.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/playback_error_mapper.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/toast.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/live/live_controller.dart';
import 'package:tvapp/features/live/player/player_overlay.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Back com overlay aberto fecha o overlay; back sem overlay sai do player.
/// Na TV, cima/baixo trocam de canal e OK abre o overlay.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const Duration _overlayTimeout = Duration(seconds: 5);
  static const Duration _seekStep = Duration(seconds: 10);
  static const Duration _delayStep = Duration(milliseconds: 50);

  final FocusNode _rootFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _overlayFocus = FocusNode(debugLabel: 'player-overlay');
  final FocusNode _retryFocus = FocusNode(debugLabel: 'player-retry');

  late final PlaybackController _player;
  late final bool _touch;
  StreamSubscription<PlayerEvent>? _events;
  Timer? _hideTimer;
  bool _overlay = false;
  Duration _audioDelay = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider.notifier);
    _touch = ref.read(deviceModeProvider) == DeviceMode.touch;
    _events = _player.events.listen(_onEvent);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_touch) {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _events?.cancel();
    _rootFocus.dispose();
    _overlayFocus.dispose();
    _retryFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_touch) SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onEvent(PlayerEvent event) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    AppToast.show(
      context,
      l.skippedChannel(
        event.from.name,
        describePlaybackError(event.reason, l),
        event.to.name,
      ),
      icon: Icons.skip_next,
    );
  }

  void _showOverlay() {
    setState(() => _overlay = true);
    _bumpOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlay) _overlayFocus.requestFocus();
    });
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    if (_overlay) setState(() => _overlay = false);
    _rootFocus.requestFocus();
  }

  void _toggleOverlay() => _overlay ? _hideOverlay() : _showOverlay();

  void _bumpOverlay() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_overlayTimeout, () {
      if (mounted && _overlay) _hideOverlay();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_overlay) {
      _bumpOverlay();
      return KeyEventResult.ignored;
    }
    final st = ref.read(playbackControllerProvider);
    if (st.status == PlaybackStatus.failed) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final zapUp =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp;
    final zapDown =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown;
    if (zapUp || zapDown) {
      if (st.isLive) {
        unawaited(_player.zap(zapUp ? -1 : 1));
      } else {
        _showOverlay();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (st.canSeek) {
        unawaited(
          _player.seekBy(
            key == LogicalKeyboardKey.arrowLeft ? -_seekStep : _seekStep,
          ),
        );
      } else {
        _showOverlay();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_player.togglePause());
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.contextMenu)) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _toggleFavorite() async {
    final channel = ref.read(playbackControllerProvider).channel;
    if (channel == null) return;
    final l = AppLocalizations.of(context);
    final added = await ref.read(liveActionsProvider).toggleFavorite(channel);
    if (!mounted) return;
    AppToast.show(
      context,
      added
          ? l.addedToFavorites(channel.name)
          : l.removedFromFavorites(channel.name),
    );
  }

  Future<void> _openAudioTracks(PlaybackEngine engine) async {
    final tracks = await engine.audioTracks();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l.audioTracks),
        children: tracks.isEmpty
            ? <Widget>[
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.noAudioTracks),
                ),
              ]
            : <Widget>[
                for (var i = 0; i < tracks.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: AppButton(
                      label: tracks[i].label,
                      primary: false,
                      autofocus: i == 0,
                      onPressed: () {
                        unawaited(engine.selectAudioTrack(tracks[i].id));
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  ),
              ],
      ),
    );
  }

  Future<void> _openAudioDelay(PlaybackEngine engine) async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void change(Duration delta) {
            setDialogState(() => _audioDelay += delta);
            unawaited(engine.setAudioDelay(_audioDelay));
          }

          return AlertDialog(
            title: Text(l.audioDelay),
            content: Text(
              l.audioDelayValue(_audioDelay.inMilliseconds),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            actions: [
              AppButton(
                label: '-50',
                primary: false,
                autofocus: true,
                onPressed: () => change(-_delayStep),
              ),
              AppButton(
                label: '+50',
                primary: false,
                onPressed: () => change(_delayStep),
              ),
              AppButton(
                label: l.close,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(playbackControllerProvider);

    ref.listen<PlaybackStatus>(
      playbackControllerProvider.select((s) => s.status),
      (previous, next) {
        if (next == PlaybackStatus.failed &&
            previous != PlaybackStatus.failed) {
          _hideTimer?.cancel();
          if (_overlay) setState(() => _overlay = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retryFocus.requestFocus();
          });
        } else if (previous == PlaybackStatus.failed &&
            next != PlaybackStatus.failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_overlay) _rootFocus.requestFocus();
          });
        }
      },
    );

    final engine = st.engine;
    final error = st.error;
    final channel = st.channel;

    Widget body = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (engine != null) engine.buildView(context),
        if (st.isBusy) const Center(child: CircularProgressIndicator()),
        if (st.status == PlaybackStatus.failed && error != null)
          _ErrorPanel(
            error: error,
            channelName: channel?.name ?? '',
            retryFocus: _retryFocus,
            onRetry: () => unawaited(_player.retry()),
            onNext: st.isLive ? () => unawaited(_player.zap(1)) : null,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_overlay && st.status != PlaybackStatus.failed)
          PlayerOverlay(
            state: st,
            firstFocus: _overlayFocus,
            onInteraction: _bumpOverlay,
            onClose: _hideOverlay,
            onZap: (delta) => unawaited(_player.zap(delta)),
            onTogglePause: () => unawaited(_player.togglePause()),
            onToggleFavorite: () => unawaited(_toggleFavorite()),
            onSeek: (position) => unawaited(_player.seekTo(position)),
            onAudioTracks: engine == null
                ? null
                : () => unawaited(_openAudioTracks(engine)),
            onAudioDelay: engine == null
                ? null
                : () => unawaited(_openAudioDelay(engine)),
          ),
      ],
    );

    if (!UiVariantScope.isTv(context)) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleOverlay,
        child: body,
      );
    }

    return PopScope(
      canPop: !_overlay,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_player.stop());
        } else {
          _hideOverlay();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: body,
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.error,
    required this.channelName,
    required this.retryFocus,
    required this.onRetry,
    required this.onNext,
    required this.onBack,
  });

  final PlaybackError error;
  final String channelName;
  final FocusNode retryFocus;
  final VoidCallback onRetry;

  /// Nulo fora do ao vivo: filme, episódio e catch-up não têm próximo canal.
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xE6101418),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l.playbackFailedTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(channelName, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Text(
              describePlaybackError(error, l),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                AppButton(
                  label: l.retry,
                  icon: Icons.refresh,
                  focusNode: retryFocus,
                  onPressed: onRetry,
                ),
                if (onNext != null)
                  AppButton(
                    label: l.nextChannel,
                    icon: Icons.skip_next,
                    primary: false,
                    onPressed: onNext,
                  ),
                AppButton(
                  label: l.back,
                  icon: Icons.arrow_back,
                  primary: false,
                  onPressed: onBack,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
