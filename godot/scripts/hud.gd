## Bottom left of the 3D view: a brass compass whose card turns as you do
## (N always points north), and beside it your health, mana and moves.
class_name Hud
extends Control

var yaw := 0.0                   # which way you're facing (radians, 0 = north)
var vit := {}                    # h/H, m/M, v/V from Legend's prompt
var ui_scale := 1.0
var show_compass := true
var show_bars := true
var _font: Font
var _pulse := 0.0

const BAR_COLS := [
	[Color("9e2a20"), Color("d4553c"), Color("5a140e")],   # health
	[Color("2a4c9a"), Color("5a82d0"), Color("142650")],   # mana
	[Color("6a8a2a"), Color("a8c45a"), Color("34481a")],   # moves
]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace"])
	_font = f


func tick(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var px := roundf(2.0 * ui_scale * 2.0) / 2.0   # size of one art pixel on screen
	var margin := 12.0
	var cs := HudArt.COMPASS * px
	var origin := Vector2(margin, size.y - margin - cs)
	if show_compass:
		var c := origin + Vector2(HudArt.COMPASS / 2.0, HudArt.COMPASS / 2.0 + 3.0) * px
		# card turns with you: facing west, north is off to your right
		draw_set_transform(c, yaw, Vector2(px, px))
		draw_texture(HudArt.compass_card(), Vector2(-32, -32))
		draw_set_transform(c, 0.0, Vector2(px, px))
		draw_texture(HudArt.compass_glass(), Vector2(-32, -32))
		draw_set_transform(origin, 0.0, Vector2(px, px))
		draw_texture(HudArt.compass_bezel(), Vector2.ZERO)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	if show_bars:
		var bx := origin.x + (cs + 4.0 * px if show_compass else 0.0)
		var by := origin.y + cs - (HudArt.BARS_H + 4) * px
		var o := Vector2(bx, by)
		draw_set_transform(o, 0.0, Vector2(px, px))
		draw_texture(HudArt.bars_frame(), Vector2.ZERO)
		var pairs := [["h", "H"], ["m", "M"], ["v", "V"]]
		for i in 3:
			var cur = vit.get(pairs[i][0])
			var mx = vit.get(pairs[i][1])
			var r := HudArt.bar_rect(i)
			var frac := 0.0
			if cur != null and mx != null and float(mx) > 0.0:
				frac = clampf(float(cur) / float(mx), 0.0, 1.0)
			var w := floorf(r.size.x * frac)
			var cols: Array = BAR_COLS[i]
			var base: Color = cols[0]
			if i == 0 and frac > 0.0 and frac < 0.25:
				base = base.lerp(Color("ff6040"), 0.5 + 0.5 * sin(_pulse * 7.0))
			if w > 0:
				draw_rect(Rect2(r.position, Vector2(w, r.size.y)), base)
				draw_rect(Rect2(r.position, Vector2(w, 2)), cols[1])
				draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(w, 1)), cols[2])
				# a notch every quarter, like a gauge
				for q in [0.25, 0.5, 0.75]:
					var qx := floorf(r.size.x * q)
					if qx < w:
						draw_rect(Rect2(r.position + Vector2(qx, 0), Vector2(1, r.size.y)), Color(0, 0, 0, 0.25))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# numbers, sharp, on the bars
		var fs := int(round(11.0 * ui_scale))
		for i in 3:
			var cur = vit.get(pairs[i][0])
			var mx = vit.get(pairs[i][1])
			var text := "%d/%d" % [int(cur), int(mx)] if cur != null and mx != null else "?"
			var r := HudArt.bar_rect(i)
			var tl := o + (r.position + Vector2(r.size.x, r.size.y)) * px
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := tl + Vector2(-tw - 3.0 * px * 0.5, -r.size.y * px * 0.5 + fs * 0.36)
			draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f4ead0"))
			var tag: String = ["HP", "MA", "MV"][i]
			var tat := o + Vector2(r.position.x + 2, r.position.y + r.size.y) * px + Vector2(0, -r.size.y * px * 0.5 + fs * 0.36)
			draw_string_outline(_font, tat, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, 4, Color(0, 0, 0, 0.8))
			draw_string(_font, tat, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color("e8d39a"))
