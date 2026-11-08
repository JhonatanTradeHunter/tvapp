import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/features/guide/guide_controller.dart';

void main() {
  final start = DateTime(2026, 11, 8, 20);
  final layout = GuideLayout(
    viewStart: start,
    span: const Duration(hours: 3),
    width: 900,
  );

  test('floorToHalfHour arredonda para :00 ou :30', () {
    expect(
      floorToHalfHour(DateTime(2026, 11, 8, 20, 29, 59)),
      DateTime(2026, 11, 8, 20),
    );
    expect(
      floorToHalfHour(DateTime(2026, 11, 8, 20, 30)),
      DateTime(2026, 11, 8, 20, 30),
    );
    expect(
      floorToHalfHour(DateTime(2026, 11, 8, 20, 59)),
      DateTime(2026, 11, 8, 20, 30),
    );
  });

  test('xFor é linear dentro da janela', () {
    expect(layout.xFor(start), 0);
    expect(layout.xFor(start.add(const Duration(minutes: 90))), 450);
    expect(layout.xFor(start.add(const Duration(hours: 3))), 900);
  });

  test('cellFor recorta nas bordas e some fora da janela', () {
    expect(
      layout.cellFor(
        start.subtract(const Duration(minutes: 30)),
        start.add(const Duration(minutes: 30)),
      ),
      (0.0, 150.0),
    );
    expect(
      layout.cellFor(
        start.add(const Duration(hours: 2, minutes: 30)),
        start.add(const Duration(hours: 4)),
      ),
      (750.0, 900.0),
    );
    expect(
      layout.cellFor(start.subtract(const Duration(hours: 2)), start),
      isNull,
    );
    expect(
      layout.cellFor(
        start.add(const Duration(hours: 3)),
        start.add(const Duration(hours: 4)),
      ),
      isNull,
    );
  });

  test('ticks de meia em meia hora começam na primeira marca visível', () {
    final shifted = GuideLayout(
      viewStart: DateTime(2026, 11, 8, 20, 10),
      span: const Duration(hours: 1),
      width: 300,
    );
    expect(shifted.ticks(const Duration(minutes: 30)), [
      DateTime(2026, 11, 8, 20, 30),
      DateTime(2026, 11, 8, 21),
    ]);
  });

  test('clampStart mantém a janela visível dentro da carregada', () {
    final window = GuideWindow.around(DateTime(2026, 11, 8, 20, 40));
    expect(window.start, DateTime(2026, 11, 8, 19, 30));
    expect(window.end, DateTime(2026, 11, 9, 8, 30));
    const span = Duration(hours: 3);
    expect(
      GuideLayout.clampStart(DateTime(2026, 11, 8, 10), window, span),
      window.start,
    );
    expect(
      GuideLayout.clampStart(DateTime(2026, 11, 9, 7), window, span),
      window.end.subtract(span),
    );
  });
}
