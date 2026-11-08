import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/theme/app_theme.dart';
import 'package:tvapp/features/demo/demo_bootstrap.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Abre o banco e importa a demonstração mostrando o progresso; se falhar
/// ou estourar o tempo, mostra o motivo em vez de uma tela vazia.
class DemoBoot extends StatefulWidget {
  const DemoBoot({super.key, required this.mode, required this.builder});

  final DeviceMode mode;
  final Widget Function(AppDatabase db) builder;

  @override
  State<DemoBoot> createState() => _DemoBootState();
}

class _DemoBootState extends State<DemoBoot> {
  late final Future<AppDatabase> _ready = _open();

  Future<AppDatabase> _open() async {
    final db = AppDatabase();
    try {
      await DemoBootstrap.run(db);
      return db;
    } catch (_) {
      unawaited(db.close().catchError((Object _) {}));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDatabase>(
      future: _ready,
      builder: (context, snap) {
        final db = snap.data;
        if (db != null) return widget.builder(db);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(widget.mode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: snap.hasError
              ? _BootError(error: snap.error!)
              : const _BootProgress(),
        );
      },
    );
  }
}

class _BootProgress extends StatelessWidget {
  const _BootProgress();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.demoLoading),
          ],
        ),
      ),
    );
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail =
        error is TimeoutException ||
            error.toString().contains('TimeoutException')
        ? l10n.demoOpenTimeout
        : error.toString();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.demoOpenFailed,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(detail, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
