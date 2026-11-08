import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/prefs/app_prefs.dart';
import 'package:tvapp/core/data/source/connection_tester.dart';
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/source/source_repository.dart';
import 'package:tvapp/core/models/playlist_source.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Sobrescrito em main()'),
);

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final playlistLoaderProvider = Provider<PlaylistLoader>(
  (ref) => PlaylistLoader(),
);

final connectionTesterProvider = Provider<ConnectionTester>(
  (ref) => ConnectionTester(),
);

final sourceRepositoryProvider = Provider<SourceRepository>(
  (ref) => SourceRepository(
    db: ref.watch(databaseProvider),
    loader: ref.watch(playlistLoaderProvider),
  ),
);

final activeSourceProvider = StreamProvider<PlaylistSource?>(
  (ref) => ref.watch(sourceRepositoryProvider).watchActive(),
);

/// (sourceId, geração ativa). Muda só quando a fonte ou a geração muda,
/// então as listas não reassinam a cada escrita na tabela de fontes.
final activeListingKeyProvider = Provider<(int, int)?>((ref) {
  final source = ref.watch(activeSourceProvider).valueOrNull;
  final id = source?.id;
  if (source == null || id == null) return null;
  return (id, source.activeGeneration);
});
