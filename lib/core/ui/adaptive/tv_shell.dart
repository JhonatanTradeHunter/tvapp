import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tvapp/core/ui/adaptive/adaptive_root.dart';
import 'package:tvapp/core/ui/focus/focus_memory.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Sidebar + conteúdo. Back sobe um nível de região; na sidebar, sai do app.
class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final FocusRegionController _sidebar = FocusRegionController(
    debugLabel: 'tv-sidebar',
  );
  final FocusRegionController _content = FocusRegionController(
    debugLabel: 'tv-content',
  );
  ShellDestination _current = ShellDestination.live;

  @override
  void initState() {
    super.initState();
    _content.backTarget = _sidebar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_content.hasFocus) _content.restore();
    });
  }

  @override
  void dispose() {
    _sidebar.dispose();
    _content.dispose();
    super.dispose();
  }

  void _select(ShellDestination destination) {
    if (destination != _current) setState(() => _current = destination);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _content.restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!FocusRegionController.handleBack()) SystemNavigator.pop();
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusRegion(
              controller: _sidebar,
              right: _content,
              child: _Sidebar(current: _current, onSelect: _select),
            ),
            Expanded(
              child: FocusRegion(
                controller: _content,
                left: _sidebar,
                child: IndexedStack(
                  index: _current.index,
                  children: [
                    for (final destination in ShellDestination.values)
                      ExcludeFocus(
                        excluding: destination != _current,
                        child: DestinationBody(
                          destination: destination,
                          onGoLive: () => _select(ShellDestination.live),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final ShellDestination current;
  final ValueChanged<ShellDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: 240,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(l.appTitle, style: theme.textTheme.titleLarge),
          ),
          for (final destination in ShellDestination.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: FocusableScale(
                onSelect: () => onSelect(destination),
                semanticLabel: destination.label(l),
                selected: destination == current,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: destination == current
                        ? theme.colorScheme.secondaryContainer
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(destination.icon),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          destination.label(l),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
