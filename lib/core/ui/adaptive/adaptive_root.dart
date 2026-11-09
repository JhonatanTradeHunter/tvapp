import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/adaptive/phone_shell.dart';
import 'package:tvapp/core/ui/adaptive/tv_shell.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/guide/guide_screen.dart';
import 'package:tvapp/features/live/live_screen.dart';
import 'package:tvapp/features/profiles/profile_picker_screen.dart';
import 'package:tvapp/features/profiles/profiles_screen.dart';
import 'package:tvapp/features/setup/setup_screen.dart';
import 'package:tvapp/features/vod/vod_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

enum ShellDestination { live, guide, vod, settings }

extension ShellDestinationUi on ShellDestination {
  IconData get icon {
    switch (this) {
      case ShellDestination.live:
        return Icons.live_tv;
      case ShellDestination.guide:
        return Icons.view_timeline_outlined;
      case ShellDestination.vod:
        return Icons.movie_outlined;
      case ShellDestination.settings:
        return Icons.settings_outlined;
    }
  }

  String label(AppLocalizations l) {
    switch (this) {
      case ShellDestination.live:
        return l.navLive;
      case ShellDestination.guide:
        return l.navGuide;
      case ShellDestination.vod:
        return l.navVod;
      case ShellDestination.settings:
        return l.navSettings;
    }
  }
}

/// Único ponto que escolhe entre [TvShell] e [PhoneShell].
class AdaptiveRoot extends ConsumerWidget {
  const AdaptiveRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final active = ref.watch(activeSourceProvider);
    return active.when(
      data: (source) {
        if (source == null) return const SetupScreen(initial: true);
        return ProfileGate(
          child: UiVariantScope.isTv(context)
              ? const TvShell()
              : const PhoneShell(),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        body: EmptyState(
          icon: Icons.error_outline,
          title: l.genericError,
          message: '$error',
        ),
      ),
    );
  }
}

/// Conteúdo de cada destino, compartilhado pelos dois shells.
class DestinationBody extends StatelessWidget {
  const DestinationBody({
    super.key,
    required this.destination,
    required this.onGoLive,
  });

  final ShellDestination destination;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    switch (destination) {
      case ShellDestination.live:
        return const LiveScreen();
      case ShellDestination.guide:
        return GuideScreen(onGoLive: onGoLive);
      case ShellDestination.vod:
        return VodScreen(onGoLive: onGoLive);
      case ShellDestination.settings:
        return const _SettingsHome();
    }
  }
}

/// Por enquanto, as Configurações são estes atalhos. No perfil infantil só
/// aparece a troca de perfil.
class _SettingsHome extends ConsumerWidget {
  const _SettingsHome();

  Future<void> _clearHistory(
    BuildContext context,
    WidgetRef ref,
    int profileId,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.clearHistory),
        content: Text(l.clearHistoryConfirm),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.clearHistory),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(databaseProvider).historyDao.clear(profileId);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(l.historyCleared)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(activeProfileProvider);
    final kids = profile?.isKids ?? false;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ShellDestination.settings.icon,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(l.navSettings, style: theme.textTheme.headlineSmall),
              if (profile != null) ...[
                const SizedBox(height: 8),
                Text(l.currentProfile(profile.name)),
              ],
              if (kids) ...[
                const SizedBox(height: 8),
                Text(l.kidsSettingsLocked, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (!kids) ...[
                    AppButton(
                      label: l.manageSource,
                      icon: Icons.playlist_add,
                      autofocus: true,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SetupScreen(),
                        ),
                      ),
                    ),
                    AppButton(
                      label: l.manageProfiles,
                      icon: Icons.manage_accounts,
                      primary: false,
                      onPressed: () => openProfilesWithGuard(context, ref),
                    ),
                  ],
                  AppButton(
                    label: l.switchProfile,
                    icon: Icons.switch_account,
                    primary: kids,
                    autofocus: kids,
                    onPressed: () =>
                        ref.read(activeProfileIdProvider.notifier).signOut(),
                  ),
                  if (profile != null)
                    AppButton(
                      label: l.clearHistory,
                      icon: Icons.history_toggle_off,
                      primary: false,
                      onPressed: () => _clearHistory(context, ref, profile.id),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
