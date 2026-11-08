# TV App

Player de mídia "bring your own source" em Flutter para Android TV, Google TV,
Fire TV, iPhone e Android phone. O app não hospeda, não transcodifica e não
licencia conteúdo: reproduz apenas listas que o próprio usuário informa
(arquivo M3U, URL de playlist ou credenciais Xtream Codes).

Contato: jhonatanbaseggio123@gmail.com

## Estado

Fase 1 de 6: shell adaptativo, Setup, parser M3U por streaming, engines de
reprodução e tela Ao vivo. Guia, VOD e Configurações aparecem como telas
vazias com ação focável.

## Requisitos

1. Flutter estável 3.38 ou mais novo (Dart 3.10+). O pacote `sqlite3` 3.x
   usado pelo drift depende de build hooks.
2. Android SDK; para iOS, macOS com Xcode.
3. Internet no primeiro build: o hook do `sqlite3` baixa o SQLite
   pré-compilado das releases do pacote no GitHub.

## Primeira execução

Este repositório traz só o código do app e os arquivos de plataforma que
mudam em relação ao template. O restante (Gradle, projeto Xcode, ícones) é
gerado pelo `flutter create`, que não sobrescreve arquivos existentes.

```bash
flutter create --platforms=android,ios --org com.jhonatanbaseggio123 --project-name tvapp .
rm -f test/widget_test.dart
```

Isso gera `applicationId` e bundle id `com.jhonatanbaseggio123.tvapp` e
preserva `AndroidManifest.xml`, `res/drawable/banner.xml` e
`ios/Runner/Info.plist` deste repositório.

## Ordem obrigatória antes de qualquer build

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

O `build_runner` gera os arquivos `*.g.dart` do Drift
(`app_database.g.dart`, `channel_dao.g.dart`, `source_dao.g.dart`). Sem eles,
`flutter analyze` e qualquer build falham. O `gen-l10n` gera
`lib/l10n/gen/app_localizations.dart` a partir dos ARB (PT-BR é o padrão).

## Executar

```bash
# Android TV / Google TV / Fire TV (emulador ou aparelho)
flutter run --dart-define=TV=true

# Celular Android ou simulador iOS
flutter run
```

O `--dart-define=TV=true` declara a intenção. Em runtime o app confirma: o
recurso `android.software.leanback` (ou equivalente do Fire TV) decide
sozinho. Sem ele, o build de TV só entra no modo TV se a tela tiver
`shortestSide > 600` ou se não houver touchscreen.

## Builds de verificação

```bash
flutter analyze
flutter test
flutter build apk --debug --dart-define=TV=true
flutter build ios --no-codesign
```

`test/m3u_import_perf_test.dart` cobre o critério de importar 5.000 linhas
em menos de 2s com banco SQLite em memória.

## Navegação na TV

| Tecla | Lista | Player sem overlay | Player com overlay |
|---|---|---|---|
| Setas | move o foco; na borda, pula para a região vizinha | cima/baixo trocam de canal | move o foco |
| OK | abre o canal | abre o overlay | aciona o botão |
| Menu | favorita/desfavorita | abre o overlay | |
| Back | sobe uma região (canais, grupos, sidebar, sair) | sai do player | fecha o overlay |

## Arquitetura

```
lib/core/models    modelos puros
lib/core/util      normalização de nomes
lib/core/data      Drift, parser M3U, loader, repositório, preferências
lib/core/player    PlaybackEngine, EngineSelector, engines, controller
lib/core/ui        shells, foco, tema, componentes com variante tv/touch
lib/features       setup, live
```

Engines: `ExoPlayerEngine` (Android) e `AvPlayerEngine` (iOS), ambos sobre
`video_player`, mais `MpvEngine`. Na fase 1 o mpv é um stub que retorna
`PlaybackError.Codec` e o `EngineSelector` o marca como indisponível; a
integração com `media_kit` entra na fase 2. A UI degrada pelas flags de
`EngineCapabilities`, nunca pelo tipo da engine.
