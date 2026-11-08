import 'package:flutter/material.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class ErrorDialogAction {
  const ErrorDialogAction(this.label, this.onPressed, {this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
}

Future<void> showErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
  List<ErrorDialogAction> actions = const <ErrorDialogAction>[],
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ErrorDialog(title: title, message: message, actions: actions),
  );
}

class ErrorDialog extends StatelessWidget {
  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.actions = const <ErrorDialogAction>[],
  });

  final String title;
  final String message;
  final List<ErrorDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final effective = actions.isEmpty
        ? <ErrorDialogAction>[ErrorDialogAction(l.close, null, primary: true)]
        : actions;
    return AlertDialog(
      icon: const Icon(Icons.error_outline),
      title: Text(title),
      content: Text(message),
      actions: [
        for (var i = 0; i < effective.length; i++)
          AppButton(
            label: effective[i].label,
            primary: effective[i].primary,
            autofocus: i == 0,
            onPressed: () {
              Navigator.of(context).pop();
              effective[i].onPressed?.call();
            },
          ),
      ],
    );
  }
}
