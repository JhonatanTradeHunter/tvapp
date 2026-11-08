#!/usr/bin/env python3
"""Roteiro do teste com emulador, dirigido por adb e uiautomator.

Cada verificação vira uma linha do relatório (out/report.md) com o print da
tela. Uma falha não interrompe o roteiro: os passos seguintes continuam, para
o relatório mostrar o máximo possível numa execução só.

Uso: driver.py <apk_novo> [apk_antigo]
"""

import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

PKG = "com.jhonatanbaseggio123.tvapp"
BASE = "http://10.0.2.2:8080"
ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
SHOTS = os.path.join(OUT, "screens")
LOG = os.path.join(OUT, "server.log")

results = []
shot_index = [0]
last_dump = [[]]


# ---------------------------------------------------------------- adb

def adb(*args, timeout=120, check=False):
    proc = subprocess.run(
        ["adb", *args], capture_output=True, text=True, timeout=timeout
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout


def shell(cmd, timeout=60):
    return adb("shell", cmd, timeout=timeout)


def screenshot(label):
    shot_index[0] += 1
    name = f"{shot_index[0]:02d}-{re.sub(r'[^a-z0-9]+', '-', label.lower()).strip('-')}.png"
    path = os.path.join(SHOTS, name)
    with open(path, "wb") as f:
        subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=f, timeout=30)
    return name


def app_alive():
    return shell(f"pidof {PKG}").strip() != ""


def launch():
    shell(f"monkey -p {PKG} -c android.intent.category.LAUNCHER 1")
    time.sleep(6)


def stop_app():
    shell(f"am force-stop {PKG}")
    time.sleep(1)


# ---------------------------------------------------------- uiautomator

def _bounds(text):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", text or "")
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return x1, y1, x2, y2


def dump():
    for _ in range(3):
        shell("uiautomator dump /sdcard/ui.xml >/dev/null 2>&1", timeout=30)
        xml = adb("exec-out", "cat", "/sdcard/ui.xml", timeout=30)
        if xml.strip().startswith("<?xml"):
            break
        time.sleep(1)
    else:
        return []
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    nodes = []
    last_dump[0] = nodes
    for n in root.iter("node"):
        b = _bounds(n.get("bounds"))
        if not b or b[2] <= b[0] or b[3] <= b[1]:
            continue
        label = " | ".join(
            v for v in (n.get("text"), n.get("content-desc"), n.get("hint")) if v
        )
        nodes.append(
            {
                "label": label,
                "cls": n.get("class", ""),
                "bounds": b,
                "clickable": n.get("clickable") == "true",
            }
        )
    return nodes


SYSTEM_DIALOG = re.compile(r"isn't responding|keeps stopping|has stopped", re.I)
dismissed = []


def dismiss_system_dialogs(nodes):
    """O emulador lento às vezes mostra ANR do launcher por cima do app."""
    if not any(SYSTEM_DIALOG.search(n["label"]) for n in nodes):
        return False
    title = next(n["label"] for n in nodes if SYSTEM_DIALOG.search(n["label"]))
    for n in nodes:
        if re.fullmatch(r"Wait|Close app|OK", n["label"], re.I):
            dismissed.append(title)
            print(f"    diálogo do sistema fechado: {title}", flush=True)
            tap_node(n)
            return True
    return False


def find(pattern, timeout=20, cls=None):
    rx = re.compile(pattern, re.I | re.M)
    end = time.time() + timeout
    while True:
        nodes = dump()
        if dismiss_system_dialogs(nodes):
            continue
        for n in nodes:
            if rx.search(n["label"]) and (cls is None or cls in n["cls"]):
                return n
        if time.time() > end:
            return None
        time.sleep(1.5)


def tap_node(node):
    x1, y1, x2, y2 = node["bounds"]
    shell(f"input tap {(x1 + x2) // 2} {(y1 + y2) // 2}")
    time.sleep(1.5)


def tap(pattern, timeout=20, cls=None):
    node = find(pattern, timeout, cls)
    if node is None:
        return False
    tap_node(node)
    return True


def nth_edit(index, timeout=10):
    """Campos de texto do Flutter não expõem o rótulo ao uiautomator."""
    end = time.time() + timeout
    while True:
        nodes = dump()
        if dismiss_system_dialogs(nodes):
            continue
        edits = [n for n in nodes if n["cls"].endswith("EditText")]
        if len(edits) > index:
            return edits[index]
        if time.time() > end:
            return None
        time.sleep(1.5)


def type_into(pattern, text, timeout=20, index=None):
    node = find(pattern, 3) if pattern else None
    if node is None and index is not None:
        node = nth_edit(index, timeout)
    if node is None:
        return False
    tap_node(node)
    time.sleep(1)
    safe = text.replace(" ", "%s").replace("&", "\\&")
    shell(f"input text '{safe}'")
    time.sleep(1)
    return True


def hide_keyboard():
    # ESC fecha o teclado sem disparar o "voltar" da rota.
    shell("input keyevent 111")
    time.sleep(1)


def back():
    shell("input keyevent 4")
    time.sleep(2)


def swipe_up():
    shell("input swipe 540 1500 540 600 300")
    time.sleep(1)


# ------------------------------------------------------------- relatório

def check(name, ok, detail="", shot_label=None):
    shot = screenshot(shot_label or name)
    results.append({"name": name, "ok": ok, "detail": detail, "shot": shot})
    mark = "OK " if ok else "FALHOU"
    print(f"[{mark}] {name} {detail}", flush=True)
    if not ok:
        shell("uiautomator dump /sdcard/ui.xml >/dev/null 2>&1", timeout=30)
        raw = adb("exec-out", "cat", "/sdcard/ui.xml", timeout=30)
        compact = re.sub(r'(index|package|checkable|checked|enabled|focusable|focused|scrollable|long-clickable|password|selected|resource-id|NAF|drawing-order|hint|display-id)="[^"]*" ?', "", raw)
        print("    xml: " + compact[:3000].replace("\n", " "), flush=True)
    return ok


def skip(name, detail):
    results.append({"name": name, "ok": None, "detail": detail, "shot": None})
    print(f"[PULADO] {name} {detail}", flush=True)


def server_log(since=0.0):
    entries = []
    try:
        with open(LOG, encoding="utf-8") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if e.get("t", 0) >= since:
                    entries.append(e)
    except FileNotFoundError:
        pass
    return entries


def last_past_start():
    starts = [e["past_start"] for e in server_log() if "past_start" in e]
    return starts[-1] if starts else None


# --------------------------------------------------------------- passos

def import_url_source():
    """Primeira execução: a tela de configuração é a raiz."""
    if not tap(r"^URL$", timeout=40):
        print("    passo: aba URL não encontrada", flush=True)
        return False
    if not type_into(None, f"{BASE}/playlist.m3u", index=0):
        print("    passo: campo da URL não encontrado", flush=True)
        return False
    hide_keyboard()
    if not tap(r"^Import$|^Importar$", timeout=10):
        swipe_up()
        if not tap(r"^Import$|^Importar$", timeout=10):
            print("    passo: botão Importar não encontrado", flush=True)
            return False
    return find(r"Canal Um HLS", timeout=60) is not None


def scenario_migration(old_apk, new_apk):
    if not old_apk or not os.path.exists(old_apk):
        skip("Migração do banco", "APK antigo indisponível; instalação limpa.")
        adb("install", "-r", "-g", new_apk, timeout=300, check=True)
        launch()
        ok = import_url_source()
        check("Importar lista M3U pela URL", ok, shot_label="import-m3u")
        return ok

    adb("install", "-r", "-g", old_apk, timeout=300, check=True)
    launch()
    ok_old = import_url_source()
    check("Versão antiga (banco v1): importar lista M3U", ok_old, shot_label="old-import")
    stop_app()

    adb("install", "-r", "-g", new_apk, timeout=300, check=True)
    launch()
    alive = app_alive()
    kept = find(r"Canal Um HLS", timeout=40) is not None
    check(
        "Migração v1 → atual: app abre e a lista continua lá",
        alive and kept,
        "" if alive else "o app fechou ao abrir",
        shot_label="migration",
    )
    if not kept:
        # Segue o roteiro com a lista importada de novo, se der.
        ok = import_url_source()
        check("Importar lista M3U pela URL (após migração)", ok, shot_label="reimport")
        return ok
    return True


def wait_requests(kinds, since, timeout=25):
    end = time.time() + timeout
    while time.time() < end:
        hits = [e for e in server_log(since) if e.get("kind") in kinds]
        if hits:
            return hits
        time.sleep(1)
    return []


def scenario_epg_download():
    hits = [e for e in server_log() if e.get("path", "").startswith("/epg.xml")]
    if not hits:
        end = time.time() + 30
        while time.time() < end and not hits:
            hits = [e for e in server_log() if e.get("path", "").startswith("/epg.xml")]
            time.sleep(2)
    check(
        "EPG baixado depois da importação (url-tvg)",
        bool(hits),
        f"{len(hits)} pedido(s) de /epg.xml" if hits else "o app não pediu o /epg.xml em 30s",
    )


def scenario_live_playback():
    for title, kinds in (
        ("Canal Um HLS", {"hls_segment"}),
        ("Canal Dois TS", {"media"}),
    ):
        since = time.time()
        if not tap(re.escape(title), timeout=15):
            check(f"Tocar {title}", False, "canal não encontrado na lista")
            continue
        hits = wait_requests(kinds, since)
        time.sleep(6)
        alive = app_alive()
        detail = f"{len(hits)} pedidos de mídia" if hits else "nenhum pedido de mídia chegou ao servidor"
        if not alive:
            detail += "; o app fechou"
        check(f"Tocar {title}", bool(hits) and alive, detail)
        back()
        time.sleep(1)


def open_guide_catchup(channel_label):
    if not tap(r"^Guide$|^Guia$", timeout=10):
        return "aba Guia não encontrada"
    time.sleep(3)
    screenshot(f"guide-{channel_label}")
    node = find(r"Programa Passado", timeout=15)
    if node is None:
        shell("input swipe 300 800 900 800 300")
        node = find(r"Programa Passado", timeout=10)
    if node is None:
        return "o programa encerrado não apareceu na grade"
    tap_node(node)
    if not tap(r"Watch this programme|Assistir este programa", timeout=10):
        return "o botão de catch-up não apareceu no detalhe"
    return None


def scenario_m3u_catchup():
    since = time.time()
    error = open_guide_catchup("m3u")
    if error:
        check("Catch-up M3U (catchup-source com {utc})", False, error)
        return
    hits = wait_requests({"m3u_catchup"}, since)
    expected = last_past_start()
    if not hits:
        check("Catch-up M3U (catchup-source com {utc})", False, "o pedido de catch-up não chegou")
    else:
        got = hits[0].get("start")
        ok = expected is not None and got == str(expected)
        check(
            "Catch-up M3U (catchup-source com {utc})",
            ok,
            f"pediu start={got}, esperado {expected}",
        )
    back()
    back()


def go_settings_add_xtream():
    if not tap(r"^Settings$|^Configurações$", timeout=10):
        return "aba Configurações não encontrada"
    if not tap(r"Manage source|Gerenciar fonte|Add source|Adicionar fonte", timeout=10):
        return "botão de gerenciar fonte não encontrado"
    if not tap(r"Xtream", timeout=10):
        return "aba Xtream não encontrada"
    fields = ("http://10.0.2.2", "8080", "teste", "senha123")
    for index, value in enumerate(fields):
        if not type_into(None, value, timeout=8, index=index):
            return f"campo de texto {index + 1} não encontrado"
        hide_keyboard()
    if not tap(r"^Import$|^Importar$", timeout=8):
        swipe_up()
        if not tap(r"^Import$|^Importar$", timeout=8):
            return "botão Importar não encontrado"
    return None


def scenario_xtream():
    error = go_settings_add_xtream()
    if error:
        check("Importar fonte Xtream pela API", False, error)
        return False
    time.sleep(5)
    if not tap(r"^Live$|^Ao vivo$", timeout=10):
        pass
    found = find(r"Xtream Esporte", timeout=60) is not None
    api_calls = sorted({e.get("action") or "auth" for e in server_log() if "action" in e})
    check(
        "Importar fonte Xtream pela API",
        found,
        "chamadas: " + ", ".join(api_calls) if api_calls else "nenhuma chamada ao player_api",
    )
    if not found:
        return False

    since = time.time()
    tap(r"Xtream Esporte", timeout=10)
    hits = wait_requests({"xtream_live", "hls_segment"}, since)
    time.sleep(5)
    check("Tocar canal Xtream", bool(hits) and app_alive(), f"{len(hits)} pedidos de mídia")
    back()
    return True


def scenario_xtream_catchup():
    since = time.time()
    error = open_guide_catchup("xtream")
    name = "Catch-up Xtream (timeshift)"
    if error:
        check(name, False, error)
        return
    hits = wait_requests({"xtream_timeshift"}, since)
    expected = last_past_start()
    if not hits:
        check(name, False, "o pedido de timeshift não chegou")
    else:
        when = hits[0].get("when", "")
        detail = f"pediu {when}"
        ok = False
        try:
            asked = datetime.strptime(when, "%Y-%m-%d:%H-%M").replace(tzinfo=timezone.utc)
            start = datetime.fromtimestamp(expected, timezone.utc)
            local = start + timedelta(hours=-3)
            if asked == start:
                detail += " = início em UTC. Painel declara America/Sao_Paulo: num painel real, o programa viria 3h deslocado."
            elif asked.replace(tzinfo=None) == local.replace(tzinfo=None):
                detail += " = início no fuso do painel (-03:00)."
                ok = True
            else:
                detail += f"; não bate com o início ({start:%Y-%m-%d:%H-%M} UTC)"
            if asked == start:
                ok = False
        except (ValueError, TypeError) as exc:
            detail += f"; erro ao ler: {exc}"
        check(name, ok, detail)
    back()
    back()


def scenario_vod():
    if not tap(r"Movies and series|Filmes e séries", timeout=10):
        check("Abrir Filmes e séries", False, "aba não encontrada")
        return
    if not tap(r"Filme Teste", timeout=20):
        check("Abrir Filme Teste", False, "filme não apareceu na grade")
        return
    screenshot("movie-detail")
    since = time.time()
    if not tap(r"^Play$|^Reproduzir$|From the start|Do início", timeout=10):
        check("Reproduzir filme", False, "botão Reproduzir não encontrado")
        return
    hits = wait_requests({"movie"}, since)
    time.sleep(40)
    check("Reproduzir filme por 40s", bool(hits) and app_alive(), f"{len(hits)} pedidos de mídia")
    back()
    time.sleep(2)
    resume = find(r"Resume from|Continuar de", timeout=10)
    if resume is None:
        back()
        tap(r"Filme Teste", timeout=10)
        resume = find(r"Resume from|Continuar de", timeout=10)
    check(
        "Retomar: filme oferece \"Continuar de\"",
        resume is not None,
        resume["label"] if resume else "opção não apareceu",
    )
    back()

    if tap(r"^Series$|^Séries$", timeout=10) and tap(r"Série Teste", timeout=20):
        ep = find(r"Episodio Um|S1 E1", timeout=20)
        check("Abrir série e listar episódios", ep is not None, ep["label"] if ep else "episódio não apareceu")
        back()
    else:
        check("Abrir série e listar episódios", False, "série não apareceu")


# ---------------------------------------------------------------- main

def write_report():
    lines = ["# Teste com emulador", ""]
    ok = sum(1 for r in results if r["ok"] is True)
    bad = sum(1 for r in results if r["ok"] is False)
    lines.append(f"**{ok} passaram, {bad} falharam.**")
    lines.append("")
    lines.append("| Resultado | Verificação | Detalhe | Print |")
    lines.append("|---|---|---|---|")
    for r in results:
        mark = "✅" if r["ok"] else ("⏭️" if r["ok"] is None else "❌")
        detail = (r["detail"] or "").replace("|", "/")
        lines.append(f"| {mark} | {r['name']} | {detail} | {r['shot'] or ''} |")
    if dismissed:
        lines.append("")
        lines.append("Diálogos do sistema fechados durante o teste: " + "; ".join(sorted(set(dismissed))))
    with open(os.path.join(OUT, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return bad


def main():
    os.makedirs(SHOTS, exist_ok=True)
    # Sem o aviso "Viewing full screen" ao entrar no player em tela cheia.
    shell("settings put secure immersive_mode_confirmations confirmed")
    new_apk = sys.argv[1]
    old_apk = sys.argv[2] if len(sys.argv) > 2 else None

    steps = [
        ("migração", lambda: scenario_migration(old_apk, new_apk)),
        ("epg", scenario_epg_download),
        ("ao vivo", scenario_live_playback),
        ("catch-up m3u", scenario_m3u_catchup),
        ("xtream", scenario_xtream),
        ("catch-up xtream", scenario_xtream_catchup),
        ("vod", scenario_vod),
    ]
    for label, step in steps:
        try:
            if not app_alive():
                launch()
            step()
        except Exception as exc:  # noqa: BLE001
            check(f"Erro inesperado em {label}", False, str(exc)[:200])
    bad = write_report()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
