import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/app.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final mode = await DeviceModeDetector.detect();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceModeProvider.overrideWithValue(mode),
      ],
      child: const TvApp(),
    ),
  );
}
