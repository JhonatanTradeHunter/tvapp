Execução: https://github.com/JhonatanTradeHunter/tvapp/actions/runs/42606387364

## Celular


**13 passaram, 0 falharam.**

| Resultado | Verificação | Detalhe | Print |
|---|---|---|---|
| ✅ | Versão antiga (banco v1): importar lista M3U |  | ![](screens/01-old-import.png) |
| ✅ | Migração v1 → atual: app abre e a lista continua lá |  | ![](screens/02-migration.png) |
| ✅ | EPG disponível para a lista que veio da versão antiga | 1 pedido(s) de /epg.xml | ![](screens/03-epg-dispon-vel-para-a-lista-que-veio-da-vers-o-antiga.png) |
| ✅ | Tocar Canal Um HLS | 1 pedidos de mídia | ![](screens/04-tocar-canal-um-hls.png) |
| ✅ | Tocar Canal Dois TS | 1 pedidos de mídia | ![](screens/05-tocar-canal-dois-ts.png) |
| ✅ | Depois de reimportar, o EPG é baixado | 1 pedido(s) de /epg.xml | ![](screens/09-depois-de-reimportar-o-epg-baixado.png) |
| ✅ | Catch-up M3U (catchup-source com {utc}) | pediu start=1794217200, esperado 1794217200 | ![](screens/11-catch-up-m3u-catchup-source-com-utc.png) |
| ✅ | Importar fonte Xtream pela API | chamadas: auth, get_live_categories, get_live_streams, get_series, get_series_categories, get_vod_categories, get_vod_streams | ![](screens/15-importar-fonte-xtream-pela-api.png) |
| ✅ | Tocar canal Xtream | 2 pedidos de mídia | ![](screens/16-tocar-canal-xtream.png) |
| ✅ | Catch-up Xtream (timeshift) | pediu 2026-11-09:06-40 = início no fuso do painel (-03:00). | ![](screens/18-catch-up-xtream-timeshift.png) |
| ✅ | Reproduzir filme por 40s | 1 pedidos de mídia | ![](screens/20-reproduzir-filme-por-40s.png) |
| ✅ | Retomar: filme oferece "Continuar de" | Resume from 00:39 | ![](screens/21-retomar-filme-oferece-continuar-de.png) |
| ✅ | Abrir série e listar episódios | S1 E1, Episodio Um, 2 min | ![](screens/22-abrir-s-rie-e-listar-epis-dios.png) |

Diálogos do sistema fechados durante o teste: Pixel Launcher isn't responding

## TV (D-pad)


**7 passaram, 0 falharam.**

| Resultado | Verificação | Detalhe | Print |
|---|---|---|---|
| ✅ | TV: app abre na configuração | emulador com leanback | ![](screens-tv/01-tv-open.png) |
| ✅ | TV: importar M3U pelo D-pad |  | ![](screens-tv/02-tv-import.png) |
| ✅ | TV: navegar na lista pelo D-pad | 1, Canal Um HLS.  → 2, Canal Dois TS.  → 2, Canal Dois TS.  → 1, Canal Um HLS.  | ![](screens-tv/03-tv-list.png) |
| ✅ | TV: tocar canal pelo D-pad | 1 pedidos de mídia | ![](screens-tv/04-tv-play.png) |
| ✅ | TV: voltar do player com BACK |  | ![](screens-tv/05-tv-back-player.png) |
| ✅ | TV: abrir o Guia pelo D-pad |  | ![](screens-tv/06-tv-guide.png) |
| ✅ | TV: voltar do Guia com BACK |  | ![](screens-tv/07-tv-guide-back.png) |
