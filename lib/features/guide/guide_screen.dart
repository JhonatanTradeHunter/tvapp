import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/features/guide/guide_controller.dart';
import 'package:tvapp/features/guide/guide_grid.dart';
import 'package:tvapp/features/guide/programme_details.dart';
import 'package:tvapp/features/live/live_controller.dart';
import 'package:tvapp/features/live/player/player_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class _Cursor {
  const _Cursor(this.channel, this.programmes, this.index);

  final Channel channel;
  final List<ProgrammeRow> programmes;
  final int index;
}

/// Grade de programação. A janela visível anda pelo tempo em vez de rolar
/// na horizontal: esquerda/direita vão para o programa anterior/seguinte da
/// mesma linha e deslocam a janela quando ele está fora da tela. Cima/baixo
/// ficam com a navegação direcional padrão. Mesmos canais e grupo da tela
/// Ao vivo.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key, required this.onGoLive});

  final VoidCallback onGoLive;

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  static const Duration _step = Duration(minutes: 30);

  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  DateTime? _viewStart;
  _Cursor? _cursor;
  GuideLayout? _layout;
  GuideWindow? _window;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String key) =>
      _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'guide-$key'));

  Duration _span(BuildContext context) => UiVariantScope.isTv(context)
      ? const Duration(hours: 3)
      : const Duration(hours: 2);

  void _setViewStart(DateTime value) {
    final window = _window;
    final layout = _layout;
    if (window == null || layout == null) return;
    final clamped = GuideLayout.clampStart(value, window, layout.span);
    if (clamped != layout.viewStart) setState(() => _viewStart = clamped);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    return _moveHorizontal(key == LogicalKeyboardKey.arrowRight ? 1 : -1)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// true quando tratou; false deixa o evento subir (para a sidebar).
  bool _moveHorizontal(int delta) {
    final cursor = _cursor;
    final layout = _layout;
    final window = _window;
    if (cursor == null || layout == null || window == null) return false;

    final target = cursor.index + delta;
    if (target >= 0 && target < cursor.programmes.length) {
      final next = cursor.programmes[target];
      if (layout.visibleWidth(next.startUtc, next.stopUtc) < 60) {
        _setViewStart(
          delta > 0
              ? floorToHalfHour(next.startUtc).subtract(_step)
              : floorToHalfHour(next.startUtc),
        );
      }
      final node = _nodeFor(GuideRow.cellKey(cursor.channel, next));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });
      return true;
    }

    final shifted = delta > 0
        ? layout.viewStart.add(_step)
        : layout.viewStart.subtract(_step);
    final clamped = GuideLayout.clampStart(shifted, window, layout.span);
    if (clamped == layout.viewStart) return false;
    _setViewStart(clamped);
    return true;
  }

  void _play(Channel channel, List<Channel> all) {
    unawaited(
      ref
          .read(playbackControllerProvider.notifier)
          .playChannel(channel, playlist: all),
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen()));
  }

  void _select(
    Channel channel,
    ProgrammeRow? programme,
    List<Channel> all,
    DateTime now,
  ) {
    if (programme == null || isOnAir(programme, now)) {
      _play(channel, all);
      return;
    }
    unawaited(
      showProgrammeDetails(
        context,
        channel: channel,
        programme: programme,
        onWatchLive: () => _play(channel, all),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = UiVariantScope.isTv(context);
    final epgKey = ref.watch(activeEpgKeyProvider);
    final refresh = ref.watch(epgRefresherProvider);
    final channels = ref.watch(channelsProvider).valueOrNull;
    final now = ref.watch(epgMinuteProvider).valueOrNull ?? DateTime.now();
    final window = ref.watch(guideWindowProvider);
    final refreshing = refresh.phase == EpgRefreshPhase.running;

    if (epgKey == null) {
      return _NoGuide(
        refreshing: refreshing,
        failed: refresh.error != null,
        onGoLive: widget.onGoLive,
      );
    }
    if (channels == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (channels.isEmpty) {
      return EmptyState(
        icon: Icons.tv_off_outlined,
        title: l.noChannels,
        message: l.noChannelsHint,
      );
    }

    final nameWidth = tv ? 240.0 : 132.0;
    final rowHeight = tv ? 64.0 : 56.0;
    final span = _span(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = (constraints.maxWidth - nameWidth).clamp(
          120.0,
          double.infinity,
        );
        final start = GuideLayout.clampStart(
          _viewStart ?? floorToHalfHour(now).subtract(_step),
          window,
          span,
        );
        final layout = GuideLayout(
          viewStart: start,
          span: span,
          width: gridWidth,
        );
        _layout = layout;
        _window = window;
        final nowX = layout.xFor(now);
        final showNow = nowX >= 0 && nowX <= gridWidth;
        final day = DateFormat.MMMEd(
          Localizations.localeOf(context).toString(),
        ).format(start);

        Widget grid = Stack(
          children: [
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: ListView.builder(
                itemExtent: rowHeight,
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return GuideRow(
                    key: ValueKey<int>(channel.id),
                    channel: channel,
                    window: window,
                    layout: layout,
                    now: now,
                    nameWidth: nameWidth,
                    nodeFor: _nodeFor,
                    onFocusCell: (c, programmes, i) =>
                        _cursor = _Cursor(c, programmes, i),
                    onSelect: (c, p) => _select(c, p, channels, now),
                  );
                },
              ),
            ),
            if (showNow)
              Positioned(
                left: nameWidth + nowX - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: IgnorePointer(
                  child: ColoredBox(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );

        if (!tv) {
          grid = GestureDetector(
            onHorizontalDragUpdate: (details) {
              final minutes = -details.delta.dx * span.inMinutes / layout.width;
              _setViewStart(
                layout.viewStart.add(Duration(seconds: (minutes * 60).round())),
              );
            },
            child: grid,
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 3,
              child: refreshing ? const LinearProgressIndicator() : null,
            ),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  SizedBox(
                    width: nameWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        day,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                  Expanded(child: GuideHeader(layout: layout)),
                ],
              ),
            ),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}

class _NoGuide extends ConsumerWidget {
  const _NoGuide({
    required this.refreshing,
    required this.failed,
    required this.onGoLive,
  });

  final bool refreshing;
  final bool failed;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final row = ref.watch(activeSourceRowProvider).valueOrNull;
    final url = row?.epgUrl;
    if (url == null || url.isEmpty) {
      return EmptyState(
        icon: Icons.view_timeline_outlined,
        title: l.navGuide,
        message: l.guideNoUrl,
        actionLabel: l.goToLive,
        onAction: onGoLive,
        autofocusAction: true,
      );
    }
    if (refreshing) {
      return EmptyState(
        icon: Icons.downloading,
        title: l.guideUpdating,
        message: l.guideNoDataHint,
        actionLabel: l.goToLive,
        onAction: onGoLive,
        autofocusAction: true,
      );
    }
    return EmptyState(
      icon: Icons.view_timeline_outlined,
      title: failed ? l.guideRefreshFailed : l.guideNoData,
      message: l.guideNoDataHint,
      actionLabel: l.guideRefresh,
      onAction: () =>
          unawaited(ref.read(epgRefresherProvider.notifier).refreshNow()),
      autofocusAction: true,
    );
  }
}
