import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';

class OpenMenuIntent extends Intent {
  const OpenMenuIntent();
}

/// Setas já viram `DirectionalFocusIntent` nos atalhos padrão do WidgetsApp.
/// Aqui entram as teclas de controle remoto que faltam. Back fica com o
/// `PopScope` de cada tela, porque chega como evento de sistema.
class TvShortcuts extends StatelessWidget {
  const TvShortcuts({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static const Map<ShortcutActivator, Intent> shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): OpenMenuIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonY): OpenMenuIntent(),
      };

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Shortcuts(shortcuts: shortcuts, child: child);
  }
}

TraversalDirection? directionForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
  if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
  if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
  if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
  return null;
}

/// Em campo de texto na TV, cima/baixo saem do campo em vez de mover o cursor.
class DpadFieldGuard extends StatelessWidget {
  const DpadFieldGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!UiVariantScope.isTv(context)) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.arrowUp &&
            key != LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.ignored;
        }
        final focused = FocusManager.instance.primaryFocus;
        final direction = directionForKey(key);
        if (focused == null || direction == null) return KeyEventResult.ignored;
        return focused.focusInDirection(direction)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
