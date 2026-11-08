import 'package:flutter/material.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/components/channel_tile.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class ChannelList extends StatelessWidget {
  const ChannelList({
    super.key,
    required this.channels,
    required this.loading,
    required this.onOpen,
    required this.onToggleFavorite,
    this.onFocusChannel,
    this.autofocusFirst = false,
    this.firstItemFocusNode,
  });

  final List<Channel>? channels;
  final bool loading;
  final void Function(Channel channel, List<Channel> list) onOpen;
  final ValueChanged<Channel> onToggleFavorite;
  final ValueChanged<Channel>? onFocusChannel;

  /// Só na primeira carga. Com `autofocus` permanente, cada troca de grupo
  /// recriaria o primeiro item e roubaria o foco da lista de grupos.
  final bool autofocusFirst;

  /// Nó estável do primeiro item, usado como alvo preferido da região.
  final FocusNode? firstItemFocusNode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = channels;
    if (items == null) {
      return loading
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.tv_off_outlined,
        title: l.noChannels,
        message: l.noChannelsHint,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemExtent: ChannelTile.extentFor(context),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final channel = items[index];
        final first = index == 0;
        return ChannelTile(
          key: ValueKey<int>(channel.id),
          channel: channel,
          autofocus: first && autofocusFirst,
          focusNode: first ? firstItemFocusNode : null,
          onSelect: () => onOpen(channel, items),
          onToggleFavorite: () => onToggleFavorite(channel),
          onFocused: () => onFocusChannel?.call(channel),
        );
      },
    );
  }
}
