import 'package:flutter/material.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';

/// Estado vazio com ação focável opcional, para que a navegação por D-pad
/// sempre encontre um alvo na tela.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.autofocusAction = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool autofocusAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message;
    final label = actionLabel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (text != null) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
              if (label != null && onAction != null) ...[
                const SizedBox(height: 24),
                AppButton(
                  label: label,
                  onPressed: onAction,
                  autofocus: autofocusAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
