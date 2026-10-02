## Pixel art for the HUD and your hands, painted in code: the brass compass,
## the frame for the health/mana/moves bars, and weapons and lights held in
## first person. Drawn small and scaled up with hard pixels, like the world.
class_name HudArt
extends RefCounted

static var _cache := {}

const BRASS_HI := Color("f2d98a")
const BRASS := Color("c9a24a")
const BRASS_MID := Color("a07a2e")
const BRASS_DK := Color("6a4a1a")
const BRASS_DEEP := Color("3e2a0e")
const CARD := Color("e8dcb8")
const CARD_DK := Color("c8b88e")
const INK := Color("2a1f14")
const NORTH_RED := Color("a8281e")

# 5x7 letters for the compass card
const GLYPHS := {
	"N": ["10001", "11001", "10101", "10101", "10011", "10001", "10001"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
}


static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		if c.a >= 0.999:
			img.set_pixel(x, y, c)
		else:
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			_px(img, x, y, c)


## A thick line from a to b.
static func _line(img: Image, a: Vector2, b: Vector2, wdt: float, c: Color) -> void:
	var n := int(maxf(a.distance_to(b), 1.0) * 2.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var r := wdt * 0.5
		for y in range(int(p.y - r) - 1, int(p.y + r) + 2):
			for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
				if Vector2(x + 0.5, y + 0.5).distance_to(p) <= r:
					_px(img, x, y, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy)) <= r:
				_px(img, x, y, c)


static func _poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(int(lo.y) - 1, int(hi.y) + 2):
		for x in range(int(lo.x) - 1, int(hi.x) + 2):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_px(img, x, y, c)


static func _glyph(img: Image, ch: String, x0: int, y0: int, c: Color) -> void:
	var rows: Array = GLYPHS.get(ch, [])
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "1":
				_px(img, x0 + x, y0 + y, c)


# ================================================================== compass

const COMPASS := 80   # bezel size in art pixels
const CARD_R := 27.0


## The brass case: ring, screws, a lubber line at the top (your heading).
static func compass_bezel() -> Texture2D:
	if _cache.has("bezel"):
		return _cache["bezel"]
	var s := COMPASS
	var img := _img(s, s)
	var c := Vector2(s / 2.0, s / 2.0 + 3.0)
	var outer := 36.0
	var inner := CARD_R + 2.5
	# suspension ring on top, like a pocket compass
	for y in range(0, 10):
		for x in range(s / 2 - 7, s / 2 + 7):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(s / 2.0, 6.5))
			if d <= 6.0 and d >= 3.6:
				_px(img, x, y, BRASS_HI if y < 5 else BRASS_MID)
	_rect(img, s / 2 - 3, 7, s / 2 + 3, 10, BRASS_DK)
	_rect(img, s / 2 - 2, 7, s / 2 + 2, 9, BRASS)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := p.length()
			if d > outer or d < inner:
				continue
			# light from the top left
			var lit := clampf(0.5 - (p.normalized().dot(Vector2(0.7, 0.7))) * 0.5, 0.0, 1.0)
			var col: Color
			if d > outer - 1.2:
				col = BRASS_DEEP
			elif d > outer - 3.0:
				col = BRASS_DK.lerp(BRASS_HI, lit)
			elif d > inner + 3.5:
				col = BRASS_MID.lerp(BRASS_HI, lit * 0.9)
				# a little hand-hammered texture
				if (x * 7 + y * 13) % 11 == 0:
					col = col.darkened(0.12)
			elif d > inner + 1.0:
				col = BRASS_DK.lerp(BRASS, lit)
			else:
				col = BRASS_DEEP
			_px(img, x, y, col)
	# engraved degree marks round the bezel
	for i in 32:
		var a := i * TAU / 32.0
		var dir := Vector2(sin(a), -cos(a))
		var r0 := outer - 4.5
		var r1 := r0 - (2.0 if i % 4 == 0 else 1.0)
		_line(img, c + dir * r0, c + dir * r1, 1.0, BRASS_DEEP)
	# four screws
	for i in 4:
		var a := PI / 4 + i * PI / 2
		var sp := c + Vector2(sin(a), -cos(a)) * (outer - 2.0)
		_disc(img, sp.x, sp.y, 1.6, BRASS_DEEP)
		_px(img, int(sp.x), int(sp.y) - 1, BRASS_HI)
	# lubber line: a small brass pointer over the glass at the top
	var tip := c + Vector2(0, -inner + 5.0)
	_poly(img, PackedVector2Array([c + Vector2(-3, -inner - 1), c + Vector2(3, -inner - 1), tip]), BRASS_HI)
	_line(img, c + Vector2(0, -inner - 1), tip, 1.0, BRASS_DK)
	var t := _tex(img)
	_cache["bezel"] = t
	return t


## The card that turns: a compass rose with N in red.
static func compass_card() -> Texture2D:
	if _cache.has("card"):
		return _cache["card"]
	var s := 64
	var img := _img(s, s)
	var c := Vector2(s / 2.0, s / 2.0)
	var r := CARD_R
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				var col := CARD.lerp(CARD_DK, clampf((d / r) * (d / r), 0.0, 1.0) * 0.6)
				if (x * 5 + y * 3) % 9 == 0:
					col = col.darkened(0.04)
				_px(img, x, y, col)
	# rings
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if absf(d - (r - 0.6)) < 0.6 or absf(d - (r - 6.0)) < 0.5:
				_px(img, x, y, INK)
	# ticks every 10 degrees
	for i in 36:
		var a := i * TAU / 36.0
		var dir := Vector2(sin(a), -cos(a))
		_line(img, c + dir * (r - 1.0), c + dir * (r - (3.5 if i % 9 == 0 else 2.2)), 1.0, INK)
	# the rose: diagonal points first, then the cardinal ones over them
	for i in 4:
		var a := PI / 4 + i * PI / 2
		var dir := Vector2(sin(a), -cos(a))
		var perp := Vector2(-dir.y, dir.x)
		var tipp := c + dir * (r - 9.0)
		_poly(img, PackedVector2Array([c + perp * 2.5, tipp, c - perp * 2.5]), CARD_DK.darkened(0.35))
		_poly(img, PackedVector2Array([c, tipp, c + perp * 2.5]), INK.lightened(0.25))
	for i in 4:
		var a := i * PI / 2
		var dir := Vector2(sin(a), -cos(a))
		var perp := Vector2(-dir.y, dir.x)
		var tipp := c + dir * (r - 8.0)
		var dark := NORTH_RED if i == 0 else INK
		var light := NORTH_RED.lightened(0.35) if i == 0 else CARD_DK.darkened(0.15)
		_poly(img, PackedVector2Array([c + perp * 3.6, tipp, c]), light)
		_poly(img, PackedVector2Array([c, tipp, c - perp * 3.6]), dark)
	_disc(img, c.x, c.y, 2.2, BRASS)
	_px(img, int(c.x) - 1, int(c.y) - 1, BRASS_HI)
	# letters, upright to the card, just inside the ring
	var letters := ["N", "E", "S", "W"]
	for i in 4:
		var a := i * PI / 2
		var dir := Vector2(sin(a), -cos(a))
		var at := c + dir * (r - 3.4)
		# rotate the glyph with the card by drawing it on a small image and turning it
		var g := _img(9, 9)
		_glyph(g, letters[i], 2, 1, NORTH_RED if i == 0 else INK)
		for gy in 9:
			for gx in 9:
				var col := g.get_pixel(gx, gy)
				if col.a < 0.5:
					continue
				var off := Vector2(gx - 4.0, gy - 4.0).rotated(a)
				_px(img, int(round(at.x + off.x)), int(round(at.y + off.y)), col)
	var t := _tex(img)
	_cache["card"] = t
	return t


## Light catching the glass, drawn over the card.
static func compass_glass() -> Texture2D:
	if _cache.has("glass"):
		return _cache["glass"]
	var s := 64
	var img := _img(s, s)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := p.length()
			if d > CARD_R + 1.5:
				continue
			# a soft crescent of reflection top-left, and a shadow under the rim
			var refl := Vector2(x + 0.5, y + 0.5).distance_to(c + Vector2(-9, -11))
			if refl < 13.0 and d > CARD_R - 9.0:
				_px(img, x, y, Color(1, 1, 0.95, 0.22))
			elif d > CARD_R - 1.5:
				_px(img, x, y, Color(0, 0, 0, 0.35))
	_px(img, 22, 17, Color(1, 1, 1, 0.8))
	_px(img, 23, 17, Color(1, 1, 1, 0.6))
	_px(img, 22, 18, Color(1, 1, 1, 0.6))
	var t := _tex(img)
	_cache["glass"] = t
	return t


# ================================================================== bars

const BAR_W := 92
const BAR_H := 7
const BARS_W := 104
const BARS_H := 34


## A dark oak plank with brass corners, three channels for the bars.
static func bars_frame() -> Texture2D:
	if _cache.has("bars"):
		return _cache["bars"]
	var img := _img(BARS_W, BARS_H)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in BARS_H:
		for x in BARS_W:
			var grain := sin(x * 0.21 + sin(y * 0.9) * 1.7) * 0.5 + 0.5
			var col := Color("3a2614").lerp(Color("5a3a1e"), grain * 0.6 + rng.randf() * 0.15)
			if y == 0 or x == 0:
				col = Color("7a5430")
			elif y == BARS_H - 1 or x == BARS_W - 1:
				col = Color("1e130a")
			_px(img, x, y, col)
	for i in 3:
		var y0 := 3 + i * 10
		_rect(img, 5, y0, 5 + BAR_W + 2, y0 + BAR_H + 2, Color("120b06"))
		_rect(img, 6, y0 + 1, 6 + BAR_W, y0 + 1 + BAR_H, Color("1c120a"))
	# brass corner caps and studs
	for cx in [0, BARS_W - 4]:
		for cy in [0, BARS_H - 4]:
			_rect(img, cx, cy, cx + 4, cy + 4, BRASS_MID)
			_px(img, cx + 1, cy + 1, BRASS_HI)
			_px(img, cx + 2, cy + 2, BRASS_DK)
	var t := _tex(img)
	_cache["bars"] = t
	return t


## Where each bar's channel sits inside the frame (art pixels).
static func bar_rect(i: int) -> Rect2:
	return Rect2(6, 4 + i * 10, BAR_W, BAR_H)


# ================================================================== hands

const SKIN := Color("e0b088")
const SKIN_DK := Color("b07a56")
const SLEEVE := Color("4a3a2a")
const IRON := Color("8e9298")
const IRON_HI := Color("d6dade")
const IRON_DK := Color("4a4e54")
const WOOD := Color("6a4426")
const WOOD_DK := Color("3e2614")
const LEATHER := Color("5a3418")


## A right hand gripping something at (gx, gy), seen from behind.
static func _fist(img: Image, gx: int, gy: int, sleeve := true) -> void:
	if sleeve:
		_poly(img, PackedVector2Array([Vector2(gx - 8, gy + 8), Vector2(gx + 12, gy + 6), Vector2(gx + 22, img.get_height()), Vector2(gx - 4, img.get_height())]), SLEEVE)
		_line(img, Vector2(gx - 8, gy + 8), Vector2(gx + 12, gy + 6), 2.0, SLEEVE.darkened(0.3))
	_rect(img, gx - 7, gy - 4, gx + 8, gy + 8, SKIN)
	for k in 4:
		_rect(img, gx - 7, gy - 4 + k * 3, gx + 8, gy - 3 + k * 3, SKIN_DK)
	_rect(img, gx - 9, gy - 2, gx - 6, gy + 6, SKIN)  # thumb
	_line(img, Vector2(gx - 9, gy - 2), Vector2(gx - 9, gy + 5), 1.0, SKIN_DK)


## Weapon in your right hand, bottom right of the view. Size 72x110 art px.
static func weapon(kind: String) -> Texture2D:
	var key := "w_" + kind
	if _cache.has(key):
		return _cache[key]
	var img := _img(72, 110)
	var g := Vector2(44, 84)   # where the hand grips
	match kind:
		"dagger":
			_line(img, g + Vector2(4, -8), g + Vector2(-10, -46), 5.0, IRON)
			_line(img, g + Vector2(5, -10), g + Vector2(-8, -45), 1.5, IRON_HI)
			_line(img, g + Vector2(-8, -8), g + Vector2(14, -10), 3.0, IRON_DK)
			_line(img, g + Vector2(2, 2), g + Vector2(6, 12), 4.0, LEATHER)
		"axe":
			_line(img, g + Vector2(6, 16), g + Vector2(-12, -70), 4.0, WOOD)
			_line(img, g + Vector2(7, 14), g + Vector2(-11, -70), 1.0, WOOD.lightened(0.25))
			_poly(img, PackedVector2Array([g + Vector2(-10, -58), g + Vector2(-34, -74), g + Vector2(-36, -48), g + Vector2(-8, -50)]), IRON)
			_line(img, g + Vector2(-34, -73), g + Vector2(-36, -49), 2.0, IRON_HI)
			_rect(img, int(g.x) - 15, int(g.y) - 66, int(g.x) - 7, int(g.y) - 50, IRON_DK)
		"mace":
			_line(img, g + Vector2(6, 16), g + Vector2(-8, -56), 4.0, WOOD)
			_disc(img, g.x - 10, g.y - 62, 9.0, IRON)
			for k in 6:
				var a := k * TAU / 6
				_line(img, Vector2(g.x - 10, g.y - 62), Vector2(g.x - 10, g.y - 62) + Vector2(cos(a), sin(a)) * 12.0, 3.0, IRON_DK)
			_disc(img, g.x - 12, g.y - 65, 3.0, IRON_HI)
		"hammer":
			_line(img, g + Vector2(6, 16), g + Vector2(-8, -60), 4.0, WOOD)
			_poly(img, PackedVector2Array([g + Vector2(-24, -72), g + Vector2(6, -66), g + Vector2(4, -52), g + Vector2(-26, -58)]), IRON)
			_line(img, g + Vector2(-24, -71), g + Vector2(5, -65), 2.0, IRON_HI)
		"spear":
			_line(img, g + Vector2(10, 30), g + Vector2(-16, -96), 3.5, WOOD)
			_poly(img, PackedVector2Array([g + Vector2(-14, -88), g + Vector2(-12, -96), g + Vector2(-20, -110), g + Vector2(-22, -98)]), IRON)
			_line(img, g + Vector2(-13, -92), g + Vector2(-20, -108), 1.0, IRON_HI)
		"staff":
			_line(img, g + Vector2(10, 30), g + Vector2(-14, -100), 5.0, WOOD)
			_line(img, g + Vector2(11, 28), g + Vector2(-13, -100), 1.5, WOOD.lightened(0.3))
			_disc(img, g.x - 15, g.y - 98, 5.0, WOOD_DK)
			for k in 3:
				_line(img, g + Vector2(-6 - k * 3, -50 - k * 16), g + Vector2(-1 - k * 3, -48 - k * 16), 1.0, Color("c9a24a"))
		"bow":
			var top := g + Vector2(-6, -90)
			var bot := g + Vector2(6, 24)
			for i in 30:
				var t0 := float(i) / 30.0
				var t1 := float(i + 1) / 30.0
				var p0 := top.lerp(bot, t0) + Vector2(-sin(t0 * PI) * 16.0, 0)
				var p1 := top.lerp(bot, t1) + Vector2(-sin(t1 * PI) * 16.0, 0)
				_line(img, p0, p1, 3.5, WOOD)
			_line(img, top, bot, 1.0, Color("d8d0b8"))
		"whip", "sling":
			for i in 12:
				var a0 := Vector2(g.x - 4 + sin(i * 0.9) * 10, g.y - 6 - i * 5)
				var a1 := Vector2(g.x - 4 + sin((i + 1) * 0.9) * 10, g.y - 6 - (i + 1) * 5)
				_line(img, a0, a1, 2.5 - i * 0.12, LEATHER)
		_:  # sword
			var tip := g + Vector2(-34, -100)
			var base := g + Vector2(1, -13)
			var dir := (tip - base).normalized()
			var perp := Vector2(-dir.y, dir.x)
			_poly(img, PackedVector2Array([base + perp * 4.5, base - perp * 4.5, tip - perp * 1.2 - dir * 8.0, tip, tip + perp * 1.2 - dir * 8.0]), IRON)
			_line(img, base + perp * 3.5, tip + perp * 0.6 - dir * 6.0, 1.0, IRON_HI)
			_line(img, base - perp * 0.2, tip - dir * 14.0, 1.0, IRON_DK)
			_line(img, base - perp * 4.0, tip - perp * 0.8 - dir * 7.0, 1.0, IRON_DK.lightened(0.15))
			# crossguard, grip, pommel
			_line(img, g + Vector2(-15, -10), g + Vector2(17, -15), 5.0, Color("7a5a22"))
			_line(img, g + Vector2(-15, -12), g + Vector2(17, -17), 1.0, Color("d4b04a"))
			_line(img, g + Vector2(1, -8), g + Vector2(4, 12), 6.0, LEATHER)
			for k in 4:
				_line(img, g + Vector2(-2, -4 + k * 4), g + Vector2(6, -5 + k * 4), 1.0, LEATHER.darkened(0.35))
			_disc(img, g.x + 4.5, g.y + 15, 4.0, Color("7a5a22"))
			_px(img, int(g.x) + 3, int(g.y) + 13, Color("d4b04a"))
	_fist(img, int(g.x), int(g.y))
	var t := _tex(img)
	_cache[key] = t
	return t


## A light in your left hand, bottom left. frame 0/1/2 flickers the flame.
static func light(kind: String, frame: int) -> Texture2D:
	var key := "l_%s_%d" % [kind, frame]
	if _cache.has(key):
		return _cache[key]
	var img := _img(64, 110)
	var g := Vector2(26, 84)
	var rng := RandomNumberGenerator.new()
	rng.seed = frame * 97 + 3
	match kind:
		"lantern":
			# hanging from the hand by its ring
			var top := Vector2(g.x, g.y - 14)
			_line(img, top + Vector2(0, -6), top + Vector2(0, -16), 1.5, IRON_DK)
			_disc(img, top.x, top.y - 20, 4.0, IRON_DK)
			_disc(img, top.x, top.y - 20, 2.2, Color(0, 0, 0, 0))
			var body := Rect2(top.x - 11, top.y - 58, 22, 30)
			_rect(img, int(body.position.x), int(body.position.y), int(body.end.x), int(body.end.y), Color("ffcf6a"))
			_rect(img, int(body.position.x) + 3, int(body.position.y) + 3, int(body.end.x) - 3, int(body.end.y) - 3, Color("fff0b0"))
			_disc(img, top.x, top.y - 40 - frame, 3.0 + frame * 0.4, Color("ffffff"))
			for x in [body.position.x, body.position.x + 10, body.end.x - 2]:
				_rect(img, int(x), int(body.position.y), int(x) + 2, int(body.end.y), IRON_DK)
			_rect(img, int(body.position.x) - 2, int(body.position.y) - 4, int(body.end.x) + 2, int(body.position.y), IRON_DK)
			_rect(img, int(body.position.x) - 2, int(body.end.y), int(body.end.x) + 2, int(body.end.y) + 3, IRON_DK)
			_poly(img, PackedVector2Array([Vector2(body.position.x - 2, body.position.y - 4), Vector2(top.x, body.position.y - 12), Vector2(body.end.x + 2, body.position.y - 4)]), IRON_DK)
			# hand above it, holding the ring
			_rect(img, int(g.x) - 7, int(g.y) - 40, int(g.x) + 8, int(g.y) - 30, SKIN)
			_poly(img, PackedVector2Array([Vector2(g.x - 6, g.y - 32), Vector2(g.x + 10, g.y - 32), Vector2(g.x + 20, 110), Vector2(g.x - 10, 110)]), SLEEVE)
		"candle":
			_rect(img, int(g.x) - 12, int(g.y) - 14, int(g.x) + 12, int(g.y) - 10, Color("8a6a2a"))
			_rect(img, int(g.x) - 3, int(g.y) - 36, int(g.x) + 3, int(g.y) - 14, Color("ece0c0"))
			_flame(img, Vector2(g.x, g.y - 38), 4.0, 9.0, frame, rng)
			_fist(img, int(g.x), int(g.y) - 2)
		"orb":
			_disc(img, g.x, g.y - 30, 15.0, Color(0.7, 0.85, 1.0, 0.35))
			_disc(img, g.x, g.y - 30, 10.0, Color(0.85, 0.93, 1.0, 0.8))
			_disc(img, g.x - 3, g.y - 34, 3.0 + frame * 0.3, Color(1, 1, 1))
			_fist(img, int(g.x), int(g.y))
		_:  # torch
			_line(img, g + Vector2(4, 22), g + Vector2(-6, -40), 5.0, WOOD)
			_line(img, g + Vector2(5, 20), g + Vector2(-5, -40), 1.0, WOOD.lightened(0.25))
			for k in 4:
				_line(img, g + Vector2(-11, -40 - k * 3), g + Vector2(0, -38 - k * 3), 2.0, Color("4a3a24") if k % 2 == 0 else Color("6a5636"))
			_flame(img, g + Vector2(-6, -52), 9.0, 24.0, frame, rng)
			_fist(img, int(g.x), int(g.y))
	var t := _tex(img)
	_cache[key] = t
	return t


static func _flame(img: Image, base: Vector2, w: float, h: float, frame: int, rng: RandomNumberGenerator) -> void:
	var lean: float = [-1.5, 1.0, 0.0][frame % 3]
	var layers := [[1.0, Color("c8481a")], [0.75, Color("f08a24")], [0.5, Color("ffd060")], [0.25, Color("fff6d0")]]
	for L in layers:
		var f: float = L[0]
		var col: Color = L[1]
		var pts := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			var a := t * TAU
			var x := sin(a) * w * f * (0.6 + 0.4 * cos(a * 0.5))
			var y := -(1.0 - cos(a)) * 0.5 * h * f * (0.9 + rng.randf() * 0.15)
			pts.append(base + Vector2(x + lean * (-y / h) * 4.0, y * 1.0 + 2))
		_poly(img, pts, col)
