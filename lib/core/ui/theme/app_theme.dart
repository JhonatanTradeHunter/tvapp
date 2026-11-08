import 'package:flutter/material.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';

class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF3D7BFD);
  static const Color _background = Color(0xFF0E1116);

  static ThemeData build(DeviceMode mode) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: mode == DeviceMode.tv
          ? VisualDensity.standard
          : VisualDensity.adaptivePlatformDensity,
    );
    return base.copyWith(
      scaffoldBackgroundColor: _background,
      focusColor: scheme.primary.withValues(alpha: 0.24),
      textTheme: mode == DeviceMode.tv
          ? base.textTheme.apply(fontSizeFactor: 1.1)
          : base.textTheme,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
