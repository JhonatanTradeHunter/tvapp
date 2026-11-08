import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/source/connection_tester.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/setup/setup_controller.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

class ImportProgressView extends StatelessWidget {
  const ImportProgressView({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final ImportProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.importing, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            SizedBox(
              width: 420,
              child: LinearProgressIndicator(value: progress.fraction),
            ),
            const SizedBox(height: 12),
            Text(
              l.importProgressDetail(
                progress.entries,
                _megabytes(progress.bytesRead),
              ),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            AppButton(
              label: l.cancel,
              icon: Icons.close,
              primary: false,
              autofocus: true,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botões "Testar conexão" e "Importar" com o relatório abaixo.
/// [buildSource] devolve null quando o formulário é inválido.
class SetupActionBar extends ConsumerWidget {
  const SetupActionBar({super.key, required this.buildSource});

  final PlaylistSource? Function() buildSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);
    final report = state.report;
    final error = state.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: state.phase == SetupPhase.testing
                  ? l.testing
                  : l.testConnection,
              icon: Icons.network_check,
              primary: false,
              onPressed: state.busy
                  ? null
                  : () {
                      final source = buildSource();
                      if (source != null) controller.test(source);
                    },
            ),
            AppButton(
              label: l.importAction,
              icon: Icons.download,
              onPressed: state.busy
                  ? null
                  : () {
                      final source = buildSource();
                      if (source != null) controller.importSource(source);
                    },
            ),
          ],
        ),
        if (state.phase == SetupPhase.testing) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (report != null) ...[
          const SizedBox(height: 16),
          ConnectionReportView(report: report),
        ] else if (error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(message: sourceErrorMessage(error, l)),
        ],
      ],
    );
  }
}

class ConnectionReportView extends StatelessWidget {
  const ConnectionReportView({super.key, required this.report});

  final ConnectionReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = report.statusCode;
    final type = report.contentType;
    final length = report.contentLength;
    final playlist = report.looksLikePlaylist;
    final error = report.error;
    final color = report.ok
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    final lines = <String>[
      if (status != null) l.reportStatus(status.toString()),
      if (type != null) l.reportContentType(type),
      if (length != null) l.reportSize(_megabytes(length)),
      l.reportElapsed(report.elapsed.inMilliseconds),
      if (playlist != null)
        playlist ? l.reportLooksLikePlaylist : l.reportNotPlaylist,
      if (report.headRejected) l.reportHeadFallback,
      if (error != null)
        sourceErrorMessage(SourceException(error, statusCode: status), l),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report.ok ? Icons.check_circle : Icons.error_outline,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                report.ok ? l.reportOk : l.reportFailed,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
