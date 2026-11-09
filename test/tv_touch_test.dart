import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';

Widget _tv(Widget child) => MaterialApp(
  home: UiVariantScope(
    mode: DeviceMode.tv,
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('TV: tocar no AppButton aciona o onPressed', (tester) async {
    var imports = 0;
    var tests = 0;
    await tester.pumpWidget(
      _tv(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: 'Testar conexão',
              primary: false,
              onPressed: () => tests++,
            ),
            AppButton(label: 'Importar', onPressed: () => imports++),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Importar'));
    await tester.pump();
    expect(imports, 1);

    await tester.tap(find.text('Testar conexão'));
    await tester.pump();
    expect(tests, 1);
  });

  testWidgets('TV: toque e D-pad acionam o mesmo FocusableScale', (
    tester,
  ) async {
    var selected = 0;
    var menus = 0;
    await tester.pumpWidget(
      _tv(
        FocusableScale(
          autofocus: true,
          onSelect: () => selected++,
          onMenu: () => menus++,
          child: const SizedBox(width: 120, height: 60, child: Text('Canal')),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Canal'));
    await tester.pump();
    expect(selected, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 2);

    await tester.longPress(find.text('Canal'));
    await tester.pump();
    expect(menus, 1);
  });

  testWidgets('TV: botão desabilitado ignora o toque', (tester) async {
    await tester.pumpWidget(
      _tv(const AppButton(label: 'Importar', onPressed: null)),
    );
    await tester.tap(find.text('Importar'), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
