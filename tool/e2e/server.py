#!/usr/bin/env python3
"""Servidor falso para o teste com emulador.

Serve uma lista M3U, um guia XMLTV com horários relativos ao momento do
pedido, um painel Xtream Codes mínimo (player_api.php e xmltv.php) e a mídia
de teste gerada pelo ffmpeg. Cada pedido vai para server.log em JSON, para o
driver conferir o que o app pediu (segmentos HLS, catch-up, timeshift).

O emulador enxerga a máquina do runner em 10.0.2.2.
"""

import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = 8080
HOST = "10.0.2.2"
BASE = f"http://{HOST}:{PORT}"
USER = "teste"
PASS = "senha123"
ROOT = os.path.dirname(os.path.abspath(__file__))
WWW = os.path.join(ROOT, "www")
LOG = os.path.join(ROOT, "out", "server.log")

# Fuso declarado pelo painel falso, como muitos painéis brasileiros.
PANEL_TZ = "America/Sao_Paulo"
PANEL_OFFSET = timedelta(hours=-3)


def now_utc():
    return datetime.now(timezone.utc)


def epg_times():
    """Horários do guia, arredondados para 5 min para ficarem estáveis."""
    n = now_utc().replace(second=0, microsecond=0)
    n = n - timedelta(minutes=n.minute % 5)
    past_start = n - timedelta(minutes=90)
    past_stop = n - timedelta(minutes=15)
    cur_stop = n + timedelta(minutes=45)
    next_stop = n + timedelta(minutes=105)
    return past_start, past_stop, cur_stop, next_stop


def xmltv_time(t):
    return t.strftime("%Y%m%d%H%M%S +0000")


CHANNELS = [
    ("canal.um", "Canal Um HLS"),
    ("canal.dois", "Canal Dois TS"),
    ("xt.esporte", "Xtream Esporte"),
]


def build_epg():
    ps, pe, ce, ne = epg_times()
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="e2e">']
    for cid, name in CHANNELS:
        parts.append(f'<channel id="{cid}"><display-name>{name}</display-name></channel>')
    for cid, _ in CHANNELS:
        for start, stop, title in (
            (ps, pe, "Programa Passado"),
            (pe, ce, "Programa Atual"),
            (ce, ne, "Programa Seguinte"),
        ):
            parts.append(
                f'<programme start="{xmltv_time(start)}" stop="{xmltv_time(stop)}" '
                f'channel="{cid}"><title lang="pt">{title}</title>'
                f"<desc>Programa de teste.</desc></programme>"
            )
    parts.append("</tv>")
    return "\n".join(parts), ps


def build_m3u():
    return "\n".join(
        [
            f'#EXTM3U url-tvg="{BASE}/epg.xml"',
            '#EXTINF:-1 tvg-id="canal.um" tvg-chno="1" group-title="Testes" '
            'catchup="default" catchup-days="3" '
            f'catchup-source="{BASE}/catchup/101.ts?start={{utc}}&end={{utcend}}",Canal Um HLS',
            f"{BASE}/media/hls/index.m3u8",
            '#EXTINF:-1 tvg-id="canal.dois" tvg-chno="2" group-title="Testes",Canal Dois TS',
            f"{BASE}/media/test.ts",
            "",
        ]
    )


def xtream_api(action, qs):
    ts = int(time.time())
    if action is None:
        return {
            "user_info": {
                "username": USER,
                "password": PASS,
                "auth": 1,
                "status": "Active",
                "exp_date": "1999999999",
                "is_trial": "0",
                "active_cons": "0",
                "max_connections": "1",
                "allowed_output_formats": ["m3u8", "ts"],
            },
            "server_info": {
                "url": HOST,
                "port": str(PORT),
                "server_protocol": "http",
                "timezone": PANEL_TZ,
                "timestamp_now": ts,
                "time_now": (now_utc() + PANEL_OFFSET).strftime("%Y-%m-%d %H:%M:%S"),
            },
        }
    if action == "get_live_categories":
        return [{"category_id": "10", "category_name": "Esportes", "parent_id": 0}]
    if action == "get_vod_categories":
        return [{"category_id": "20", "category_name": "Filmes de Teste", "parent_id": 0}]
    if action == "get_series_categories":
        return [{"category_id": "30", "category_name": "Séries de Teste", "parent_id": 0}]
    if action == "get_live_streams":
        return [
            {
                "num": 1,
                "name": "Xtream Esporte",
                "stream_type": "live",
                "stream_id": 301,
                "stream_icon": "",
                "epg_channel_id": "xt.esporte",
                "added": str(ts),
                "category_id": "10",
                "tv_archive": 1,
                "tv_archive_duration": 3,
            }
        ]
    if action == "get_vod_streams":
        return [
            {
                "num": 1,
                "name": "Filme Teste",
                "stream_type": "movie",
                "stream_id": 201,
                "stream_icon": "",
                "rating": "7",
                "added": str(ts),
                "category_id": "20",
                "container_extension": "mp4",
            }
        ]
    if action == "get_series":
        return [
            {
                "num": 1,
                "name": "Série Teste",
                "series_id": 401,
                "cover": "",
                "plot": "Série de teste.",
                "category_id": "30",
                "last_modified": str(ts),
            }
        ]
    if action == "get_vod_info":
        return {
            "info": {"name": "Filme Teste", "plot": "Filme de teste.", "duration_secs": 120},
            "movie_data": {
                "stream_id": 201,
                "name": "Filme Teste",
                "container_extension": "mp4",
                "category_id": "20",
            },
        }
    if action == "get_series_info":
        return {
            "seasons": [{"season_number": 1, "name": "Temporada 1", "episode_count": 1}],
            "info": {"name": "Série Teste", "plot": "Série de teste."},
            "episodes": {
                "1": [
                    {
                        "id": "501",
                        "episode_num": 1,
                        "title": "Episodio Um",
                        "container_extension": "mp4",
                        "season": 1,
                        "info": {"duration_secs": 120},
                    }
                ]
            },
        }
    return []


STATE = {"past_start": None}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WWW, **kwargs)

    def log_message(self, fmt, *args):  # silencia o log padrão
        pass

    def _record(self, status, extra=None):
        entry = {"t": time.time(), "path": self.path, "status": status}
        if extra:
            entry.update(extra)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

    def _send(self, body, ctype, status=200):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _file(self, rel, ctype):
        path = os.path.join(WWW, rel)
        with open(path, "rb") as f:
            data = f.read()
        self._send(data, ctype)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        url = urlparse(self.path)
        p = url.path
        qs = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            if p == "/state":
                self._send(json.dumps(STATE), "application/json")
                return
            if p == "/playlist.m3u":
                self._record(200)
                self._send(build_m3u(), "audio/x-mpegurl")
                return
            if p in ("/epg.xml", "/xmltv.php"):
                body, ps = build_epg()
                STATE["past_start"] = int(ps.timestamp())
                self._record(200, {"past_start": STATE["past_start"]})
                self._send(body, "application/xml")
                return
            if p == "/player_api.php":
                if qs.get("username") != USER or qs.get("password") != PASS:
                    self._record(200, {"auth": False})
                    self._send(json.dumps({"user_info": {"auth": 0}}), "application/json")
                    return
                self._record(200, {"action": qs.get("action")})
                self._send(json.dumps(xtream_api(qs.get("action"), qs)), "application/json")
                return
            m = re.match(r"^/live/[^/]+/[^/]+/(seg\d+\.ts)$", p)
            if m:
                self._record(200, {"kind": "hls_segment"})
                self._file(os.path.join("media", "hls", m.group(1)), "video/mp2t")
                return
            m = re.match(r"^/live/[^/]+/[^/]+/(\d+)\.(ts|m3u8)$", p)
            if m:
                self._record(200, {"kind": "xtream_live", "ext": m.group(2)})
                if m.group(2) == "m3u8":
                    self._file(os.path.join("media", "hls", "index.m3u8"), "application/vnd.apple.mpegurl")
                else:
                    self._file(os.path.join("media", "test.ts"), "video/mp2t")
                return
            m = re.match(r"^/(movie|series)/[^/]+/[^/]+/(\d+)\.\w+$", p)
            if m:
                self._record(200, {"kind": m.group(1)})
                self._file(os.path.join("media", "test.mp4"), "video/mp4")
                return
            m = re.match(r"^/timeshift/[^/]+/[^/]+/(\d+)/([0-9:\-]+)/(\d+)\.\w+$", p)
            if m:
                self._record(200, {"kind": "xtream_timeshift", "minutes": m.group(1), "when": m.group(2)})
                self._file(os.path.join("media", "test.ts"), "video/mp2t")
                return
            if p.startswith("/catchup/"):
                self._record(200, {"kind": "m3u_catchup", "start": qs.get("start"), "end": qs.get("end")})
                self._file(os.path.join("media", "test.ts"), "video/mp2t")
                return
            if p.startswith("/media/"):
                kind = "hls_segment" if p.endswith(".ts") and "/hls/" in p else "media"
                self._record(200, {"kind": kind})
                super().do_GET()
                return
            self._record(404)
            self._send("not found", "text/plain", 404)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # noqa: BLE001
            self._record(500, {"error": str(exc)})
            try:
                self._send(str(exc), "text/plain", 500)
            except Exception:  # noqa: BLE001
                pass


def main():
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    open(LOG, "w").close()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"servidor falso em :{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
