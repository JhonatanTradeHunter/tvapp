#!/usr/bin/env python3
"""Roteiro no emulador Android TV, só com o controle remoto (D-pad).

Reaproveita adb, prints, relatório e servidor falso de driver.py. Nenhum
passo usa toque: o foco anda com DPAD_*, a escolha é DPAD_CENTER e o
uiautomator confirma qual item está focado.

Uso: tv.py <apk>
"""

import os
import re
import sys
import time
import xml.etree.ElementTree as ET

import driver as d

d.OUT = os.path.join(d.ROOT, "out-tv")
d.SHOTS = os.path.join(d.OUT, "screens")

KEYS = {"up": 19, "down": 20, "left": 21, "right": 22, "center": 23, "back": 4}
NAV_LIVE = r"^Live$|^Ao vivo$"


def key(name, wait=0.8):
    d.shell(f"input keyevent {KEYS[name]}")
    time.sleep(wait)


def nodes_with_focus():
    for _ in range(3):
        d.shell("uiautomator dump /sdcard/ui.xml >/dev/null 2>&1", timeout=30)
        xml = d.adb("exec-out", "cat", "/sdcard/ui.xml", timeout=30)
        if xml.strip().startswith("<?xml"):
            break
        time.sleep(1)
    else:
        return []
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    out = []
    for n in root.iter("node"):
        b = d._bounds(n.get("bounds"))
        if not b or b[2] <= b[0] or b[3] <= b[1]:
            continue
        label = " | ".join(
            v for v in (n.get("text"), n.get("content-desc")) if v
        )
        out.append(
            {
                "label": label,
                "cls": n.get("class", ""),
                "bounds": b,
                "focused": n.get("focused") == "true",
                "focusable": n.get("focusable") == "true",
            }
        )
    return out


def area(n):
    x1, y1, x2, y2 = n["bounds"]
    return (x2 - x1) * (y2 - y1)


def center(n):
    x1, y1, x2, y2 = n["bounds"]
    return (x1 + x2) / 2, (y1 + y2) / 2


def focused(nodes):
    """O nó focado de menor área (a FlutterView inteira também aparece)."""
    candidates = [n for n in nodes if n["focused"]]
    return min(candidates, key=area) if candidates else None


def focused_label():
    cur = focused(nodes_with_focus())
    return cur["label"] if cur else ""


def focus_to(pattern, max_steps=30, scroll="down"):
    """Leva o foco até o item cujo rótulo casa com [pattern], escolhendo a
    seta pela posição do alvo em relação ao item focado."""
    rx = re.compile(pattern, re.I | re.M)
    tried = {}
    for _ in range(max_steps):
        nodes = nodes_with_focus()
        cur = focused(nodes)
        if cur and rx.search(cur["label"]):
            return True
        targets = [n for n in nodes if rx.search(n["label"])]
        focusable = [n for n in targets if n["focusable"]] or targets
        if not focusable:
            key(scroll)
            continue
        if cur is None:
            print("    foco: nenhum item focado no uiautomator → down", flush=True)
            key("down")
            continue
        if cur["cls"].endswith("EditText"):
            # Na TV o teclado na tela abre ao focar o campo e passa a receber
            # o D-pad; ESC fecha o teclado antes de seguir.
            d.hide_keyboard()
        tx, ty = center(focusable[0])
        cx, cy = center(cur)
        dx, dy = tx - cx, ty - cy
        if abs(dy) > abs(dx):
            direction = "down" if dy > 0 else "up"
        else:
            direction = "right" if dx > 0 else "left"
        print(f"    foco: {cur['label'][:40]!r} → {direction}", flush=True)
        state = (cur["label"], direction)
        tried[state] = tried.get(state, 0) + 1
        if tried[state] > 2:
            # Foco preso: tenta pelo outro eixo.
            direction = {"down": "right", "up": "left", "right": "down", "left": "up"}[direction]
        key(direction)
    return False


def press(pattern, max_steps=30):
    if not focus_to(pattern, max_steps):
        return False
    key("center", wait=1.5)
    return True


def wait_text(pattern, timeout=40):
    return d.find(pattern, timeout=timeout) is not None


# ---------------------------------------------------------------- passos

def scenario_open(apk):
    d.adb("install", "-r", "-g", apk, timeout=300, check=True)
    d.launch()
    alive = d.app_alive()
    ui = d.find(r"^URL$", timeout=40) is not None
    tv_feature = "android.software.leanback" in d.shell("pm list features")
    d.check(
        "TV: app abre na configuração",
        alive and ui,
        ("emulador com leanback" if tv_feature else "emulador sem leanback")
        + ("" if alive else "; o app fechou"),
        shot_label="tv-open",
    )
    return alive and ui


def scenario_import():
    if not press(r"^URL$"):
        d.check("TV: importar M3U pelo D-pad", False, "não chegou à aba URL")
        return False
    edit = None
    for _ in range(5):
        key("down")
        edit = next(
            (n for n in nodes_with_focus() if n["focused"] and n["cls"].endswith("EditText")),
            None,
        )
        if edit:
            break
    if edit is None:
        d.check("TV: importar M3U pelo D-pad", False, "campo da URL não recebeu o foco")
        return False
    d.shell(f"input text '{d.BASE}/playlist.m3u'")
    time.sleep(1)
    d.hide_keyboard()
    if not press(r"^Import$|^Importar$"):
        d.check("TV: importar M3U pelo D-pad", False, "botão Importar não recebeu o foco")
        return False
    ok = wait_text(r"Canal Um HLS", timeout=60)
    d.check("TV: importar M3U pelo D-pad", ok, shot_label="tv-import")
    return ok


def scenario_list():
    if not focus_to(r"Canal Um HLS"):
        d.check("TV: navegar na lista pelo D-pad", False, "o foco não chegou ao primeiro canal")
        return
    seen = [focused_label()]
    for _ in range(3):
        key("down")
        seen.append(focused_label())
    moved = len({s for s in seen if s}) >= 3
    d.check(
        "TV: navegar na lista pelo D-pad",
        moved,
        " → ".join(s.split("\n")[0][:30] for s in seen),
        shot_label="tv-list",
    )


def scenario_play():
    since = time.time()
    if not press(r"Canal Dois TS"):
        d.check("TV: tocar canal pelo D-pad", False, "o foco não chegou ao canal")
        return
    hits = d.wait_requests({"media"}, since)
    time.sleep(6)
    alive = d.app_alive()
    d.check(
        "TV: tocar canal pelo D-pad",
        bool(hits) and alive,
        f"{len(hits)} pedidos de mídia" + ("" if alive else "; o app fechou"),
        shot_label="tv-play",
    )
    key("back", wait=2)
    back_ok = wait_text(r"Canal Dois TS", timeout=10)
    d.check("TV: voltar do player com BACK", back_ok, shot_label="tv-back-player")


def scenario_guide():
    if not press(r"^Guide$|^Guia$"):
        d.check("TV: abrir o Guia pelo D-pad", False, "o foco não chegou ao Guia")
        return
    time.sleep(3)
    ok = wait_text(r"Programa", timeout=15)
    d.check("TV: abrir o Guia pelo D-pad", ok, shot_label="tv-guide")
    key("back", wait=2)
    alive = d.app_alive() and d.in_foreground()
    still = wait_text(NAV_LIVE, timeout=10)
    d.check(
        "TV: voltar do Guia com BACK",
        alive and still,
        "" if alive else "o app saiu",
        shot_label="tv-guide-back",
    )


def main():
    os.makedirs(d.SHOTS, exist_ok=True)
    d.shell("settings put secure immersive_mode_confirmations confirmed")
    apk = sys.argv[1]
    if scenario_open(apk) and scenario_import():
        for label, step in (
            ("lista", scenario_list),
            ("tocar", scenario_play),
            ("guia", scenario_guide),
        ):
            try:
                if not d.app_alive() or not d.in_foreground():
                    d.launch()
                step()
            except Exception as exc:  # noqa: BLE001
                d.check(f"Erro inesperado em {label}", False, str(exc)[:200])
    bad = d.write_report()
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
