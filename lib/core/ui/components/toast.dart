import 'package:flutter/material.dart';

class AppToast {
  AppToast._();

  static void show(BuildContext context, String message, {IconData? icon}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final iconData = icon;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              if (iconData != null) ...[
                Icon(iconData),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
