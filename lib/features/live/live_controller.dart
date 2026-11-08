import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/channel_group.dart';

class GroupFilterNotifier extends Notifier<GroupFilter> {
  @override
  GroupFilter build() {
    ref.watch(activeListingKeyProvider);
    return const GroupFilter.all();
  }

  void select(GroupFilter filter) {
    if (filter != state) state = filter;
  }
}

final groupFilterProvider = NotifierProvider<GroupFilterNotifier, GroupFilter>(
  GroupFilterNotifier.new,
);

class LiveSortNotifier extends Notifier<LiveSort> {
  @override
  LiveSort build() => ref.read(appPrefsProvider).liveSort;

  void select(LiveSort sort) {
    if (sort == state) return;
    state = sort;
    ref.read(appPrefsProvider).setLiveSort(sort);
  }
}

final liveSortProvider = NotifierProvider<LiveSortNotifier, LiveSort>(
  LiveSortNotifier.new,
);

final groupsProvider = StreamProvider<List<ChannelGroup>>((ref) {
  final key = ref.watch(activeListingKeyProvider);
  if (key == null) {
    return Stream<List<ChannelGroup>>.value(const <ChannelGroup>[]);
  }
  return ref.watch(databaseProvider).channelDao.watchGroups(key.$1, key.$2);
});

final channelsProvider = StreamProvider<List<Channel>>((ref) {
  final key = ref.watch(activeListingKeyProvider);
  if (key == null) return Stream<List<Channel>>.value(const <Channel>[]);
  final filter = ref.watch(groupFilterProvider);
  final sort = ref.watch(liveSortProvider);
  return ref
      .watch(databaseProvider)
      .channelDao
      .watchChannels(
        sourceId: key.$1,
        generation: key.$2,
        filter: filter,
        sort: sort,
      );
});

final liveActionsProvider = Provider<LiveActions>((ref) => LiveActions(ref));

class LiveActions {
  LiveActions(this._ref);

  final Ref _ref;

  Future<bool> toggleFavorite(Channel channel) =>
      _ref.read(sourceRepositoryProvider).toggleFavorite(channel);
}
