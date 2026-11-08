import 'package:flutter/material.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/ui/components/channel_tile.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

String engineLabel(EngineKind kind) {
  switch (kind) {
    case EngineKind.exoPlayer:
      return 'ExoPlayer';
    case EngineKind.avPlayer:
      return 'AVPlayer';
    case EngineKind.mpv:
      return 'mpv';
    case EngineKind.web:
      return 'HTML5';
  }
}

/// Controles sobre o vídeo. Cada controle aparece só quando a engine
/// declara a capacidade correspondente.
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.state,
    required this.firstFocus,
    required this.onInteraction,
    required this.onClose,
    required this.onZap,
    required this.onTogglePause,
    required this.onToggleFavorite,
    required this.onSeek,
    this.onAudioTracks,
    this.onAudioDelay,
  });

  final PlayerViewState state;
  final FocusNode firstFocus;
  final VoidCallback onInteraction;
  final VoidCallback onClose;
  final ValueChanged<int> onZap;
  final VoidCallback onTogglePause;
  final VoidCallback onToggleFavorite;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onAudioTracks;
  final VoidCallback? onAudioDelay;

  VoidCallback _wrap(VoidCallback action) => () {
    onInteraction();
    action();
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final channel = state.channel;
    final engine = state.engine;
    final caps = state.capabilities;
    final playing = state.status == PlaybackStatus.playing;
    final live = state.isLive;
    final audioTracks = onAudioTracks;
    final audioDelay = onAudioDelay;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xDD000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (channel != null)
              Row(
                children: [
                  ChannelLogo(url: channel.logo, size: 56),
                  const SizedBox(width: 16),
                  if (live) ...[
                    Text(
                      '${channel.displayNumber}',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Text(
                      channel.name,
                      style: theme.textTheme.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (engine != null)
                    Text(
                      l.engineLabel(engineLabel(engine.kind)),
                      style: theme.textTheme.labelMedium,
                    ),
                ],
              ),
            if (state.canSeek) ...[
              const SizedBox(height: 12),
              _SeekBar(
                position: state.position,
                duration: state.duration,
                onSeek: (d) {
                  onInteraction();
                  onSeek(d);
                },
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (live)
                  _OverlayButton(
                    icon: Icons.skip_previous,
                    label: l.previousChannel,
                    focusNode: firstFocus,
                    onPressed: _wrap(() => onZap(-1)),
                  ),
                _OverlayButton(
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  label: playing ? l.pause : l.play,
                  focusNode: live ? null : firstFocus,
                  onPressed: _wrap(onTogglePause),
                ),
                if (live) ...[
                  _OverlayButton(
                    icon: Icons.skip_next,
                    label: l.nextChannel,
                    onPressed: _wrap(() => onZap(1)),
                  ),
                  _OverlayButton(
                    icon: (channel?.isFavorite ?? false)
                        ? Icons.star
                        : Icons.star_border,
                    label: l.favorite,
                    onPressed: _wrap(onToggleFavorite),
                  ),
                ],
                if (caps.supportsTrackSelection && audioTracks != null)
                  _OverlayButton(
                    icon: Icons.audiotrack,
                    label: l.audioTracks,
                    onPressed: _wrap(audioTracks),
                  ),
                if (caps.supportsAudioDelay && audioDelay != null)
                  _OverlayButton(
                    icon: Icons.av_timer,
                    label: l.audioDelay,
                    onPressed: _wrap(audioDelay),
                  ),
                _OverlayButton(
                  icon: Icons.close,
                  label: l.close,
                  onPressed: onClose,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableScale(
      focusNode: focusNode,
      onSelect: onPressed,
      semanticLabel: label,
      child: Container(
        width: 112,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();
    return Row(
      children: [
        Text(_format(position)),
        Expanded(
          child: Slider(
            value: total > 0 ? value : 0,
            max: total > 0 ? total : 1,
            onChanged: total > 0
                ? (v) => onSeek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
        Text(_format(duration)),
      ],
    );
  }
}
