import 'package:tvapp/core/data/m3u/m3u_entry.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/xtream/xtream_client.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/util/normalize.dart';

class XtreamImportResult {
  const XtreamImportResult({
    required this.account,
    required this.live,
    required this.duplicates,
    required this.vod,
    required this.series,
    required this.vodAvailable,
    required this.seriesAvailable,
    required this.elapsed,
  });

  final XtreamAccount account;
  final int live;
  final int duplicates;
  final int vod;
  final int series;

  /// Painéis podem desligar VOD ou séries; falha nessas listas não derruba
  /// a importação dos canais.
  final bool vodAvailable;
  final bool seriesAvailable;
  final Duration elapsed;

  ImportResult toImportResult() => ImportResult(
    imported: live,
    discarded: 0,
    duplicates: duplicates,
    truncated: false,
    elapsed: elapsed,
  );
}

typedef XtreamVodSink =
    Future<void> Function(
      List<XtreamVodStream> batch,
      int startPosition,
      Map<String, String> categoryNames,
    );
typedef XtreamSeriesSink =
    Future<void> Function(
      List<XtreamSeries> batch,
      int startPosition,
      Map<String, String> categoryNames,
    );

/// Importa uma conta Xtream pela API. Os canais ao vivo viram [M3uEntry] e
/// vão para o mesmo [EntrySink] do parser M3U, então a UI não sabe a origem.
/// Arquivo (`tv_archive`) vira `catchup="xc"` com os dias do painel.
class XtreamImporter {
  XtreamImporter({this.insertBatchSize = 2000, this.maxEntries = 500000});

  final int insertBatchSize;
  final int maxEntries;

  Future<XtreamImportResult> run({
    required XtreamClient client,
    required EntrySink liveSink,
    required XtreamVodSink vodSink,
    required XtreamSeriesSink seriesSink,
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    var written = 0;

    void ensureNotCancelled() {
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
    }

    void report() =>
        onProgress?.call(ImportProgress(bytesRead: 0, entries: written));

    final account = await client.authenticate();
    if (!account.isActive) {
      throw SourceException(
        SourceError.credentials,
        detail: account.status ?? 'inactive',
      );
    }
    ensureNotCancelled();

    final liveNames = _names(await client.liveCategories());
    ensureNotCancelled();
    final streams = await client.liveStreams();
    ensureNotCancelled();

    final extension = account.preferredLiveExtension;
    final seen = <String>{};
    var duplicates = 0;
    var live = 0;
    var batch = <KeyedEntry>[];
    for (final s in streams) {
      if (live + batch.length >= maxEntries) break;
      final entry = M3uEntry(
        name: s.name,
        url: client.liveUrl(s.streamId, extension: extension).toString(),
        tvgId: s.epgChannelId,
        logo: s.icon,
        group: liveNames[s.categoryId],
        tvgChno: s.num,
        catchup: s.tvArchive ? 'xc' : null,
        catchupDays: s.tvArchive ? s.archiveDays : null,
      );
      final folded = foldName(entry.name);
      final key = channelKeyFrom(entry.tvgId, folded);
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      batch.add(KeyedEntry(entry, key, folded));
      if (batch.length == insertBatchSize) {
        await liveSink(batch, live);
        live += batch.length;
        written += batch.length;
        batch = <KeyedEntry>[];
        ensureNotCancelled();
        report();
      }
    }
    if (batch.isNotEmpty) {
      await liveSink(batch, live);
      live += batch.length;
      written += batch.length;
      report();
    }

    var vod = 0;
    var vodAvailable = true;
    try {
      final names = _names(await client.vodCategories());
      final items = await client.vodStreams();
      ensureNotCancelled();
      vod = await _write(
        items,
        (chunk, start) => vodSink(chunk, start, names),
        () {
          ensureNotCancelled();
        },
      );
      written += vod;
      report();
    } on SourceException catch (e) {
      if (e.error == SourceError.cancelled) rethrow;
      vodAvailable = false;
    }

    var series = 0;
    var seriesAvailable = true;
    try {
      final names = _names(await client.seriesCategories());
      final items = await client.series();
      ensureNotCancelled();
      series = await _write(
        items,
        (chunk, start) => seriesSink(chunk, start, names),
        ensureNotCancelled,
      );
      written += series;
      report();
    } on SourceException catch (e) {
      if (e.error == SourceError.cancelled) rethrow;
      seriesAvailable = false;
    }

    watch.stop();
    return XtreamImportResult(
      account: account,
      live: live,
      duplicates: duplicates,
      vod: vod,
      series: series,
      vodAvailable: vodAvailable,
      seriesAvailable: seriesAvailable,
      elapsed: watch.elapsed,
    );
  }

  Future<int> _write<T>(
    List<T> items,
    Future<void> Function(List<T> chunk, int start) sink,
    void Function() afterChunk,
  ) async {
    final limit = items.length < maxEntries ? items.length : maxEntries;
    var start = 0;
    while (start < limit) {
      final end = start + insertBatchSize < limit
          ? start + insertBatchSize
          : limit;
      await sink(items.sublist(start, end), start);
      start = end;
      afterChunk();
    }
    return limit;
  }

  static Map<String, String> _names(List<XtreamCategory> categories) =>
      <String, String>{for (final c in categories) c.id: c.name};
}
