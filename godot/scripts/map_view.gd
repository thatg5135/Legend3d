## The map in the menu: every room you've explored on one level, drawn
## from above around where you stand. Wheel zooms, drag pans, the arrows
## change level, hovering names a room.
class_name MapView
extends Control

var world: World
var level := 0
var zoom := 26.0
var pan := Vector2.ZERO
var picked: World.Room = null
var _drag := false
var _font: Font
signal room_picked(r: World.Room)

const INK := Color("2a1f14")


func _init() -> void:
	custom_minimum_size = Vector2(0, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func center_on_you() -> void:
	pan = Vector2.ZERO
	if world != null and world.current != null:
		level = world.current.cell.y
	queue_redraw()


func _origin() -> Vector2:
	var c := Vector2.ZERO
	if world != null and world.current != null:
		c = Vector2(world.current.cell.x, world.current.cell.z)
	return size * 0.5 - c * zoom + pan


func _cell_pos(r: World.Room) -> Vector2:
	return _origin() + Vector2(r.cell.x, r.cell.z) * zoom


func room_at_point(p: Vector2) -> World.Room:
	if world == null:
		return null
	for r: World.Room in world.rooms.values():
		if r.cell.y != level:
			continue
		if Rect2(_cell_pos(r) - Vector2(zoom, zoom) * 0.36, Vector2(zoom, zoom) * 0.72).has_point(p):
			return r
	return null


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = minf(zoom * 1.15, 80.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = maxf(zoom / 1.15, 8.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:
				var r := room_at_point(mb.position)
				if r != null:
					picked = r
					room_picked.emit(r)
					queue_redraw()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _drag and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			pan += mm.relative
			queue_redraw()
		var r := room_at_point(mm.position)
		tooltip_text = "%s  (#%d)" % [r.room_name(), r.vnum] if r != null else ""


func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.93, 0.87, 0.72, 0.55))
	if world == null:
		return
	var here: World.Room = world.current
	var s := zoom * 0.72
	# ways between rooms first, under the squares
	for r: World.Room in world.rooms.values():
		if r.cell.y != level:
			continue
		for e in r.exits():
			var d := str(e.get("dir", ""))
			if not World.DIRS.has(d):
				continue
			var dv: Vector3i = World.DIRS[d]
			var a := _cell_pos(r)
			if dv.y != 0:
				# a small mark for up and down
				var up := dv.y > 0
				var tri := PackedVector2Array([a + Vector2(s * 0.28, -s * 0.05 if up else s * 0.05),
					a + Vector2(s * 0.42, -s * 0.25 if up else s * 0.25), a + Vector2(s * 0.14, -s * 0.25 if up else s * 0.25)])
				draw_colored_polygon(tri, INK)
				continue
			var to: World.Room = world.rooms.get(int(e.get("to_vnum", -1)))
			var b := a + Vector2(dv.x, dv.z) * zoom * 0.5
			if to != null and to.cell.y == level:
				b = _cell_pos(to)
			draw_line(a, b, INK.lerp(Color(0, 0, 0, 0), 0.25), maxf(zoom * 0.08, 1.5))
	for r: World.Room in world.rooms.values():
		if r.cell.y != level:
			continue
		var p := _cell_pos(r)
		if p.x < -zoom or p.y < -zoom or p.x > size.x + zoom or p.y > size.y + zoom:
			continue
		var col := Color("6f8a4a") if r.is_outdoor() else Color("8a6036")
		var rect := Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_rect(rect, col)
		draw_rect(rect, INK, false, 1.5)
		if r == picked:
			draw_rect(rect.grow(3), Color("a8281e"), false, 2.0)
		if r == here:
			draw_circle(p, s * 0.22, Color("f2d98a"))
			draw_arc(p, s * 0.22, 0, TAU, 16, INK, 1.5)
	if here != null and here.cell.y == level:
		var p2 := _cell_pos(here)
		draw_string(_font, p2 + Vector2(-60, -s * 0.7), here.room_name(), HORIZONTAL_ALIGNMENT_CENTER, 120, 13, INK)
	draw_string(_font, Vector2(10, size.y - 10), "level %d   (wheel zooms, drag to move)" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
