import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Detalhes de um programa que não está no ar. Com [onCatchup], a ação
/// principal reproduz o programa gravado; sem ela, abre o canal ao vivo.
/// [ended] mostra o aviso de arquivo indisponível quando não há catch-up.
Future<void> showProgrammeDetails(
  BuildContext context, {
  required Channel channel,
  required ProgrammeRow programme,
  required VoidCallback onWatchLive,
  VoidCallback? onCatchup,
  bool ended = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l = AppLocalizations.of(dialogContext);
      final theme = Theme.of(dialogContext);
      final locale = Localizations.localeOf(dialogContext).toString();
      final day = DateFormat.MMMEd(locale).format(programme.startUtc.toLocal());
      final time = DateFormat.Hm(locale);
      final range =
          '$day, ${time.format(programme.startUtc.toLocal())} - '
          '${time.format(programme.stopUtc.toLocal())}';
      final subtitle = programme.subtitle;
      final category = programme.category;
      final description = programme.description;

      return AlertDialog(
        title: Text(
          programme.title.isEmpty ? l.programmeUntitled : programme.title,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.name, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(range, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: theme.textTheme.titleSmall),
                ],
                if (category != null) ...[
                  const SizedBox(height: 4),
                  Text(category, style: theme.textTheme.labelMedium),
                ],
                if (description != null) ...[
                  const SizedBox(height: 12),
                  Text(description, style: theme.textTheme.bodyMedium),
                ],
                if (ended && onCatchup == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.catchupUnavailable,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (onCatchup != null)
            AppButton(
              label: l.watchCatchup,
              icon: Icons.replay,
              autofocus: true,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onCatchup();
              },
            ),
          AppButton(
            label: l.watchLive,
            icon: Icons.live_tv,
            primary: onCatchup == null,
            autofocus: onCatchup == null,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onWatchLive();
            },
          ),
          AppButton(
            label: l.close,
            primary: false,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}
