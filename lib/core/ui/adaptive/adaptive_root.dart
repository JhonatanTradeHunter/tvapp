import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/adaptive/phone_shell.dart';
import 'package:tvapp/core/ui/adaptive/tv_shell.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/features/guide/guide_screen.dart';
import 'package:tvapp/features/live/live_screen.dart';
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
        return UiVariantScope.isTv(context)
            ? const TvShell()
            : const PhoneShell();
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
    final l = AppLocalizations.of(context);
    switch (destination) {
      case ShellDestination.live:
        return const LiveScreen();
      case ShellDestination.guide:
        return GuideScreen(onGoLive: onGoLive);
      case ShellDestination.vod:
        return VodScreen(onGoLive: onGoLive);
      case ShellDestination.settings:
        return EmptyState(
          icon: ShellDestination.settings.icon,
          title: l.navSettings,
          message: l.settingsComingSoon,
          actionLabel: l.manageSource,
          onAction: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen())),
          autofocusAction: true,
        );
    }
  }
}
