import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/profiles/parental_policy.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/util/pin.dart';

final profilesProvider = StreamProvider<List<ProfileRow>>(
  (ref) => ref.watch(databaseProvider).profileDao.watchAll(),
);

/// Perfil escolhido, lembrado entre aberturas. Perfil com PIN precisa ser
/// liberado de novo a cada sessão: [isUnlocked] só vale para quem digitou o
/// PIN desde que o app abriu.
class ActiveProfileNotifier extends Notifier<int?> {
  final Set<int> _unlocked = <int>{};

  @override
  int? build() => ref.read(appPrefsProvider).activeProfileId;

  bool isUnlocked(int id) => _unlocked.contains(id);

  void select(int id, {bool verified = false}) {
    if (verified) _unlocked.add(id);
    state = id;
    ref.read(appPrefsProvider).setActiveProfileId(id);
  }

  /// Volta para a escolha de perfil e exige o PIN outra vez.
  void signOut() {
    _unlocked.clear();
    state = null;
    ref.read(appPrefsProvider).setActiveProfileId(null);
  }
}

final activeProfileIdProvider = NotifierProvider<ActiveProfileNotifier, int?>(
  ActiveProfileNotifier.new,
);

final activeProfileProvider = Provider<ProfileRow?>((ref) {
  final id = ref.watch(activeProfileIdProvider);
  final profiles = ref.watch(profilesProvider).valueOrNull;
  if (id == null || profiles == null) return null;
  for (final p in profiles) {
    if (p.id == id) return p;
  }
  return null;
});

final blockedGroupsProvider = StreamProvider.family<Set<String>, BlockedKind>((
  ref,
  kind,
) {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) return Stream.value(const <String>{});
  return ref.watch(databaseProvider).profileDao.watchBlocked(profile.id, kind);
});

final parentalPolicyProvider = Provider<ParentalPolicy>((ref) {
  final profile = ref.watch(activeProfileProvider);
  Set<String> blocked(BlockedKind kind) =>
      ref.watch(blockedGroupsProvider(kind)).valueOrNull ?? const <String>{};
  return ParentalPolicy(
    isKids: profile?.isKids ?? false,
    maxAge: profile?.maxAge,
    blockedLive: blocked(BlockedKind.live),
    blockedVod: blocked(BlockedKind.vod),
    blockedSeries: blocked(BlockedKind.series),
  );
});

bool profileHasPin(ProfileRow profile) =>
    profile.pinHash != null && profile.pinSalt != null;

bool checkProfilePin(ProfileRow profile, String pin) {
  final hash = profile.pinHash;
  final salt = profile.pinSalt;
  if (hash == null || salt == null) return true;
  return PinHasher.verify(pin, salt, hash);
}

/// PIN de responsável: qualquer perfil adulto com PIN libera um bloqueio
/// do infantil. Sem nenhum, o bloqueio não tem como ser liberado.
bool checkGuardianPin(List<ProfileRow> profiles, String pin) {
  for (final p in profiles) {
    if (!p.isKids && profileHasPin(p) && checkProfilePin(p, pin)) return true;
  }
  return false;
}

bool hasGuardianPin(List<ProfileRow> profiles) =>
    profiles.any((p) => !p.isKids && profileHasPin(p));
