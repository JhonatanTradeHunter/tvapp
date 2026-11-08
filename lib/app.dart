import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/ui/adaptive/adaptive_root.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';
import 'package:tvapp/core/ui/theme/app_theme.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class TvApp extends ConsumerWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(deviceModeProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(mode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => UiVariantScope(
        mode: mode,
        child: TvShortcuts(
          enabled: mode == DeviceMode.tv,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const AdaptiveRoot(),
    );
  }
}
