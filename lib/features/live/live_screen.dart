import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/epg/epg_providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/epg_preview_row.dart';
import 'package:tvapp/core/ui/components/toast.dart';
import 'package:tvapp/core/ui/focus/focus_memory.dart';
import 'package:tvapp/features/live/live_controller.dart';
import 'package:tvapp/features/live/player/player_screen.dart';
import 'package:tvapp/features/live/widgets/channel_list.dart';
import 'package:tvapp/features/live/widgets/group_list.dart';
import 'package:tvapp/features/live/widgets/sort_selector.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  final FocusRegionController _groups = FocusRegionController(
    debugLabel: 'live-groups',
  );
  final FocusRegionController _channels = FocusRegionController(
    debugLabel: 'live-channels',
  );
  final FocusNode _firstChannel = FocusNode(debugLabel: 'live-first-channel');
  Channel? _focused;
  bool _initialFocusPending = true;

  @override
  void initState() {
    super.initState();
    _channels.backTarget = _groups;
    _channels.preferredFallback = _firstChannel;
  }

  @override
  void dispose() {
    _groups.dispose();
    _channels.dispose();
    _firstChannel.dispose();
    super.dispose();
  }

  void _open(Channel channel, List<Channel> list) {
    unawaited(
      ref
          .read(playbackControllerProvider.notifier)
          .playChannel(channel, playlist: list),
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen()));
  }

  Future<void> _toggleFavorite(Channel channel) async {
    final l = AppLocalizations.of(context);
    final added = await ref.read(liveActionsProvider).toggleFavorite(channel);
    if (!mounted) return;
    AppToast.show(
      context,
      added
          ? l.addedToFavorites(channel.name)
          : l.removedFromFavorites(channel.name),
      icon: added ? Icons.star : Icons.star_border,
    );
  }

  void _selectGroup(GroupFilter filter, {required bool moveFocus}) {
    ref.read(groupFilterProvider.notifier).select(filter);
    if (moveFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _channels.restore();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups =
        ref.watch(groupsProvider).valueOrNull ?? const <ChannelGroup>[];
    final channelsAsync = ref.watch(channelsProvider);
    final filter = ref.watch(groupFilterProvider);
    final sort = ref.watch(liveSortProvider);
    // Mantém o atualizador de EPG vivo sem reconstruir a tela a cada progresso.
    ref.listen<EpgRefreshState>(epgRefresherProvider, (previous, next) {});

    final groupList = GroupList(
      groups: groups,
      selected: filter,
      onFocusGroup: (f) => _selectGroup(f, moveFocus: false),
      onSelectGroup: (f) =>
          _selectGroup(f, moveFocus: UiVariantScope.isTv(context)),
    );

    final channelList = ChannelList(
      channels: channelsAsync.valueOrNull,
      loading: channelsAsync.isLoading,
      onOpen: _open,
      onToggleFavorite: _toggleFavorite,
      autofocusFirst: _initialFocusPending && UiVariantScope.isTv(context),
      firstItemFocusNode: _firstChannel,
      onFocusChannel: (c) {
        if (_focused?.id != c.id || _initialFocusPending) {
          setState(() {
            _focused = c;
            _initialFocusPending = false;
          });
        }
      },
    );

    final sortSelector = SortSelector(
      sort: sort,
      onChanged: (s) => ref.read(liveSortProvider.notifier).select(s),
    );

    if (!UiVariantScope.isTv(context)) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(width: double.infinity, child: sortSelector),
          ),
          groupList,
          Expanded(child: channelList),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: FocusRegion(
            controller: _groups,
            right: _channels,
            child: groupList,
          ),
        ),
        Expanded(
          child: FocusRegion(
            controller: _channels,
            left: _groups,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
              child: Column(
                children: [
                  sortSelector,
                  const SizedBox(height: 12),
                  Expanded(child: channelList),
                  const SizedBox(height: 12),
                  _FocusedEpg(channel: _focused),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusedEpg extends ConsumerWidget {
  const _FocusedEpg({required this.channel});

  final Channel? channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = channel;
    if (focused == null) return const EpgPreviewRow();
    final info = ref.watch(nowNextProvider(focused)).valueOrNull;
    final current = info?.current;
    final next = info?.next;
    return EpgPreviewRow(
      channelName: focused.name,
      title: current?.title,
      start: current?.startUtc,
      end: current?.stopUtc,
      nextTitle: next?.title,
      nextStart: next?.startUtc,
      approximate: info?.match.isApproximate ?? false,
    );
  }
}
