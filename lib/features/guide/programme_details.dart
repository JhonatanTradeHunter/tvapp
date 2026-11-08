import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Detalhes de um programa que não está no ar. A ação principal abre o
/// canal ao vivo; o catch-up entra aqui quando estiver disponível.
Future<void> showProgrammeDetails(
  BuildContext context, {
  required Channel channel,
  required ProgrammeRow programme,
  required VoidCallback onWatchLive,
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
              ],
            ),
          ),
        ),
        actions: [
          AppButton(
            label: l.watchLive,
            icon: Icons.live_tv,
            autofocus: true,
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
