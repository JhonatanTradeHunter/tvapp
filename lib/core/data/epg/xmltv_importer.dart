import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tvapp/core/data/epg/xmltv_parser.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/models/playlist_source.dart';

class XmltvImportResult {
  const XmltvImportResult({
    required this.channels,
    required this.programmes,
    required this.discarded,
    required this.skippedElements,
    required this.elapsed,
  });

  final int channels;
  final int programmes;
  final int discarded;
  final int skippedElements;
  final Duration elapsed;
}

typedef XmltvChannelSink = Future<void> Function(List<XmltvChannel> batch);
typedef XmltvProgrammeSink = Future<void> Function(List<XmltvProgramme> batch);

/// `compute`: isolate no nativo, inline na web.
Future<ParsedXmltv> parseXmltvInIsolate(
  List<String> elements,
  int minStopMs,
  int maxStartMs,
) {
  return compute(_parseXmltv, (elements, minStopMs, maxStartMs));
}

ParsedXmltv _parseXmltv((List<String>, int, int) args) =>
    XmltvParser.parseElements(args.$1, minStopMs: args.$2, maxStartMs: args.$3);

Future<(List<int>?, Stream<List<int>>)> _peek(
  Stream<List<int>> source, {
  int minBytes = 1,
}) async {
  final iterator = StreamIterator<List<int>>(source);
  final head = <int>[];
  var ended = false;
  while (head.length < minBytes) {
    if (!await iterator.moveNext()) {
      ended = true;
      break;
    }
    head.addAll(iterator.current);
  }
  if (head.isEmpty) {
    await iterator.cancel();
    return (null, const Stream<List<int>>.empty());
  }
  Stream<List<int>> all() async* {
    try {
      yield head;
      if (ended) return;
      while (await iterator.moveNext()) {
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  return (head, all());
}

const int _prologBytes = 200;

final RegExp _latinProlog = RegExp(
  r'encoding\s*=\s*[\x22\x27](iso-8859-1|iso8859-1|latin-?1|windows-1252|cp1252)',
);

/// Descompacta gzip pelo número mágico e escolhe o decoder pelo prólogo
/// `<?xml encoding=...?>`. Padrão: UTF-8 tolerante.
Future<Stream<String>> decodeXmltvBytes(Stream<List<int>> input) async {
  var (head, stream) = await _peek(input, minBytes: _prologBytes);
  if (head == null) return const Stream<String>.empty();
  if (head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b) {
    (head, stream) = await _peek(
      stream.transform(gzip.decoder),
      minBytes: _prologBytes,
    );
    if (head == null) return const Stream<String>.empty();
  }
  final prologBytes = head.length > _prologBytes
      ? head.sublist(0, _prologBytes)
      : head;
  final prolog = latin1.decode(prologBytes, allowInvalid: true).toLowerCase();
  if (_latinProlog.hasMatch(prolog)) return stream.transform(latin1.decoder);
  return stream.transform(const Utf8Decoder(allowMalformed: true));
}

class XmltvImporter {
  XmltvImporter({
    this.elementsPerChunk = 4000,
    this.insertBatchSize = 2000,
    this.useIsolate = true,
    this.pastWindow = const Duration(days: 7),
    this.futureWindow = const Duration(days: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int elementsPerChunk;
  final int insertBatchSize;
  final bool useIsolate;

  /// Programas que terminaram antes disso não são guardados. Cobre o
  /// catch-up mais longo usual.
  final Duration pastWindow;
  final Duration futureWindow;
  final DateTime Function() _clock;

  static const Duration _progressInterval = Duration(milliseconds: 100);

  Future<XmltvImportResult> run({
    required Stream<List<int>> bytes,
    required XmltvChannelSink channelSink,
    required XmltvProgrammeSink programmeSink,
    int? totalBytes,
    ImportCancelToken? cancel,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    final now = _clock().toUtc();
    final minStop = now.subtract(pastWindow);
    final minStopMs = minStop.millisecondsSinceEpoch;
    final maxStartMs = now.add(futureWindow).millisecondsSinceEpoch;

    final chunker = XmltvChunker();
    final pendingStop = <String, XmltvProgramme>{};
    var elements = <String>[];
    var channelBatch = <XmltvChannel>[];
    var programmeBatch = <XmltvProgramme>[];
    var channels = 0;
    var programmes = 0;
    var discarded = 0;
    var bytesRead = 0;
    var lastReport = Duration.zero;
    var sawContent = false;

    void report({bool force = false}) {
      if (onProgress == null) return;
      final elapsed = watch.elapsed;
      if (!force && elapsed - lastReport < _progressInterval) return;
      lastReport = elapsed;
      onProgress(
        ImportProgress(
          bytesRead: bytesRead,
          totalBytes: totalBytes,
          entries: programmes,
        ),
      );
    }

    void ensureNotCancelled() {
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
    }

    Future<void> flushBatches({bool force = false}) async {
      if (channelBatch.isNotEmpty &&
          (force || channelBatch.length >= insertBatchSize)) {
        final batch = channelBatch;
        channelBatch = <XmltvChannel>[];
        await channelSink(batch);
        channels += batch.length;
      }
      while (programmeBatch.length >= insertBatchSize ||
          (force && programmeBatch.isNotEmpty)) {
        final take = programmeBatch.length < insertBatchSize
            ? programmeBatch.length
            : insertBatchSize;
        final batch = programmeBatch.sublist(0, take);
        programmeBatch = programmeBatch.sublist(take);
        await programmeSink(batch);
        programmes += batch.length;
        ensureNotCancelled();
      }
      report();
    }

    void accept(XmltvProgramme programme) {
      final waiting = pendingStop.remove(programme.channelId);
      if (waiting != null) {
        final inferred = waiting.withStop(programme.start);
        if (XmltvParser.isSaneDuration(inferred.start, programme.start) &&
            !programme.start.isBefore(minStop)) {
          programmeBatch.add(inferred);
        } else {
          discarded++;
        }
      }
      if (programme.stop == null) {
        pendingStop[programme.channelId] = programme;
      } else {
        programmeBatch.add(programme);
      }
    }

    Future<void> processElements() async {
      if (elements.isEmpty) return;
      final chunk = elements;
      elements = <String>[];
      final parsed = useIsolate
          ? await parseXmltvInIsolate(chunk, minStopMs, maxStartMs)
          : XmltvParser.parseElements(
              chunk,
              minStopMs: minStopMs,
              maxStartMs: maxStartMs,
            );
      ensureNotCancelled();
      discarded += parsed.discarded;
      channelBatch.addAll(parsed.channels);
      for (final programme in parsed.programmes) {
        accept(programme);
      }
      await flushBatches();
    }

    final counted = bytes.map((chunk) {
      bytesRead += chunk.length;
      report();
      return chunk;
    });

    try {
      final text = await decodeXmltvBytes(counted);
      await for (final piece in text) {
        ensureNotCancelled();
        if (!sawContent) {
          final head = piece.trimLeft().toLowerCase();
          if (head.isEmpty) continue;
          sawContent = true;
          if (head.startsWith('<!doctype html') || head.startsWith('<html')) {
            throw const SourceException(
              SourceError.invalidContent,
              detail: 'html',
            );
          }
          if (!head.startsWith('<')) {
            throw const SourceException(
              SourceError.invalidContent,
              detail: 'not-xml',
            );
          }
        }
        elements.addAll(chunker.feed(piece));
        if (elements.length >= elementsPerChunk) await processElements();
      }
      await processElements();
      discarded += pendingStop.length;
      pendingStop.clear();
      await flushBatches(force: true);
    } on SourceException {
      rethrow;
    } on FormatException catch (e) {
      throw SourceException(SourceError.invalidContent, detail: e.message);
    } catch (error) {
      if (cancel != null && cancel.isCancelled) {
        throw const SourceException(SourceError.cancelled);
      }
      rethrow;
    }

    if (channels == 0 && programmes == 0) {
      throw const SourceException(SourceError.empty);
    }

    report(force: true);
    watch.stop();
    return XmltvImportResult(
      channels: channels,
      programmes: programmes,
      discarded: discarded,
      skippedElements: chunker.skipped,
      elapsed: watch.elapsed,
    );
  }
}
