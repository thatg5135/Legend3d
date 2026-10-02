## Your settings and key bindings, kept in data/settings.json.
## Every key Legend3D answers to is listed in ACTIONS and can be rebound in
## the menu (Settings > Controls); your own command shortcuts live here too.
class_name Settings
extends RefCounted

const PATH := "res://data/settings.json"

## [id, label, group, default binding]
## A binding is {"key": keycode} or {"mouse": button}, plus "ctrl"/"alt"/"shift".
const ACTIONS := [
	["forward", "Walk forward", "Moving", {"key": KEY_UP}],
	["back", "Walk back", "Moving", {"key": KEY_DOWN}],
	["turn_left", "Turn left", "Moving", {"key": KEY_LEFT}],
	["turn_right", "Turn right", "Moving", {"key": KEY_RIGHT}],
	["run", "Run (hold)", "Moving", {"key": KEY_SHIFT}],
	["sidestep", "Sidestep with turn keys (hold)", "Moving", {"key": KEY_ALT}],
	["mouse_look", "Mouse look on/off", "Moving", {"mouse": MOUSE_BUTTON_RIGHT}],
	["menu", "Open / close the menu", "Menu", {"key": KEY_TAB}],
	["character", "Character", "Menu", {"key": KEY_I, "ctrl": true}],
	["spellbook", "Spellbook", "Menu", {"key": KEY_B, "ctrl": true}],
	["world", "World (map, notes, NPCs)", "Menu", {"key": KEY_M, "ctrl": true}],
	["settings", "Settings", "Menu", {"key": KEY_O, "ctrl": true}],
	["help", "Help", "Menu", {"key": KEY_F1}],
	["history_prev", "Previous command", "Typing", {"key": KEY_UP, "ctrl": true}],
	["history_next", "Next command", "Typing", {"key": KEY_DOWN, "ctrl": true}],
	["log_up", "Scroll text up", "Typing", {"key": KEY_PAGEUP}],
	["log_down", "Scroll text down", "Typing", {"key": KEY_PAGEDOWN}],
	["sound", "Sound on/off", "View", {"key": KEY_F2}],
	["pixels", "Pixel size", "View", {"key": KEY_F3}],
	["quality", "Quality", "View", {"key": KEY_F4}],
	["reload", "Reload your data files", "View", {"key": KEY_F5}],
]

var binds := {}       # id -> binding
var shortcuts := []   # [{"bind": binding, "cmd": "cast 'heal'"}]
var video := {}
var audio := {}
var ui := {}
var spell_cmd := "spells"
var skill_cmd := "skills"


func _init() -> void:
	reset_all()


func reset_all() -> void:
	binds = {}
	for a in ACTIONS:
		binds[a[0]] = (a[3] as Dictionary).duplicate()
	shortcuts = []
	video = {"quality": 2, "pixel": 2, "rays": true, "fps_cap": 0, "fov": 68.0, "mouse_sens": 1.0}
	audio = {"sound": false, "volume": 0.8}
	ui = {"hud_scale": 1.0, "compass": true, "bars": true, "held": true, "names": true, "exit_labels": true}


func default_of(id: String) -> Dictionary:
	for a in ACTIONS:
		if a[0] == id:
			return (a[3] as Dictionary).duplicate()
	return {}


func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary):
		push_warning("Legend3D: couldn't read %s" % PATH)
		return
	if d.get("keys") is Dictionary:
		for id in d["keys"]:
			if binds.has(id) and d["keys"][id] is Dictionary:
				binds[id] = _clean(d["keys"][id])
	if d.get("shortcuts") is Array:
		shortcuts = []
		for s in d["shortcuts"]:
			if s is Dictionary and s.get("bind") is Dictionary:
				shortcuts.append({"bind": _clean(s["bind"]), "cmd": str(s.get("cmd", ""))})
	for part in [["video", video], ["audio", audio], ["interface", ui]]:
		if d.get(part[0]) is Dictionary:
			for k in d[part[0]]:
				if (part[1] as Dictionary).has(k):
					part[1][k] = d[part[0]][k]
	spell_cmd = str(d.get("spell_command", spell_cmd))
	skill_cmd = str(d.get("skill_command", skill_cmd))


func save_file() -> void:
	var out := {
		"_help": "Legend3D settings. Easiest to change in the menu (Tab). Keys are Godot keycodes.",
		"keys": binds, "shortcuts": shortcuts, "video": video, "audio": audio, "interface": ui,
		"spell_command": spell_cmd, "skill_command": skill_cmd,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Legend3D: couldn't write %s" % PATH)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()


static func _clean(b: Dictionary) -> Dictionary:
	var o := {}
	if b.has("key"):
		o["key"] = int(b["key"])
	if b.has("mouse"):
		o["mouse"] = int(b["mouse"])
	for m in ["ctrl", "alt", "shift"]:
		if bool(b.get(m, false)):
			o[m] = true
	return o


## A binding from what you just pressed.
static func from_event(e: InputEvent) -> Dictionary:
	var b := {}
	if e is InputEventKey:
		b["key"] = int((e as InputEventKey).keycode)
		var k := int(b["key"])
		if e.ctrl_pressed and k != KEY_CTRL:
			b["ctrl"] = true
		if e.alt_pressed and k != KEY_ALT:
			b["alt"] = true
		if e.shift_pressed and k != KEY_SHIFT:
			b["shift"] = true
	elif e is InputEventMouseButton:
		b["mouse"] = int((e as InputEventMouseButton).button_index)
		if e.ctrl_pressed:
			b["ctrl"] = true
		if e.alt_pressed:
			b["alt"] = true
		if e.shift_pressed:
			b["shift"] = true
	return b


static func bind_text(b: Dictionary) -> String:
	if b.is_empty():
		return "(none)"
	var parts := []
	if b.get("ctrl", false):
		parts.append("Ctrl")
	if b.get("alt", false):
		parts.append("Alt")
	if b.get("shift", false):
		parts.append("Shift")
	if b.has("mouse"):
		parts.append({MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse",
			MOUSE_BUTTON_MIDDLE: "Middle mouse", MOUSE_BUTTON_XBUTTON1: "Mouse back",
			MOUSE_BUTTON_XBUTTON2: "Mouse forward"}.get(int(b["mouse"]), "Mouse %d" % int(b["mouse"])))
	elif b.has("key"):
		parts.append(OS.get_keycode_string(int(b["key"])))
	return "+".join(parts)


## Does this binding type a character when pressed (a plain letter, digit...)?
static func types_text(b: Dictionary) -> bool:
	if not b.has("key") or b.get("ctrl", false) or b.get("alt", false):
		return false
	var k := int(b["key"])
	return k >= 32 and k < 256


## Was this event a press of the action's binding? Modifiers must match.
func pressed(id: String, e: InputEvent) -> bool:
	return event_matches(binds.get(id, {}), e)


static func event_matches(b: Dictionary, e: InputEvent) -> bool:
	if b.is_empty():
		return false
	if e is InputEventKey:
		if not e.pressed or e.echo or not b.has("key"):
			return false
		if int((e as InputEventKey).keycode) != int(b["key"]):
			return false
	elif e is InputEventMouseButton:
		if not e.pressed or not b.has("mouse"):
			return false
		if int((e as InputEventMouseButton).button_index) != int(b["mouse"]):
			return false
	else:
		return false
	var k := int(b.get("key", 0))
	if k != KEY_CTRL and bool(e.ctrl_pressed) != bool(b.get("ctrl", false)):
		return false
	if k != KEY_ALT and bool(e.alt_pressed) != bool(b.get("alt", false)):
		return false
	if k != KEY_SHIFT and bool(e.shift_pressed) != bool(b.get("shift", false)):
		return false
	return true


## For keys you hold (walking, running): is it down right now?
func held(id: String) -> bool:
	var b: Dictionary = binds.get(id, {})
	if b.has("key"):
		if not Input.is_key_pressed(int(b["key"])):
			return false
	elif b.has("mouse"):
		if not Input.is_mouse_button_pressed(int(b["mouse"])):
			return false
	else:
		return false
	if b.get("ctrl", false) and not Input.is_key_pressed(KEY_CTRL):
		return false
	if b.get("alt", false) and not Input.is_key_pressed(KEY_ALT):
		return false
	if b.get("shift", false) and not Input.is_key_pressed(KEY_SHIFT):
		return false
	return true


func label_of(id: String) -> String:
	for a in ACTIONS:
		if a[0] == id:
			return a[1]
	return id


## Other actions already on this binding.
func clashes(id: String, b: Dictionary) -> Array:
	var out := []
	for other in binds:
		if other != id and _same(binds[other], b):
			out.append(label_of(other))
	for s in shortcuts:
		if _same(s["bind"], b):
			out.append("shortcut: " + str(s["cmd"]))
	return out


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return _clean(a) == _clean(b)
