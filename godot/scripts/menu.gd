## The menu (Tab): parchment scrolls for Character, Spellbook and World, a
## leather-bound ledger for Settings, and Help. It reads what the view
## already knows and asks Legend (quietly) for the rest.
class_name GameMenu
extends Control

const CATEGORIES := [
	["character", "Character", ["Equipment", "Inventory", "Score"]],
	["spellbook", "Spellbook", ["Spells", "Skills"]],
	["world", "World", ["Map", "Notes", "People & things"]],
	["settings", "Settings", ["Video", "Audio", "Controls", "Interface"]],
	["help", "Help", ["Help"]],
]
const INK := Color("2a1f14")
const INK_SOFT := Color("5a4630")
const RED_INK := Color("8e2418")
const PAPER := Color("e9dcb6")
const LEDGER_PAPER := Color("efe6cc")

var m: Node                     # main: where the data and the link live
var category := "character"
var page := "Equipment"
var capturing := ""             # an action waiting for its new key ("sc:3" for shortcut 3)
var _picked_item := -1
var _picked_npc := ""

var _serif: SystemFont
var _mono: SystemFont
var _sheet: PanelContainer
var _paper_bg: TextureRect
var _rod_top: Panel
var _rod_bot: Panel
var _cats: HBoxContainer
var _tabs: HBoxContainer
var _title: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _map: MapView


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func build(main: Node) -> void:
	m = main
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["DejaVu Serif", "Liberation Serif", "Noto Serif", "FreeSerif", "serif"])
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace"])
	theme = _make_theme()

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	center.add_child(stack)

	_rod_top = _rod()
	stack.add_child(_rod_top)
	_sheet = PanelContainer.new()
	stack.add_child(_sheet)
	_rod_bot = _rod()
	stack.add_child(_rod_bot)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	_sheet.add_child(inner)

	_cats = HBoxContainer.new()
	_cats.add_theme_constant_override("separation", 4)
	inner.add_child(_cats)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(open_category.bind(c[0]))
		b.set_meta("cat", c[0])
		_cats.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cats.add_child(spacer)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(hide_menu)
	_cats.add_child(close)

	inner.add_child(_rule())
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", RED_INK)
	inner.add_child(_title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	inner.add_child(_tabs)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

	_map = MapView.new()
	_map.world = m.world
	_map.room_picked.connect(_on_map_pick)


func _on_map_pick(_r: World.Room) -> void:
	if page == "Map":
		_refresh()


func _rod() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("5a3a1e")
	sb.border_color = Color("2e1c0c")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	return p


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(INK, 0.45)
	r.custom_minimum_size = Vector2(0, 2)
	return r


var _papers := {}


func _paper_texture(lined: bool) -> Texture2D:
	if _papers.has(lined):
		return _papers[lined]
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if lined else 5
	var base := LEDGER_PAPER if lined else PAPER
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.02
	for y in 256:
		for x in 256:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.darkened(n * 0.12 + rng.randf() * 0.03)
			if lined and y % 22 == 21:
				c = c.lerp(Color("8aa0b8"), 0.35)
			img.set_pixel(x, y, c)
	_papers[lined] = ImageTexture.create_from_image(img)
	return _papers[lined]


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _serif
	t.default_font_size = 16
	for cls in ["Label", "Button", "CheckBox", "LineEdit", "OptionButton", "RichTextLabel"]:
		t.set_color("font_color", cls, INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_hover_color", "Button", RED_INK)
	t.set_color("font_pressed_color", "Button", RED_INK)
	t.set_color("font_hover_pressed_color", "Button", RED_INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_hover_color", "CheckBox", RED_INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", RED_INK)
	t.set_color("font_hover_color", "OptionButton", RED_INK)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.content_margin_left = 8
	flat.content_margin_right = 8
	flat.content_margin_top = 3
	flat.content_margin_bottom = 3
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(INK, 0.08)
	var pressed := flat.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(INK, 0.14)
	pressed.border_color = RED_INK
	pressed.border_width_bottom = 2
	var boxed := flat.duplicate() as StyleBoxFlat
	boxed.bg_color = Color(INK, 0.05)
	boxed.border_color = Color(INK, 0.5)
	boxed.set_border_width_all(1)
	boxed.set_corner_radius_all(3)
	var boxed_h := boxed.duplicate() as StyleBoxFlat
	boxed_h.bg_color = Color(INK, 0.12)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, boxed if cls == "OptionButton" else flat)
		t.set_stylebox("hover", cls, boxed_h if cls == "OptionButton" else hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	t.set_stylebox("normal", "CheckBox", flat)
	t.set_stylebox("hover", "CheckBox", hover)
	t.set_stylebox("pressed", "CheckBox", flat)
	t.set_stylebox("hover_pressed", "CheckBox", hover)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	var le := StyleBoxFlat.new()
	le.bg_color = Color(1, 1, 1, 0.35)
	le.border_color = Color(INK, 0.6)
	le.border_width_bottom = 2
	le.content_margin_left = 6
	le.content_margin_right = 6
	le.content_margin_top = 3
	le.content_margin_bottom = 3
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = RED_INK
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(INK, 0.35)
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider)
	var popup := StyleBoxFlat.new()
	popup.bg_color = PAPER
	popup.border_color = INK
	popup.set_border_width_all(1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", RED_INK)
	var ph := StyleBoxFlat.new()
	ph.bg_color = Color(INK, 0.1)
	t.set_stylebox("hover", "PopupMenu", ph)
	t.set_color("font_color", "TooltipLabel", INK)
	var tip := StyleBoxFlat.new()
	tip.bg_color = PAPER
	tip.border_color = INK
	tip.set_border_width_all(1)
	tip.content_margin_left = 6
	tip.content_margin_right = 6
	tip.content_margin_top = 3
	tip.content_margin_bottom = 3
	t.set_stylebox("panel", "TooltipPanel", tip)
	return t


# ------------------------------------------------------------------ open / close

func toggle() -> void:
	if visible:
		hide_menu()
	else:
		open_category(category)


func hide_menu() -> void:
	visible = false
	capturing = ""
	m.call("_menu_closed")


func open_category(cat: String, pg := "") -> void:
	var was := category
	category = cat
	var pages: Array = _pages_of(cat)
	if pg != "" and pages.has(pg):
		page = pg
	elif cat != was or not pages.has(page):
		page = pages[0]
	visible = true
	_style_sheet()
	_refresh()
	m.call("_menu_opened", cat, page)


func open_page(pg: String) -> void:
	page = pg
	_refresh()
	m.call("_menu_opened", category, page)


func _pages_of(cat: String) -> Array:
	for c in CATEGORIES:
		if c[0] == cat:
			return c[2]
	return ["Help"]


func _style_sheet() -> void:
	var ledger := category == "settings"
	var sb := StyleBoxTexture.new()
	sb.texture = _paper_texture(ledger)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	if ledger:
		# a ledger: a leather binding round the page instead of scroll rods
		var frame := StyleBoxFlat.new()
		frame.bg_color = LEDGER_PAPER
		frame.border_color = Color("5a1e16")
		frame.set_border_width_all(12)
		frame.set_corner_radius_all(4)
		frame.content_margin_left = 34
		frame.content_margin_right = 34
		frame.content_margin_top = 22
		frame.content_margin_bottom = 22
		frame.shadow_color = Color(0, 0, 0, 0.5)
		frame.shadow_size = 8
		_sheet.add_theme_stylebox_override("panel", frame)
	else:
		_sheet.add_theme_stylebox_override("panel", sb)
	_rod_top.visible = not ledger
	_rod_bot.visible = not ledger
	var avail := get_parent_area_size()
	var w := clampf(avail.x * 0.86, 520.0, 980.0)
	var h := clampf(avail.y - 60.0, 260.0, 900.0)
	_sheet.custom_minimum_size = Vector2(w, h)
	_rod_top.custom_minimum_size = Vector2(w + 24, 16)
	_rod_bot.custom_minimum_size = Vector2(w + 24, 16)
	for b in _cats.get_children():
		if b is Button and b.has_meta("cat"):
			(b as Button).button_pressed = b.get_meta("cat") == category


func _refresh() -> void:
	if not visible:
		return
	for c in _tabs.get_children():
		c.queue_free()
	for p in _pages_of(category):
		var b := Button.new()
		b.text = p
		b.toggle_mode = true
		b.button_pressed = p == page
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(open_page.bind(p))
		_tabs.add_child(b)
	_title.text = page if page != "Help" else "Help"
	if _map.get_parent() != null:
		_map.get_parent().remove_child(_map)
	for c in _body.get_children():
		c.queue_free()
	match page:
		"Equipment": _page_equipment()
		"Inventory": _page_inventory()
		"Score": _page_text("score", "Your score sheet, as Legend gives it.")
		"Spells": _page_spells()
		"Skills": _page_text(str(m.settings.skill_cmd), "Your skills, as Legend lists them.")
		"Map": _page_map()
		"Notes": _page_notes()
		"People & things": _page_people()
		"Video": _page_video()
		"Audio": _page_audio()
		"Controls": _page_controls()
		"Interface": _page_interface()
		_: _page_help()


# ------------------------------------------------------------------ little builders

func _label(text: String, size := 16, col := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _note(text: String) -> Label:
	return _label(text, 14, INK_SOFT)


func _heading(text: String) -> Label:
	var l := _label(text, 19, RED_INK, false)
	return l


func _button(text: String, fn: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(fn)
	return b


func _row(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for c in children:
		# wrapping text in a row takes the spare width, or it shrinks to one letter
		if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(c)
	return h


func _grow(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _mono_text(lines: Array) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = true
	r.add_theme_font_override("normal_font", _mono)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_color_override("default_color", INK)
	r.text = "\n".join(lines)
	return r


func _asked(cmd: String) -> void:
	m.call("request_quiet", cmd)
	_body.add_child(_note("Asking Legend (quietly)…"))


# ------------------------------------------------------------------ Character

func _page_equipment() -> void:
	var slots: Array = m.get("equip_slots")
	_body.add_child(_row([_note("What you're wearing and holding."), _button("Check again", func(): _asked("equipment"))]))
	if slots.is_empty():
		_body.add_child(_label("Nothing known yet. Legend3D asks for your equipment when it links and whenever you change gear."))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	for s in slots:
		grid.add_child(_label(str(s["slot"]), 15, INK_SOFT, false))
		grid.add_child(_grow(_label(str(s["item"]), 16, INK, false)))
		var kw := str(s["item"]).to_lower().replace("(glowing)", "").replace("(humming)", "").strip_edges().split(" ", false)
		var word: String = kw[kw.size() - 1] if kw.size() > 0 else ""
		grid.add_child(_row([_button("Look", func(): m.call("send_cmd", "look " + word)),
			_button("Remove", func(): m.call("send_cmd", "remove " + word); m.call("request_quiet_later", "equipment"))]))


func _page_inventory() -> void:
	var groups: Array = Gear.group_items(m.get("inventory_items"))
	_body.add_child(_note("What you're carrying. Pick something to see what you can do with it."))
	if groups.is_empty():
		var raw: Array = m.get("quiet_text").get("inventory", [])
		if raw.is_empty():
			_body.add_child(_label("Legend hasn't sent your inventory yet (it does whenever it changes)."))
			_body.add_child(_button("Ask Legend now", func(): _asked("inventory")))
		else:
			_body.add_child(_mono_text(raw))
		return
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	_body.add_child(split)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(320, 0)
	split.add_child(list)
	for i in groups.size():
		var g: Dictionary = groups[i]
		var text := str(g["short"])
		if int(g["count"]) > 1:
			text = "(%d) %s" % [int(g["count"]), text]
		var b := Button.new()
		b.text = text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = i == _picked_item
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _picked_item = i; _refresh())
		list.add_child(b)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail)
	if _picked_item >= 0 and _picked_item < groups.size():
		var it: Dictionary = groups[_picked_item]["items"][0]
		detail.add_child(_heading(str(it.get("short", ""))))
		if str(it.get("desc", "")) != "":
			detail.add_child(_label(str(it["desc"]), 15, INK_SOFT))
		var facts := []
		if it.has("type"):
			facts.append(str(it["type"]).capitalize())
		if it.has("weight"):
			facts.append("weight %s" % str(it["weight"]))
		if it.get("condition") is Dictionary:
			var cond: Dictionary = it["condition"]
			facts.append("wear %d/%d" % [int(cond.get("dam", 0)), int(cond.get("damMax", 0))])
		if it.get("wearFlags") is Array and not (it["wearFlags"] as Array).is_empty():
			facts.append("worn on: " + ", ".join(PackedStringArray(it["wearFlags"])).to_lower())
		detail.add_child(_label("  ·  ".join(PackedStringArray(facts)), 14, INK_SOFT))
		var acts := HFlowContainer.new()
		for a in Gear.actions_for(it):
			var cmd: String = a[1]
			acts.add_child(_button(a[0], func(): m.call("send_cmd", cmd); m.call("request_quiet_later", "equipment"), cmd))
		detail.add_child(acts)
	else:
		detail.add_child(_note("(nothing picked)"))


func _page_text(cmd: String, blurb: String) -> void:
	var lines: Array = m.get("quiet_text").get(cmd, [])
	_body.add_child(_row([_note(blurb), _button("Ask again", func(): _asked(cmd))]))
	if lines.is_empty():
		_body.add_child(_label("Not asked yet. Legend3D asks the first time you open this page."))
		return
	_body.add_child(_mono_text(lines))


# ------------------------------------------------------------------ Spellbook

func _page_spells() -> void:
	var cmd := str(m.settings.spell_cmd)
	var lines: Array = m.get("quiet_text").get(cmd, [])
	_body.add_child(_row([_note("Click a spell to start typing it. Mana and level are Legend's two numbers, (mana:level)."),
		_button("Ask again", func(): _asked(cmd))]))
	if lines.is_empty():
		_body.add_child(_label("Not asked yet. Legend3D asks the first time you open this page."))
		return
	var spells := Gear.parse_spells(lines)
	if spells.is_empty():
		_body.add_child(_mono_text(lines))
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(grid)
	for h in ["Spell", "Words", "Mana", "Level"]:
		grid.add_child(_label(h, 15, RED_INK, false))
	for s in spells:
		var name := str(s["name"])
		var b := Button.new()
		b.text = name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "cast '%s'" % name
		b.pressed.connect(func(): m.call("put_cmd_line", "cast '%s' " % name); hide_menu())
		grid.add_child(b)
		grid.add_child(_label(str(s["words"]), 15, INK_SOFT, false))
		grid.add_child(_label(str(s["mana"]), 15, INK, false))
		grid.add_child(_label(str(s["level"]), 15, INK, false))


# ------------------------------------------------------------------ World

func _page_map() -> void:
	var here: World.Room = m.world.current
	var bar := _row([
		_button("▲ level up", func(): _map.level += 1; _map.queue_redraw()),
		_button("▼ level down", func(): _map.level -= 1; _map.queue_redraw()),
		_button("Back to me", func(): _map.center_on_you()),
	])
	_body.add_child(bar)
	if _map.picked == null:
		_map.center_on_you()
	_map.custom_minimum_size = Vector2(0, maxf(_scroll.size.y - 140.0, 300.0))
	_body.add_child(_map)
	var r: World.Room = _map.picked if _map.picked != null else here
	if r != null:
		_body.add_child(_heading("%s  (#%d)" % [r.room_name(), r.vnum]))
		var notes: Array = m.call("notes_for", r.vnum)
		for n in notes:
			_body.add_child(_label("✎ " + str(n["text"]), 15, INK_SOFT))


func _page_notes() -> void:
	var here: World.Room = m.world.current
	_body.add_child(_note("Notes you've made with /note while mapping, newest last. They're kept in godot/data/notes.json."))
	if here != null:
		var edit := LineEdit.new()
		edit.placeholder_text = "Add a note for %s…" % here.room_name()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var add := func():
			if edit.text.strip_edges() != "":
				m.call("add_note", edit.text.strip_edges())
				_refresh()
		edit.text_submitted.connect(func(_t): add.call())
		_body.add_child(_row([edit, _button("Add", add)]))
	var notes: Array = m.get("notes")
	if notes.is_empty():
		_body.add_child(_label("No notes yet. Type /note followed by what you noticed, e.g. /note this street is twice as long."))
		return
	var last_room := -1
	for i in notes.size():
		var n: Dictionary = notes[i]
		if int(n.get("vnum", -1)) != last_room:
			last_room = int(n.get("vnum", -1))
			_body.add_child(_heading("%s  (#%d)" % [str(n.get("room", "?")), last_room]))
		var idx := i
		_body.add_child(_row([_grow(_label(str(n["text"]))), _button("Delete", func(): m.call("delete_note", idx); _refresh())]))


func _page_people() -> void:
	var cat: Catalog = m.catalog
	_body.add_child(_note("Everyone and everything Legend3D has looked at. Pick one to change how it's drawn; your changes always win over the guesses."))
	if cat.entries.is_empty():
		_body.add_child(_label("Nothing looked at yet."))
		return
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	_body.add_child(split)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(300, 0)
	split.add_child(list)
	var keys := cat.entries.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = cat.entries[k]
		var b := Button.new()
		b.text = str(e.get("name", e.get("short", k)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = k == _picked_npc
		b.focus_mode = Control.FOCUS_NONE
		var key: String = k
		b.pressed.connect(func(): _picked_npc = key; _refresh())
		list.add_child(b)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail)
	if not cat.entries.has(_picked_npc):
		detail.add_child(_note("(nothing picked)"))
		return
	var e: Dictionary = cat.entries[_picked_npc]
	detail.add_child(_heading(str(e.get("name", e.get("short", _picked_npc)))))
	detail.add_child(_label(str(e.get("short", "")), 14, INK_SOFT))
	var look: Array = e.get("look", []) if e.get("look") is Array else []
	if not look.is_empty():
		detail.add_child(_label(" ".join(PackedStringArray(look.slice(0, 6))).strip_edges(), 14, INK_SOFT))
	var app: Dictionary = e.get("appearance", {}) if e.get("appearance") is Dictionary else {}
	var auto: Dictionary = e.get("auto", {}) if e.get("auto") is Dictionary else {}
	var fields := ["sex", "age", "hair", "hair_color", "beard", "garment", "garment_color", "cloak_color", "held", "height"]
	if str(e.get("body", "")) != "" and str(e.get("body", "")) != "human":
		fields = ["body", "color", "height"]
	var grid := GridContainer.new()
	grid.columns = 2
	detail.add_child(grid)
	var edits := {}
	for f in fields:
		grid.add_child(_label(f.replace("_", " "), 15, INK_SOFT, false))
		var le := LineEdit.new()
		le.custom_minimum_size = Vector2(220, 0)
		le.text = str(app.get(f, e.get(f, "") if f == "body" else ""))
		le.placeholder_text = str(auto.get(f, ""))
		grid.add_child(le)
		edits[f] = le
	detail.add_child(_row([
		_button("Save", _save_appearance.bind(edits)),
		_button("Look again", func(): m.call("send_cmd", "look " + str(e.get("keyword", "")))),
	]))
	detail.add_child(_note("Empty boxes use the guess shown faintly. Changes are saved to npcs.json."))


func _save_appearance(edits: Dictionary) -> void:
	var out := {}
	for f in edits:
		var v: String = (edits[f] as LineEdit).text.strip_edges()
		if v != "":
			out[f] = float(v) if f == "height" and v.is_valid_float() else v
	m.call("set_appearance", _picked_npc, out)
	_refresh()


# ------------------------------------------------------------------ Settings

func _option(items: Array, selected: int, fn: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(fn)
	return o


func _check(text: String, on: bool, fn: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(fn)
	return c


func _slider(lo: float, hi: float, step: float, val: float, fn: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(240, 20)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(fn)
	return s


func _setting_row(label: String, ctl: Control, hint := "") -> void:
	var l := _label(label, 16, INK, false)
	l.custom_minimum_size = Vector2(220, 0)
	var row := _row([l, ctl])
	if hint != "":
		row.add_child(_label(hint, 13, INK_SOFT, false))
	_body.add_child(row)


func _changed() -> void:
	m.call("apply_settings", true)


func _page_video() -> void:
	var v: Dictionary = m.settings.video
	_setting_row("Quality", _option(["Low", "Medium", "High"], int(v["quality"]), func(i): v["quality"] = i; _changed()),
		"how many lamps and fires cast shadows")
	_setting_row("Pixel size", _option(["1 (sharpest)", "2", "3", "4 (chunkiest)"], int(v["pixel"]) - 1, func(i): v["pixel"] = i + 1; _changed()),
		"bigger pixels run faster")
	_setting_row("Sun rays", _check("on", bool(v["rays"]), func(on): v["rays"] = on; _changed()))
	var caps := [0, 30, 60]
	_setting_row("Frame limit", _option(["None", "30 per second", "60 per second"], maxi(caps.find(int(v["fps_cap"])), 0),
		func(i): v["fps_cap"] = caps[i]; _changed()), "a limit keeps a laptop cooler")
	var fov_l := _label("%d°" % int(v["fov"]), 14, INK_SOFT, false)
	var fs := _slider(55, 95, 1, float(v["fov"]), func(x): v["fov"] = x; fov_l.text = "%d°" % int(x); _changed())
	_setting_row("Field of view", _row([fs, fov_l]))
	var ms_l := _label("%.1f×" % float(v["mouse_sens"]), 14, INK_SOFT, false)
	var ms := _slider(0.2, 3.0, 0.1, float(v["mouse_sens"]), func(x): v["mouse_sens"] = x; ms_l.text = "%.1f×" % x; _changed())
	_setting_row("Mouse look speed", _row([ms, ms_l]))


func _page_audio() -> void:
	var a: Dictionary = m.settings.audio
	_setting_row("Legend's sounds", _check("play in Legend3D", bool(a["sound"]), func(on): a["sound"] = on; _changed()),
		"off by default: Mudlet already plays them")
	var vl := _label("%d%%" % int(float(a["volume"]) * 100), 14, INK_SOFT, false)
	_setting_row("Volume", _row([_slider(0, 1, 0.05, float(a["volume"]), func(x): a["volume"] = x; vl.text = "%d%%" % int(x * 100); _changed()), vl]))


func _page_controls() -> void:
	var st: Settings = m.settings
	_body.add_child(_note("Click a key to change it, then press the new key (or mouse button). Esc cancels."))
	var group := ""
	var grid: GridContainer = null
	for a in Settings.ACTIONS:
		if a[2] != group:
			group = a[2]
			_body.add_child(_heading(group))
			grid = GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 14)
			_body.add_child(grid)
		var id: String = a[0]
		var l := _label(a[1], 16, INK, false)
		l.custom_minimum_size = Vector2(280, 0)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 0)
		b.focus_mode = Control.FOCUS_NONE
		b.text = "press a key…" if capturing == id else Settings.bind_text(st.binds.get(id, {}))
		b.add_theme_stylebox_override("normal", theme.get_stylebox("normal", "OptionButton"))
		b.pressed.connect(func(): capturing = id; _refresh())
		grid.add_child(b)
		grid.add_child(_button("Reset", func(): st.binds[id] = st.default_of(id); _changed(); _refresh()))
		var warn := ""
		var clash := st.clashes(id, st.binds.get(id, {}))
		if not clash.is_empty():
			warn = "also: " + ", ".join(PackedStringArray(clash))
		elif Settings.types_text(st.binds.get(id, {})):
			warn = "types a letter too: only works with the command line empty"
		grid.add_child(_label(warn, 13, RED_INK, false))
	_body.add_child(_heading("Your shortcuts"))
	_body.add_child(_note("A key that sends a command to Legend, e.g. F6 → cast 'heal'. They go through your Mudlet aliases."))
	for i in st.shortcuts.size():
		var sc: Dictionary = st.shortcuts[i]
		var idx := i
		var kb := Button.new()
		kb.custom_minimum_size = Vector2(170, 0)
		kb.focus_mode = Control.FOCUS_NONE
		kb.text = "press a key…" if capturing == "sc:%d" % i else Settings.bind_text(sc["bind"])
		kb.add_theme_stylebox_override("normal", theme.get_stylebox("normal", "OptionButton"))
		kb.pressed.connect(func(): capturing = "sc:%d" % idx; _refresh())
		var ce := LineEdit.new()
		ce.text = str(sc["cmd"])
		ce.placeholder_text = "command to send"
		ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ce.text_changed.connect(func(t): sc["cmd"] = t; m.call("apply_settings", false))
		ce.focus_exited.connect(func(): m.call("apply_settings", true))
		_body.add_child(_row([kb, ce, _button("Remove", func(): st.shortcuts.remove_at(idx); _changed(); _refresh())]))
	_body.add_child(_row([_button("Add a shortcut", _add_shortcut), _button("Reset every key", _reset_keys)]))


func _add_shortcut() -> void:
	var st: Settings = m.settings
	st.shortcuts.append({"bind": {}, "cmd": ""})
	capturing = "sc:%d" % (st.shortcuts.size() - 1)
	_changed()
	_refresh()


func _reset_keys() -> void:
	var st: Settings = m.settings
	for a in Settings.ACTIONS:
		st.binds[a[0]] = (a[3] as Dictionary).duplicate()
	_changed()
	_refresh()


## A key arrived while waiting for a new binding. True if it was used.
func capture_input(e: InputEvent) -> bool:
	if capturing == "":
		return false
	if e is InputEventMouseMotion or not (e is InputEventKey or e is InputEventMouseButton):
		return false
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return false   # left click and the wheel are for the menu itself
	if not e.is_pressed():
		return true
	if e is InputEventKey and (e as InputEventKey).keycode == KEY_ESCAPE:
		capturing = ""
		_refresh()
		return true
	var st: Settings = m.settings
	var b := Settings.from_event(e)
	if e is InputEventKey:
		var k := (e as InputEventKey).keycode
		# a lone Shift/Ctrl/Alt is only a key in itself for the hold-down actions
		if k in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META] and not (capturing in ["run", "sidestep"]):
			return true
	if capturing.begins_with("sc:"):
		var i := int(capturing.substr(3))
		if i >= 0 and i < st.shortcuts.size():
			st.shortcuts[i]["bind"] = b
	else:
		st.binds[capturing] = b
	capturing = ""
	_changed()
	_refresh()
	return true


func _page_interface() -> void:
	var u: Dictionary = m.settings.ui
	var sl := _label("%d%%" % int(float(u["hud_scale"]) * 100), 14, INK_SOFT, false)
	_setting_row("HUD size", _row([_slider(0.5, 2.0, 0.25, float(u["hud_scale"]), func(x): u["hud_scale"] = x; sl.text = "%d%%" % int(x * 100); _changed()), sl]))
	_setting_row("Compass", _check("show", bool(u["compass"]), func(on): u["compass"] = on; _changed()))
	_setting_row("Health, mana, moves", _check("show", bool(u["bars"]), func(on): u["bars"] = on; _changed()))
	_setting_row("Weapon and light in hand", _check("show", bool(u["held"]), func(on): u["held"] = on; _changed()))
	_setting_row("Names over people", _check("show", bool(u["names"]), func(on): u["names"] = on; _changed()))
	_setting_row("Exit labels (UP, DOWN...)", _check("show", bool(u["exit_labels"]), func(on): u["exit_labels"] = on; _changed()))


# ------------------------------------------------------------------ Help

func _page_help() -> void:
	var st: Settings = m.settings
	var linked: bool = m.link.is_linked
	_body.add_child(_label("Link to Mudlet: " + ("linked (relay v%s)" % str(m.get("relay_version")) if linked else "not linked. Type 3d in Mudlet."),
		16, Color("2e5a1e") if linked else RED_INK))
	_body.add_child(_heading("Your keys"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	_body.add_child(grid)
	for a in Settings.ACTIONS:
		grid.add_child(_label(Settings.bind_text(st.binds.get(a[0], {})), 15, RED_INK, false))
		grid.add_child(_label(a[1], 15, INK, false))
	grid.add_child(_label("any letter", 15, RED_INK, false))
	grid.add_child(_label("starts typing a command", 15, INK, false))
	_body.add_child(_heading("Legend3D commands"))
	_body.add_child(_mono_text(["/note <text>   note something about this room (for mapping)",
		"/note          show this room's notes",
		"/scan          look at anything new here    /scan all   look at everything again",
		"/menu          open this menu"]))
	var path := ProjectSettings.globalize_path("res://").path_join("../HELP.md").simplify_path()
	if FileAccess.file_exists(path):
		_body.add_child(_heading("The help file"))
		var rt := RichTextLabel.new()
		rt.fit_content = true
		rt.scroll_active = false
		rt.selection_enabled = true
		rt.bbcode_enabled = true
		rt.add_theme_color_override("default_color", INK)
		rt.add_theme_font_size_override("normal_font_size", 15)
		rt.add_theme_font_override("mono_font", _mono)
		rt.text = _md_to_bbcode(FileAccess.get_file_as_string(path))
		_body.add_child(rt)
	else:
		_body.add_child(_note("(HELP.md is in the legend3d folder.)"))


## Just enough Markdown for HELP.md: headings, bold, code, bullets, tables.
func _md_to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var code := RegEx.create_from_string("`([^`]+)`")
	for raw in md.split("\n"):
		var l := raw.replace("[", "[lb]")
		if l.begins_with("|---") or l.begins_with("|-"):
			continue
		if l.begins_with("# "):
			l = "[font_size=24][color=#8e2418]%s[/color][/font_size]" % l.substr(2)
		elif l.begins_with("## "):
			l = "\n[font_size=20][color=#8e2418]%s[/color][/font_size]" % l.substr(3)
		elif l.begins_with("### "):
			l = "[font_size=17][b]%s[/b][/font_size]" % l.substr(4)
		elif l.begins_with("---"):
			l = ""
		elif l.begins_with("|"):
			var cells := l.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
			l = "    " + "  —  ".join(cells).strip_edges()
		l = bold.sub(l, "[b]$1[/b]", true)
		l = code.sub(l, "[code]$1[/code]", true)
		l = l.replace("- ", "• ") if l.strip_edges().begins_with("- ") else l
		out.append(l)
	return "\n".join(out)
