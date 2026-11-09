import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/channel_tile.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/guide/guide_controller.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Cabeçalho fixo com as marcas de meia em meia hora.
class GuideHeader extends StatelessWidget {
  const GuideHeader({super.key, required this.layout});

  final GuideLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.Hm(Localizations.localeOf(context).toString());
    return ClipRect(
      child: Stack(
        children: [
          for (final tick in layout.ticks(const Duration(minutes: 30)))
            Positioned(
              left: layout.xFor(tick),
              top: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  format.format(tick),
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma linha da grade: nome do canal fixo à esquerda e programas
/// posicionados pelo tempo. Sem programação, a linha inteira vira uma
/// célula focável que abre o canal ao vivo.
class GuideRow extends ConsumerWidget {
  const GuideRow({
    super.key,
    required this.channel,
    required this.window,
    required this.layout,
    required this.now,
    required this.nameWidth,
    required this.nodeFor,
    required this.onFocusCell,
    required this.onSelect,
  });

  final Channel channel;
  final GuideWindow window;
  final GuideLayout layout;
  final DateTime now;
  final double nameWidth;
  final FocusNode Function(String key) nodeFor;
  final void Function(Channel channel, List<ProgrammeRow> programmes, int index)
  onFocusCell;
  final void Function(Channel channel, ProgrammeRow? programme) onSelect;

  static String cellKey(Channel channel, ProgrammeRow? programme) =>
      '${channel.id}:${programme?.id ?? 'empty'}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final tv = UiVariantScope.isTv(context);
    final data = ref.watch(guideRowProvider((channel, window))).valueOrNull;
    final programmes = data?.programmes ?? const <ProgrammeRow>[];

    final cells = <Widget>[];
    for (var i = 0; i < programmes.length; i++) {
      final p = programmes[i];
      final box = layout.cellFor(p.startUtc, p.stopUtc);
      if (box == null) continue;
      final index = i;
      cells.add(
        Positioned(
          key: ValueKey<int>(p.id),
          left: box.$1,
          width: box.$2 - box.$1,
          top: 3,
          bottom: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: _ProgrammeCell(
              programme: p,
              now: now,
              focusNode: nodeFor(cellKey(channel, p)),
              onFocus: () => onFocusCell(channel, programmes, index),
              onSelect: () => onSelect(channel, p),
            ),
          ),
        ),
      );
    }
    if (cells.isEmpty) {
      cells.add(
        Positioned.fill(
          top: 3,
          bottom: 3,
          child: FocusableScale(
            focusNode: nodeFor(cellKey(channel, null)),
            onFocusChange: (focused) {
              if (focused) onFocusCell(channel, const <ProgrammeRow>[], -1);
            },
            onSelect: () => onSelect(channel, null),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            semanticLabel: l.guideNoProgramme,
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l.guideNoProgramme,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                ChannelLogo(url: channel.logo, size: tv ? 36 : 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${channel.displayNumber}  ${channel.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: Stack(clipBehavior: Clip.none, children: cells),
          ),
        ),
      ],
    );
  }
}

class _ProgrammeCell extends StatelessWidget {
  const _ProgrammeCell({
    required this.programme,
    required this.now,
    required this.focusNode,
    required this.onFocus,
    required this.onSelect,
  });

  final ProgrammeRow programme;
  final DateTime now;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final format = DateFormat.Hm(Localizations.localeOf(context).toString());
    final onAir = isOnAir(programme, now);
    final past = !programme.stopUtc.isAfter(now);
    final title = programme.title.isEmpty
        ? l.programmeUntitled
        : programme.title;
    final background = onAir
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final foreground = onAir
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return FocusableScale(
      focusNode: focusNode,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocus();
      },
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      semanticLabel: l.programmeSemantics(
        title,
        format.format(programme.startUtc.toLocal()),
        format.format(programme.stopUtc.toLocal()),
        onAir ? l.programmeOnAirShort : '',
      ),
      child: Opacity(
        opacity: past ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: foreground),
              ),
              Text(
                format.format(programme.startUtc.toLocal()),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
