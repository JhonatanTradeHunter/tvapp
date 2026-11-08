import 'package:flutter/material.dart';
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
  final String? semanticLabel;

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

  @override
  Widget build(BuildContext context) {
    if (!UiVariantScope.isTv(context)) {
      return Semantics(
        button: true,
        label: widget.semanticLabel,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onSelect,
            onLongPress: widget.onMenu,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onFocusChange: widget.onFocusChange,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      );
    }

    final accent = Theme.of(context).colorScheme.primary;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      actions: _actions,
      onFocusChange: _handleFocus,
      child: Semantics(
        button: true,
        focused: _focused,
        label: widget.semanticLabel,
        child: AnimatedScale(
          scale: _focused ? FocusableScale.focusedScale : 1,
          duration: FocusableScale.animation,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: FocusableScale.animation,
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
            child: widget.child,
          ),
        ),
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
