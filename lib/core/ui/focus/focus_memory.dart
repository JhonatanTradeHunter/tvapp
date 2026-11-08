import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';

/// Dono de um `FocusScopeNode` que lembra o último item focado da região.
class FocusRegionController {
  FocusRegionController({String? debugLabel})
    : node = FocusScopeNode(debugLabel: debugLabel) {
    _registry[node] = this;
  }

  static final Map<FocusNode, FocusRegionController> _registry =
      <FocusNode, FocusRegionController>{};

  final FocusScopeNode node;

  /// Região que recebe o foco quando o usuário aperta back dentro desta.
  FocusRegionController? backTarget;

  /// Alvo quando não há item lembrado (por exemplo, a lista foi trocada e o
  /// item antigo saiu da árvore). Sem ele, vale o primeiro item da região.
  FocusNode? preferredFallback;

  bool get hasFocus => node.hasFocus;

  void restore() {
    final remembered = node.focusedChild;
    if (remembered != null && remembered.canRequestFocus) {
      remembered.requestFocus();
      return;
    }
    final fallback = preferredFallback;
    if (fallback != null &&
        fallback.context != null &&
        fallback.canRequestFocus) {
      fallback.requestFocus();
      return;
    }
    for (final candidate in node.traversalDescendants) {
      if (candidate is! FocusScopeNode && candidate.canRequestFocus) {
        candidate.requestFocus();
        return;
      }
    }
    node.requestFocus();
  }

  void dispose() {
    _registry.remove(node);
    node.dispose();
  }

  /// Sobe a partir do foco atual até a primeira região com `backTarget`.
  /// Retorna false quando ninguém tratou, e então a tela decide (sair, fechar).
  static bool handleBack() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return false;
    for (final node in <FocusNode>[focused, ...focused.ancestors]) {
      final target = _registry[node]?.backTarget;
      if (target != null) {
        target.restore();
        return true;
      }
    }
    return false;
  }
}

/// Região de foco: `FocusScope` próprio, `FocusTraversalGroup` com ordem
/// explícita e vizinhos por direção. Quando a navegação direcional não acha
/// candidato dentro da região, o foco vai para a região vizinha e restaura
/// o último item dela.
class FocusRegion extends StatelessWidget {
  const FocusRegion({
    super.key,
    required this.controller,
    required this.child,
    this.left,
    this.right,
    this.up,
    this.down,
  });

  final FocusRegionController controller;
  final FocusRegionController? left;
  final FocusRegionController? right;
  final FocusRegionController? up;
  final FocusRegionController? down;
  final Widget child;

  FocusRegionController? _neighbor(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.left:
        return left;
      case TraversalDirection.right:
        return right;
      case TraversalDirection.up:
        return up;
      case TraversalDirection.down:
        return down;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = directionForKey(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return KeyEventResult.ignored;
    if (focused.focusInDirection(direction)) return KeyEventResult.handled;
    final neighbor = _neighbor(direction);
    if (neighbor == null) return KeyEventResult.ignored;
    neighbor.restore();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: FocusScope(
        node: controller.node,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}
