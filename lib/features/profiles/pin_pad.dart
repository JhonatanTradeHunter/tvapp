import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Pede um PIN de 4 dígitos. Teclado navegável por D-pad e dígitos do
/// controle remoto ou teclado. [validate] decide se o PIN serve; sem ele,
/// qualquer PIN de 4 dígitos é aceito (útil para cadastrar).
Future<String?> showPinPad(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool Function(String pin)? validate,
  String? errorText,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => PinPadDialog(
      title: title,
      subtitle: subtitle,
      validate: validate,
      errorText: errorText,
    ),
  );
}

class PinPadDialog extends StatefulWidget {
  const PinPadDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.validate,
    this.errorText,
  });

  final String title;
  final String? subtitle;
  final bool Function(String pin)? validate;
  final String? errorText;

  @override
  State<PinPadDialog> createState() => _PinPadDialogState();
}

class _PinPadDialogState extends State<PinPadDialog> {
  static const int _length = 4;
  String _pin = '';
  bool _error = false;

  void _press(String digit) {
    if (_pin.length >= _length) return;
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == _length) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final ok = widget.validate?.call(_pin) ?? true;
    if (ok) {
      Navigator.of(context).pop(_pin);
    } else {
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1 && RegExp(r'\d').hasMatch(char)) {
      _press(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtitle = widget.subtitle;
    Widget key(String label, VoidCallback onTap, {bool autofocus = false}) =>
        _PadKey(label: label, onTap: onTap, autofocus: autofocus);

    return AlertDialog(
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null) ...[
              Text(subtitle, textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _length; i++)
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 28,
              child: _error
                  ? Center(
                      child: Text(
                        widget.errorText ?? l.pinWrong,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    )
                  : null,
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in row)
                    key(d, () => _press(d), autofocus: d == '1'),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 76),
                key('0', () => _press('0')),
                _PadKey(
                  label: '⌫',
                  semanticLabel: l.pinBackspace,
                  onTap: _backspace,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l.cancel,
          primary: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(30));
    return Padding(
      padding: const EdgeInsets.all(6),
      child: FocusableScale(
        autofocus: autofocus,
        onSelect: onTap,
        borderRadius: radius,
        semanticLabel: semanticLabel ?? label,
        child: Container(
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          child: Text(label, style: theme.textTheme.titleLarge),
        ),
      ),
    );
  }
}
