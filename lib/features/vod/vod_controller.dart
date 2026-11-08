import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/channel_group.dart';

enum VodTab { movies, series }

/// Cliente da fonte ativa, quando ela é Xtream. Nulo para M3U.
final xtreamClientProvider = Provider<XtreamClient?>((ref) {
  final source = ref.watch(activeSourceProvider).valueOrNull;
  final credentials = source?.xtream;
  if (credentials == null) return null;
  return XtreamClient(credentials);
});

final vodCategoriesProvider = StreamProvider<List<ChannelGroup>>((ref) {
  final key = ref.watch(activeListingKeyProvider);
  if (key == null) return Stream.value(const <ChannelGroup>[]);
  return ref.watch(databaseProvider).vodDao.watchVodCategories(key.$1, key.$2);
});

final seriesCategoriesProvider = StreamProvider<List<ChannelGroup>>((ref) {
  final key = ref.watch(activeListingKeyProvider);
  if (key == null) return Stream.value(const <ChannelGroup>[]);
  return ref
      .watch(databaseProvider)
      .vodDao
      .watchSeriesCategories(key.$1, key.$2);
});

/// Categoria nula = todas.
final vodItemsProvider = StreamProvider.autoDispose
    .family<List<VodItemRow>, String?>((ref, category) {
      final key = ref.watch(activeListingKeyProvider);
      if (key == null) return Stream.value(const <VodItemRow>[]);
      return ref
          .watch(databaseProvider)
          .vodDao
          .watchVod(sourceId: key.$1, generation: key.$2, category: category);
    });

final seriesItemsProvider = StreamProvider.autoDispose
    .family<List<SeriesItemRow>, String?>((ref, category) {
      final key = ref.watch(activeListingKeyProvider);
      if (key == null) return Stream.value(const <SeriesItemRow>[]);
      return ref
          .watch(databaseProvider)
          .vodDao
          .watchSeries(
            sourceId: key.$1,
            generation: key.$2,
            category: category,
          );
    });

final vodInfoProvider = FutureProvider.autoDispose.family<XtreamVodInfo?, int>((
  ref,
  streamId,
) async {
  final client = ref.watch(xtreamClientProvider);
  if (client == null) return null;
  return client.vodInfo(streamId);
});

final seriesInfoProvider = FutureProvider.autoDispose
    .family<XtreamSeriesInfo?, int>((ref, seriesId) async {
      final client = ref.watch(xtreamClientProvider);
      if (client == null) return null;
      return client.seriesInfo(seriesId);
    });

/// O player trabalha com [Channel]; filmes e episódios entram como um
/// canal sintético de id negativo, sem lista para zapear.
Channel playableItem({
  required int id,
  required int sourceId,
  required String title,
  required Uri url,
  String? image,
}) => Channel(
  id: -id,
  sourceId: sourceId,
  channelKey: 'vod|$id',
  position: 0,
  name: title,
  group: '',
  streamUrl: url.toString(),
  logo: image,
);
