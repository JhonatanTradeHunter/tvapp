import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/app.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/features/demo/demo_bootstrap.dart';
import 'package:tvapp/features/demo/demo_xtream_client.dart';
import 'package:tvapp/features/vod/vod_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final mode = await DeviceModeDetector.detect();

  AppDatabase? demoDb;
  if (kDemo) {
    demoDb = AppDatabase();
    await DemoBootstrap.run(demoDb);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceModeProvider.overrideWithValue(mode),
        if (demoDb != null) ...[
          databaseProvider.overrideWithValue(demoDb),
          xtreamClientProvider.overrideWithValue(DemoXtreamClient()),
        ],
      ],
      child: const TvApp(),
    ),
  );
}
