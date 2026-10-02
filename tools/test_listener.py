#!/usr/bin/env python3
"""Legend3D link tester.

Stands in for the 3D view so you can check the Mudlet relay works.
Run it, then load the relay in Mudlet. It prints what Mudlet sends
(rooms, game time, sounds, text lines), and anything you type here is
sent to the MUD through Mudlet, the same way the 3D view will do it.

    python3 test_listener.py            # show everything
    python3 test_listener.py --quiet    # hide the raw text lines

Special input:
    /resync   ask Mudlet to resend the current room
    /quit     stop
"""
import argparse
import json
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HOST, PORT = "127.0.0.1", 7359
POLL_HOLD = 15  # seconds a /commands request is held open when idle

DIRS = {"north": "n", "south": "s", "east": "e", "west": "w",
        "up": "u", "down": "d", "northeast": "ne", "northwest": "nw",
        "southeast": "se", "southwest": "sw"}

state = {"session": None, "last_seq": 0, "quiet": False}
commands = queue.Queue()
lock = threading.Lock()


def out(msg):
    with lock:
        print(msg, flush=True)


def show_room(r, label="room"):
    if not isinstance(r, dict):
        out(f"[{label}] (none)")
        return
    exits = []
    for e in r.get("exits") or []:
        d = DIRS.get(e.get("dir"), e.get("dir"))
        s = f"{d}->{e.get('to_vnum')}"
        if e.get("to_name"):
            s += f" '{e['to_name']}'"
        exits.append(s)
    inn = ", inn" if r.get("is_inn") else ""
    out(f"[{label}] {r.get('vnum')} {r.get('name')} "
        f"({r.get('type')}, {r.get('area')}{inn})")
    out(f"        exits: {'  '.join(exits) or '(none)'}")


def show_event(ev):
    seq, kind, data = ev.get("seq"), ev.get("type"), ev.get("data")
    if isinstance(seq, int):
        if state["last_seq"] and seq != state["last_seq"] + 1:
            out(f"[warn] sequence jumped {state['last_seq']} -> {seq}")
        state["last_seq"] = seq
    if kind == "room":
        show_room(data)
    elif kind == "snapshot":
        show_room((data or {}).get("room"), "resync")
    elif kind == "time":
        out(f"[time] game clock {data.get('game')}")
    elif kind == "media_play":
        out(f"[sound] play {data.get('name')} (key {data.get('key')}, "
            f"vol {data.get('volume')}, loops {data.get('loops')})")
    elif kind == "media_stop":
        out(f"[sound] stop key {data.get('key')}")
    elif kind == "line":
        if not state["quiet"]:
            tag = "prompt" if data.get("prompt") else "  |"
            out(f"{tag} {data.get('text')}")
    else:
        out(f"[{kind}] {json.dumps(data)[:200]}")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # keep the console readable

    def reply(self, body, code=200):
        raw = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw.decode("utf-8", "replace") or "null")
        except json.JSONDecodeError as e:
            out(f"[warn] bad JSON from Mudlet: {e}")
            return None

    def do_POST(self):
        path = urlparse(self.path).path
        body = self.read_json()
        if path == "/hello" and isinstance(body, dict):
            data = body.get("data") or {}
            if not data.get("session"):
                self.reply('{"ok":false,"error":"no session"}', 400)
                return
            state["session"] = data.get("session")
            state["last_seq"] = body.get("seq") or 0
            # Wake any poll left over from an older session.
            commands.put(None)
            out(f"\n=== Mudlet linked (relay v{data.get('version')}, "
                f"session {state['session']}) ===")
            show_room(data.get("room"), "start")
            t = (data.get("time") or {}).get("game")
            if t:
                out(f"[time] game clock {t}")
            if data.get("ambient"):
                out(f"[sound] ambient {data['ambient'].get('name')}")
            out("Type a command here to send it to the MUD.\n")
            self.reply('{"ok":true}')
        elif path == "/events" and isinstance(body, list):
            for ev in body:
                if isinstance(ev, dict):
                    show_event(ev)
            self.reply('{"ok":true}')
        else:
            self.reply('{"ok":false}', 404)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/commands":
            self.reply('{"ok":false}', 404)
            return
        session = (parse_qs(url.query).get("s") or [None])[0]
        if session != state["session"]:
            # Not the session we know: make the relay redo its handshake.
            self.reply('{"ok":false,"error":"unknown session"}', 409)
            return
        batch = []
        deadline = time.monotonic() + POLL_HOLD
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                break
            try:
                item = commands.get(timeout=left)
            except queue.Empty:
                break
            if session != state["session"]:
                # Poll from an older session: hand anything real back and quit.
                if item is not None:
                    commands.put(item)
                break
            if item is None:
                continue  # wake-up marker meant for an older poll
            batch.append(item)
            while True:  # grab anything else already waiting
                try:
                    more = commands.get_nowait()
                except queue.Empty:
                    break
                if more is not None:
                    batch.append(more)
            break
        self.reply(json.dumps(batch))


def read_input(server):
    for raw in sys.stdin:
        cmd = raw.strip()
        if not cmd:
            continue
        if cmd == "/quit":
            break
        if cmd == "/resync":
            commands.put({"kind": "resync"})
            continue
        if not state["session"]:
            out("[not linked yet - load the relay in Mudlet or type 3d on]")
            continue
        commands.put({"kind": "raw", "cmd": cmd})
    server.shutdown()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quiet", action="store_true", help="hide raw text lines")
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()
    state["quiet"] = args.quiet

    server = ThreadingHTTPServer((HOST, args.port), Handler)
    server.daemon_threads = True
    out(f"Legend3D link tester listening on {HOST}:{args.port}")
    out("Waiting for Mudlet... (in Mudlet, type: 3d)")
    threading.Thread(target=read_input, args=(server,), daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    out("bye")


if __name__ == "__main__":
    main()
