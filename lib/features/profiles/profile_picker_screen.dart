import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/profiles/pin_pad.dart';
import 'package:tvapp/features/profiles/profiles_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

const List<Color> profileColors = <Color>[
  Color(0xFF3D7BFD),
  Color(0xFFE5484D),
  Color(0xFF30A46C),
  Color(0xFFF5A524),
  Color(0xFF8E4EC6),
  Color(0xFF12A594),
];

Color profileColor(int index) =>
    profileColors[index.abs() % profileColors.length];

/// Mostra [child] só com um perfil escolhido (e liberado, se tiver PIN).
/// Cria o perfil padrão na primeira vez e escolhe sozinho quando há um
/// único perfil sem PIN.
class ProfileGate extends ConsumerStatefulWidget {
  const ProfileGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends ConsumerState<ProfileGate> {
  bool _creatingDefault = false;

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider).valueOrNull;
    final active = ref.watch(activeProfileProvider);
    final notifier = ref.read(activeProfileIdProvider.notifier);
    const loading = Scaffold(body: Center(child: CircularProgressIndicator()));

    if (profiles == null) return loading;
    if (profiles.isEmpty) {
      if (!_creatingDefault) {
        _creatingDefault = true;
        final name = AppLocalizations.of(context).defaultProfileName;
        ref.read(databaseProvider).profileDao.ensureDefault(name);
      }
      return loading;
    }
    if (active != null &&
        (!profileHasPin(active) || notifier.isUnlocked(active.id))) {
      return widget.child;
    }
    final only = profiles.length == 1 ? profiles.first : null;
    if (active == null && only != null && !profileHasPin(only)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notifier.select(only.id);
      });
      return loading;
    }
    return const ProfilePickerScreen();
  }
}

class ProfilePickerScreen extends ConsumerWidget {
  const ProfilePickerScreen({super.key});

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    ProfileRow profile,
  ) async {
    final notifier = ref.read(activeProfileIdProvider.notifier);
    if (!profileHasPin(profile)) {
      notifier.select(profile.id);
      return;
    }
    final l = AppLocalizations.of(context);
    final pin = await showPinPad(
      context,
      title: l.pinForProfile(profile.name),
      validate: (value) => checkProfilePin(profile, value),
    );
    if (pin != null) notifier.select(profile.id, verified: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profiles =
        ref.watch(profilesProvider).valueOrNull ?? const <ProfileRow>[];
    final canManage = profiles.isNotEmpty && !profiles.every((p) => p.isKids);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.whoIsWatching, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < profiles.length; i++)
                      ProfileAvatar(
                        profile: profiles[i],
                        autofocus: i == 0,
                        onSelect: () => _choose(context, ref, profiles[i]),
                      ),
                  ],
                ),
                if (canManage) ...[
                  const SizedBox(height: 40),
                  AppButton(
                    label: l.manageProfiles,
                    icon: Icons.manage_accounts,
                    primary: false,
                    onPressed: () => openProfilesWithGuard(context, ref),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    required this.onSelect,
    this.autofocus = false,
  });

  final ProfileRow profile;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.name.isEmpty
        ? '?'
        : profile.name.characters.first.toUpperCase();
    return SizedBox(
      width: 132,
      child: FocusableScale(
        autofocus: autofocus,
        onSelect: onSelect,
        semanticLabel: profile.name,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: profileColor(profile.colorIndex),
                child: Text(
                  initial,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(
                height: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (profile.isKids) const Icon(Icons.child_care, size: 18),
                    if (profileHasPin(profile))
                      const Icon(Icons.lock_outline, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
