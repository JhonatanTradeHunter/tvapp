import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/ui/adaptive/device_mode.dart';
import 'package:tvapp/core/ui/components/channel_tile.dart';
import 'package:tvapp/core/ui/focus/focusable_scale.dart';
import 'package:tvapp/core/ui/theme/app_theme.dart';
import 'package:tvapp/features/vod/poster_card.dart';
import 'package:tvapp/l10n/gen/app_localizations.dart';

Channel _channel(int i, {bool favorite = false}) => Channel(
  id: i,
  sourceId: 1,
  channelKey: 'k$i',
  position: i,
  name: 'Canal $i',
  group: 'Notícias',
  streamUrl: 'http://x/$i.ts',
  number: 10 + i,
  isFavorite: favorite,
);

Widget _host(DeviceMode mode, Widget child, {double textScale = 1}) {
  return MaterialApp(
    theme: AppTheme.build(mode),
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: UiVariantScope(
        mode: mode,
        child: Scaffold(body: child),
      ),
    ),
  );
}

Widget _catalog() {
  return ListView(
    children: [
      for (var i = 0; i < 3; i++)
        SizedBox(
          height: 64,
          child: ChannelTile(
            channel: _channel(i, favorite: i == 0),
            onSelect: () {},
            onToggleFavorite: () {},
          ),
        ),
      SizedBox(
        height: 260,
        width: 140,
        child: PosterCard(title: 'Filme', rating: 7.5, onSelect: () {}),
      ),
      AppButton(label: 'Importar', onPressed: () {}),
    ],
  );
}

void main() {
  testWidgets('toque: alvos com rótulo, tamanho mínimo e contraste', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(DeviceMode.touch, _catalog()));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('TV: canal lido com número, nome e favorito, e com ação', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(DeviceMode.tv, _catalog()));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(ChannelTile).first),
      containsSemantics(
        label: '10, Canal 0. Favorito',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byType(PosterCard)),
      containsSemantics(label: 'Filme, nota 7.5', hasTapAction: true),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('linha de canal cresce com a fonte do sistema', (tester) async {
    late double normal;
    late double large;
    await tester.pumpWidget(
      _host(
        DeviceMode.tv,
        Builder(
          builder: (context) {
            normal = ChannelTile.extentFor(context);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        DeviceMode.tv,
        Builder(
          builder: (context) {
            large = ChannelTile.extentFor(context);
            return const SizedBox();
          },
        ),
        textScale: 1.5,
      ),
    );
    expect(normal, ChannelTile.tvExtent);
    expect(large, closeTo(ChannelTile.tvExtent * 1.5, 0.01));
  });
}
