import 'package:flutter/material.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class SortSelector extends StatelessWidget {
  const SortSelector({super.key, required this.sort, required this.onChanged});

  final LiveSort sort;
  final ValueChanged<LiveSort> onChanged;

  static String labelFor(LiveSort sort, AppLocalizations l) {
    switch (sort) {
      case LiveSort.number:
        return l.sortNumber;
      case LiveSort.alpha:
        return l.sortAlpha;
      case LiveSort.favorites:
        return l.sortFavorites;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!UiVariantScope.isTv(context)) {
      return SegmentedButton<LiveSort>(
        segments: <ButtonSegment<LiveSort>>[
          for (final option in LiveSort.values)
            ButtonSegment<LiveSort>(
              value: option,
              label: Text(labelFor(option, l)),
            ),
        ],
        selected: <LiveSort>{sort},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      );
    }

    final theme = Theme.of(context);
    return Row(
      children: [
        Text(l.sortLabel, style: theme.textTheme.labelLarge),
        const SizedBox(width: 12),
        for (final option in LiveSort.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FocusableScale(
              onSelect: () => onChanged(option),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              semanticLabel: labelFor(option, l),
              selected: option == sort,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  color: option == sort
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHigh,
                ),
                child: Text(
                  labelFor(option, l),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
