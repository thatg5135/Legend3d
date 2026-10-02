## Legend3D main: the low-res 3D view on top, the MUD text and a command
## line below. Arrow keys walk; everything you type goes to the MUD.
extends Node

const WALK := 4.5
const RUN := 7.5
const TURN := 2.4
const MEDIA_URL := "https://www.legendmud.org/media/"
const LOG_MAX := 400

## LegendMUD's text conventions (see data/npcs.json for what we learn from them)
const PROMPT_RE := "^>< Hp:"
const EXITS_RE := "^\\[Exits:.*\\]\\s*$"
const NOT_FOUND_RE := "(?i)(you do not see|you don't see|nothing like that|isn't here|is not here|can't find|cannot find)"

const QUALITY := [
	{"name": "low", "shadows": 0, "sun_shadow": true, "rays": false},
	{"name": "medium", "shadows": 1, "sun_shadow": true, "rays": true},
	{"name": "high", "shadows": 2, "sun_shadow": true, "rays": true},
]
const MAX_LIGHTS := 5

var link: LinkServer
var world: World
var catalog := Catalog.new()
var player: CharacterBody3D
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _rays: ShaderMaterial
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _look := false              # mouse look on (right-click toggles)

# Legend's calendar, moon and weather (from the quiet `time` / `weather` checks)
var _date := {"month": 5, "day": 26, "year": "300 BC", "weekday": ""}
var _moon_name := ""
var _moon_phase := 0.5          # 0 new, .25 first quarter, .5 full, .75 last quarter
var _weather_text := ""
var _wx := {"cover": 0.35, "dark": 0.0, "rain": 0.0, "snow": 0.0, "fog": 0.0, "wind": 0.4, "storm": false}
var _flash_t := 0.0
var _next_bolt := 0.0
var _sun_dir := Vector3.UP
var _moon_dir := Vector3.DOWN
var _body_dir := Vector3.UP     # whichever is lighting the world
var _daylight := 1.0
var _exits_state := {}          # dir -> closed, from the last [Exits: ...] line
var _door_cmd := {}             # the last open/close you typed
var _last_cmd := ""
var _last_cmd_t := 0

var _svc: SubViewportContainer
var _sv: SubViewport
var _overlay: Control
var _tags: Array[Label] = []
var _status: Label
var _log: RichTextLabel
var _cmd: LineEdit
var _mono: SystemFont
var _prompt_re := RegEx.create_from_string(PROMPT_RE)
var _exits_re := RegEx.create_from_string(EXITS_RE)
var _notfound_re := RegEx.create_from_string(NOT_FOUND_RE)

var _pending := {}              # move we're waiting on Legend for
var _arrival: World.Portal = null  # portal we just came through (re-closes once we step away)
var _refused: World.Portal = null  # a way Legend just said no to; quiet until you step back
var _gliding := false
var _block: Array[String] = []  # lines since the last prompt
var _collecting := false        # between [Exits:] and the prompt
var _contents: Array[String] = []
var _deferred := {}             # contents that arrived before their room did
var _game_time := ""
var _flash := ""
var _flash_until := 0
var _history: Array[String] = []
var _hist_i := 0
var _quality := 2
var _light_tick := 0.0

var _scan := {}                 # the scan in progress
var _autoscan_at := 0           # when to look at new things in this room
var _fighting := false
var _save_tick := 0.0
const MAP_PATH := "res://data/map.json"
const AUTOSCAN_DELAY_MS := 1200
const LATITUDE := 53.5          # Tara
const MONTHS := ["january", "february", "march", "april", "may", "june", "july", "august",
	"september", "october", "november", "december"]
const MOON_PHASES := {"new": 0.0, "waxing crescent": 0.125, "first quarter": 0.25, "half": 0.25,
	"waxing gibbous": 0.375, "full": 0.5, "waning gibbous": 0.625, "last quarter": 0.75,
	"third quarter": 0.75, "waning crescent": 0.875}
const SHORT_DIRS := {"n": "north", "s": "south", "e": "east", "w": "west", "u": "up", "d": "down",
	"ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest"}

var _audio_on := false
var _players := {}
var _last_ambient := {}

var settings := Settings.new()
var hud: Hud
var held: Held
var menu: GameMenu
var _hand_light: OmniLight3D
var equip_slots: Array = []     # [{slot, item}] from `equipment`
var hands := {}                 # what's in your hands (see Gear.hands_of)
var inventory_items: Array = [] # GMCP char.inventory items
var quiet_text := {}            # cmd -> lines, for the menu pages
var notes: Array = []           # your /note entries
var relay_version := ""
var _quiet_later := {}          # cmd -> when to ask
var _asked := {}                # pages already asked about this session
const NOTES_PATH := "res://data/notes.json"
const GEAR_CMD_RE := "^(wield|wie|wear|wea|remove|rem|hold|hol|grab|light|extinguish|douse|unwield|sheath|draw)\\b"

var _auto: Array = []           # autopilot steps (testing only)
var _auto_forward := false
var _auto_wait_until := 0
var _auto_step_started := 0
var _auto_room_at_start := -1
var _shots_dir := ""


func _ready() -> void:
	DisplayServer.window_set_title("Legend3D")
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace"])
	catalog.load_file()
	settings.load_file()
	_quality = int(settings.video["quality"])
	_load_notes()

	link = LinkServer.new()
	add_child(link)
	link.linked.connect(_on_linked)
	link.unlinked.connect(_on_unlinked)
	link.event_received.connect(_on_event)

	_build_ui()
	_build_scene()
	_build_hud()
	_load_map()
	apply_settings(false)
	_apply_time("12:00 pm")
	_log_line("Legend3D. Waiting for Mudlet (type 3d in Mudlet if it doesn't link by itself).", Color("c9a65a"))
	if link.listen_error != OK:
		_log_line("Can't open port %d. Close the test listener (or another Legend3D) and restart this." % LinkServer.PORT, Color("e06c5a"))
	_log_line("Arrows: walk/turn.  %s: menu (keys, settings, inventory, spells, map).  /note: notes for mapping." % Settings.bind_text(settings.binds["menu"]), Color("8a8070"))
	_log_line("New people and things get looked at automatically (paused while fighting). /scan all redoes a room.", Color("8a8070"))

	var steps := OS.get_environment("LEGEND3D_AUTOPILOT")
	if steps != "":
		_auto = Array(steps.split(","))
	_shots_dir = OS.get_environment("LEGEND3D_SHOTS")


# ------------------------------------------------------------------ the saved map

func _load_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not (parsed is Dictionary) or not (parsed.get("rooms") is Dictionary):
		push_warning("Legend3D: couldn't read %s" % MAP_PATH)
		return
	if parsed.get("doors") is Dictionary:
		world.import_doors(parsed["doors"])
	var n := world.import_map(parsed["rooms"], _items_for)
	_log_line("Remembered %d rooms from earlier sessions." % n, Color("8a8070"))
	print("[L3D] map loaded: %d rooms" % n)


func _save_map() -> void:
	if not world.dirty:
		return
	var out := {
		"_help": [
			"Every room Legend3D has seen: Legend's data, where it sits on the grid, what was",
			"last seen in it, and its furnishing ('layout'). Rooms keep their place forever.",
			"Each layout item is {type, x, z (meters from the room's center), rot, o (options)}.",
			"Edit a layout and set \"layout_locked\": true so it's never regenerated.",
			"Delete a room's entry to have it rebuilt fresh next time you visit.",
		],
		"version": 2,
		"doors": world.export_doors(),
		"rooms": world.export_map(),
	}
	var f := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Legend3D: couldn't write %s" % MAP_PATH)
		return
	f.store_string(JSON.stringify(out, "", false))
	f.close()
	world.dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if world != null:
			_save_map()
		if catalog != null and catalog.dirty:
			catalog.save_file()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _cmd != null:
		_cmd.grab_focus()


# ------------------------------------------------------------------ setup

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("15110d")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 0)
	root.add_child(vb)

	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	vb.add_child(holder)
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.stretch_shrink = 2
	_rays = ShaderMaterial.new()
	_rays.shader = preload("res://shaders/godrays.gdshader")
	_svc.material = _rays
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_svc)
	_sv = SubViewport.new()
	_sv.name = "View"
	_sv.positional_shadow_atlas_size = 1024
	_svc.add_child(_sv)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_overlay)

	var bar := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color("2a2118")
	bar_style.content_margin_left = 10
	bar_style.content_margin_top = 4
	bar_style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", bar_style)
	vb.add_child(bar)
	_status = Label.new()
	_status.add_theme_font_override("font", _mono)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("e8d39a"))
	bar.add_child(_status)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 200)
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.add_theme_font_override("normal_font", _mono)
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color("cfc6b4"))
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color("0e0b08")
	log_style.content_margin_left = 8
	log_style.content_margin_right = 8
	log_style.content_margin_top = 4
	_log.add_theme_stylebox_override("normal", log_style)
	vb.add_child(_log)

	_cmd = LineEdit.new()
	_cmd.placeholder_text = "Type a command and press Enter. Arrow keys walk."
	_cmd.add_theme_font_override("font", _mono)
	_cmd.add_theme_font_size_override("font_size", 15)
	_cmd.text_submitted.connect(_on_submit)
	_cmd.focus_exited.connect(func(): call_deferred("_refocus_cmd"))
	vb.add_child(_cmd)
	_cmd.call_deferred("grab_focus")


func _build_scene() -> void:
	world = World.new()
	world.catalog = catalog
	_sv.add_child(world)

	var we := WorldEnvironment.new()
	env = Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_density = 0.012
	env.fog_sky_affect = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	we.environment = env
	_sv.add_child(we)

	sun = DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	_sv.add_child(sun)

	_rain = _make_weather_particles(false)
	_snow = _make_weather_particles(true)
	_sv.add_child(_rain)
	_sv.add_child(_snow)

	player = CharacterBody3D.new()
	player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	player.floor_snap_length = 0.45
	player.floor_max_angle = deg_to_rad(46.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	player.add_child(shape)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = 68
	camera.near = 0.05
	camera.far = 160
	player.add_child(camera)
	_sv.add_child(player)
	camera.make_current()


## The compass and bars, your hands, the menu.
func _build_hud() -> void:
	var holder := _overlay.get_parent()
	hud = Hud.new()
	holder.add_child(hud)
	var layer := CanvasLayer.new()
	_sv.add_child(layer)
	held = Held.new()
	layer.add_child(held)
	_hand_light = OmniLight3D.new()
	_hand_light.position = Vector3(-0.35, -0.2, -0.45)
	_hand_light.shadow_enabled = false
	_hand_light.visible = false
	camera.add_child(_hand_light)
	menu = GameMenu.new()
	holder.add_child(menu)
	menu.build(self)


## Keep typing going to the command line, unless you're typing in the menu.
func _refocus_cmd() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and menu != null and menu.is_ancestor_of(f):
		return
	_cmd.grab_focus()


func _menu_has_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and menu != null and menu.visible and menu.is_ancestor_of(f)


func _make_weather_particles(snow: bool) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	ps.emitting = false
	ps.amount = 500 if snow else 1100
	ps.lifetime = 5.0 if snow else 0.55
	ps.local_coords = false
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(16, 0.5, 16)
	ps.direction = Vector3(0.1, -1, 0)
	ps.spread = 6.0 if not snow else 25.0
	ps.gravity = Vector3(0, -2.0 if snow else -40.0, 0)
	ps.initial_velocity_min = 0.6 if snow else 14.0
	ps.initial_velocity_max = 1.4 if snow else 18.0
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08) if snow else Vector2(0.018, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if snow else BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(1, 1, 1, 0.85) if snow else Color(0.7, 0.75, 0.82, 0.22)
	if snow:
		m.albedo_texture = Tex.puff()
	else:
		# a streak that fades at both ends instead of a hard white bar
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 32
		m.albedo_texture = gt
	q.material = m
	ps.mesh = q
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ps


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if menu != null and menu.visible and menu.capture_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _look:
			var sens := 0.0032 * float(settings.video["mouse_sens"])
			player.rotation.y -= event.relative.x * sens
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sens, deg_to_rad(-80), deg_to_rad(80))
		return
	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if settings.pressed("mouse_look", event) and not menu.visible:
			_set_look(not _look)
			get_viewport().set_input_as_handled()
		elif _action_for(event, false):
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var k: int = event.keycode
	if event.pressed and k == KEY_ESCAPE:
		if menu.visible:
			menu.hide_menu()
		elif _look:
			_set_look(false)
		else:
			_cmd.clear()
		get_viewport().set_input_as_handled()
		return
	var menu_edit := _menu_has_focus()
	var typing := _cmd.text != ""
	if event.pressed and not event.echo and not menu_edit:
		if _action_for(event, typing):
			get_viewport().set_input_as_handled()
			return
	if menu_edit:
		return
	if event.pressed and not _cmd.has_focus():
		_cmd.grab_focus()
		if event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed:
			_cmd.insert_text_at_caret(char(event.unicode))
			get_viewport().set_input_as_handled()
			return
	# walking keys never move the caret in the command line
	for id in ["forward", "back", "turn_left", "turn_right"]:
		if int(settings.binds.get(id, {}).get("key", -1)) == k and not Settings.types_text(settings.binds[id]):
			get_viewport().set_input_as_handled()
			return


## A key (or mouse button) bound to something. Keys that also type letters
## only count when the command line is empty.
func _action_for(event: InputEvent, typing: bool) -> bool:
	for id in ["menu", "character", "spellbook", "world", "settings", "help", "history_prev", "history_next",
			"log_up", "log_down", "sound", "pixels", "quality", "reload"]:
		if settings.pressed(id, event):
			if typing and Settings.types_text(settings.binds[id]):
				return false
			_do_action(id)
			return true
	for sc in settings.shortcuts:
		if Settings.event_matches(sc["bind"], event) and str(sc["cmd"]).strip_edges() != "":
			if typing and Settings.types_text(sc["bind"]):
				return false
			send_cmd(str(sc["cmd"]).strip_edges())
			return true
	return false


func _do_action(id: String) -> void:
	match id:
		"menu":
			menu.toggle()
		"character", "spellbook", "world", "settings", "help":
			if menu.visible and menu.category == id:
				menu.hide_menu()
			else:
				menu.open_category(id)
		"history_prev":
			_history_step(-1)
		"history_next":
			_history_step(1)
		"log_up", "log_down":
			var bar := _log.get_v_scroll_bar()
			bar.value += (-1 if id == "log_up" else 1) * _log.size.y * 0.8
		"sound":
			settings.audio["sound"] = not _audio_on
			apply_settings(true)
		"pixels":
			settings.video["pixel"] = 1 if int(settings.video["pixel"]) >= 4 else int(settings.video["pixel"]) + 1
			apply_settings(true)
			_flash_msg("pixel size %d" % int(settings.video["pixel"]))
		"quality":
			settings.video["quality"] = (_quality + 1) % QUALITY.size()
			apply_settings(true)
			_flash_msg("quality: " + str(QUALITY[_quality]["name"]))
		"reload":
			world.load_overrides()
			catalog.load_file()
			settings.load_file()
			_load_notes()
			apply_settings(false)
			_refresh_contents_entries()
			world.rebuild_all()
			_flash_msg("your data files reloaded")


## Put your settings into effect (and save them).
func apply_settings(save := true) -> void:
	var v: Dictionary = settings.video
	_quality = clampi(int(v["quality"]), 0, QUALITY.size() - 1)
	_apply_quality()
	_svc.stretch_shrink = clampi(int(v["pixel"]), 1, 4)
	Engine.max_fps = int(v["fps_cap"])
	camera.fov = float(v["fov"])
	var a: Dictionary = settings.audio
	if bool(a["sound"]) != _audio_on:
		_set_audio(bool(a["sound"]))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(a["volume"]), 0.001)))
	var u: Dictionary = settings.ui
	hud.ui_scale = float(u["hud_scale"])
	hud.show_compass = bool(u["compass"])
	hud.show_bars = bool(u["bars"])
	held.visible = bool(u["held"])
	if save:
		settings.save_file()


func _set_look(on: bool) -> void:
	_look = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	_flash_msg("mouse look on (right-click to stop)" if on else "mouse look off")


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	_cmd.clear()
	if t == "":
		return
	if _history.is_empty() or _history[-1] != t:
		_history.append(t)
	_hist_i = _history.size()
	if t.begins_with("/"):
		_local_command(t)
		return
	if not link.is_linked:
		_log_line("(not linked to Mudlet: %s)" % t, Color("e06c5a"))
		return
	_note_command(t)
	link.send_command(t)


## Remember what you typed, for doors you open/close and for weather you ask about.
func _note_command(t: String) -> void:
	_last_cmd = t.to_lower()
	_last_cmd_t = Time.get_ticks_msec()
	var m := RegEx.create_from_string("^(open|close|lock|unlock)\\s+(?:the\\s+)?(?:\\w+\\s+)?(north|south|east|west|up|down|northeast|northwest|southeast|southwest|n|s|e|w|u|d|ne|nw|se|sw)$").search(_last_cmd)
	if m != null:
		_door_cmd = {"verb": m.get_string(1), "dir": SHORT_DIRS.get(m.get_string(2), m.get_string(2)), "t": _last_cmd_t}
	if RegEx.create_from_string(GEAR_CMD_RE).search(_last_cmd) != null:
		request_quiet_later("equipment", 1.5)


func _local_command(t: String) -> void:
	var parts := t.substr(1).split(" ", false)
	var cmd := parts[0].to_lower() if parts.size() > 0 else ""
	match cmd:
		"scan":
			_start_scan(parts.size() > 1 and parts[1].to_lower() == "all")
		"note":
			var text := t.substr(5).strip_edges()
			if text == "":
				var here := notes_for(world.current.vnum) if world.current != null else []
				if here.is_empty():
					_log_line("No notes for this room. /note <text> adds one.", Color("c9a65a"))
				for n in here:
					_log_line("✎ " + str(n["text"]), Color("c9a65a"))
			else:
				add_note(text)
		"notes":
			menu.open_category("world", "Notes")
		"menu":
			menu.toggle()
		_:
			_log_line("Legend3D commands: /note <text>, /note, /notes, /menu, /scan, /scan all", Color("c9a65a"))


func _history_step(d: int) -> void:
	if _history.is_empty():
		return
	_hist_i = clampi(_hist_i + d, 0, _history.size())
	_cmd.text = _history[_hist_i] if _hist_i < _history.size() else ""
	_cmd.caret_column = _cmd.text.length()


# ------------------------------------------------------------------ walking

func _physics_process(delta: float) -> void:
	if _gliding:
		return
	var fwd := 0.0
	var turn := 0.0
	var strafe := 0.0
	var walking_ok := not Input.is_key_pressed(KEY_CTRL) and not (menu != null and menu.visible) and not _menu_has_focus()
	if walking_ok:
		fwd = float(settings.held("forward")) - float(settings.held("back"))
		var lr := float(settings.held("turn_left")) - float(settings.held("turn_right"))
		if settings.held("sidestep"):
			strafe = -lr
		else:
			turn = lr
	if _auto_forward:
		fwd = 1.0
	player.rotation.y += turn * TURN * delta
	var speed := RUN if settings.held("run") else WALK
	var b := player.global_transform.basis
	var move := (-b.z * fwd + b.x * strafe)
	move.y = 0
	var horiz := move.normalized() * speed if move.length() > 0.01 else Vector3.ZERO
	player.velocity.x = horiz.x
	player.velocity.z = horiz.z
	if player.is_on_floor():
		player.velocity.y = -0.5
	else:
		player.velocity.y -= 22.0 * delta
	player.move_and_slide()
	# fell through somewhere? put them back in the room
	if world.current != null and player.position.y < World.center_of(world.current.cell).y - 6.0:
		_place_at(world.current, null)
	_check_portals()
	world.update_ground(player.position)


## Walking up to a way out sends the move; the doorway stays shut until
## Legend says you went through.
func _check_portals() -> void:
	var cur := world.current
	if cur == null:
		return
	if _arrival != null and _arrival.distance(player.position) > 1.8:
		_arrival.set_blocking(not (_arrival.kind in ["pad", "stairs", "well", "stairs_down"]))
		_arrival = null
	if _refused != null and _refused.distance(player.position) > 2.2:
		_refused = null
	if not _pending.is_empty():
		return
	var heading := player.velocity
	for p: World.Portal in cur.portals:
		if p == _arrival or p == _refused:
			continue
		var d := p.distance(player.position)
		if p.kind == "pad":
			if d < 0.8:
				_send_move(p)
				return
			continue
		if p.kind == "stairs":
			# at the top of the flight
			if d < 1.0 and player.position.y > p.a.y - World.FLOOR_H * 0.3:
				_send_move(p)
				return
			continue
		if p.kind == "well":
			if d < 0.8:
				_send_move(p)
				return
			continue
		if p.kind == "stairs_down":
			# partway down the stairs into the floor below
			if d < 5.5 and player.position.y < p.a.y - World.FLOOR_H * 0.3:
				_send_move(p)
				return
			continue
		if d < 1.4 and heading.length() > 0.1 and heading.normalized().dot(p.normal) > 0.25:
			_send_move(p)
			return


func _send_move(p: World.Portal) -> void:
	if not link.is_linked:
		_flash_msg("not linked to Mudlet")
		return
	_pending = {"dir": p.dir, "to": p.to_vnum, "from": world.current.vnum, "portal": p,
		"t": Time.get_ticks_msec(), "prompt_t": 0}
	link.send_command(p.dir)


func _give_up_move(why: String) -> void:
	_refused = _pending.get("portal")
	_pending = {}
	_flash_msg(why)
	print("[L3D] move not taken: ", why)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not _pending.is_empty():
		var waited: int = now - _pending["t"]
		var after_prompt: int = now - _pending["prompt_t"] if _pending["prompt_t"] > 0 else 0
		# no pushing back: you never got through, so there's nothing to undo
		if waited > 5000 or (after_prompt > 700 and waited > 900):
			_give_up_move("blocked (see the text below)")
	if not _deferred.is_empty() and now - int(_deferred["t"]) > 4000:
		_deferred = {}  # never matched a room: it wasn't this one, so drop it
	_weather_tick(delta)
	_update_rays()
	_light_tick -= delta
	if _light_tick <= 0.0:
		_light_tick = 0.25
		_budget_lights()
	_flicker(now)
	_scan_tick(now)
	_save_tick -= delta
	if _save_tick <= 0.0:
		_save_tick = 3.0
		_save_map()
		if catalog.dirty and _scan.is_empty():
			catalog.save_file()
	_update_status()
	_update_tags()
	_hud_tick(delta, now)
	_run_autopilot(now)


# ------------------------------------------------------------------ link events

func _on_linked(hello: Dictionary) -> void:
	relay_version = str(hello.get("version", "?"))
	_log_line("── linked to Mudlet (relay v%s) ──" % relay_version, Color("8fc77a"))
	if hello.get("vitals") is Dictionary:
		hud.vit = hello["vitals"]
	if hello.get("inventory") is Dictionary and hello["inventory"].get("items") is Array:
		inventory_items = hello["inventory"]["items"]
	if relay_version.begins_with("0.1") or relay_version.begins_with("0.2") or relay_version.begins_with("0.3"):
		_log_line("(Mudlet has relay v%s: reinstall Legend3D.xml for health bars, equipment and the spellbook)" % relay_version, Color("e0b85a"))
	else:
		request_quiet_later("equipment", 2.0)
	print("[L3D] linked, relay ", hello.get("version", "?"))
	if hello.get("room") is Dictionary:
		_on_room(hello["room"])
	var t = hello.get("time")
	if t is Dictionary and t.get("game") is String:
		_apply_time(t["game"])
	if hello.get("ambient") is Dictionary:
		_media_play(hello["ambient"])
	if hello.get("status") is Dictionary:
		_fighting = bool(hello["status"].get("fighting", false))
	_log_line("(type look to fill in who and what is here)", Color("8a8070"))


func _on_unlinked() -> void:
	_log_line("── link to Mudlet lost; waiting for it to come back ──", Color("e06c5a"))
	_pending = {}
	_scan = {}


func _on_event(ev: Dictionary) -> void:
	var data = ev.get("data")
	match str(ev.get("type", "")):
		"room":
			if data is Dictionary:
				_on_room(data)
		"snapshot":
			if data is Dictionary and data.get("room") is Dictionary:
				_on_room(data["room"])
		"time":
			if data is Dictionary and data.get("game") is String:
				_apply_time(data["game"])
		"quiet":
			if data is Dictionary and data.get("lines") is Array:
				_on_quiet(str(data.get("cmd", "")), data["lines"])
		"vitals":
			if data is Dictionary:
				hud.vit = data
		"gmcp":
			if data is Dictionary:
				_on_gmcp(str(data.get("pkg", "")), data.get("data"))
		"status":
			if data is Dictionary:
				var was := _fighting
				_fighting = bool(data.get("fighting", false))
				if was and not _fighting:
					_autoscan_at = Time.get_ticks_msec() + AUTOSCAN_DELAY_MS  # catch up after the fight
		"line":
			if data is Dictionary:
				_on_line(str(data.get("text", "")), bool(data.get("prompt", false)))
		"media_play":
			if data is Dictionary:
				_media_play(data)
		"media_stop":
			if data is Dictionary:
				_media_stop(data)


func _on_room(data: Dictionary) -> void:
	var vnum := int(data.get("vnum", -1))
	if vnum < 0:
		return
	var cur := world.current
	if cur != null and vnum == cur.vnum:
		world.upsert(data)
		return

	var via := ""
	var from := -1
	var walked := false
	if cur != null:
		from = cur.vnum
		if not _pending.is_empty() and int(_pending["to"]) == vnum:
			via = _pending["dir"]
			var p: World.Portal = _pending["portal"]
			walked = p.distance(player.position) < 3.0 and p.kind in ["door", "edge"]
		else:
			for e in cur.exits():
				if int(e.get("to_vnum", -1)) == vnum:
					via = str(e.get("dir", ""))
	_autoscan_at = 0
	var through: World.Portal = _pending.get("portal") if walked else null
	_pending = {}
	var level_before := cur.cell.y if cur != null else 0
	var r := world.upsert(data, via, from)
	world.set_current(r)
	var arrival: World.Portal = r.portal_to(from, World.REVERSE.get(via, "")) if from >= 0 else null
	world.set_barriers(r, arrival)
	_arrival = arrival

	var on_stairs := arrival != null and arrival.kind in ["stairs", "stairs_down"] \
		and Vector2(player.position.x - arrival.a.x, player.position.z - arrival.a.z).length() < 7.0 \
		and absf(player.position.y - arrival.a.y) < World.FLOOR_H + 0.6
	if walked and through != null and through.kind in ["door", "edge"] and r.cell.y == level_before:
		# you were at the doorway: step on through
		var target := through.mid() + through.normal * 1.9
		_glide(target)
	elif on_stairs:
		pass  # you walked up or down the stairs yourself: you're already there
	else:
		_place_at(r, arrival)
	if not _deferred.is_empty() and (_deferred["block"] as Array).has(r.room_name()):
		_apply_contents(r, _deferred["lines"], _deferred.get("exits", {}))
		_deferred = {}
	_apply_env()
	print("[L3D] room %d '%s' cell %s via '%s'%s" % [vnum, r.room_name(), r.cell, via, " (walked)" if walked else ""])


func _glide(target: Vector3) -> void:
	_gliding = true
	var tw := create_tween()
	tw.tween_property(player, "position", Vector3(target.x, player.position.y, target.z), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _gliding = false)


## Put the player just inside `arrival` (or somewhere sensible), facing in.
func _place_at(r: World.Room, arrival: World.Portal) -> void:
	player.velocity = Vector3.ZERO
	var base_y := World.center_of(r.cell).y
	if arrival != null and arrival.land != Vector3.INF:
		player.position = arrival.land
		player.rotation.y = atan2(-arrival.land_face.x, -arrival.land_face.z)
		return
	if arrival != null:
		var inward := -arrival.normal
		if arrival.kind == "pad":
			player.position = arrival.a + inward * 1.6
		else:
			player.position = arrival.mid() + inward * 2.0
		player.position.y = base_y + 0.05
		player.rotation.y = atan2(-inward.x, -inward.z)
		return
	for p: World.Portal in r.portals:
		if p.kind in ["door", "edge"]:
			player.position = p.mid() - p.normal * 2.5
			player.position.y = base_y + 0.05
			player.rotation.y = atan2(p.normal.x, p.normal.z)
			return
	player.position = Vector3(r.shape.get("center", World.center_of(r.cell))) + Vector3(0, 0.05, 0)


func _on_line(text: String, flagged_prompt: bool) -> void:
	var is_prompt := flagged_prompt or _prompt_re.search(text) != null
	_log_line(text, Color("7f7766") if is_prompt else Color("cfc6b4"))
	if not _scan.is_empty() and _scan.get("waiting", false):
		if is_prompt:
			_scan_got(_scan["lines"])
		else:
			_scan["lines"].append(text)
	if not is_prompt:
		_watch_line(text)
		if _exits_re.search(text) != null:
			_collecting = true
			_contents = []
			_exits_state = _parse_exits(text)
		elif _collecting and text.strip_edges() != "":
			_contents.append(text.strip_edges())
		else:
			_block.append(text.strip_edges())
		return
	if not _pending.is_empty() and _pending["prompt_t"] == 0:
		_pending["prompt_t"] = Time.get_ticks_msec()
	if _collecting:
		_collecting = false
		var cur := world.current
		if cur != null and _block.has(cur.room_name()):
			_apply_contents(cur, _contents.duplicate(), _exits_state.duplicate())
		else:
			# the room update may still be on its way; hold the list briefly,
			# and only ever give it to the room it names
			_deferred = {"block": _block.duplicate(), "lines": _contents.duplicate(),
				"exits": _exits_state.duplicate(), "t": Time.get_ticks_msec()}
	_block.clear()


## Room listing lines -> things to show. "(2) A pig is here." means two pigs.
## The same line twice in one listing is counted, never drawn twice.
func _items_for(lines: Array) -> Array:
	var items := []
	var by_line := {}
	for raw in lines:
		var counted := Catalog.strip_count(str(raw))
		var line: String = counted[1]
		var key := Catalog.key_of(line)
		if by_line.has(key):
			items[by_line[key]]["count"] += int(counted[0])
			continue
		var entry := catalog.lookup(line)
		var kind := str(entry.get("kind", Catalog.guess_kind(line)))
		by_line[key] = items.size()
		items.append({"raw": str(raw), "line": line, "count": int(counted[0]), "kind": kind, "entry": entry})
	return items


func _apply_contents(r: World.Room, lines: Array, exits := {}) -> void:
	var items := _items_for(lines)
	world.set_contents(r, items)
	for d in exits:
		var e := r.exit(d)
		if not e.is_empty():
			var to := int(e.get("to_vnum", -1))
			if bool(exits[d]) or world.door_known(r.vnum, to):
				world.set_door(r.vnum, to, bool(exits[d]))
	var names := []
	for it in items:
		if it["kind"] == "creature":
			names.append(str(it["entry"].get("name", Catalog.short_of(it["line"]))) + ("" if it["count"] == 1 else " x%d" % it["count"]))
	print("[L3D] contents of %d: %d things, creatures: %s" % [r.vnum, items.size(), names])
	if r == world.current:
		_autoscan_at = Time.get_ticks_msec() + AUTOSCAN_DELAY_MS


## "[Exits: [n] s]" -> {"north": true (closed), "south": false}
func _parse_exits(text: String) -> Dictionary:
	var out := {}
	var m := RegEx.create_from_string("^\\[Exits:\\s*(.*)\\]\\s*$").search(text.strip_edges())
	if m == null:
		return out
	for t in RegEx.create_from_string("(\\[)?([a-z]+)(\\])?").search_all(m.get_string(1).to_lower()):
		var d: String = SHORT_DIRS.get(t.get_string(2), t.get_string(2))
		if World.DIRS.has(d):
			out[d] = t.get_string(1) == "["
	return out


## Lines worth noticing outside room listings: doors you open or close,
## `time` and `weather` when you type them yourself.
func _watch_line(text: String) -> void:
	var t := text.strip_edges()
	var now := Time.get_ticks_msec()
	if not _door_cmd.is_empty() and now - int(_door_cmd["t"]) < 4000:
		var low := t.to_lower()
		var closed := -1
		if low.begins_with("you open"):
			closed = 0
		elif low.begins_with("you close") or low.begins_with("you lock"):
			closed = 1
		elif low.contains("is already open"):
			closed = 0
		elif low.contains("is already closed") or low.contains("is closed"):
			closed = 1
		if closed != -1 and world.current != null:
			var e := world.current.exit(str(_door_cmd["dir"]))
			if not e.is_empty():
				world.set_door(world.current.vnum, int(e.get("to_vnum", -1)), closed == 1)
			_door_cmd = {}
	if t.begins_with("It is ") and t.contains(" on ") and (t.contains(" BC") or t.contains(" AD")):
		_on_quiet("time", [t])
	elif t.begins_with("The almanac"):
		_on_quiet("time", [t])
	elif _last_cmd == "weather" and now - _last_cmd_t < 3000 and t != "" and not _prompt_re.search(t):
		_on_quiet("weather", [t])


func _refresh_contents_entries() -> void:
	for r in world.rooms.values():
		for it in r.contents:
			var entry := catalog.lookup(str(it["line"]))
			it["entry"] = entry
			it["kind"] = str(entry.get("kind", Catalog.guess_kind(str(it["line"]))))


# ------------------------------------------------------------------ /scan

## Look at each thing in the room once, and remember what we learn.
func _start_scan(everything: bool, quiet := false) -> void:
	var cur := world.current
	if cur == null or not link.is_linked:
		if not quiet:
			_log_line("(can't scan: not linked or no room yet)", Color("e06c5a"))
		return
	if cur.contents.is_empty():
		if not quiet:
			_log_line("(nothing listed here yet; type look first)", Color("c9a65a"))
		return
	var queue := []
	var used := {}
	for it in cur.contents:
		var line := str(it["line"])
		var kws := Catalog.keywords_for(line)
		if kws.is_empty():
			continue
		used[kws[0]] = int(used.get(kws[0], 0)) + 1
		if not everything and not catalog.lookup(line).is_empty():
			continue
		var n: int = used[kws[0]]
		var tries := []
		for kw in kws:
			tries.append(("%d.%s" % [n, kw]) if n > 1 and kw == kws[0] else kw)
		queue.append({"line": line, "tries": tries})
	if queue.is_empty():
		if not quiet:
			_log_line("(everything here is already in the catalog; /scan all to redo)", Color("c9a65a"))
		return
	_scan = {"queue": queue, "i": 0, "try": 0, "waiting": false, "lines": [], "next_at": 0, "done": 0,
		"room": cur.vnum, "quiet": quiet}
	if not quiet:
		_log_line("── scanning %d thing(s) ──" % queue.size(), Color("8fc77a"))


func _scan_tick(now: int) -> void:
	if _autoscan_at > 0 and now >= _autoscan_at:
		_autoscan_at = 0
		if _scan.is_empty() and not _fighting and _pending.is_empty():
			_start_scan(false, true)
	if not _scan.is_empty() and (_fighting or world.current == null or int(_scan.get("room", -1)) != world.current.vnum):
		if int(_scan["done"]) > 0:
			catalog.save_file()
		_scan = {}  # left the room or a fight started: stop looking around
		return
	if _scan.is_empty() or _scan["waiting"] or now < int(_scan["next_at"]):
		if not _scan.is_empty() and _scan["waiting"] and now - int(_scan.get("sent_at", now)) > 6000:
			_scan_got(_scan["lines"])  # no prompt came back; take what we have
		return
	var q: Array = _scan["queue"]
	if int(_scan["i"]) >= q.size():
		catalog.save_file()
		_refresh_contents_entries()
		if world.current != null:
			world.set_contents(world.current, world.current.contents)
		if not _scan.get("quiet", false) or int(_scan["done"]) > 0:
			_log_line("── learned %d new thing(s) here (saved to data/npcs.json) ──" % int(_scan["done"]), Color("8fc77a"))
		print("[L3D] scan done, ", _scan["done"])
		_scan = {}
		return
	var item: Dictionary = q[_scan["i"]]
	var tries: Array = item["tries"]
	var kw: String = tries[_scan["try"]]
	_scan["waiting"] = true
	_scan["lines"] = []
	_scan["sent_at"] = now
	_scan["kw"] = kw
	link.send_command("look " + kw)


func _scan_got(lines: Array) -> void:
	_scan["waiting"] = false
	_scan["next_at"] = Time.get_ticks_msec() + 350
	var item: Dictionary = _scan["queue"][_scan["i"]]
	var joined := " ".join(lines)
	if _notfound_re.search(joined) != null or lines.is_empty():
		_scan["try"] = int(_scan["try"]) + 1
		if int(_scan["try"]) < (item["tries"] as Array).size():
			return
		print("[L3D] scan: couldn't look at ", item["line"])
		_scan["i"] = int(_scan["i"]) + 1
		_scan["try"] = 0
		return
	var entry := Catalog.parse_look(lines, str(item["line"]), str(_scan["kw"]))
	catalog.put(str(item["line"]), entry)
	_scan["done"] = int(_scan["done"]) + 1
	print("[L3D] scan: %s -> %s %s" % [_scan["kw"], entry.get("kind"), entry.get("name", entry.get("short"))])
	_scan["i"] = int(_scan["i"]) + 1
	_scan["try"] = 0


# ------------------------------------------------------------------ light

func _apply_quality() -> void:
	var q: Dictionary = QUALITY[_quality]
	sun.shadow_enabled = bool(q["sun_shadow"])
	env.glow_enabled = _quality > 0
	_light_tick = 0.0


## Only the few lights nearest you cast shadows; far ones switch off.
## Only the nearest few lights are on (each one costs a pass over everything
## it touches), and only the most important of those cast shadows.
func _budget_lights() -> void:
	var allowed: int = QUALITY[_quality]["shadows"]
	var lights := []
	for l in get_tree().get_nodes_in_group("l3d_light"):
		var light := l as Light3D
		if light == null or not light.is_inside_tree():
			continue
		var dist := light.global_position.distance_to(player.global_position)
		var pri := float(light.get_meta("priority", 0.0))
		lights.append([dist - pri * 0.6, light, pri])
	lights.sort_custom(func(a, b): return a[0] < b[0])
	var shadows := 0
	for i in lights.size():
		var light: Light3D = lights[i][1]
		var on: bool = i < MAX_LIGHTS and float(lights[i][0]) < 26.0
		light.visible = on
		var cast: bool = on and float(lights[i][2]) > 0.0 and shadows < allowed
		light.shadow_enabled = cast
		if cast:
			shadows += 1


func _flicker(now: int) -> void:
	var t := now / 1000.0
	for l in get_tree().get_nodes_in_group("l3d_light"):
		var light := l as Light3D
		if light == null or not light.visible:
			continue
		var f := float(light.get_meta("flicker", 0.0))
		if f <= 0.0:
			continue
		var seed := light.get_instance_id() % 97
		var n := sin(t * 11.0 + seed) * 0.5 + sin(t * 23.0 + seed * 2.0) * 0.3 + sin(t * 5.3 + seed) * 0.2
		light.light_energy = float(light.get_meta("base_energy", 1.0)) * (1.0 + n * f)


func _apply_time(t: String) -> void:
	_game_time = t.strip_edges()
	_apply_env()


func _hour() -> float:
	var m := RegEx.create_from_string("(\\d+):(\\d+)\\s*(am|pm)").search(_game_time.to_lower())
	if m == null:
		return 12.0
	var h := int(m.get_string(1)) % 12
	if m.get_string(3) == "pm":
		h += 12
	return h + int(m.get_string(2)) / 60.0


## Results of the quiet background checks (or the same text typed by hand).
func _on_quiet(cmd: String, lines: Array) -> void:
	var text := " ".join(lines)
	if cmd == "time":
		var m := RegEx.create_from_string("It is (\\d+:\\d+ [ap]m) on (\\w+), (\\w+) (\\d+), (\\d+ (?:BC|AD))").search(text)
		if m != null:
			_game_time = m.get_string(1)
			var mi := MONTHS.find(m.get_string(3).to_lower())
			_date = {"weekday": m.get_string(2), "month": mi + 1 if mi >= 0 else 5, "day": int(m.get_string(4)), "year": m.get_string(5)}
		var mm := RegEx.create_from_string("(?i)there will be (?:an? )?([a-z ]+?) moon tonight").search(text)
		if mm != null:
			_moon_name = mm.get_string(1).strip_edges().to_lower()
			_moon_phase = float(MOON_PHASES.get(_moon_name, _moon_phase))
		elif text.to_lower().contains("no moon"):
			_moon_name = "new"
			_moon_phase = 0.0
		print("[L3D] time: %s %s, moon %s (%.3f)" % [_game_time, _date, _moon_name, _moon_phase])
	elif cmd == "weather":
		_weather_text = text.strip_edges()
		_wx = _classify_weather(_weather_text)
		print("[L3D] weather: %s -> %s" % [_weather_text, _wx])
	else:
		# answers for the menu: equipment, spells, score...
		quiet_text[cmd] = lines
		if cmd == "equipment" or cmd.begins_with("eq"):
			equip_slots = Gear.parse_slots(lines)
			hands = Gear.hands_of(equip_slots)
			_apply_hands()
			print("[L3D] equipment: %d slots, hands %s" % [equip_slots.size(), hands])
		if menu.visible:
			menu.call("_refresh")
		return
	_apply_env()


## Legend's weather sentence -> what the sky should do.
func _classify_weather(t: String) -> Dictionary:
	var low := t.to_lower()
	var wx := {"cover": 0.3, "dark": 0.0, "rain": 0.0, "snow": 0.0, "fog": 0.0, "wind": 0.4, "storm": false}
	var has := func(pat: String) -> bool: return RegEx.create_from_string("\\b(" + pat + ")").search(low) != null
	if has.call("cloudless|clear|starry|bright blue|blue sky"):
		wx["cover"] = 0.05
	if has.call("puffy|fluffy|white clouds|scattered clouds|few clouds|partly"):
		wx["cover"] = 0.45
	if has.call("cloudy|clouds cover|grey|gray|overcast|leaden|dull"):
		wx["cover"] = 0.85
		wx["dark"] = 0.45
	if has.call("drizzl|light rain|misting|sprinkl|spitting"):
		wx["rain"] = 0.35
		wx["cover"] = 0.9
		wx["dark"] = 0.55
	if has.call("rain|raining|showers|pouring|downpour"):
		wx["rain"] = maxf(float(wx["rain"]), 0.75)
		wx["cover"] = 0.95
		wx["dark"] = 0.7
	if has.call("pouring|downpour|torrential|heavy rain"):
		wx["rain"] = 1.0
	if has.call("thunder|lightning|storm"):
		wx["storm"] = true
		wx["cover"] = 1.0
		wx["dark"] = 0.9
		wx["wind"] = 1.0
	if has.call("snow|blizzard|flurr"):
		wx["snow"] = 1.0 if has.call("blizzard|heavy snow") else 0.6
		wx["cover"] = 0.9
		wx["dark"] = 0.35
	if has.call("sleet|hail"):
		wx["rain"] = 0.6
		wx["snow"] = 0.3
	if has.call("fog|mist|haze|hazy"):
		wx["fog"] = 1.0 if has.call("thick|dense|heavy") else 0.6
	if has.call("wind|breez|gust|blowing|gale"):
		wx["wind"] = 1.0 if has.call("gale|howling|strong") else 0.7
	if has.call("calm|still"):
		wx["wind"] = 0.1
	return wx


func _day_of_year() -> int:
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var doy := 0
	for i in clampi(int(_date["month"]) - 1, 0, 11):
		doy += lengths[i]
	return doy + int(_date["day"])


## Where a body sits in the sky over Tara for an hour angle and declination.
func _sky_dir(hour_angle: float, decl: float) -> Vector3:
	var lat := deg_to_rad(LATITUDE)
	var alt := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hour_angle))
	var az := atan2(-cos(decl) * sin(hour_angle), sin(decl) * cos(lat) - cos(decl) * cos(hour_angle) * sin(lat))
	return Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt)).normalized()


func _apply_env() -> void:
	var h := _hour()
	var doy := _day_of_year()
	var decl := deg_to_rad(23.44) * sin(TAU * (doy - 80) / 365.0)
	var ha := (h - 12.0) / 24.0 * TAU
	_sun_dir = _sky_dir(ha, decl)
	_moon_dir = _sky_dir(ha - TAU * _moon_phase, -decl * 0.7)
	var sun_alt := rad_to_deg(asin(_sun_dir.y))
	var moon_illum := 0.5 * (1.0 - cos(TAU * _moon_phase))
	var cover := float(_wx["cover"])
	var dark := float(_wx["dark"])

	# daylight from the sun's height: night < -8°, dawn/dusk -8..8°, day above
	_daylight = smoothstep(-8.0, 12.0, sun_alt)
	var dusk := clampf(1.0 - absf(sun_alt - 1.0) / 10.0, 0.0, 1.0)
	var zen := Color(0.28, 0.5, 0.82).lerp(Color(0.04, 0.05, 0.12), 1.0 - _daylight)
	var hor := Color(0.7, 0.8, 0.9).lerp(Color(0.08, 0.1, 0.18), 1.0 - _daylight)
	hor = hor.lerp(Color(0.98, 0.58, 0.32), dusk * 0.8)
	zen = zen.lerp(Color(0.32, 0.36, 0.62), dusk * 0.4)
	var night_glow := moon_illum * clampf(_moon_dir.y * 3.0, 0.0, 1.0) * (1.0 - _daylight)
	zen = zen.lerp(Color(0.1, 0.13, 0.25), night_glow * 0.5)
	hor = hor.lerp(Color(0.16, 0.19, 0.3), night_glow * 0.5)
	# overcast greys it all down
	var grey := Color(0.5, 0.52, 0.55) * (0.25 + 0.75 * _daylight) * (1.0 - dark * 0.45)
	zen = zen.lerp(grey * 0.85, cover * dark * 0.9)
	hor = hor.lerp(grey, cover * dark * 0.9)
	var sun_col := Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.36), dusk)

	_sky_mat.set_shader_parameter("zenith", Vector3(zen.r, zen.g, zen.b))
	_sky_mat.set_shader_parameter("horizon", Vector3(hor.r, hor.g, hor.b))
	_sky_mat.set_shader_parameter("ground_col", Vector3(hor.r, hor.g, hor.b) * 0.35)
	_sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	_sky_mat.set_shader_parameter("sun_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
	_sky_mat.set_shader_parameter("sun_vis", clampf(_sun_dir.y * 8.0 + 0.3, 0.0, 1.0) * (1.0 - cover * dark))
	_sky_mat.set_shader_parameter("moon_dir", _moon_dir)
	_sky_mat.set_shader_parameter("moon_phase", _moon_phase)
	_sky_mat.set_shader_parameter("moon_vis", clampf(_moon_dir.y * 10.0, 0.0, 1.0) * (1.0 - cover * 0.9 * dark))
	_sky_mat.set_shader_parameter("night", 1.0 - smoothstep(-12.0, -2.0, sun_alt))
	_sky_mat.set_shader_parameter("day", clampf(_daylight + night_glow * 0.25, 0.0, 1.0))
	_sky_mat.set_shader_parameter("cover", cover)
	_sky_mat.set_shader_parameter("cloud_dark", dark)
	var wind := float(_wx["wind"])
	_sky_mat.set_shader_parameter("wind", Vector2(0.004, 0.0015) + Vector2(0.012, 0.005) * wind)

	# one light: the sun by day, the moon by night (its brightness by phase)
	var sun_up := sun_alt > -4.0
	_body_dir = _sun_dir if sun_up else _moon_dir
	if _body_dir.y < 0.05:
		_body_dir = Vector3(_body_dir.x, 0.05, _body_dir.z).normalized()
	sun.global_transform.basis = Basis.looking_at(-_body_dir, Vector3.UP if absf(_body_dir.y) < 0.99 else Vector3.FORWARD)
	if sun_up:
		sun.light_color = sun_col
		sun.light_energy = 1.15 * clampf((sun_alt + 4.0) / 14.0, 0.0, 1.0) * (1.0 - cover * dark * 0.75)
	else:
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = (0.05 + 0.4 * moon_illum) * clampf(_moon_dir.y * 4.0, 0.15, 1.0) * (1.0 - cover * 0.7)
	sun.shadow_opacity = 0.85 if sun_up else 0.7

	var cur := world.current
	var outdoor := cur == null or cur.is_outdoor()
	var sky_amb := Color(zen.r, zen.g, zen.b).lerp(Color(hor.r, hor.g, hor.b), 0.5)
	if outdoor:
		env.ambient_light_color = sky_amb.lerp(Color(0.85, 0.85, 0.85), 0.25)
		env.ambient_light_energy = (0.18 + 0.5 * _daylight) * (1.0 - cover * dark * 0.4) + 0.12 * night_glow * (1.0 - cover * 0.6)
	else:
		var lvl := world.light_of(cur)
		# cool daylight seeping in, warm firelight does the rest
		env.ambient_light_color = Color(0.85, 0.74, 0.6)
		env.ambient_light_energy = 0.08 + lvl * 0.14 + 0.06 * _daylight
	env.fog_light_color = Color(hor.r, hor.g, hor.b).lerp(Color(0.6, 0.62, 0.65), float(_wx["fog"]) * 0.5)
	env.fog_density = 0.008 + 0.006 * cover * dark + 0.05 * float(_wx["fog"])
	if not outdoor:
		env.fog_density = 0.01
		env.fog_light_color = Color(0.09, 0.065, 0.045)
	_update_shafts(sun_up, sun_col, moon_illum)
	_update_precip()


## Beams through windows and doors when the sun or moon is on that side.
func _update_shafts(sun_up: bool, sun_col: Color, moon_illum: float) -> void:
	var travel := -_body_dir
	var body_alt := asin(clampf(_body_dir.y, -1.0, 1.0))
	var str := 0.22 * (1.0 - float(_wx["cover"]) * float(_wx["dark"]))
	if not sun_up:
		str *= 0.25 * moon_illum
	for node in get_tree().get_nodes_in_group("l3d_shaft"):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var outward: Vector3 = mi.get_meta("outward")
		var size: Vector2 = mi.get_meta("size")
		var facing := Vector2(travel.x, travel.z).normalized().dot(Vector2(-outward.x, -outward.z))
		var on := body_alt > deg_to_rad(3.0) and facing > 0.15 and str > 0.01 and _quality > 0
		mi.visible = on
		if not on:
			continue
		var length := 6.0
		var z := travel.normalized()
		var x := Vector3.UP.cross(z).normalized()
		if x.length() < 0.5:
			x = Vector3.RIGHT
		var y := z.cross(x)
		var origin: Vector3 = mi.get_meta("origin", mi.position)
		mi.set_meta("origin", origin)
		mi.transform = Transform3D(Basis(x, y, z * length), origin + z * length * 0.5)
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("color", sun_col if sun_up else Color(0.6, 0.7, 1.0))
		m.set_shader_parameter("strength", str * facing)


func _update_precip() -> void:
	var cur := world.current
	var outdoor := cur == null or cur.is_outdoor()
	var rain := float(_wx["rain"])
	var snow := float(_wx["snow"])
	var rain_n := int(1100 * clampf(rain, 0.2, 1.0))
	if _rain.amount != rain_n:
		_rain.amount = rain_n
	_rain.emitting = outdoor and rain > 0.0
	var lit := clampf(env.ambient_light_energy, 0.08, 0.7) / 0.7
	((_rain.mesh as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.72 * lit, 0.77 * lit, 0.85 * lit, 0.3 + 0.2 * rain)
	var snow_n := int(500 * clampf(snow, 0.2, 1.0))
	if _snow.amount != snow_n:
		_snow.amount = snow_n
	_snow.emitting = outdoor and snow > 0.0
	var wind := float(_wx["wind"])
	_rain.gravity = Vector3(wind * 6.0, -40.0, wind * 2.0)
	_snow.gravity = Vector3(wind * 1.5, -2.0, wind * 0.6)
	for node in get_tree().get_nodes_in_group("l3d_smoke"):
		(node as CPUParticles3D).gravity = Vector3(0.15 + wind * 0.9, 0.32, wind * 0.3)


func _weather_tick(delta: float) -> void:
	if camera == null:
		return
	var cp := camera.global_position
	_rain.global_position = cp + Vector3(0, 9, 0)
	_snow.global_position = cp + Vector3(0, 9, 0)
	# lightning
	if bool(_wx.get("storm", false)):
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = randf_range(6.0, 18.0)
			_flash_t = 0.35
	if _flash_t > 0.0:
		_flash_t -= delta
		var f := 0.0
		if _flash_t > 0.22 or (_flash_t > 0.05 and _flash_t < 0.12):
			f = 1.0
		_sky_mat.set_shader_parameter("flash", f * 0.8)
		env.adjustment_brightness = 1.0 + f * 0.6
	else:
		env.adjustment_brightness = 1.0


## God rays toward the sun (or the moon) when it's in front of you.
func _update_rays() -> void:
	if _rays == null or camera == null:
		return
	var q: Dictionary = QUALITY[_quality]
	var target := camera.global_position + _body_dir * 400.0
	var fwd := -camera.global_transform.basis.z
	var facing := fwd.dot(_body_dir)
	if not bool(q["rays"]) or not bool(settings.video["rays"]) or camera.is_position_behind(target) or facing < 0.2:
		_rays.set_shader_parameter("strength", 0.0)
		return
	var sp := camera.unproject_position(target) / Vector2(_sv.size)
	var sun_up := _sun_dir.y > -0.07
	var s := smoothstep(0.2, 0.75, facing) * (1.0 - float(_wx["dark"]) * 0.8)
	s *= 1.0 if sun_up else 0.35 * (0.5 * (1.0 - cos(TAU * _moon_phase)))
	_rays.set_shader_parameter("light_pos", sp)
	_rays.set_shader_parameter("strength", s)
	_rays.set_shader_parameter("threshold", 0.78 if sun_up else 0.35)
	_rays.set_shader_parameter("aspect", float(_sv.size.x) / maxf(float(_sv.size.y), 1.0))
	_rays.set_shader_parameter("ray_col", Vector3(1.0, 0.86, 0.62) if sun_up else Vector3(0.6, 0.7, 1.0))


func _update_status() -> void:
	var parts := []
	var cur := world.current
	if cur != null:
		parts.append(cur.room_name())
		parts.append(str(cur.data.get("area", "")))
	if _game_time != "":
		parts.append(_game_time)
	if _moon_name != "" and _sun_dir.y < 0.0:
		parts.append(_moon_name + " moon")
	parts.append("linked" if link.is_linked else "waiting for Mudlet")
	if not _scan.is_empty():
		parts.append("scanning %d/%d" % [int(_scan["i"]) + 1, (_scan["queue"] as Array).size()])
	if _audio_on:
		parts.append("sound on")
	parts.append("%s %d fps" % [QUALITY[_quality]["name"], Engine.get_frames_per_second()])
	var s := "  ·  ".join(parts)
	if Time.get_ticks_msec() < _flash_until:
		s += "   ▸ " + _flash
	_status.text = s


func _flash_msg(msg: String) -> void:
	_flash = msg
	_flash_until = Time.get_ticks_msec() + 2500


func _log_line(text: String, color: Color) -> void:
	_log.push_color(color)
	_log.add_text(text)
	_log.pop()
	_log.newline()
	while _log.get_paragraph_count() > LOG_MAX:
		_log.remove_paragraph(0)


## Names over people and exit markers, drawn at full resolution on top.
func _update_tags() -> void:
	var used := 0
	var placed: Array[Rect2] = []
	var cam_pos := camera.global_position
	for m in get_tree().get_nodes_in_group("l3d_label"):
		var mk := m as Node3D
		if mk == null or not mk.is_inside_tree():
			continue
		var p := mk.global_position
		var dist := cam_pos.distance_to(p)
		var kind := str(mk.get_meta("kind"))
		if (kind == "name" and not bool(settings.ui["names"])) or (kind == "exit" and not bool(settings.ui["exit_labels"])):
			continue
		if dist > (12.0 if kind == "sign" else 20.0) or camera.is_position_behind(p):
			continue
		if not _can_see(cam_pos, p):
			continue
		# names belong to the room you're in, or to open ground you can see across
		if mk.has_meta("vnum") and world.current != null and int(mk.get_meta("vnum")) != world.current.vnum:
			var other: World.Room = world.rooms.get(int(mk.get_meta("vnum")))
			if not world.current.is_outdoor() or other == null or not other.is_outdoor():
				continue
		var sp := camera.unproject_position(p) * float(_svc.stretch_shrink)
		if used >= _tags.size():
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_constant_override("outline_size", 5)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			_overlay.add_child(l)
			_tags.append(l)
		var tag := _tags[used]
		used += 1
		tag.text = str(mk.get_meta("text"))
		var fade := clampf(1.5 - dist / 16.0, 0.25, 1.0)
		var col := Color("ffeec4")
		if kind == "exit":
			col = Color("e8c46a")
		elif kind == "sign":
			col = Color("f0d890")
		tag.add_theme_color_override("font_color", col * Color(1, 1, 1, fade))
		tag.reset_size()
		var rect := Rect2(sp - Vector2(tag.size.x / 2, tag.size.y), tag.size)
		for k in 6:  # nudge up out of the way of names already placed
			var clash := false
			for other in placed:
				if rect.intersects(other):
					clash = true
			if not clash:
				break
			rect.position.y -= rect.size.y
		placed.append(rect)
		tag.position = rect.position
		tag.visible = true
	for i in range(used, _tags.size()):
		_tags[i].visible = false


## Is anything solid (walls, posts) between the camera and this point?
func _can_see(from: Vector3, to: Vector3) -> bool:
	var space := _sv.world_3d.direct_space_state if _sv.world_3d != null else null
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.6


# ------------------------------------------------------------------ sound

func _set_audio(on: bool) -> void:
	_audio_on = on
	settings.audio["sound"] = on
	_flash_msg("sound on" if on else "sound off")
	if on and not _last_ambient.is_empty():
		_media_play(_last_ambient)
	if not on:
		for p in _players.values():
			if is_instance_valid(p):
				p.queue_free()
		_players.clear()


func _media_play(m: Dictionary) -> void:
	if str(m.get("source", "")) == "ambient" or str(m.get("tag", "")) == "ambient":
		_last_ambient = m
	if not _audio_on:
		return
	var name := str(m.get("name", ""))
	if not name.ends_with(".ogg") or name.contains(".."):
		return
	var path := "user://media/" + name
	if FileAccess.file_exists(path):
		_play_bytes(m, FileAccess.get_file_as_bytes(path))
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(body)
				f.close()
			_play_bytes(m, body))
	req.request(MEDIA_URL + name)


func _play_bytes(m: Dictionary, bytes: PackedByteArray) -> void:
	if not _audio_on:
		return
	var st := AudioStreamOggVorbis.load_from_buffer(bytes)
	if st == null:
		return
	st.loop = int(m.get("loops", 1)) == -1
	var key := str(m.get("key", m.get("name", "")))
	if _players.has(key) and is_instance_valid(_players[key]):
		_players[key].queue_free()
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = linear_to_db(clampf(float(m.get("volume", 50)) / 100.0, 0.001, 1.0))
	add_child(p)
	p.play()
	_players[key] = p
	if not st.loop:
		p.finished.connect(p.queue_free)


func _media_stop(m: Dictionary) -> void:
	var key := str(m.get("key", ""))
	if not _players.has(key):
		return
	var p: AudioStreamPlayer = _players[key]
	_players.erase(key)
	if not is_instance_valid(p):
		return
	var fade := float(m.get("fadeout", 0)) / 1000.0
	if fade <= 0:
		p.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ HUD, hands, menu

func _hud_tick(delta: float, now: int) -> void:
	hud.yaw = player.rotation.y
	hud.tick(delta)
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	held.tick(delta, spd, Vector2(_sv.size))
	# your hands are lit by where you are, or by what you carry
	var outdoor := world.current == null or world.current.is_outdoor()
	var b := env.ambient_light_energy * 1.25
	if outdoor:
		b += sun.light_energy * 0.45
	else:
		b += 0.25 * world.light_of(world.current)
	b = clampf(b, 0.22, 1.0)
	var tint := Color(b, b * 0.96, b * 0.9)
	if _hand_light.visible:
		tint = tint.lerp(Color(1.0, 0.84, 0.62), 0.7)
		var base := float(_hand_light.get_meta("base", 1.0))
		var fl := float(_hand_light.get_meta("flicker", 0.0))
		var t := now / 1000.0
		_hand_light.light_energy = base * (1.0 + fl * (sin(t * 11.0) * 0.5 + sin(t * 23.7 + 1.3) * 0.3 + sin(t * 4.1) * 0.2))
	held.tint = tint
	for cmd in _quiet_later.keys():
		if now >= int(_quiet_later[cmd]):
			_quiet_later.erase(cmd)
			request_quiet(cmd)


## What's in your hands, on screen and as light.
func _apply_hands() -> void:
	var w = hands.get("weapon")
	held.weapon = str(w["kind"]) if w is Dictionary else ""
	var l = hands.get("light")
	held.light_kind = str(l["kind"]) if l is Dictionary else ""
	var conf := {"torch": [Color(1.0, 0.66, 0.36), 9.0, 1.35, 0.18], "lantern": [Color(1.0, 0.8, 0.52), 8.0, 1.1, 0.05],
		"candle": [Color(1.0, 0.78, 0.5), 4.5, 0.6, 0.12], "orb": [Color(0.75, 0.88, 1.0), 7.0, 0.95, 0.02]}
	var lit: bool = l is Dictionary and bool(l.get("lit", true))
	_hand_light.visible = held.light_kind != "" and lit
	if _hand_light.visible:
		var c: Array = conf.get(held.light_kind, conf["torch"])
		_hand_light.light_color = c[0]
		_hand_light.omni_range = c[1]
		_hand_light.light_energy = c[2]
		_hand_light.set_meta("base", c[2])
		_hand_light.set_meta("flicker", c[3])


## Inventory and item changes as Legend sends them over GMCP.
func _on_gmcp(pkg: String, data) -> void:
	if pkg == "char.inventory":
		if data is Dictionary and data.get("items") is Array:
			inventory_items = data["items"]
	elif pkg.begins_with("char.items"):
		_apply_item_changes(data)
		request_quiet_later("equipment", 1.0)
	if menu.visible and menu.page == "Inventory":
		menu.call("_refresh")


## Find {item, loc} pairs anywhere in a char.items message and file them.
func _apply_item_changes(d, removing := false) -> void:
	if d is Array:
		for x in d:
			_apply_item_changes(x, removing)
		return
	if not (d is Dictionary):
		return
	if d.get("item") is Dictionary:
		var it: Dictionary = d["item"]
		var oid := str(it.get("oid", ""))
		var loc := str(d.get("loc", "")).to_lower()
		for i in range(inventory_items.size() - 1, -1, -1):
			if str((inventory_items[i] as Dictionary).get("oid", "")) == oid:
				inventory_items.remove_at(i)
		if not removing and (loc == "" or loc.begins_with("inv")):
			inventory_items.append(it)
		return
	for k in d:
		var key := str(k).to_lower()
		_apply_item_changes(d[k], removing or key.begins_with("remove"))


func request_quiet(cmd: String) -> void:
	if link.is_linked and cmd.strip_edges() != "":
		link.send_quiet(cmd)


func request_quiet_later(cmd: String, secs := 1.5) -> void:
	_quiet_later[cmd] = Time.get_ticks_msec() + int(secs * 1000.0)


## Send a command to Legend as if you'd typed it.
func send_cmd(cmd: String) -> void:
	if not link.is_linked:
		_log_line("(not linked to Mudlet: %s)" % cmd, Color("e06c5a"))
		return
	_note_command(cmd)
	link.send_command(cmd)


func put_cmd_line(text: String) -> void:
	_cmd.text = text
	_cmd.caret_column = text.length()
	_cmd.grab_focus()


func _menu_opened(_cat: String, page: String) -> void:
	if _look:
		_set_look(false)
	var ask := ""
	match page:
		"Equipment":
			if equip_slots.is_empty():
				ask = "equipment"
		"Score":
			ask = "score"
		"Spells":
			if not quiet_text.has(settings.spell_cmd):
				ask = settings.spell_cmd
		"Skills":
			if not quiet_text.has(settings.skill_cmd):
				ask = settings.skill_cmd
	if ask != "" and not (_asked.has(ask) and Time.get_ticks_msec() - int(_asked[ask]) < 4000):
		_asked[ask] = Time.get_ticks_msec()
		request_quiet(ask)


func _menu_closed() -> void:
	_cmd.grab_focus()


func set_appearance(key: String, app: Dictionary) -> void:
	if not catalog.entries.has(key):
		return
	var e: Dictionary = catalog.entries[key]
	if app.has("body"):
		e["body"] = app["body"]
		app.erase("body")
	e["appearance"] = app
	catalog.dirty = true
	catalog.save_file()
	_refresh_contents_entries()
	for r in world.rooms.values():
		if r.node != null:
			world.set_contents(r, r.contents)
	_flash_msg("saved how %s looks" % str(e.get("name", e.get("short", key))))


# ------------------------------------------------------------------ /note

func _load_notes() -> void:
	notes = []
	if not FileAccess.file_exists(NOTES_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(NOTES_PATH))
	if d is Dictionary and d.get("notes") is Array:
		notes = d["notes"]
	else:
		push_warning("Legend3D: couldn't read %s" % NOTES_PATH)


func _save_notes() -> void:
	var f := FileAccess.open(NOTES_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"_help": "Your /note notes, by room (vnum). Edit freely; Legend3D only adds to this.",
		"notes": notes}, "  "))
	f.close()


func add_note(text: String) -> void:
	var r := world.current
	if r == null:
		_log_line("(not in a room yet: walk somewhere first)", Color("e06c5a"))
		return
	notes.append({"vnum": r.vnum, "room": r.room_name(), "area": str(r.data.get("area", "")),
		"cell": [r.cell.x, r.cell.y, r.cell.z], "text": text, "time": Time.get_datetime_string_from_system()})
	_save_notes()
	_log_line("✎ noted for %s: %s" % [r.room_name(), text], Color("c9a65a"))


func delete_note(i: int) -> void:
	if i >= 0 and i < notes.size():
		notes.remove_at(i)
		_save_notes()


func notes_for(vnum: int) -> Array:
	var out := []
	for n in notes:
		if int(n.get("vnum", -1)) == vnum:
			out.append(n)
	return out


# ------------------------------------------------------------------ autopilot (tests)

## LEGEND3D_AUTOPILOT="look,south,shot:a,say:/scan,wait:3,quit" drives the view
## for automated testing. Not used in normal play.
func _run_autopilot(now: int) -> void:
	if _auto.is_empty() or world.current == null:
		return
	if now < _auto_wait_until or _gliding:
		return
	var step: String = _auto[0]
	var is_walk := World.DIRS.has(step) or step.begins_with("pad:")
	if is_walk:
		if not _auto_forward:
			var want := step.substr(4) if step.begins_with("pad:") else step
			var portal: World.Portal = null
			for p: World.Portal in world.current.portals:
				if p.dir == want:
					portal = p
			if portal == null:
				print("[L3D] AUTO no way ", want)
				_auto.pop_front()
				return
			var out := portal.normal
			if portal.kind == "stairs":
				var run := World.FLOOR_H / tan(deg_to_rad(37.0)) + 0.6
				player.position = portal.a - out * (run + 0.8) - Vector3(0, World.FLOOR_H, 0) + Vector3(0, 0.1, 0)
			elif portal.kind == "well":
				player.position = portal.a - out * 2.2
			elif portal.kind == "stairs_down":
				player.position = portal.a - out * 1.3 + Vector3(0, 0.05, 0)
			else:
				player.position = portal.mid() - out * (2.0 if portal.kind == "pad" else 3.5)
				player.position.y = World.center_of(world.current.cell).y + 0.05
			player.velocity = Vector3.ZERO
			player.rotation.y = atan2(-out.x, -out.z)
			_auto_forward = true
			_auto_step_started = now
			_auto_room_at_start = world.current.vnum
			return
		var moved := world.current.vnum != _auto_room_at_start
		var stuck := now - _auto_step_started > 7000
		if moved or stuck:
			_auto_forward = false
			print("[L3D] AUTO %s -> room %d%s" % [step, world.current.vnum, " (stuck)" if stuck else ""])
			_auto.pop_front()
			_auto_wait_until = now + 900
		return
	_auto.pop_front()
	if step.begins_with("shot:"):
		_shoot(step.substr(5))
	elif step.begins_with("turn:"):
		player.rotation.y += deg_to_rad(float(step.substr(5)))
		_auto_wait_until = now + 300
	elif step.begins_with("wait:"):
		_auto_wait_until = now + int(float(step.substr(5)) * 1000)
	elif step.begins_with("fwd:"):
		player.position += -player.global_transform.basis.z * float(step.substr(4))
	elif step.begins_with("at:"):
		var xy := step.substr(3).split(";")
		var c: Vector3 = world.current.shape.get("center", Vector3.ZERO)
		player.position = c + Vector3(float(xy[0]), 0.05, float(xy[1]))
		player.velocity = Vector3.ZERO
		if xy.size() > 2:
			player.rotation.y = deg_to_rad(float(xy[2]))
		if xy.size() > 3:
			camera.rotation.x = deg_to_rad(float(xy[3]))
		_auto_wait_until = now + 250
	elif step.begins_with("weather:"):
		_on_quiet("weather", [step.substr(8).replace("_", " ")])
	elif step.begins_with("clock:"):
		_apply_time(step.substr(6).replace("_", " "))
	elif step.begins_with("say:"):
		_on_submit(step.substr(4))
		_auto_wait_until = now + 900
	elif step.begins_with("quality:"):
		_quality = int(step.substr(8))
		_apply_quality()
	elif step.begins_with("menu:"):
		var mp := step.substr(5).split(":")
		menu.open_category(mp[0], mp[1].replace("_", " ") if mp.size() > 1 else "")
		_auto_wait_until = now + 600
	elif step == "menuclose":
		menu.hide_menu()
	elif step.begins_with("type:"):
		_on_submit(step.substr(5).replace("_", " "))
		_auto_wait_until = now + 900
	elif step == "stats":
		print("[L3D] STATS fps=%d draw_calls=%d objects=%d primitives=%d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	elif step == "quit":
		print("[L3D] AUTO done")
		get_tree().quit()


func _shoot(name: String) -> void:
	if _shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join(name + ".png"))
	print("[L3D] AUTO shot ", name)
