import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/ui/components/toast.dart';
import 'package:tvapp/features/setup/import_progress.dart';
import 'package:tvapp/features/setup/setup_controller.dart';
import 'package:tvapp/features/setup/tabs/local_file_tab.dart';
import 'package:tvapp/features/setup/tabs/url_tab.dart';
import 'package:tvapp/features/setup/tabs/xtream_tab.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.initial = false});

  /// Primeira execução: a tela é a raiz e some sozinha quando a fonte vira ativa.
  final bool initial;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onStateChanged(SetupState? previous, SetupState next) {
    if (next.phase != SetupPhase.done || previous?.phase == SetupPhase.done) {
      return;
    }
    final result = next.result;
    final l = AppLocalizations.of(context);
    if (result != null) {
      final summary = l.importSummary(
        result.imported,
        result.duplicates,
        result.discarded,
      );
      AppToast.show(
        context,
        result.truncated ? '$summary ${l.importTruncated}' : summary,
        icon: Icons.check_circle,
      );
    }
    ref.read(setupControllerProvider.notifier).reset();
    // pop direto: o PopScope desta tela ainda está com canPop falso (montado
    // durante a importação), então maybePop seria recusado.
    if (!widget.initial && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(setupControllerProvider);
    ref.listen<SetupState>(setupControllerProvider, _onStateChanged);
    final progress = state.progress;

    return PopScope(
      canPop: !state.busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) ref.read(setupControllerProvider.notifier).cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.setupTitle),
          automaticallyImplyLeading: !widget.initial,
          bottom: state.phase == SetupPhase.importing
              ? null
              : TabBar(
                  controller: _tabs,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.insert_drive_file_outlined),
                      text: l.tabLocalFile,
                    ),
                    Tab(icon: const Icon(Icons.link), text: l.tabUrl),
                    Tab(
                      icon: const Icon(Icons.dns_outlined),
                      text: l.tabXtream,
                    ),
                  ],
                ),
        ),
        body: state.phase == SetupPhase.importing && progress != null
            ? ImportProgressView(
                progress: progress,
                onCancel: () =>
                    ref.read(setupControllerProvider.notifier).cancel(),
              )
            : TabBarView(
                controller: _tabs,
                children: const [LocalFileTab(), UrlTab(), XtreamTab()],
              ),
      ),
    );
  }
}

/// Moldura comum das abas: aviso de que o app só reproduz fontes do usuário.
class SetupTabFrame extends StatelessWidget {
  const SetupTabFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.setupIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
