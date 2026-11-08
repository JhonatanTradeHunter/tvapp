import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/epg/epg_matcher.dart';
import 'package:tvapp/core/data/epg/epg_providers.dart';
import 'package:tvapp/core/data/providers.dart';
import 'package:tvapp/core/models/channel.dart';

/// Arredonda para baixo até :00 ou :30, no horário local.
DateTime floorToHalfHour(DateTime t) {
  final local = t.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute < 30 ? 0 : 30,
  );
}

/// Faixa de tempo carregada do banco para cada linha. Só muda a cada meia
/// hora, então as linhas não refazem a consulta a cada minuto.
class GuideWindow {
  const GuideWindow(this.start, this.end);

  static const Duration before = Duration(hours: 1);
  static const Duration after = Duration(hours: 12);

  factory GuideWindow.around(DateTime now) {
    final anchor = floorToHalfHour(now);
    return GuideWindow(anchor.subtract(before), anchor.add(after));
  }

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is GuideWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Converte tempo em pixels dentro da janela visível da grade.
class GuideLayout {
  const GuideLayout({
    required this.viewStart,
    required this.span,
    required this.width,
  });

  final DateTime viewStart;
  final Duration span;
  final double width;

  DateTime get viewEnd => viewStart.add(span);

  double xFor(DateTime t) =>
      t.difference(viewStart).inMilliseconds * width / span.inMilliseconds;

  /// (esquerda, direita) já recortados à área visível; null se não aparece.
  (double, double)? cellFor(DateTime start, DateTime stop) {
    if (!stop.isAfter(viewStart) || !start.isBefore(viewEnd)) return null;
    final left = xFor(start).clamp(0.0, width);
    final right = xFor(stop).clamp(0.0, width);
    if (right - left < 1) return null;
    return (left, right);
  }

  double visibleWidth(DateTime start, DateTime stop) {
    final cell = cellFor(start, stop);
    return cell == null ? 0 : cell.$2 - cell.$1;
  }

  /// Marcas de horário dentro da janela, alinhadas em [step].
  List<DateTime> ticks(Duration step) {
    var t = floorToHalfHour(viewStart);
    while (t.isBefore(viewStart)) {
      t = t.add(step);
    }
    final out = <DateTime>[];
    while (t.isBefore(viewEnd)) {
      out.add(t);
      t = t.add(step);
    }
    return out;
  }

  /// Mantém o início da janela visível dentro do que foi carregado.
  static DateTime clampStart(
    DateTime value,
    GuideWindow window,
    Duration span,
  ) {
    final latest = window.end.subtract(span);
    if (value.isBefore(window.start)) return window.start;
    if (value.isAfter(latest)) return latest;
    return value;
  }
}

final guideWindowProvider = Provider<GuideWindow>((ref) {
  final now = ref.watch(epgMinuteProvider).valueOrNull ?? DateTime.now();
  return GuideWindow.around(now);
});

class GuideRowData {
  const GuideRowData({this.match, this.programmes = const <ProgrammeRow>[]});

  final EpgMatch? match;
  final List<ProgrammeRow> programmes;
}

final guideRowProvider = FutureProvider.autoDispose
    .family<GuideRowData, (Channel, GuideWindow)>((ref, key) async {
      final (channel, window) = key;
      final db = ref.watch(databaseProvider);
      final epgKey = ref.watch(activeEpgKeyProvider);
      final matcher = await ref.watch(epgMatcherProvider.future);
      if (epgKey == null || matcher == null) return const GuideRowData();
      final match = matcher.match(tvgId: channel.tvgId, name: channel.name);
      if (match == null) return const GuideRowData();
      final rows = await db.epgDao.programmesInRange(
        sourceId: epgKey.$1,
        generation: epgKey.$2,
        channelIds: <String>[match.xmltvId],
        from: window.start,
        to: window.end,
      );
      return GuideRowData(match: match, programmes: rows);
    });

bool isOnAir(ProgrammeRow p, DateTime now) =>
    !p.startUtc.isAfter(now) && p.stopUtc.isAfter(now);
