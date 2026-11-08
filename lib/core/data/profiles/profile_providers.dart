import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/profiles/parental_policy.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/util/pin.dart';

final profilesProvider = StreamProvider<List<ProfileRow>>(
  (ref) => ref.watch(databaseProvider).profileDao.watchAll(),
);

/// Perfil escolhido nesta sessão, lembrado entre aberturas. Nulo até a
/// escolha: a tela de perfis aparece quando há mais de um perfil ou PIN.
class ActiveProfileNotifier extends Notifier<int?> {
  @override
  int? build() => ref.read(appPrefsProvider).activeProfileId;

  void select(int? id) {
    state = id;
    ref.read(appPrefsProvider).setActiveProfileId(id);
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
