## Hand-painted-style textures, generated in code.
##
## The look: big, readable shapes (each stone, plank and bundle drawn on
## purpose), painted light along top/left edges and shade along bottom/right,
## soft color variation, very little pixel noise. Every texture tiles.
## Results are cached in user://tex_cache so startup stays quick.
class_name Tex
extends RefCounted

const S := 128
const VERSION := 3
static var _cache := {}


static func get_tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var img := _load_cached(name)
	if img == null:
		img = Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name)
		_paint(name, img, rng)
		_save_cached(name, img)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[name] = tex
	return tex


static func _cache_path(name: String) -> String:
	return "user://tex_cache/%s_v%d.png" % [name, VERSION]


static func _load_cached(name: String) -> Image:
	var p := _cache_path(name)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))
	if img == null or img.get_width() != S:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _save_cached(name: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tex_cache"))
	img.save_png(ProjectSettings.globalize_path(_cache_path(name)))


static func _paint(name: String, img: Image, rng: RandomNumberGenerator) -> void:
	match name:
		"stone": _blocks(img, rng, Color("7c766c"), 4, 0.10)
		"drystone": _fieldstone(img, rng, Color("817a6e"), 0.13)
		"hearthstone": _fieldstone(img, rng, Color("5e5650"), 0.09)
		"rock": _rock(img, rng)
		"plaster": _daub(img, rng, Color("c4b496"))
		"daub": _daub(img, rng, Color("b7a585"))
		"wattle": _wattle(img, rng)
		"thatch": _thatch(img, rng, Color("a68a52"))
		"thatch_under": _thatch(img, rng, Color("5a4426"))
		"wood": _planks(img, rng, Color("7a5434"), false)
		"beams": _planks(img, rng, Color("4e3622"), true)
		"timber": _timber(img, rng, Color("6e4c2e"))
		"darktimber": _timber(img, rng, Color("44301e"))
		"post_painted": _painted_post(img, rng)
		"earth": _earth(img, rng)
		"dirt": _path(img, rng, false)
		"path_stones": _path(img, rng, true)
		"grass": _grass(img, rng)
		"cobble": _cobble(img, rng, Color("8a8478"))
		"hedge": _hedge(img, rng)
		"sand": _soft(img, rng, Color("c8b07c"), Color("a89060"), 0.06)
		"water": _water(img, rng)
		"iron": _soft(img, rng, Color("4a4744"), Color("33302d"), 0.05)
		"cloth": _cloth(img, rng, Color("8a7658"))
		"wool_white": _cloth(img, rng, Color("dcd2bc"))
		"hanging_a": _hanging(img, rng, Color("7a2a20"), Color("d8b860"), 0)
		"hanging_b": _hanging(img, rng, Color("2c4a3a"), Color("d0c090"), 1)
		"knot_band": _knot_band(img, rng)
		"palisade": _palisade(img, rng)
		"pad": _pad(img)
		"fog": _soft(img, rng, Color("26282e"), Color("34363e"), 0.03)
		_: _soft(img, rng, Color("808080"), Color("606060"), 0.05)


# ---------------------------------------------------------------- helpers

static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1))


static func _tint(c: Color, d: float) -> Color:
	return Color(clampf(c.r + d, 0, 1), clampf(c.g + d, 0, 1), clampf(c.b + d, 0, 1))


## Smooth tileable value noise in 0..1. `cells` lattice cells across the tile.
static func _vnoise(x: float, y: float, cells: int, seed_value: int) -> float:
	var fx := x / S * cells
	var fy := y / S * cells
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lat(x0, y0, cells, seed_value)
	var b := _lat(x0 + 1, y0, cells, seed_value)
	var c := _lat(x0, y0 + 1, cells, seed_value)
	var d := _lat(x0 + 1, y0 + 1, cells, seed_value)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


static func _lat(x: int, y: int, cells: int, seed_value: int) -> float:
	var xi := posmod(x, cells)
	var yi := posmod(y, cells)
	var h := hash(Vector3i(xi, yi, seed_value))
	return float(h % 10007) / 10006.0


static func _fbm(x: float, y: float, seed_value: int) -> float:
	return _vnoise(x, y, 4, seed_value) * 0.55 + _vnoise(x, y, 8, seed_value + 1) * 0.3 + _vnoise(x, y, 16, seed_value + 2) * 0.15


## Soft painted mottling over a base color.
static func _soft(img: Image, rng: RandomNumberGenerator, a: Color, b: Color, grain: float) -> void:
	var sd := rng.randi()
	for y in S:
		for x in S:
			var n := _fbm(x, y, sd)
			var c := a.lerp(b, smoothstep(0.3, 0.75, n))
			c = _tint(c, (_vnoise(x, y, 32, sd + 9) - 0.5) * grain)
			img.set_pixel(x, y, c)


## Gentle quantization: a painted, slightly posterized finish.
static func _posterize(img: Image, levels: float) -> void:
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			var q := Color(round(c.r * levels) / levels, round(c.g * levels) / levels, round(c.b * levels) / levels, c.a)
			img.set_pixel(x, y, c.lerp(q, 0.5))


## Region map from wrapped jittered Voronoi; returns [owner, d1, d2] per pixel.
static func _voronoi(rng: RandomNumberGenerator, count: int, squash := 1.0) -> Array:
	var pts := []
	for i in count:
		pts.append(Vector2(rng.randf() * S, rng.randf() * S))
	var owner := PackedInt32Array()
	var d1s := PackedFloat32Array()
	var d2s := PackedFloat32Array()
	owner.resize(S * S)
	d1s.resize(S * S)
	d2s.resize(S * S)
	for y in S:
		for x in S:
			var d1 := 1e9
			var d2 := 1e9
			var best := 0
			for i in pts.size():
				var dx: float = absf(x - pts[i].x)
				var dy: float = absf(y - pts[i].y)
				dx = minf(dx, S - dx)
				dy = minf(dy, S - dy) * squash
				var d := sqrt(dx * dx + dy * dy)
				if d < d1:
					d2 = d1
					d1 = d
					best = i
				elif d < d2:
					d2 = d
			owner[y * S + x] = best
			d1s[y * S + x] = d1
			d2s[y * S + x] = d2
	return [owner, d1s, d2s, pts]


## Painted stones: each region gets its own tone, a lit top-left rim, a shaded
## bottom-right rim and a dark gap between.
static func _stones(img: Image, rng: RandomNumberGenerator, base: Color, count: int, squash: float, gap: float, var_amt: float, gap_col: Color) -> void:
	var v := _voronoi(rng, count, squash)
	var owner: PackedInt32Array = v[0]
	var d1s: PackedFloat32Array = v[1]
	var d2s: PackedFloat32Array = v[2]
	var tones := []
	for i in count:
		var t := _tint(base, rng.randf_range(-var_amt, var_amt))
		t = Color(t.r * rng.randf_range(0.96, 1.04), t.g, t.b * rng.randf_range(0.96, 1.04))
		tones.append(t)
	var sd := rng.randi()
	for y in S:
		for x in S:
			var i := y * S + x
			var edge := d2s[i] - d1s[i]
			if edge < gap:
				img.set_pixel(x, y, gap_col)
				continue
			var tone: Color = tones[owner[i]]
			var n := _fbm(x, y, sd)
			var c := _tint(tone, (n - 0.5) * 0.1)
			# which way the nearest gap lies: light from up-left
			var up := 0.0
			var ny := (y - 1 + S) % S
			var nx := (x - 1 + S) % S
			if owner[ny * S + x] != owner[i] or d2s[ny * S + x] - d1s[ny * S + x] < gap:
				up += 1.0
			if owner[y * S + nx] != owner[i] or d2s[y * S + nx] - d1s[y * S + nx] < gap:
				up += 0.7
			var dn := 0.0
			var sy := (y + 1) % S
			var sx := (x + 1) % S
			if owner[sy * S + x] != owner[i] or d2s[sy * S + x] - d1s[sy * S + x] < gap:
				dn += 1.0
			if owner[y * S + sx] != owner[i] or d2s[y * S + sx] - d1s[y * S + sx] < gap:
				dn += 0.7
			if edge < gap + 2.5:
				c = _shade(c, 1.0 + up * 0.12 - dn * 0.22)
			# a little dome to each stone
			c = _shade(c, 1.06 - clampf(d1s[i] / 28.0, 0.0, 0.16))
			img.set_pixel(x, y, c)


# ---------------------------------------------------------------- stone

static func _fieldstone(img: Image, rng: RandomNumberGenerator, base: Color, var_amt: float) -> void:
	_stones(img, rng, base, 26, 1.7, 2.4, var_amt, Color("231f1b"))
	# lichen and moss patches
	var sd := rng.randi()
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			if c.r < 0.2:
				continue
			var m := _vnoise(x, y, 8, sd)
			if m > 0.72:
				img.set_pixel(x, y, c.lerp(Color("6f7a48"), (m - 0.72) * 1.6))
	_posterize(img, 24.0)


static func _blocks(img: Image, rng: RandomNumberGenerator, base: Color, rows: int, var_amt: float) -> void:
	var row_h := S / rows
	var sd := rng.randi()
	for r in rows:
		var y0 := r * row_h
		var starts := []
		var pos := rng.randi_range(0, 30)
		while pos < S + 40:
			starts.append(pos % S)
			pos += rng.randi_range(26, 44)
		var tones := {}
		for y in range(y0, y0 + row_h):
			for x in S:
				var bi := 0
				var dist_left := 999
				var dist_right := 999
				for k in starts.size():
					var sx: int = starts[k]
					var dl := posmod(x - sx, S)
					if dl < dist_left:
						dist_left = dl
						bi = k
				for k in starts.size():
					var dr := posmod(int(starts[k]) - x, S)
					if dr > 0 and dr < dist_right:
						dist_right = dr
				if not tones.has(bi):
					tones[bi] = _tint(base, rng.randf_range(-var_amt, var_amt))
				var c: Color = tones[bi]
				c = _tint(c, (_fbm(x, y, sd) - 0.5) * 0.1)
				var top := y - y0
				var bottom := y0 + row_h - 1 - y
				if top < 2 or dist_left < 2:
					c = Color("2a2622")
				elif top < 4 or dist_left < 4:
					c = _shade(c, 1.18)
				elif bottom < 3 or dist_right < 3:
					c = _shade(c, 0.78)
				img.set_pixel(x, y, c)
	_posterize(img, 24.0)


static func _rock(img: Image, rng: RandomNumberGenerator) -> void:
	_stones(img, rng, Color("5f5a52"), 10, 1.0, 1.2, 0.08, Color("2a2723"))
	var sd := rng.randi()
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			var n := _vnoise(x, y, 16, sd)
			img.set_pixel(x, y, _shade(c, 0.9 + n * 0.2))


static func _cobble(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	_stones(img, rng, base, 30, 1.0, 2.6, 0.12, Color("3a3428"))
	_posterize(img, 24.0)


## Flat stones set into a beaten earth path.
static func _path(img: Image, rng: RandomNumberGenerator, stones: bool) -> void:
	_soft(img, rng, Color("7a5e40"), Color("5e4630"), 0.08)
	var sd := rng.randi()
	# ruts and footprints of darker earth
	for y in S:
		for x in S:
			var n := _vnoise(x * 1.0, y * 3.0, 8, sd)
			if n > 0.68:
				img.set_pixel(x, y, _shade(img.get_pixel(x, y), 0.86))
	# scattered pebbles
	for i in 70:
		var px := rng.randi_range(0, S - 1)
		var py := rng.randi_range(0, S - 1)
		var c := Color("8c8274") if rng.randf() < 0.6 else Color("6c6458")
		img.set_pixel(px, py, c)
		img.set_pixel((px + 1) % S, py, _shade(c, 0.85))
	if not stones:
		_posterize(img, 24.0)
		return
	for i in 7:
		var cx := rng.randf_range(0, S)
		var cy := rng.randf_range(0, S)
		var rx := rng.randf_range(9, 15)
		var ry := rng.randf_range(7, 11)
		var tone := _tint(Color("8a847a"), rng.randf_range(-0.06, 0.06))
		for y in range(int(cy - ry) - 2, int(cy + ry) + 3):
			for x in range(int(cx - rx) - 2, int(cx + rx) + 3):
				var dx := (x - cx) / rx
				var dy := (y - cy) / ry
				var d := dx * dx + dy * dy
				var px := posmod(x, S)
				var py := posmod(y, S)
				if d <= 1.0:
					var c := _shade(tone, 1.1 - dy * 0.12 - d * 0.1)
					img.set_pixel(px, py, c)
				elif d <= 1.25 and dy > 0:
					img.set_pixel(px, py, _shade(img.get_pixel(px, py), 0.7))
	_posterize(img, 24.0)


# ---------------------------------------------------------------- walls

static func _daub(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	_soft(img, rng, base, _shade(base, 0.86), 0.05)
	var sd := rng.randi()
	# trowel marks: broad horizontal swipes
	for y in S:
		for x in S:
			var n := _vnoise(x * 0.5, y * 2.5, 8, sd)
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, _shade(c, 0.95 + n * 0.09))
	# a few cracks
	for i in 3:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		for k in rng.randi_range(14, 30):
			img.set_pixel(x, y, _shade(base, 0.62))
			img.set_pixel((x + 1) % S, y, _shade(base, 1.08))
			x = posmod(x + rng.randi_range(-1, 1), S)
			y = (y + 1) % S
	# damp, darker band near the bottom of the tile is applied by the shader
	_posterize(img, 28.0)


static func _wattle(img: Image, rng: RandomNumberGenerator) -> void:
	img.fill(Color("2c2014"))
	var rod_h := 8
	for row in S / rod_h:
		var y0 := row * rod_h
		var tone := _tint(Color("7c5c38"), rng.randf_range(-0.05, 0.05))
		for x in S:
			var over := ((x / 32) + row) % 2 == 0
			var bulge := sin(float(x % 32) / 32.0 * PI)
			for dy in rod_h - 1:
				var t := float(dy) / (rod_h - 2)
				var c := _shade(tone, (1.2 - t * 0.5) * (0.82 + 0.18 * (bulge if over else 1.0 - bulge)))
				img.set_pixel(x, y0 + dy, c)
	for x in [0, 32, 64, 96]:
		for y in S:
			for k in 4:
				img.set_pixel(x + k, y, _shade(Color("5a4026"), 1.15 - k * 0.12))
	_posterize(img, 24.0)


## Straw thatch in courses, strands running down the roof.
static func _thatch(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	var course := 32
	var sd := rng.randi()
	for x in S:
		var strand := _tint(base, rng.randf_range(-0.07, 0.07))
		var len_jit := rng.randi_range(0, 5)
		for y in S:
			var in_course := (y + len_jit) % course
			var t := float(in_course) / course
			var c := _shade(strand, 1.12 - t * 0.38)
			c = _tint(c, (_vnoise(x, y, 16, sd) - 0.5) * 0.08)
			if in_course > course - 4:
				c = _shade(c, 0.62)  # the shadowed lip of the course above
			img.set_pixel(x, y, c)
	for i in 120:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		for k in rng.randi_range(4, 10):
			img.set_pixel(x, (y + k) % S, _shade(base, 0.7))
	_posterize(img, 24.0)


static func _planks(img: Image, rng: RandomNumberGenerator, base: Color, ceiling: bool) -> void:
	var h := 16
	var sd := rng.randi()
	for r in S / h:
		var tone := _tint(base, rng.randf_range(-0.06, 0.06))
		var seam := rng.randi_range(0, S - 1)
		var phase := rng.randf() * TAU
		for y in range(r * h, r * h + h):
			for x in S:
				var gy := y - r * h
				var grain := sin(x * 0.18 + phase + sin(x * 0.05 + gy) * 1.5) * 0.035
				var c := _tint(tone, grain + (_vnoise(x, y, 16, sd) - 0.5) * 0.05)
				if gy < 1:
					c = _shade(base, 0.4)
				elif gy < 3:
					c = _shade(c, 1.15)
				elif gy > h - 3:
					c = _shade(c, 0.8)
				if absi(x - seam) < 1:
					c = _shade(base, 0.45)
				img.set_pixel(x, y, c)
		if not ceiling:
			for k in [seam - 5, seam + 5]:
				img.set_pixel(posmod(k, S), r * h + h / 2, Color("2a241e"))
	_posterize(img, 24.0)


static func _timber(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	var sd := rng.randi()
	for x in S:
		var tone := _tint(base, (_vnoise(x, 0, 8, sd) - 0.5) * 0.08)
		for y in S:
			var g := sin(y * 0.09 + x * 0.35 + sin(y * 0.02) * 2.0) * 0.03
			var c := _tint(tone, g + (_vnoise(x * 3.0, y * 0.3, 16, sd + 1) - 0.5) * 0.06)
			if x % 32 < 1:
				c = _shade(base, 0.5)
			elif x % 32 < 3:
				c = _shade(c, 1.12)
			img.set_pixel(x, y, c)
	for i in 3:  # knots
		var cx := rng.randi_range(4, S - 5)
		var cy := rng.randi_range(4, S - 5)
		for y in range(-3, 4):
			for x in range(-2, 3):
				if x * x + y * y / 2 <= 4:
					img.set_pixel(cx + x, cy + y, _shade(base, 0.6 + 0.1 * absf(x)))
	_posterize(img, 24.0)


## Timber post with a painted band of La Tène spirals.
static func _painted_post(img: Image, rng: RandomNumberGenerator) -> void:
	_timber(img, rng, Color("5c3e24"))
	for y in range(40, 88):
		for x in S:
			img.set_pixel(x, y, Color("7a2a1c") if y < 44 or y > 83 else Color("3a2a1c"))
	for k in 4:
		_spiral(img, 16 + k * 32, 64, 14.0, Color("d8b860"), 1.6)


static func _earth(img: Image, rng: RandomNumberGenerator) -> void:
	_soft(img, rng, Color("54402c"), Color("3e2e20"), 0.06)
	for i in 80:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		var c := Color("a08e54") if rng.randf() < 0.6 else Color("7c6e3c")
		var dx := 1 if rng.randf() < 0.5 else 0
		var dy := 1 - dx
		var n := rng.randi_range(6, 16)
		for k in n:
			var px := (x + dx * k + (k / 5) * dy) % S
			var py := (y + dy * k + (k / 5) * dx) % S
			img.set_pixel(px, py, c)
			img.set_pixel((px + dy) % S, (py + dx) % S, _shade(c, 0.6))
	_posterize(img, 24.0)


static func _grass(img: Image, rng: RandomNumberGenerator) -> void:
	_soft(img, rng, Color("56743a"), Color("3e5a2a"), 0.05)
	for i in 900:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		var c: Color = [Color("6e8e44"), Color("4a6a30"), Color("7e9c50"), Color("3a5424")][rng.randi_range(0, 3)]
		var lean := rng.randi_range(-1, 1)
		for k in rng.randi_range(2, 5):
			img.set_pixel(posmod(x + (lean * k) / 2, S), posmod(y - k, S), _shade(c, 1.0 + k * 0.04))
	for i in 14:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		img.set_pixel(x, y, Color("e8e0b0") if i % 3 else Color("c8a8d8"))
	_posterize(img, 28.0)


static func _hedge(img: Image, rng: RandomNumberGenerator) -> void:
	_soft(img, rng, Color("26381c"), Color("1a2814"), 0.04)
	for i in 160:
		var cx := rng.randi_range(0, S - 1)
		var cy := rng.randi_range(0, S - 1)
		var c: Color = [Color("4a6a2e"), Color("3a5826"), Color("5a7a36")][rng.randi_range(0, 2)]
		for y in range(-3, 4):
			for x in range(-3, 4):
				if x * x + y * y <= 9:
					img.set_pixel(posmod(cx + x, S), posmod(cy + y, S), _shade(c, 1.12 - (y + 3) * 0.05))
	_posterize(img, 24.0)


static func _water(img: Image, rng: RandomNumberGenerator) -> void:
	for y in S:
		for x in S:
			var w := sin((x + y * 0.5) * TAU / 64.0) * 0.5 + sin((x - y) * TAU / 32.0) * 0.5
			var c := Color("2a4c62").lerp(Color("3a6680"), 0.5 + w * 0.3)
			if w > 0.8:
				c = Color("7aa0b8")
			img.set_pixel(x, y, c)


static func _cloth(img: Image, rng: RandomNumberGenerator, base: Color) -> void:
	for y in S:
		for x in S:
			var weave := 0.04 if (x + y) % 2 == 0 else -0.03
			var c := _tint(base, weave + (_vnoise(x, y, 8, 77) - 0.5) * 0.08)
			img.set_pixel(x, y, c)


## A woven wall hanging: border, knotwork band, central triskele or spirals.
static func _hanging(img: Image, rng: RandomNumberGenerator, field: Color, ink: Color, variant: int) -> void:
	_cloth(img, rng, field)
	for y in S:
		for x in S:
			var e := mini(mini(x, y), mini(S - 1 - x, S - 1 - y))
			if e < 6:
				img.set_pixel(x, y, _shade(ink, 0.75))
			elif e < 8:
				img.set_pixel(x, y, _shade(field, 0.55))
	if variant == 0:
		_triskele(img, S / 2, S / 2, 40.0, ink)
	else:
		_spiral(img, S / 2 - 26, S / 2, 20.0, ink, 2.2)
		_spiral(img, S / 2 + 26, S / 2, 20.0, ink, 2.2)
		_triskele(img, S / 2, S / 2 - 34, 14.0, ink)
		_triskele(img, S / 2, S / 2 + 34, 14.0, ink)


## A horizontal band of interlace, for carved lintels.
static func _knot_band(img: Image, rng: RandomNumberGenerator) -> void:
	_timber(img, rng, Color("4a3220"))
	for x in S:
		for k in 2:
			var ph := k * PI
			var y := 64.0 + sin(x / float(S) * TAU * 4.0 + ph) * 22.0
			for t in range(-3, 4):
				var c := Color("c8a868") if absi(t) < 2 else Color("2a1c10")
				img.set_pixel(x, clampi(int(y) + t, 0, S - 1), c)
	for y in [30, 31, 96, 97]:
		for x in S:
			img.set_pixel(x, y, Color("2a1c10"))


## Upright split stakes of a palisade.
static func _palisade(img: Image, rng: RandomNumberGenerator) -> void:
	img.fill(Color("1e160e"))
	for s in 4:
		var x0 := s * 32 + 1
		var tone := _tint(Color("6a4a2c"), rng.randf_range(-0.06, 0.06))
		for x in range(x0, x0 + 30):
			var t := float(x - x0) / 30.0
			var round := sin(t * PI)
			for y in S:
				var c := _shade(tone, 0.7 + round * 0.45)
				c = _tint(c, (_vnoise(x * 3.0, y * 0.4, 16, s) - 0.5) * 0.08)
				img.set_pixel(x, y, c)
	_posterize(img, 24.0)


static func _pad(img: Image) -> void:
	for y in S:
		for x in S:
			var edge := mini(mini(x, y), mini(S - 1 - x, S - 1 - y))
			var c := Color("c9a65a") if edge < 8 else Color("5b4a2a")
			img.set_pixel(x, y, c)


# ---------------------------------------------------------------- La Tène motifs

static func _dot(img: Image, x: float, y: float, r: float, c: Color) -> void:
	for yy in range(int(y - r) - 1, int(y + r) + 2):
		for xx in range(int(x - r) - 1, int(x + r) + 2):
			if (xx - x) * (xx - x) + (yy - y) * (yy - y) <= r * r:
				img.set_pixel(posmod(xx, S), posmod(yy, S), c)


static func _spiral(img: Image, cx: float, cy: float, r: float, c: Color, w: float) -> void:
	var t := 0.0
	while t < 3.2 * TAU:
		var rr := r * t / (3.2 * TAU)
		_dot(img, cx + cos(t) * rr, cy + sin(t) * rr, w, c)
		t += 0.06


## Three spiral arms turning from a shared center.
static func _triskele(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for arm in 3:
		var a0 := arm * TAU / 3.0
		var t := 0.0
		while t < 1.0:
			var ang := a0 + t * 2.4
			var rr := r * (0.15 + t * 0.85)
			var px := cx + cos(ang) * rr * 0.55
			var py := cy + sin(ang) * rr * 0.55
			_dot(img, px, py, 1.4 + t * 2.2, c)
			t += 0.01
		var ex := cx + cos(a0 + 2.4) * r * 0.55
		var ey := cy + sin(a0 + 2.4) * r * 0.55
		_spiral(img, ex, ey, r * 0.32, c, 1.4)


# ---------------------------------------------------------------- small textures

## Soft round puff for smoke and steam.
static func puff() -> Texture2D:
	if _cache.has("puff"):
		return _cache["puff"]
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.8 + 0.2 * _vnoise(x * 4.0, y * 4.0, 8, 5))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_cache["puff"] = tex
	return tex


## A tuft of grass blades for the scattered ground cover.
static func tuft(variant: int) -> Texture2D:
	var key := "tuft%d" % variant
	if _cache.has(key):
		return _cache[key]
	var w := 24
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	for b in 11:
		var x := rng.randf_range(4, w - 4)
		var lean := rng.randf_range(-0.5, 0.5)
		var top := rng.randi_range(2, 12)
		var c: Color = [Color("5e7e3a"), Color("6e9044"), Color("4a6a2e"), Color("7ea050")][rng.randi_range(0, 3)]
		for y in range(top, h):
			var t := float(y - top) / (h - top)
			var px := int(x + lean * (h - y) * 0.6)
			if px >= 0 and px < w:
				img.set_pixel(px, y, _shade(c, 0.75 + (1.0 - t) * 0.4))
	if variant == 2:  # a few flower heads
		for i in 3:
			_dot_small(img, rng.randi_range(5, w - 5), rng.randi_range(3, 9), Color("e8d878") if i % 2 else Color("c8a0d8"))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _dot_small(img: Image, x: int, y: int, c: Color) -> void:
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var px: int = x + d.x
		var py: int = y + d.y
		if px < img.get_width() and py < img.get_height():
			img.set_pixel(px, py, c)
