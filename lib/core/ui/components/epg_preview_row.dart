import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Linha "agora" do EPG. Na fase 1 não há guia, então mostra o estado
/// indisponível; a fase 2 passa título e horários.
class EpgPreviewRow extends StatelessWidget {
  const EpgPreviewRow({
    super.key,
    this.channelName,
    this.title,
    this.start,
    this.end,
    this.now,
  });

  final String? channelName;
  final String? title;
  final DateTime? start;
  final DateTime? end;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final programme = title;
    final from = start;
    final to = end;
    final name = channelName;

    double? progress;
    if (from != null && to != null && to.isAfter(from)) {
      final current = now ?? DateTime.now();
      final total = to.difference(from).inSeconds;
      final elapsed = current.difference(from).inSeconds;
      progress = (elapsed / total).clamp(0.0, 1.0);
    }

    String? timeRange;
    if (from != null && to != null) {
      final format = DateFormat.Hm(Localizations.localeOf(context).toString());
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
          if (name != null)
            Text(name, style: theme.textTheme.labelLarge, maxLines: 1),
          const SizedBox(height: 4),
          Text(
            programme ?? l.epgUnavailable,
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
        ],
      ),
    );
  }
}
