import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_matcher.dart';
import 'package:tvapp/core/data/epg/epg_repository.dart';
import 'package:tvapp/core/data/epg/xmltv_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/core/player/playback_controller.dart';

final epgRepositoryProvider = Provider<EpgRepository>(
  (ref) => EpgRepository(db: ref.watch(databaseProvider)),
);

/// Linha crua da fonte ativa: o modelo não carrega os campos de EPG.
final activeSourceRowProvider = StreamProvider<SourceRow?>(
  (ref) => ref.watch(databaseProvider).sourceDao.watchActive(),
);

/// (sourceId, geração do EPG). Nulo enquanto não houver EPG importado.
final activeEpgKeyProvider = Provider<(int, int)?>((ref) {
  final row = ref.watch(activeSourceRowProvider).valueOrNull;
  if (row == null || row.epgGeneration == 0) return null;
  return (row.id, row.epgGeneration);
});

final epgMatcherProvider = FutureProvider<EpgMatcher?>((ref) async {
  final key = ref.watch(activeEpgKeyProvider);
  if (key == null) return null;
  final rows = await ref
      .watch(databaseProvider)
      .epgDao
      .channels(key.$1, key.$2);
  return EpgMatcher(<EpgChannelInfo>[
    for (final r in rows)
      EpgChannelInfo(id: r.xmltvId, normalizedName: r.nameNormalized),
  ]);
});

/// Relógio de minuto em minuto para "agora" e "a seguir" virarem sozinhos.
final epgMinuteProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now(),
  );
});

class NowNext {
  const NowNext({required this.match, this.current, this.next});

  final EpgMatch match;
  final ProgrammeRow? current;
  final ProgrammeRow? next;
}

final nowNextProvider = FutureProvider.autoDispose.family<NowNext?, Channel>((
  ref,
  channel,
) async {
  final key = ref.watch(activeEpgKeyProvider);
  final matcher = await ref.watch(epgMatcherProvider.future);
  if (key == null || matcher == null) return null;
  final match = matcher.match(tvgId: channel.tvgId, name: channel.name);
  if (match == null) return null;

  final now = ref.watch(epgMinuteProvider).valueOrNull ?? DateTime.now();
  final rows = await ref
      .watch(databaseProvider)
      .epgDao
      .programmesInRange(
        sourceId: key.$1,
        generation: key.$2,
        channelIds: <String>[match.xmltvId],
        from: now,
        to: now.add(const Duration(hours: 12)),
      );

  ProgrammeRow? current;
  ProgrammeRow? next;
  for (final p in rows) {
    if (!p.startUtc.isAfter(now) && p.stopUtc.isAfter(now)) {
      current ??= p;
    } else if (p.startUtc.isAfter(now)) {
      next ??= p;
    }
    if (current != null && next != null) break;
  }
  return NowNext(match: match, current: current, next: next);
});

enum EpgRefreshPhase { idle, running, failed }

class EpgRefreshState {
  const EpgRefreshState({
    this.phase = EpgRefreshPhase.idle,
    this.progress,
    this.result,
    this.error,
  });

  final EpgRefreshPhase phase;
  final ImportProgress? progress;
  final XmltvImportResult? result;
  final SourceException? error;
}

/// Atualiza o EPG ao abrir o app e depois de importar uma fonte, quando o
/// guia passou de 12h. Nunca com player ativo: não começa se houver canal
/// tocando e cancela se um canal começar. Tentativa automática é uma por
/// sessão para cada (fonte, URL); [refreshNow] ignora esse limite.
class EpgRefresher extends Notifier<EpgRefreshState> {
  final Set<String> _attempted = <String>{};
  final Set<int> _recovered = <int>{};
  ImportCancelToken? _cancel;

  @override
  EpgRefreshState build() {
    ref.listen<SourceRow?>(
      activeSourceRowProvider.select((a) => a.valueOrNull),
      (previous, next) => _scheduleAuto(),
      fireImmediately: true,
    );
    ref.listen<bool>(
      playbackControllerProvider.select((s) => s.channel != null),
      (previous, playing) {
        if (playing) {
          _cancel?.cancel();
        } else {
          _scheduleAuto();
        }
      },
    );
    ref.onDispose(() => _cancel?.cancel());
    return const EpgRefreshState();
  }

  Future<void> refreshNow() async {
    final row = ref.read(activeSourceRowProvider).valueOrNull;
    if (row == null || row.epgUrl == null) return;
    if (_playerActive || state.phase == EpgRefreshPhase.running) return;
    await _run(row.id);
  }

  void cancel() => _cancel?.cancel();

  bool get _playerActive =>
      ref.read(playbackControllerProvider).channel != null;

  /// Fora do build: [listen] com `fireImmediately` roda durante a construção,
  /// e mudar `state` ali não é permitido.
  void _scheduleAuto() {
    scheduleMicrotask(() {
      if (state.phase == EpgRefreshPhase.running || _playerActive) return;
      final row = ref.read(activeSourceRowProvider).valueOrNull;
      if (row == null) return;
      final repository = ref.read(epgRepositoryProvider);
      if (EpgRepository.needsMetadata(row) && _recovered.add(row.id)) {
        // A gravação na fonte faz a linha ativa reemitir e passar por aqui
        // de novo, já com a URL do guia.
        unawaited(repository.recoverMetadata(row.id));
        return;
      }
      if (!repository.isStale(row, DateTime.now())) return;
      if (!_attempted.add('${row.id}|${row.epgUrl}')) return;
      unawaited(_run(row.id));
    });
  }

  Future<void> _run(int sourceId) async {
    final token = ImportCancelToken();
    _cancel = token;
    state = const EpgRefreshState(phase: EpgRefreshPhase.running);
    try {
      final result = await ref
          .read(epgRepositoryProvider)
          .refresh(
            sourceId,
            cancel: token,
            onProgress: (p) {
              if (!token.isCancelled) {
                state = EpgRefreshState(
                  phase: EpgRefreshPhase.running,
                  progress: p,
                );
              }
            },
          );
      state = EpgRefreshState(result: result);
    } on SourceException catch (e) {
      if (e.error == SourceError.cancelled) {
        _attempted.clear();
        state = const EpgRefreshState();
      } else {
        state = EpgRefreshState(phase: EpgRefreshPhase.failed, error: e);
      }
    } finally {
      if (identical(_cancel, token)) _cancel = null;
    }
  }
}

final epgRefresherProvider = NotifierProvider<EpgRefresher, EpgRefreshState>(
  EpgRefresher.new,
);
