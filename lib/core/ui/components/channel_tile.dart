import 'package:flutter/material.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.onSelect,
    this.onToggleFavorite,
    this.onFocused,
    this.autofocus = false,
    this.focusNode,
  });

  static const double tvExtent = 72;
  static const double touchExtent = 64;

  final Channel channel;
  final VoidCallback onSelect;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onFocused;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Cresce com a fonte do sistema, para o nome não ser cortado.
  static double extentFor(BuildContext context) {
    final base = UiVariantScope.isTv(context) ? tvExtent : touchExtent;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return base * scale.clamp(1.0, 2.0);
  }

  @override
  Widget build(BuildContext context) {
    final tv = UiVariantScope.isTv(context);
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final toggle = onToggleFavorite;

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: tv ? 8 : 6),
      child: Row(
        children: [
          SizedBox(
            width: tv ? 52 : 40,
            child: Text(
              '${channel.displayNumber}',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 12),
          ChannelLogo(url: channel.logo, size: tv ? 48 : 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tv
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyLarge,
            ),
          ),
          if (tv && channel.isFavorite)
            Icon(
              Icons.star,
              size: 22,
              color: theme.colorScheme.tertiary,
              semanticLabel: l.favorite,
            ),
          if (!tv && toggle != null)
            IconButton(
              onPressed: toggle,
              tooltip: channel.isFavorite ? l.removeFavorite : l.addFavorite,
              icon: Icon(
                channel.isFavorite ? Icons.star : Icons.star_border,
                color: channel.isFavorite ? theme.colorScheme.tertiary : null,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tv ? 10 : 0, vertical: 2),
      child: FocusableScale(
        autofocus: autofocus,
        focusNode: focusNode,
        onSelect: onSelect,
        onMenu: toggle,
        menuLabel: channel.isFavorite ? l.removeFavorite : l.addFavorite,
        // No toque a estrela é um botão próprio; os textos falam por si.
        semanticLabel: !tv && toggle != null
            ? null
            : l.channelSemantics(
                channel.displayNumber,
                channel.name,
                channel.isFavorite ? l.favorite : '',
              ),
        excludeChildSemantics: tv || toggle == null,
        onFocusChange: (focused) {
          if (focused) onFocused?.call();
        },
        child: row,
      ),
    );
  }
}

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.live_tv,
        size: size * 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );
    final src = url;
    if (src == null || src.isEmpty) return placeholder;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: pixels,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}
