import 'package:flutter/material.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Pôster 2:3 com título abaixo. Sem imagem, mostra o título no lugar.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onSelect,
    this.image,
    this.rating,
    this.autofocus = false,
  });

  final String title;
  final String? image;
  final double? rating;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final src = image;
    final stars = rating;
    final placeholder = Container(
      color: theme.colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(6),
      child: FocusableScale(
        autofocus: autofocus,
        onSelect: onSelect,
        semanticLabel: stars != null && stars > 0
            ? AppLocalizations.of(
                context,
              ).posterSemantics(title, stars.toStringAsFixed(1))
            : title,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: src == null
                    ? placeholder
                    : Image.network(
                        src,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stack) => placeholder,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            if (stars != null && stars > 0)
              Row(
                children: [
                  Icon(Icons.star, size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 2),
                  Text(
                    stars.toStringAsFixed(1),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
