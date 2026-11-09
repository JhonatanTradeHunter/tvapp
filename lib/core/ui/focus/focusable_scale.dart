import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';

/// Item focável compartilhado. Variante TV: sem `GestureDetector`, foco com
/// escala 1.05 e borda de 2dp em 150ms, OK e menu via `Actions`.
/// Variante touch: `InkWell` com toque e toque longo.
class FocusableScale extends StatefulWidget {
  const FocusableScale({
    super.key,
    required this.child,
    this.onSelect,
    this.onMenu,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.semanticLabel,
    this.menuLabel,
    this.excludeChildSemantics,
    this.selected,
    this.toggled,
  });

  static const double focusedScale = 1.05;
  static const double borderWidth = 2;
  static const Duration animation = Duration(milliseconds: 150);

  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onMenu;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final BorderRadius borderRadius;

  /// Rótulo lido pelo leitor de tela. Com ele, os textos do filho não são
  /// lidos de novo, salvo [excludeChildSemantics] falso.
  final String? semanticLabel;

  /// Nome da ação de [onMenu] para o leitor de tela (ação personalizada).
  final String? menuLabel;

  final bool? excludeChildSemantics;

  /// Estado lido pelo leitor de tela: opção escolhida num grupo, ou chave
  /// ligada/desligada.
  final bool? selected;
  final bool? toggled;

  @override
  State<FocusableScale> createState() => _FocusableScaleState();
}

class _FocusableScaleState extends State<FocusableScale> {
  bool _focused = false;

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onSelect?.call();
        return null;
      },
    ),
    OpenMenuIntent: CallbackAction<OpenMenuIntent>(
      onInvoke: (_) {
        widget.onMenu?.call();
        return null;
      },
    ),
  };

  void _handleFocus(bool focused) {
    if (_focused != focused) setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  Map<CustomSemanticsAction, VoidCallback>? get _customActions {
    final menu = widget.onMenu;
    final label = widget.menuLabel;
    if (menu == null || label == null) return null;
    return <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(label: label): menu,
    };
  }

  Widget _child() {
    final exclude =
        widget.excludeChildSemantics ?? widget.semanticLabel != null;
    return exclude ? ExcludeSemantics(child: widget.child) : widget.child;
  }

  @override
  Widget build(BuildContext context) {
    if (!UiVariantScope.isTv(context)) {
      return Semantics(
        button: true,
        enabled: widget.onSelect != null,
        selected: widget.selected,
        toggled: widget.toggled,
        label: widget.semanticLabel,
        customSemanticsActions: _customActions,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onSelect,
            onLongPress: widget.onMenu,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onFocusChange: widget.onFocusChange,
            borderRadius: widget.borderRadius,
            child: _child(),
          ),
        ),
      );
    }

    final accent = Theme.of(context).colorScheme.primary;
    // "Remover animações" do sistema: foco muda na hora, sem escala animada.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FocusableScale.animation;
    // Um nó só para o leitor de tela: o foco do FocusableActionDetector se
    // junta ao rótulo e às ações deste container.
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onSelect != null,
      selected: widget.selected,
      toggled: widget.toggled,
      label: widget.semanticLabel,
      onTap: widget.onSelect,
      customSemanticsActions: _customActions,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.onSelect != null || widget.onMenu != null,
        actions: _actions,
        onFocusChange: _handleFocus,
        child: AnimatedScale(
          scale: _focused ? FocusableScale.focusedScale : 1,
          duration: duration,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              color: _focused
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _focused ? accent : Colors.transparent,
                width: FocusableScale.borderWidth,
              ),
            ),
            child: _touchable(),
          ),
        ),
      ),
    );
  }

  /// TVs com tela de toque, emuladores como o BlueStacks e mouse: o toque
  /// também aciona. O InkWell não pega foco nem gera semântica própria; o
  /// foco continua no FocusableActionDetector acima.
  Widget _touchable() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onSelect,
        onLongPress: widget.onMenu,
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: widget.borderRadius,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: _child(),
      ),
    );
  }
}

/// Botão com as mesmas regras de foco do [FocusableScale] na TV.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.primary = true,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autofocus;
  final bool primary;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;
    if (!UiVariantScope.isTv(context)) {
      final text = Text(label);
      if (primary) {
        return iconData == null
            ? FilledButton(
                onPressed: onPressed,
                autofocus: autofocus,
                focusNode: focusNode,
                child: text,
              )
            : FilledButton.icon(
                onPressed: onPressed,
                autofocus: autofocus,
                focusNode: focusNode,
                icon: Icon(iconData),
                label: text,
              );
      }
      return iconData == null
          ? OutlinedButton(
              onPressed: onPressed,
              autofocus: autofocus,
              focusNode: focusNode,
              child: text,
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              autofocus: autofocus,
              focusNode: focusNode,
              icon: Icon(iconData),
              label: text,
            );
    }

    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final background = primary
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = primary ? scheme.onPrimaryContainer : scheme.onSurface;
    const radius = BorderRadius.all(Radius.circular(24));

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: FocusableScale(
        autofocus: autofocus,
        focusNode: focusNode,
        onSelect: onPressed,
        borderRadius: radius,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconData != null) ...[
                Icon(iconData, color: foreground, size: 22),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
