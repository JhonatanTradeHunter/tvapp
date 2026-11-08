import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/focus_memory.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/core/ui/focus/tv_shortcuts.dart';

Widget _item(String id, List<String> log, {bool autofocus = false}) {
  return FocusableScale(
    autofocus: autofocus,
    onSelect: () => log.add(id),
    child: SizedBox(height: 56, child: Center(child: Text(id))),
  );
}

void main() {
  testWidgets('D-pad cruza regiões, restaura foco e ativa com select', (
    tester,
  ) async {
    final left = FocusRegionController(debugLabel: 'left');
    final right = FocusRegionController(debugLabel: 'right');
    right.backTarget = left;
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final log = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: UiVariantScope(
          mode: DeviceMode.tv,
          child: TvShortcuts(
            enabled: true,
            child: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: FocusRegion(
                      controller: left,
                      right: right,
                      child: Column(
                        children: [_item('a', log), _item('b', log)],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: FocusRegion(
                      controller: right,
                      left: left,
                      child: Column(
                        children: [
                          _item('c', log, autofocus: true),
                          _item('d', log),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(right.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(log, ['d']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(left.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(log, ['d', 'a']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(log, ['d', 'a', 'd'], reason: 'a região direita lembra o item d');

    expect(FocusRegionController.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(
      left.hasFocus,
      isTrue,
      reason: 'back na região direita sobe para a esquerda',
    );
    expect(FocusRegionController.handleBack(), isFalse);
  });

  testWidgets('sem item lembrado, restore usa o alvo preferido', (
    tester,
  ) async {
    final region = FocusRegionController(debugLabel: 'list');
    final preferred = FocusNode(debugLabel: 'preferred');
    region.preferredFallback = preferred;
    addTearDown(region.dispose);
    addTearDown(preferred.dispose);
    final log = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: UiVariantScope(
          mode: DeviceMode.tv,
          child: TvShortcuts(
            enabled: true,
            child: Scaffold(
              body: FocusRegion(
                controller: region,
                child: Column(
                  children: [
                    _item('filtro', log),
                    FocusableScale(
                      focusNode: preferred,
                      onSelect: () => log.add('primeiro canal'),
                      child: const SizedBox(
                        height: 56,
                        child: Text('primeiro canal'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    region.restore();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(log, ['primeiro canal']);
  });

  testWidgets('item focado na TV escala para 1.05', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UiVariantScope(
          mode: DeviceMode.tv,
          child: Scaffold(body: _item('x', <String>[], autofocus: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, FocusableScale.focusedScale);
  });
}
