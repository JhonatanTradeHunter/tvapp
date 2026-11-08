import 'dart:async';
import 'dart:isolate';

import 'package:tvapp/core/data/m3u/m3u_entry.dart';
import 'package:tvapp/core/data/m3u/m3u_parser.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/util/normalize.dart';

class ImportProgress {
  const ImportProgress({
    required this.bytesRead,
    required this.entries,
    this.totalBytes,
  });

  final int bytesRead;
  final int? totalBytes;
  final int entries;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesRead / total).clamp(0.0, 1.0);
  }
}

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.discarded,
    required this.duplicates,
    required this.truncated,
    required this.elapsed,
    this.epgUrl,
  });

  final int imported;
  final int discarded;
  final int duplicates;
  final bool truncated;
  final Duration elapsed;

  /// Primeira URL de `url-tvg`/`x-tvg-url` do cabeçalho `#EXTM3U`.
  final String? epgUrl;
}

typedef EntrySink =
    Future<void> Function(List<KeyedEntry> batch, int startPosition);

/// Função de topo para que o closure enviado ao isolate capture apenas
/// as linhas e o cabeçalho, nunca o importador nem o banco.
Future<ParsedChunk> parseChunkInIsolate(List<String> lines, M3uHeader header) {
  return Isolate.run(() => M3uParser.parseRecords(lines, header));
}

class M3uImporter {
  M3uImporter({
    this.maxEntries = 500000,
    this.parseChunkRecords = 5000,
    this.insertBatchSize = 2000,
    this.useIsolate = true,
  });

  final int maxEntries;
  final int parseChunkRecords;
  final int insertBatchSize;
  final bool useIsolate;

  static const Duration _progressInterval = Duration(milliseconds: 100);

  Future<ImportResult> run({
    required Stream<List<int>> bytes,
    required EntrySink sink,
    int? totalBytes,
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    var lastReport = Duration.zero;
    var bytesRead = 0;
    var header = M3uHeader.empty;
    var sawContent = false;
    var sawHeader = false;
    final seen = <String>{};
    var imported = 0;
    var discarded = 0;
    var duplicates = 0;
    var truncated = false;
    var buffer = <String>[];
    var records = 0;

    void report({bool force = false}) {
      if (onProgress == null) return;
      final now = clock.elapsed;
      if (!force && now - lastReport < _progressInterval) return;
      lastReport = now;
      onProgress(
        ImportProgress(
          bytesRead: bytesRead,
          totalBytes: totalBytes,
          entries: imported,
        ),
      );
    }

    void ensureNotCancelled() {
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
    }

    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final chunk = buffer;
      buffer = <String>[];
      records = 0;

      final parsed = useIsolate
          ? await parseChunkInIsolate(chunk, header)
          : M3uParser.parseRecords(chunk, header);
      ensureNotCancelled();
      discarded += parsed.discarded;

      var batch = <KeyedEntry>[];
      for (final entry in parsed.entries) {
        if (imported + batch.length >= maxEntries) {
          truncated = true;
          break;
        }
        final folded = foldName(entry.name);
        final key = channelKeyFrom(entry.tvgId, folded);
        if (!seen.add(key)) {
          duplicates++;
          continue;
        }
        batch.add(KeyedEntry(entry, key, folded));
        if (batch.length == insertBatchSize) {
          await sink(batch, imported);
          imported += batch.length;
          batch = <KeyedEntry>[];
          ensureNotCancelled();
          report();
        }
      }
      if (batch.isNotEmpty) {
        await sink(batch, imported);
        imported += batch.length;
      }
      report(force: true);
    }

    final lines = M3uStreamReader.lines(
      bytes,
      onBytes: (n) {
        bytesRead = n;
        report();
      },
    );

    try {
      await for (final raw in lines) {
        ensureNotCancelled();
        final line = raw.trim();
        if (line.isEmpty) continue;

        if (!sawContent) {
          sawContent = true;
          if (line.startsWith('<') || line.startsWith('{')) {
            throw const SourceException(
              SourceError.invalidContent,
              detail: 'html-or-json',
            );
          }
        }

        if (line.startsWith('#EXTM3U')) {
          sawHeader = true;
          header = M3uParser.parseHeader(line);
          continue;
        }

        buffer.add(line);
        if (line.codeUnitAt(0) != 0x23) {
          records++;
          if (records >= parseChunkRecords) {
            await flush();
            if (truncated) break;
          }
        }
      }
      if (!truncated) await flush();
    } on SourceException {
      rethrow;
    } catch (error) {
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
      rethrow;
    }

    if (imported == 0 && !sawHeader && sawContent) {
      throw const SourceException(SourceError.invalidContent, detail: 'no-m3u');
    }

    clock.stop();
    return ImportResult(
      imported: imported,
      discarded: discarded,
      duplicates: duplicates,
      truncated: truncated,
      elapsed: clock.elapsed,
      epgUrl: _firstUrl(header.urlTvg),
    );
  }

  /// `url-tvg` pode trazer várias URLs separadas por vírgula.
  static String? _firstUrl(String? raw) {
    if (raw == null) return null;
    for (final part in raw.split(',')) {
      final candidate = part.trim();
      final uri = Uri.tryParse(candidate);
      if (uri != null && uri.host.isNotEmpty) return candidate;
    }
    return null;
  }
}
