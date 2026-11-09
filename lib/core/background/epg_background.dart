import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_repository.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/prefs/app_prefs.dart';
import 'package:tvapp/core/data/secure/secret_store.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:workmanager/workmanager.dart';

/// Atualização do guia com o app fechado, só no Android. O iOS exigiria
/// BGTaskScheduler no projeto nativo, que hoje é gerado pelo CI.
class EpgBackground {
  EpgBackground._();

  static const String taskName = 'epg-refresh';
  static const Duration frequency = Duration(hours: 6);

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> schedule() async {
    if (!supported) return;
    await Workmanager().initialize(epgCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }
}

enum EpgTaskOutcome { appInUse, noSource, fresh, refreshed, failed }

/// Decide e executa uma rodada. Não roda com o app aberto (o heartbeat
/// cobre o player tocando) para não disputar a geração do EPG com a
/// atualização em primeiro plano.
Future<EpgTaskOutcome> runEpgTask({
  required AppDatabase db,
  required EpgRepository repository,
  required AppPrefs prefs,
  required DateTime now,
}) async {
  if (prefs.appInUse(now)) return EpgTaskOutcome.appInUse;
  final row = await db.sourceDao.watchActive().first;
  if (row == null) return EpgTaskOutcome.noSource;
  if (EpgRepository.needsMetadata(row)) {
    await repository.recoverMetadata(row.id);
  }
  final current = await db.sourceDao.byId(row.id);
  if (current == null || !repository.isStale(current, now)) {
    return EpgTaskOutcome.fresh;
  }
  try {
    await repository.refresh(row.id);
    return EpgTaskOutcome.refreshed;
  } on SourceException catch (e) {
    debugPrint('EPG em segundo plano: ${e.error}');
    return EpgTaskOutcome.failed;
  }
}

@pragma('vm:entry-point')
void epgCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase();
    try {
      final prefs = AppPrefs(await SharedPreferences.getInstance());
      await runEpgTask(
        db: db,
        repository: EpgRepository(
          db: db,
          secrets: SecureSecretStore(),
          importer: XmltvImporter(useIsolate: false),
        ),
        prefs: prefs,
        now: DateTime.now().toUtc(),
      );
    } catch (e) {
      debugPrint('EPG em segundo plano: $e');
    } finally {
      await db.close();
    }
    // Falha de rede não vira nova tentativa: a próxima rodada já vem em 6h.
    return true;
  });
}
