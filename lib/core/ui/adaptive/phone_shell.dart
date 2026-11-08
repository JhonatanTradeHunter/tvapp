import 'package:flutter/material.dart';
import 'package:tvapp/core/ui/adaptive/adaptive_root.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  ShellDestination _current = ShellDestination.live;

  void _select(ShellDestination destination) {
    if (destination != _current) setState(() => _current = destination);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current.index,
        onDestinationSelected: (i) => _select(ShellDestination.values[i]),
        destinations: [
          for (final destination in ShellDestination.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label(l),
            ),
        ],
      ),
    );
  }
}
