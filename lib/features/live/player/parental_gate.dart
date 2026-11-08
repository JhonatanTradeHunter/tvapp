import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_providers.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/profiles/pin_pad.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Programa no ar no [channel] que o perfil ativo não pode ver pela
/// classificação; null quando não há bloqueio (ou não há EPG).
final restrictedProgrammeProvider = Provider.autoDispose
    .family<ProgrammeRow?, Channel>((ref, channel) {
      final policy = ref.watch(parentalPolicyProvider);
      if (!policy.isKids || policy.maxAge == null) return null;
      final current = ref.watch(nowNextProvider(channel)).valueOrNull?.current;
      if (current == null || policy.allowsProgramme(current.ageRating)) {
        return null;
      }
      return current;
    });

/// Pede o PIN de responsável. true quando foi digitado certo.
Future<bool> askGuardianPin(BuildContext context, WidgetRef ref) async {
  final profiles =
      ref.read(profilesProvider).valueOrNull ?? const <ProfileRow>[];
  if (!hasGuardianPin(profiles)) return false;
  final l = AppLocalizations.of(context);
  final pin = await showPinPad(
    context,
    title: l.parentalUnlock,
    subtitle: l.guardianPinHint,
    validate: (value) => checkGuardianPin(profiles, value),
  );
  return pin != null;
}

class ParentalBlockPanel extends ConsumerWidget {
  const ParentalBlockPanel({
    super.key,
    required this.programme,
    required this.focusNode,
    required this.onUnlock,
    required this.onBack,
    this.onNext,
  });

  final ProgrammeRow programme;
  final FocusNode focusNode;
  final VoidCallback onUnlock;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profiles =
        ref.watch(profilesProvider).valueOrNull ?? const <ProfileRow>[];
    final canUnlock = hasGuardianPin(profiles);
    final next = onNext;
    final age = programme.ageRating ?? 18;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xE6101418),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 12),
            Text(l.parentalBlockedTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              l.parentalBlockedMessage(programme.title, age),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (!canUnlock) ...[
              const SizedBox(height: 8),
              Text(
                l.parentalNoGuardian,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (canUnlock)
                  AppButton(
                    label: l.parentalUnlock,
                    icon: Icons.lock_open,
                    focusNode: focusNode,
                    onPressed: onUnlock,
                  ),
                if (next != null)
                  AppButton(
                    label: l.nextChannel,
                    icon: Icons.skip_next,
                    primary: !canUnlock,
                    focusNode: canUnlock ? null : focusNode,
                    onPressed: next,
                  ),
                AppButton(
                  label: l.back,
                  icon: Icons.arrow_back,
                  primary: false,
                  focusNode: canUnlock || next != null ? null : focusNode,
                  onPressed: onBack,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
