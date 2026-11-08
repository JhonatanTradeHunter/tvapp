import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/features/demo/demo_bootstrap.dart';

/// Catálogo da demonstração sem rede: as telas de filme e série usam a
/// mesma interface do Xtream, mas detalhes e URLs vêm dos assets.
class DemoXtreamClient extends XtreamClient {
  DemoXtreamClient()
    : super(
        const XtreamCredentials(
          host: 'http://demo.local',
          username: 'demo',
          password: 'demo',
        ),
      );

  Uri get _clip => Uri.parse('${demoAssetBase()}clip.mp4');

  @override
  Uri movieUrl(int streamId, {String? extension}) =>
      _clip.replace(queryParameters: <String, String>{'filme': '$streamId'});

  @override
  Uri episodeUrl(int episodeId, {String? extension}) =>
      _clip.replace(queryParameters: <String, String>{'ep': '$episodeId'});

  @override
  Future<XtreamVodInfo> vodInfo(int vodId) async => const XtreamVodInfo(
    plot:
        'Clipe de teste embutido no app para demonstrar o player de VOD, '
        'a seekbar e a retomada de onde parou.',
    durationSecs: 10,
    releaseDate: '2026',
    genre: DemoBootstrap.sourceName,
    rating: 4.5,
    containerExtension: 'mp4',
  );

  @override
  Future<XtreamSeriesInfo> seriesInfo(int seriesId) async =>
      const XtreamSeriesInfo(
        plot: 'Uma temporada curta para testar episódios e retomada.',
        genre: DemoBootstrap.sourceName,
        releaseDate: '2026',
        seasons: <XtreamSeason>[XtreamSeason(number: 1, name: 'Temporada 1')],
        episodes: <XtreamEpisode>[
          XtreamEpisode(
            id: 101,
            season: 1,
            episodeNum: 1,
            title: 'Episódio 1',
            containerExtension: 'mp4',
            durationSecs: 10,
          ),
          XtreamEpisode(
            id: 102,
            season: 1,
            episodeNum: 2,
            title: 'Episódio 2',
            containerExtension: 'mp4',
            durationSecs: 10,
          ),
        ],
      );
}
