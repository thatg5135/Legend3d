## Local HTTP link to the Mudlet relay (see PROTOCOL.md).
## Mudlet connects to us; we never reach out.
class_name LinkServer
extends Node

signal linked(hello: Dictionary)
signal unlinked
signal event_received(ev: Dictionary)

const HOST := "127.0.0.1"
const PORT := 7359
const POLL_HOLD_MS := 15000
const SILENCE_MS := 25000  # no requests for this long = Mudlet is gone

class Conn:
	var peer: StreamPeerTCP
	var buf := PackedByteArray()
	var waiting := false  # holding a long poll

var session := ""
var is_linked := false
var listen_error := OK

var _server := TCPServer.new()
var _conns: Array[Conn] = []
var _poll: Conn = null
var _poll_started := 0
var _outbox: Array = []
var _last_contact := 0


func _ready() -> void:
	listen_error = _server.listen(PORT, HOST)
	if listen_error != OK:
		push_error("Legend3D: can't listen on %s:%d (error %d). Is the test listener still running?" % [HOST, PORT, listen_error])


func send_command(cmd: String) -> void:
	_outbox.append({"kind": "raw", "cmd": cmd})
	_flush_poll()


## Ask Mudlet to run a command with its output hidden from you (equipment,
## spells...); the answer comes back as a "quiet" event.
func send_quiet(cmd: String) -> void:
	_outbox.append({"kind": "quiet", "cmd": cmd})
	_flush_poll()


func request_resync() -> void:
	_outbox.append({"kind": "resync"})
	_flush_poll()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var c := Conn.new()
		c.peer = _server.take_connection()
		_conns.append(c)

	for c: Conn in _conns.duplicate():
		c.peer.poll()
		if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(c)
			continue
		var n := c.peer.get_available_bytes()
		if n > 0:
			var got: Array = c.peer.get_data(n)
			if got[0] == OK:
				c.buf = c.buf + (got[1] as PackedByteArray)
		if not c.waiting:
			_parse(c)

	var now := Time.get_ticks_msec()
	if _poll != null and now - _poll_started > POLL_HOLD_MS:
		_answer_poll([])
	if is_linked and now - _last_contact > SILENCE_MS:
		_set_unlinked()


func _drop(c: Conn) -> void:
	if _poll == c:
		_poll = null
	c.peer.disconnect_from_host()
	_conns.erase(c)


func _set_unlinked() -> void:
	if not is_linked:
		return
	is_linked = false
	session = ""
	unlinked.emit()


static func _header_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _parse(c: Conn) -> void:
	while not c.waiting:
		var end := _header_end(c.buf)
		if end < 0:
			return
		var head := c.buf.slice(0, end).get_string_from_utf8()
		var lines := head.split("\r\n")
		var first := lines[0].split(" ")
		if first.size() < 2:
			_drop(c)
			return
		var length := 0
		for i in range(1, lines.size()):
			var kv := lines[i].split(":", true, 1)
			if kv.size() == 2 and kv[0].strip_edges().to_lower() == "content-length":
				length = kv[1].strip_edges().to_int()
		var total := end + 4 + length
		if c.buf.size() < total:
			return
		var body := c.buf.slice(end + 4, total).get_string_from_utf8()
		c.buf = c.buf.slice(total)
		_handle(c, first[0], first[1], body)


func _handle(c: Conn, method: String, target: String, body: String) -> void:
	_last_contact = Time.get_ticks_msec()
	var path := target.get_slice("?", 0)
	var query := target.get_slice("?", 1) if target.contains("?") else ""

	if method == "POST" and path == "/hello":
		var msg = JSON.parse_string(body)
		var data: Dictionary = {}
		if msg is Dictionary and msg.get("data") is Dictionary:
			data = msg["data"]
		if str(data.get("session", "")) == "" or data.get("session") == null:
			_reply(c, 400, '{"ok":false,"error":"no session"}')
			return
		var old := _poll
		session = str(data["session"])
		is_linked = true
		if old != null:
			_poll = null
			old.waiting = false
			_reply(old, 409, '{"ok":false,"error":"old session"}')
		_reply(c, 200, '{"ok":true}')
		linked.emit(data)

	elif method == "POST" and path == "/events":
		var arr = JSON.parse_string(body)
		_reply(c, 200, '{"ok":true}')
		if arr is Array:
			for ev in arr:
				if ev is Dictionary:
					event_received.emit(ev)

	elif method == "GET" and path == "/commands":
		var s := ""
		for part in query.split("&"):
			if part.begins_with("s="):
				s = part.substr(2).uri_decode()
		if s == "" or s != session:
			_reply(c, 409, '{"ok":false,"error":"unknown session"}')
			return
		if _poll != null and _poll != c:
			_answer_poll([])
		_poll = c
		_poll_started = Time.get_ticks_msec()
		c.waiting = true
		_flush_poll()

	else:
		_reply(c, 404, '{"ok":false}')


func _flush_poll() -> void:
	if _poll != null and not _outbox.is_empty():
		var batch := _outbox.duplicate()
		_outbox.clear()
		_answer_poll(batch)


func _answer_poll(batch: Array) -> void:
	var c := _poll
	_poll = null
	if c == null:
		return
	c.waiting = false
	_reply(c, 200, JSON.stringify(batch))
	_parse(c)


func _reply(c: Conn, code: int, body: String) -> void:
	var reason: String = {200: "OK", 400: "Bad Request", 404: "Not Found", 409: "Conflict"}.get(code, "OK")
	var raw := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: keep-alive\r\n\r\n" % [code, reason, raw.size()]
	c.peer.put_data(head.to_utf8_buffer() + raw)
