import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Linha "agora / a seguir" do EPG. Sem programa, mostra indisponível.
/// [approximate] marca casamento feito pelo nome, não pelo `tvg-id`.
class EpgPreviewRow extends StatelessWidget {
  const EpgPreviewRow({
    super.key,
    this.channelName,
    this.title,
    this.start,
    this.end,
    this.nextTitle,
    this.nextStart,
    this.approximate = false,
    this.now,
  });

  final String? channelName;
  final String? title;
  final DateTime? start;
  final DateTime? end;
  final String? nextTitle;
  final DateTime? nextStart;
  final bool approximate;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final programme = title;
    final from = start;
    final to = end;
    final name = channelName;
    final upcoming = nextTitle;
    final upcomingAt = nextStart;
    final format = DateFormat.Hm(Localizations.localeOf(context).toString());

    double? progress;
    String? timeRange;
    if (from != null && to != null && to.isAfter(from)) {
      final current = now ?? DateTime.now();
      final total = to.difference(from).inSeconds;
      final elapsed = current.difference(from).inSeconds;
      progress = (elapsed / total).clamp(0.0, 1.0);
      timeRange =
          '${format.format(from.toLocal())} - ${format.format(to.toLocal())}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (name != null)
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (approximate)
                Tooltip(
                  message: l.epgApproximate,
                  child: Icon(
                    Icons.link,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                    semanticLabel: l.epgApproximate,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            programme == null ? l.epgUnavailable : '${l.epgNow}: $programme',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (timeRange != null) ...[
            const SizedBox(height: 4),
            Text(timeRange, style: theme.textTheme.bodySmall),
          ],
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
          if (upcoming != null && upcomingAt != null) ...[
            const SizedBox(height: 8),
            Text(
              l.epgNext(format.format(upcomingAt.toLocal()), upcoming),
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
