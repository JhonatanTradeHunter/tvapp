import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/m3u/m3u_importer.dart';
import 'package:tvapp/core/data/m3u/m3u_stream_reader.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/data/source/connection_tester.dart';
import 'package:tvapp/core/models/playlist_source.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

enum SetupPhase { idle, testing, importing, done, failed }

class SetupState {
  const SetupState({
    this.phase = SetupPhase.idle,
    this.report,
    this.progress,
    this.result,
    this.error,
  });

  final SetupPhase phase;
  final ConnectionReport? report;
  final ImportProgress? progress;
  final ImportResult? result;
  final SourceException? error;

  bool get busy => phase == SetupPhase.testing || phase == SetupPhase.importing;
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

class SetupController extends Notifier<SetupState> {
  ImportCancelToken? _cancel;

  @override
  SetupState build() => const SetupState();

  Future<void> test(PlaylistSource source) async {
    if (state.busy) return;
    state = const SetupState(phase: SetupPhase.testing);
    final report = await ref.read(connectionTesterProvider).test(source);
    final error = report.error;
    state = SetupState(
      phase: report.ok ? SetupPhase.idle : SetupPhase.failed,
      report: report,
      error: report.ok || error == null
          ? null
          : SourceException(error, statusCode: report.statusCode),
    );
  }

  Future<bool> importSource(PlaylistSource source) async {
    if (state.busy) return false;
    final token = ImportCancelToken();
    _cancel = token;
    state = const SetupState(
      phase: SetupPhase.importing,
      progress: ImportProgress(bytesRead: 0, entries: 0),
    );
    try {
      final repo = ref.read(sourceRepositoryProvider);
      var effective = source;
      if (source.kind == SourceKind.localFile) {
        final stored = await repo.persistLocalFile(source.location);
        effective = source.copyWith(location: stored);
      }
      final result = await repo.importSource(
        effective,
        cancel: token,
        onProgress: (p) {
          if (!token.isCancelled) {
            state = SetupState(phase: SetupPhase.importing, progress: p);
          }
        },
      );
      state = SetupState(phase: SetupPhase.done, result: result);
      return true;
    } on SourceException catch (e) {
      state = e.error == SourceError.cancelled
          ? const SetupState()
          : SetupState(phase: SetupPhase.failed, error: e);
      return false;
    } catch (e) {
      state = SetupState(
        phase: SetupPhase.failed,
        error: SourceException(SourceError.unknown, detail: '$e'),
      );
      return false;
    } finally {
      _cancel = null;
    }
  }

  void cancel() => _cancel?.cancel();

  void reset() => state = const SetupState();
}

String sourceErrorMessage(SourceException e, AppLocalizations l) {
  final code = e.statusCode?.toString() ?? '?';
  switch (e.error) {
    case SourceError.network:
      return l.srcErrNetwork;
    case SourceError.timeout:
      return l.srcErrTimeout;
    case SourceError.notFound:
      return l.srcErrNotFound;
    case SourceError.http4xx:
      return l.srcErrHttp4xx(code);
    case SourceError.http5xx:
      return l.srcErrHttp5xx(code);
    case SourceError.credentials:
      return l.srcErrCredentials;
    case SourceError.invalidContent:
      return l.srcErrInvalid;
    case SourceError.empty:
      return l.srcErrEmpty;
    case SourceError.cancelled:
      return l.srcErrCancelled;
    case SourceError.unknown:
      return l.srcErrUnknown;
  }
}
