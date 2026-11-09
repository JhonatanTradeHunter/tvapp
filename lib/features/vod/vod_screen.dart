import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/vod/poster_card.dart';
import 'package:tvapp/features/vod/vod_controller.dart';
import 'package:tvapp/features/vod/vod_detail_screen.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

/// Catálogo de filmes e séries: abas, categorias e grade de pôsteres.
/// Fontes sem catálogo (M3U) mostram estado vazio com ação focável.
class VodScreen extends ConsumerStatefulWidget {
  const VodScreen({super.key, required this.onGoLive});

  final VoidCallback onGoLive;

  @override
  ConsumerState<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends ConsumerState<VodScreen> {
  VodTab _tab = VodTab.movies;
  String? _category;
  bool _recent = false;

  void _setTab(VodTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _category = null;
      _recent = false;
    });
  }

  void _setCategory(String? category, {bool recent = false}) {
    setState(() {
      _category = category;
      _recent = recent;
    });
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tv = UiVariantScope.isTv(context);
    final movieCats =
        ref.watch(vodCategoriesProvider).valueOrNull ?? const <ChannelGroup>[];
    final seriesCats =
        ref.watch(seriesCategoriesProvider).valueOrNull ??
        const <ChannelGroup>[];

    if (movieCats.isEmpty && seriesCats.isEmpty) {
      return EmptyState(
        icon: Icons.movie_outlined,
        title: l.vodEmpty,
        message: l.vodEmptyHint,
        actionLabel: l.goToLive,
        onAction: widget.onGoLive,
        autofocusAction: true,
      );
    }

    final categories = _tab == VodTab.movies ? movieCats : seriesCats;
    final recentMovies =
        ref.watch(recentVodProvider).valueOrNull ?? const <VodItemRow>[];
    final recentSeries =
        ref.watch(recentSeriesProvider).valueOrNull ?? const <SeriesItemRow>[];
    final hasRecent = _tab == VodTab.movies
        ? recentMovies.isNotEmpty
        : recentSeries.isNotEmpty;
    final chips = <_Chip>[
      _Chip(
        label: l.allChannels,
        selected: !_recent && _category == null,
        dense: true,
        onSelect: () => _setCategory(null),
      ),
      if (hasRecent || _recent)
        _Chip(
          label: l.recentChannels,
          selected: _recent,
          dense: true,
          onSelect: () => _setCategory(null, recent: true),
        ),
      for (final c in categories)
        _Chip(
          label: c.name.isEmpty ? l.ungrouped : c.name,
          selected: !_recent && _category == c.name,
          dense: true,
          onSelect: () => _setCategory(c.name),
        ),
    ];

    Widget grid;
    if (_tab == VodTab.movies) {
      final items = _recent
          ? recentMovies
          : ref.watch(vodItemsProvider(_category)).valueOrNull;
      grid = _Grid(
        count: items?.length,
        builder: (context, i) {
          final item = items![i];
          return PosterCard(
            key: ValueKey<int>(item.id),
            title: item.name,
            image: item.icon,
            rating: item.rating,
            onSelect: () => _open(MovieDetailScreen(movie: item)),
          );
        },
      );
    } else {
      final items = _recent
          ? recentSeries
          : ref.watch(seriesItemsProvider(_category)).valueOrNull;
      grid = _Grid(
        count: items?.length,
        builder: (context, i) {
          final item = items![i];
          return PosterCard(
            key: ValueKey<int>(item.id),
            title: item.name,
            image: item.cover,
            rating: item.rating,
            onSelect: () => _open(SeriesDetailScreen(series: item)),
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(tv ? 16 : 8, tv ? 16 : 8, tv ? 16 : 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (movieCats.isNotEmpty)
                _Chip(
                  label: l.vodMovies,
                  selected: _tab == VodTab.movies,
                  onSelect: () => _setTab(VodTab.movies),
                ),
              if (seriesCats.isNotEmpty)
                _Chip(
                  label: l.vodSeries,
                  selected: _tab == VodTab.series,
                  onSelect: () => _setTab(VodTab.series),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: tv ? 52 : 44,
            child: ListView(scrollDirection: Axis.horizontal, children: chips),
          ),
          const SizedBox(height: 8),
          Expanded(child: grid),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.count, required this.builder});

  final int? count;
  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final n = count;
    if (n == null) return const Center(child: CircularProgressIndicator());
    if (n == 0) {
      return EmptyState(icon: Icons.movie_filter_outlined, title: l.vodNoItems);
    }
    final tv = UiVariantScope.isTv(context);
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tv ? 190 : 140,
        childAspectRatio: 0.55,
      ),
      itemCount: n,
      itemBuilder: builder,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(18));
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: FocusableScale(
        onSelect: onSelect,
        borderRadius: radius,
        semanticLabel: label,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 16,
            vertical: dense ? 6 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: selected
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHigh,
          ),
          child: Text(
            label,
            style: dense
                ? theme.textTheme.labelLarge
                : theme.textTheme.titleSmall,
          ),
        ),
      ),
    );
  }
}
