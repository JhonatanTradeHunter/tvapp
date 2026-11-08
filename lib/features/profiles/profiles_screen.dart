import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/profiles/pin_pad.dart';
import 'package:tvapp/features/profiles/profile_edit_screen.dart';
import 'package:tvapp/features/profiles/profile_picker_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Abre a gestão de perfis. Se algum perfil adulto tem PIN, pede um PIN de
/// responsável antes, para o perfil infantil não mexer nas próprias regras.
Future<void> openProfilesWithGuard(BuildContext context, WidgetRef ref) async {
  final profiles =
      ref.read(profilesProvider).valueOrNull ?? const <ProfileRow>[];
  if (hasGuardianPin(profiles)) {
    final l = AppLocalizations.of(context);
    final pin = await showPinPad(
      context,
      title: l.pinEnterTitle,
      subtitle: l.guardianPinHint,
      validate: (value) => checkGuardianPin(profiles, value),
    );
    if (pin == null || !context.mounted) return;
  }
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ProfilesScreen()));
}

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  void _edit(BuildContext context, int? profileId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileEditScreen(profileId: profileId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final profiles =
        ref.watch(profilesProvider).valueOrNull ?? const <ProfileRow>[];
    return Scaffold(
      appBar: AppBar(title: Text(l.profilesTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (var i = 0; i < profiles.length; i++)
                    ProfileAvatar(
                      profile: profiles[i],
                      autofocus: i == 0,
                      onSelect: () => _edit(context, profiles[i].id),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              AppButton(
                label: l.addProfile,
                icon: Icons.person_add_alt,
                onPressed: () => _edit(context, null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
