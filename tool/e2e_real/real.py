#!/usr/bin/env python3
"""Roteiro com um painel Xtream real, reaproveitando as funções de
tool/e2e/driver.py (sem alterá-lo).

Credenciais chegam só por variável de ambiente (XTREAM_URL, XTREAM_PORT,
XTREAM_USER, XTREAM_PASS). Nenhum print é salvo enquanto usuário ou senha
estiverem na tela: antes de cada captura a árvore do uiautomator é conferida.

Uso: real.py <apk>
"""

import os
import re
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "e2e"))

import driver as d  # noqa: E402

OUT = os.path.join(HERE, "out")
SHOTS = os.path.join(OUT, "screens")
d.OUT = OUT
d.SHOTS = SHOTS

URL = os.environ.get("XTREAM_URL", "").strip()
PORT = os.environ.get("XTREAM_PORT", "").strip()
USER = os.environ.get("XTREAM_USER", "")
PASS = os.environ.get("XTREAM_PASS", "")
SECRETS = [s for s in (USER, PASS) if s]

rows = []
notes = []


def scrub(text):
    for s in SECRETS:
        text = text.replace(s, "***")
    return text


def secret_on_screen(nodes):
    return any(s in n["label"] for n in nodes for s in SECRETS)


def shot(label):
    """Print só se nenhum segredo estiver visível."""
    nodes = d.dump()
    if secret_on_screen(nodes):
        notes.append(f"Print \"{label}\" descartado: usuário ou senha visível na tela.")
        return None
    return d.screenshot(label)


def record(name, ok, detail="", label=None):
    name_shot = shot(label or name)
    rows.append({"name": name, "ok": ok, "detail": scrub(detail), "shot": name_shot})
    print(f"[{'OK ' if ok else 'FALHOU'}] {name} {scrub(detail)}", flush=True)


def screen_texts(limit=12):
    """Textos visíveis, sem campos de texto (que podem conter credenciais)."""
    seen = []
    for n in d.dump():
        if n["cls"].endswith("EditText") or not n["label"]:
            continue
        t = scrub(n["label"].replace("\n", " "))
        if t not in seen:
            seen.append(t)
    return "; ".join(seen[:limit])


_SPECIAL = set("()<>|;&*\\~\"'`$!?#[]{}")


def type_secret_safe(index, value):
    node = d.nth_edit(index, 10)
    if node is None:
        return False
    d.tap_node(node)
    time.sleep(1)
    escaped = "".join(
        "%s" if c == " " else ("\\" + c if c in _SPECIAL else c) for c in value
    )
    d.shell(f"input text {escaped}")
    time.sleep(1)
    d.hide_keyboard()
    return True


NAV_LIVE = r"^Live$|^Ao vivo$"


def import_xtream():
    if not d.tap(r"Xtream", timeout=60):
        return False, "aba Xtream não encontrada na configuração"
    fields = (URL, PORT, USER, PASS)
    for index, value in enumerate(fields):
        if not value:
            continue
        if not type_secret_safe(index, value):
            return False, f"campo de texto {index + 1} não encontrado"
    if not d.tap(r"^Import$|^Importar$", timeout=8):
        d.swipe_up()
        if not d.tap(r"^Import$|^Importar$", timeout=8):
            return False, "botão Importar não encontrado"
    start = time.time()
    end = start + 600
    while time.time() < end:
        if d.find(NAV_LIVE, timeout=5) is not None:
            return True, f"importou em {int(time.time() - start)}s"
        nodes = d.dump()
        busy = any(
            n["cls"].endswith("ProgressBar") or re.search(r"Importando|Importing|Testando|Testing", n["label"], re.I)
            for n in nodes
        )
        if not busy and time.time() - start > 20:
            texts = screen_texts()
            if re.search(r"erro|error|falh|fail|recus|refus|tempo|timeout|inválid|invalid|negad|denied|autentic|auth", texts, re.I):
                return False, texts
        time.sleep(5)
    return False, "sem resposta em 10 min: " + screen_texts()


def wide_rows():
    """Linhas de lista ocupam quase toda a largura; chips de grupo não."""
    nodes = d.dump()
    width = max((n["bounds"][2] for n in nodes), default=1080)
    height = max((n["bounds"][3] for n in nodes), default=2400)
    out = []
    for n in nodes:
        x1, y1, x2, y2 = n["bounds"]
        if not n["clickable"] or not n["label"]:
            continue
        if (x2 - x1) < width * 0.6 or y1 < height * 0.15 or y2 > height * 0.92:
            continue
        out.append(n)
    return sorted(out, key=lambda n: n["bounds"][1])


def scenario_live():
    d.tap(NAV_LIVE, timeout=10)
    time.sleep(4)
    record("Ao vivo: lista de canais", True, screen_texts(6), "live-1")
    for i in range(2, 5):
        d.swipe_up()
        time.sleep(1.5)
        name = shot(f"live-{i}")
        if name:
            rows.append({"name": f"Ao vivo: rolagem {i - 1}", "ok": True, "detail": "", "shot": name})


def scenario_guide():
    if not d.tap(r"^Guide$|^Guia$", timeout=10):
        record("Guia", False, "aba Guia não encontrada")
        return
    time.sleep(8)
    record("Guia", True, screen_texts(6), "guide")
    d.shell("input swipe 900 1200 300 1200 300")
    time.sleep(2)
    name = shot("guide-scroll")
    if name:
        rows.append({"name": "Guia: rolagem lateral", "ok": True, "detail": "", "shot": name})
    d.to_shell()


def scenario_play():
    d.tap(NAV_LIVE, timeout=10)
    time.sleep(3)
    candidates = wide_rows()
    if not candidates:
        record("Canal tocando por 15s", False, "nenhum canal encontrado na lista")
        return
    channel = candidates[0]
    title = scrub(channel["label"].split("\n")[0])
    d.tap_node(channel)
    time.sleep(5)
    shot("play-5s")
    time.sleep(10)
    alive = d.app_alive()
    texts = screen_texts(6)
    error = re.search(r"erro|error|falh|fail|indispon|unavailable|não foi|could not", texts, re.I)
    record(
        "Canal tocando por 15s",
        alive and not error,
        f"{title}. Na tela: {texts}" if texts else title,
        "play-15s",
    )
    d.back()
    time.sleep(2)


def scenario_vod():
    d.to_shell()
    if not d.tap(r"Movies and series|Filmes e séries", timeout=10):
        record("Filmes", False, "aba não encontrada")
        return
    time.sleep(6)
    record("Filmes", True, screen_texts(6), "movies")
    d.swipe_up()
    time.sleep(1.5)
    name = shot("movies-scroll")
    if name:
        rows.append({"name": "Filmes: rolagem", "ok": True, "detail": "", "shot": name})
    if d.tap(r"^Series$|^Séries$", timeout=10):
        time.sleep(6)
        record("Séries", True, screen_texts(6), "series")
    else:
        record("Séries", False, "aba Séries não encontrada")


def counts():
    d.stop_app()
    path = os.path.join(OUT, "tvapp.sqlite")
    with open(path, "wb") as f:
        import subprocess

        subprocess.run(
            ["adb", "exec-out", "run-as", d.PKG, "cat", "files/tvapp.sqlite"],
            stdout=f,
            timeout=120,
        )
    try:
        db = sqlite3.connect(path)
        src = db.execute(
            "SELECT id, active_generation FROM sources WHERE is_active = 1"
        ).fetchone()
        if not src:
            return None
        sid, gen = src
        result = {}
        for table in ("channels", "vod_items", "series_items"):
            result[table] = db.execute(
                f"SELECT COUNT(*) FROM {table} WHERE source_id = ? AND generation = ?",
                (sid, gen),
            ).fetchone()[0]
        db.close()
        return result
    except sqlite3.Error as exc:
        notes.append(f"Contagem pelo banco falhou: {exc}")
        return None
    finally:
        os.remove(path)


def write_report(summary):
    lines = ["# Teste com painel Xtream real", ""]
    lines.extend(summary)
    lines.append("")
    lines.append("| Resultado | Verificação | Detalhe | Print |")
    lines.append("|---|---|---|---|")
    for r in rows:
        mark = "✅" if r["ok"] else "❌"
        detail = (r["detail"] or "").replace("|", "/")
        lines.append(f"| {mark} | {r['name']} | {detail} | {r['shot'] or ''} |")
    if notes:
        lines.append("")
        lines.append("**Observações:**")
        lines.extend(f"* {scrub(n)}" for n in notes)
    with open(os.path.join(OUT, "report.md"), "w", encoding="utf-8") as f:
        f.write(scrub("\n".join(lines)) + "\n")


def main():
    os.makedirs(SHOTS, exist_ok=True)
    if not (URL and USER and PASS):
        write_report(["**Segredos XTREAM_URL, XTREAM_USER e XTREAM_PASS não configurados.**"])
        return 1
    d.shell("settings put secure immersive_mode_confirmations confirmed")
    d.adb("install", "-r", "-g", sys.argv[1], timeout=300, check=True)
    d.launch()

    ok, detail = import_xtream()
    record("Importar fonte Xtream", ok, detail, "after-import")
    summary = []
    if ok:
        for label, step in (
            ("ao vivo", scenario_live),
            ("guia", scenario_guide),
            ("canal", scenario_play),
            ("filmes e séries", scenario_vod),
        ):
            try:
                if not d.app_alive() or not d.in_foreground():
                    d.launch()
                d.to_shell()
                step()
            except Exception as exc:  # noqa: BLE001
                record(f"Erro inesperado em {label}", False, str(exc)[:200])
    c = counts()
    if c:
        summary.append(
            f"**Importados: {c['channels']} canais, {c['vod_items']} filmes, "
            f"{c['series_items']} séries.**"
        )
    elif ok:
        summary.append("**Contagem indisponível.**")
    else:
        summary.append("**A importação não terminou.**")
    write_report(summary)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
