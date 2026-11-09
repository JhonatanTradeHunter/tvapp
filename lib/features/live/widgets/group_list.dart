import 'package:flutter/material.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class _GroupEntry {
  const _GroupEntry(this.filter, this.label, this.count);

  final GroupFilter filter;
  final String label;
  final int? count;
}

/// TV: lista vertical em que focar um grupo já filtra os canais.
/// Touch: chips horizontais.
class GroupList extends StatelessWidget {
  const GroupList({
    super.key,
    required this.groups,
    required this.selected,
    required this.onFocusGroup,
    required this.onSelectGroup,
  });

  final List<ChannelGroup> groups;
  final GroupFilter selected;
  final ValueChanged<GroupFilter> onFocusGroup;
  final ValueChanged<GroupFilter> onSelectGroup;

  List<_GroupEntry> _entries(AppLocalizations l) {
    var total = 0;
    for (final g in groups) {
      total += g.count;
    }
    return <_GroupEntry>[
      _GroupEntry(const GroupFilter.all(), l.allChannels, total),
      _GroupEntry(const GroupFilter.favorites(), l.favorites, null),
      _GroupEntry(const GroupFilter.recent(), l.recentChannels, null),
      for (final g in groups)
        _GroupEntry(
          GroupFilter.named(g.name),
          g.name.isEmpty ? l.ungrouped : g.name,
          g.count,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = _entries(l);
    return UiVariantScope.isTv(context)
        ? _buildVertical(context, entries)
        : _buildChips(context, entries);
  }

  Widget _buildVertical(BuildContext context, List<_GroupEntry> entries) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isSelected = entry.filter == selected;
        final count = entry.count;
        return Padding(
          key: ValueKey<String>(
            'group-${entry.filter.name}-${entry.filter.favoritesOnly}-'
            '${entry.filter.recent}',
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: FocusableScale(
            onSelect: () => onSelectGroup(entry.filter),
            onFocusChange: (focused) {
              if (focused) onFocusGroup(entry.filter);
            },
            semanticLabel: count == null
                ? entry.label
                : l.groupSemantics(entry.label, count),
            selected: isSelected,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isSelected
                    ? theme.colorScheme.secondaryContainer
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (count != null)
                    Text('$count', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChips(BuildContext context, List<_GroupEntry> entries) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ChoiceChip(
            label: Text(entry.label),
            selected: entry.filter == selected,
            onSelected: (_) => onSelectGroup(entry.filter),
          );
        },
      ),
    );
  }
}
