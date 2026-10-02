# Legend3D link protocol (relay v0.4.0)

Plain HTTP + JSON on 127.0.0.1:7359. The **view** (Godot app, or
`tools/test_listener.py`) is the server; the **Mudlet relay** is the client.

## Mudlet -> view

### POST /hello
Sent when the relay links (and on every relink). Starts a new session.

```json
{"seq": 41, "type": "hello", "data": {
  "client": "mudlet", "version": "0.4.0", "session": "1790892570-856168",
  "room": { ...gmcp room.info... },
  "time": {"game": "11:30 pm"},
  "ambient": { ...gmcp client.media.play... },
  "vitals": {"h": 650, "H": 708, "m": 401, "M": 526, "v": 380, "V": 393},
  "inventory": { ...gmcp char.inventory... } }}
```
Reply 200 to accept. Any error -> relay retries in 2 s. A hello without a session should get 400.

### POST /events
An ordered batch. `seq` increases by 1 per event within a session.

| type | data |
|------|------|
| `room` | gmcp `room.info` as sent by Legend: `vnum, name, area, desc, type ("indoors"/"outdoors"), is_inn, exits[{dir, to_vnum, to_name?}]` |
| `time` | `{"game": "12:59 am"}`, only when it changes |
| `media_play` | gmcp `client.media.play` |
| `media_stop` | gmcp `client.media.stop` |
| `line` | `{"text": "...", "prompt": false}`, every output line, in order |
| `snapshot` | same shape as hello data (reply to `resync`) |
| `status` | `{"fighting": true/false}` from gmcp `char.prompt.f`, only when it changes. The view never auto-`look`s while fighting. |
| `vitals` | `{"h", "H", "m", "M", "v", "V"}` from gmcp `char.prompt` (lowercase current, uppercase maximum), only when they change |
| `gmcp` | `{"pkg": "char.inventory" or "char.items.*", "data": ...}`, passed on whole whenever Legend sends one |
| `quiet` | `{"cmd": "time" or "weather", "lines": [...]}`: the output of a background check. The relay sends `time` every 240 s and `weather` every 120 s with `send(cmd, false)` and gags the output and its prompt, so the player never sees it. Checks are skipped while fighting or while the player has something typed in Mudlet's command line. |

Reply 200. An error drops the link; the relay re-hellos.

## View -> Mudlet

### GET /commands?s=SESSION
Long poll. The view holds it open (up to ~15 s) until it has commands,
then replies with a JSON list; an empty list `[]` is fine. The relay
immediately polls again.

```json
[{"kind": "raw", "cmd": "north"}, {"kind": "resync"}]
```

- `raw`: run through Mudlet's `expandAlias` (aliases and mapper apply)
- `quiet`: `{"kind": "quiet", "cmd": "equipment"}`. The relay sends the
  command with its output hidden from the player (everything up to the
  next prompt), then answers with a `quiet` event. Checks run one at a
  time and wait while the player is fighting or typing.
- `resync`: relay answers with a `snapshot` event

A poll whose `s` is not the current session gets HTTP 409. The relay
treats that as a lost link and sends a fresh hello.
