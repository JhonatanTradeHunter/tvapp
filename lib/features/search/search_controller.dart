import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/data/profiles/parental_policy.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/util/normalize.dart';

class SearchResults {
  const SearchResults({
    this.channels = const <Channel>[],
    this.movies = const <VodItemRow>[],
    this.series = const <SeriesItemRow>[],
  });

  static const SearchResults empty = SearchResults();

  final List<Channel> channels;
  final List<VodItemRow> movies;
  final List<SeriesItemRow> series;

  bool get isEmpty => channels.isEmpty && movies.isEmpty && series.isEmpty;
}

/// Termos mais curtos que isso não disparam busca.
const int minSearchLength = 2;

/// Canais, filmes e séries da fonte ativa cujo nome contém [query], já
/// filtrados pelo que o perfil pode ver.
Future<SearchResults> runSearch({
  required AppDatabase db,
  required int profileId,
  required int sourceId,
  required int generation,
  required String query,
  ParentalPolicy policy = ParentalPolicy.unrestricted,
  int limit = 60,
}) async {
  // % e _ são curingas do LIKE; saem antes de medir o termo.
  final folded = foldName(
    query.replaceAll('%', ' ').replaceAll('_', ' '),
  ).trim();
  if (folded.length < minSearchLength) return SearchResults.empty;
  final results = await Future.wait<List<Object>>([
    db.channelDao.search(
      profileId: profileId,
      sourceId: sourceId,
      generation: generation,
      folded: folded,
      limit: limit,
    ),
    db.vodDao.searchVod(sourceId, generation, folded, limit: limit),
    db.vodDao.searchSeries(sourceId, generation, folded, limit: limit),
  ]);
  return SearchResults(
    channels: <Channel>[
      for (final c in results[0].cast<Channel>())
        if (policy.allowsChannel(c)) c,
    ],
    movies: <VodItemRow>[
      for (final m in results[1].cast<VodItemRow>())
        if (policy.allowsItem(BlockedKind.vod, m.categoryName, m.name)) m,
    ],
    series: <SeriesItemRow>[
      for (final s in results[2].cast<SeriesItemRow>())
        if (policy.allowsItem(BlockedKind.series, s.categoryName, s.name)) s,
    ],
  );
}

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(activeListingKeyProvider);
    return '';
  }

  void set(String query) {
    if (query != state) state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final searchResultsProvider = FutureProvider.autoDispose<SearchResults>((ref) {
  final query = ref.watch(searchQueryProvider);
  final key = ref.watch(activeListingKeyProvider);
  if (key == null) return SearchResults.empty;
  return runSearch(
    db: ref.watch(databaseProvider),
    profileId: ref.watch(activeProfileIdProvider) ?? 0,
    sourceId: key.$1,
    generation: key.$2,
    query: query,
    policy: ref.watch(parentalPolicyProvider),
  );
});
