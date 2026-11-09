import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/channel_tile.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';
import 'package:tvapp/features/live/player/player_screen.dart';
import 'package:tvapp/features/search/search_controller.dart';
import 'package:tvapp/features/vod/poster_card.dart';
import 'package:tvapp/features/vod/vod_detail_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Busca por nome em canais, filmes e séries da fonte ativa. No controle
/// remoto, "buscar" no teclado leva o foco ao primeiro resultado.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const Duration _debounce = Duration(milliseconds: 300);

  late final TextEditingController _text = TextEditingController(
    text: ref.read(searchQueryProvider),
  );
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
    setState(() {});
  }

  void _submit(String value) {
    _timer?.cancel();
    ref.read(searchQueryProvider.notifier).set(value);
    FocusScope.of(context).nextFocus();
  }

  void _clear() {
    _timer?.cancel();
    _text.clear();
    ref.read(searchQueryProvider.notifier).set('');
    setState(() {});
  }

  void _openChannel(Channel channel, List<Channel> list) {
    unawaited(
      ref
          .read(playbackControllerProvider.notifier)
          .playChannel(channel, playlist: list),
    );
    _push(const PlayerScreen());
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = UiVariantScope.isTv(context);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    final Widget body;
    if (query.trim().length < minSearchLength) {
      body = EmptyState(icon: Icons.search, title: l.searchHint);
    } else {
      body = results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: l.genericError,
          message: '$error',
        ),
        data: (r) => r.isEmpty
            ? EmptyState(
                icon: Icons.search_off,
                title: l.searchNoResults(query.trim()),
              )
            : _Results(
                results: r,
                onChannel: (c) => _openChannel(c, r.channels),
                onMovie: (m) => _push(MovieDetailScreen(movie: m)),
                onSeries: (s) => _push(SeriesDetailScreen(series: s)),
              ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(tv ? 16 : 8, tv ? 16 : 8, tv ? 16 : 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DpadFieldGuard(
            child: TextField(
              controller: _text,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.searchField,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _text.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.searchClear,
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.onChannel,
    required this.onMovie,
    required this.onSeries,
  });

  final SearchResults results;
  final ValueChanged<Channel> onChannel;
  final ValueChanged<VodItemRow> onMovie;
  final ValueChanged<SeriesItemRow> onSeries;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = UiVariantScope.isTv(context);
    final posterHeight = tv ? 330.0 : 240.0;
    final posterWidth = tv ? 170.0 : 120.0;
    return FocusTraversalGroup(
      child: CustomScrollView(
        slivers: [
          if (results.channels.isNotEmpty) ...[
            _Header(text: l.searchChannels(results.channels.length)),
            SliverFixedExtentList(
              itemExtent: ChannelTile.extentFor(context),
              delegate: SliverChildBuilderDelegate((context, i) {
                final c = results.channels[i];
                return ChannelTile(
                  key: ValueKey<String>(c.channelKey),
                  channel: c,
                  onSelect: () => onChannel(c),
                );
              }, childCount: results.channels.length),
            ),
          ],
          if (results.movies.isNotEmpty) ...[
            _Header(text: l.searchMovies(results.movies.length)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: posterHeight,
                child: FocusTraversalGroup(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: results.movies.length,
                    itemBuilder: (context, i) {
                      final m = results.movies[i];
                      return SizedBox(
                        key: ValueKey<int>(m.id),
                        width: posterWidth,
                        child: PosterCard(
                          title: m.name,
                          image: m.icon,
                          rating: m.rating,
                          onSelect: () => onMovie(m),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          if (results.series.isNotEmpty) ...[
            _Header(text: l.searchSeries(results.series.length)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: posterHeight,
                child: FocusTraversalGroup(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: results.series.length,
                    itemBuilder: (context, i) {
                      final s = results.series[i];
                      return SizedBox(
                        key: ValueKey<int>(s.id),
                        width: posterWidth,
                        child: PosterCard(
                          title: s.name,
                          image: s.cover,
                          rating: s.rating,
                          onSelect: () => onSeries(s),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
    );
  }
}
