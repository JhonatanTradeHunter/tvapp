import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/daos/history_dao.dart';
import 'package:tvapp/core/data/profiles/profile_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/player/playback_controller.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/empty_state.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/features/live/player/player_screen.dart';
import 'package:tvapp/features/vod/vod_controller.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

void _play(
  BuildContext context,
  WidgetRef ref,
  Uri url, {
  required VodTab kind,
  required int id,
  required int sourceId,
  required String title,
  String? image,
  Duration? resumeAt,
  HistoryMark? history,
}) {
  final item = playableItem(
    kind: kind,
    id: id,
    sourceId: sourceId,
    title: title,
    url: url,
    image: image,
  );
  unawaited(
    ref
        .read(playbackControllerProvider.notifier)
        .playVod(item, url, resumeAt: resumeAt, history: history),
  );
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PlayerScreen()));
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String? _minutes(int? seconds, AppLocalizations l) =>
    seconds == null || seconds <= 0 ? null : l.durationMinutes(seconds ~/ 60);

class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.movie});

  final VodItemRow movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(xtreamClientProvider);
    final info = ref.watch(vodInfoProvider(movie.streamId)).valueOrNull;
    final resume = ref
        .watch(
          resumePointProvider((
            movie.sourceId,
            vodItemKey(VodTab.movies, movie.streamId),
          )),
        )
        .valueOrNull;
    final void Function(Duration? at)? play = client == null
        ? null
        : (at) => _play(
            context,
            ref,
            client.movieUrl(
              movie.streamId,
              extension: info?.containerExtension ?? movie.extension,
            ),
            kind: VodTab.movies,
            id: movie.streamId,
            sourceId: movie.sourceId,
            title: movie.name,
            image: movie.icon,
            resumeAt: at,
          );
    final facts = <String>[
      ?info?.releaseDate,
      ?info?.genre,
      ?_minutes(info?.durationSecs, l),
    ];

    return _DetailScaffold(
      title: movie.name,
      image: info?.cover ?? movie.icon,
      facts: facts,
      plot: info?.plot,
      people: info?.cast,
      actions: [
        if (resume != null)
          AppButton(
            label: l.resumeFrom(_clock(resume)),
            icon: Icons.play_arrow,
            autofocus: true,
            onPressed: play == null ? null : () => play(resume),
          ),
        AppButton(
          label: resume == null ? l.play : l.startOver,
          icon: resume == null ? Icons.play_arrow : Icons.replay,
          primary: resume == null,
          autofocus: resume == null,
          onPressed: play == null ? null : () => play(null),
        ),
        AppButton(
          label: l.back,
          primary: false,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final SeriesItemRow series;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends ConsumerState<SeriesDetailScreen> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final series = widget.series;
    final client = ref.watch(xtreamClientProvider);
    final async = ref.watch(seriesInfoProvider(series.seriesId));
    final info = async.valueOrNull;
    final seasons = info?.seasons ?? const <XtreamSeason>[];
    final season = _season ?? (seasons.isEmpty ? null : seasons.first.number);
    final episodes = season == null || info == null
        ? const <XtreamEpisode>[]
        : info.episodesOf(season);

    Widget body;
    if (async.isLoading && info == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (info == null || info.episodes.isEmpty) {
      body = EmptyState(
        icon: Icons.error_outline,
        title: async.hasError ? l.detailsLoadFailed : l.vodNoItems,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in seasons)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: AppButton(
                      label: s.name ?? l.seasonNumber(s.number),
                      primary: s.number == season,
                      onPressed: () => setState(() => _season = s.number),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: episodes.length,
              itemBuilder: (context, i) {
                final e = episodes[i];
                return _EpisodeTile(
                  key: ValueKey<int>(e.id),
                  episode: e,
                  autofocus: i == 0,
                  onSelect: client == null
                      ? null
                      : () async {
                          final key = vodItemKey(VodTab.series, e.id);
                          final profileId = ref.read(activeProfileIdProvider);
                          final at = profileId == null
                              ? null
                              : await ref
                                    .read(databaseProvider)
                                    .positionDao
                                    .resumePoint(
                                      profileId,
                                      series.sourceId,
                                      key,
                                    );
                          if (!context.mounted) return;
                          _play(
                            context,
                            ref,
                            client.episodeUrl(
                              e.id,
                              extension: e.containerExtension,
                            ),
                            kind: VodTab.series,
                            id: e.id,
                            sourceId: series.sourceId,
                            title:
                                '${series.name} · ${l.episodeLabel(e.season, e.episodeNum)}',
                            image: e.image ?? series.cover,
                            resumeAt: at,
                            history: HistoryMark(
                              kind: HistoryKind.series,
                              itemKey: 'series|${series.seriesId}',
                              title: series.name,
                              image: series.cover,
                            ),
                          );
                        },
                );
              },
            ),
          ),
        ],
      );
    }

    return _DetailScaffold(
      title: series.name,
      image: info?.cover ?? series.cover,
      facts: <String>[?series.releaseDate, ?(info?.genre ?? series.genre)],
      plot: info?.plot ?? series.plot,
      people: info?.cast,
      below: body,
      actions: const <Widget>[],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.onSelect,
    this.autofocus = false,
  });

  final XtreamEpisode episode;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final duration = _minutes(episode.durationSecs, l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: FocusableScale(
        autofocus: autofocus,
        onSelect: onSelect,
        semanticLabel: <String>[
          l.episodeLabel(episode.season, episode.episodeNum),
          episode.title,
          ?duration,
        ].join(', '),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                l.episodeLabel(episode.season, episode.episodeNum),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (duration != null)
                Text(duration, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.title,
    required this.facts,
    required this.actions,
    this.image,
    this.plot,
    this.people,
    this.below,
  });

  final String title;
  final String? image;
  final List<String> facts;
  final String? plot;
  final String? people;
  final List<Widget> actions;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tv = UiVariantScope.isTv(context);
    final src = image;
    final text = plot;
    final cast = people;
    final lower = below;

    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: tv ? 220 : 120,
        height: tv ? 330 : 180,
        child: src == null
            ? ColoredBox(color: theme.colorScheme.surfaceContainerHigh)
            : Image.network(
                src,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
              ),
      ),
    );

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poster,
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(facts.join('  ·  '), style: theme.textTheme.labelLarge),
              ],
              if (text != null) ...[
                const SizedBox(height: 12),
                Text(
                  text,
                  maxLines: tv ? 6 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (cast != null) ...[
                const SizedBox(height: 8),
                Text(
                  cast,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 12, children: actions),
              ],
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: tv ? null : AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tv ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (lower != null) ...[
                const SizedBox(height: 16),
                Expanded(child: lower),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
