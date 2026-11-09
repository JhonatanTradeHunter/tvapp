import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tvapp/core/data/prefs/app_prefs.dart';

/// Marca, a cada [interval], que o app está em primeiro plano. A tarefa de
/// fundo lê a marca e não roda enquanto ela for recente.
class AppHeartbeat extends StatefulWidget {
  const AppHeartbeat({super.key, required this.prefs, required this.child});

  static const Duration interval = Duration(minutes: 1);

  final AppPrefs prefs;
  final Widget child;

  @override
  State<AppHeartbeat> createState() => _AppHeartbeatState();
}

class _AppHeartbeatState extends State<AppHeartbeat>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _beat();
    _timer?.cancel();
    _timer = Timer.periodic(AppHeartbeat.interval, (_) => _beat());
  }

  void _beat() => unawaited(widget.prefs.markAppInUse(DateTime.now().toUtc()));

  @override
  Widget build(BuildContext context) => widget.child;
}
