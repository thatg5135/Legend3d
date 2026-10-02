## Your weapon (right hand) and light (left hand), drawn into the low-res
## view like the world, swaying as you walk. Lit by where you are, or by
## the light you're carrying.
class_name Held
extends Node2D

var weapon := ""        # sword, dagger, axe... ("" = empty-handed)
var light_kind := ""    # torch, lantern, candle, orb ("" = none)
var tint := Color.WHITE
var view := Vector2(640, 300)
var _phase := 0.0
var _move := 0.0
var _frame := 0
var _ft := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func tick(delta: float, speed: float, size: Vector2) -> void:
	view = size
	_move = lerpf(_move, clampf(speed / 4.5, 0.0, 1.6), clampf(delta * 6.0, 0.0, 1.0))
	_phase += delta * (2.0 + _move * 7.0)
	_ft -= delta
	if _ft <= 0.0:
		_ft = randf_range(0.08, 0.16)
		_frame = (_frame + 1 + randi() % 2) % 3
	queue_redraw()


func _draw() -> void:
	if weapon == "" and light_kind == "":
		return
	# big in the frame, like Daggerfall: your hands come up from the bottom edge
	var s := clampf(view.y / 150.0, 0.9, 4.0)
	var bob := Vector2(cos(_phase) * 3.0, absf(sin(_phase)) * 4.0) * (0.3 + _move)
	var breathe := sin(_phase * 0.5) * 1.2
	if weapon != "":
		var t := HudArt.weapon(weapon)
		var sz := t.get_size() * s
		var at := Vector2(view.x * 0.95 - sz.x, view.y - sz.y * 0.9) + bob * s + Vector2(0, breathe)
		draw_texture_rect(t, Rect2(at.round(), sz), false, tint)
	if light_kind != "":
		var t2 := HudArt.light(light_kind, _frame)
		var sz2 := t2.get_size() * s
		# left hand, clear of the compass and bars in the corner
		var at2 := Vector2(view.x * 0.36 - sz2.x * 0.5, view.y - sz2.y * 0.88) + Vector2(-bob.x, bob.y) * s + Vector2(0, -breathe)
		var self_lit := tint.lerp(Color.WHITE, 0.75)
		draw_texture_rect(t2, Rect2(at2.round(), sz2), false, self_lit)
