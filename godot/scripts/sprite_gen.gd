## Pixel-art sprites built in code: people from an appearance description
## ("woman, 20s, red hair, yellow kirtle, carrying a tray"), plus trees and
## bushes. Hand-drawn art dropped into data/sprites/ replaces these.
class_name SpriteGen
extends RefCounted

const W := 32
const H := 64
static var _cache := {}

const COLORS := {
	"yellow": "d9b23a", "saffron": "e0a830", "gold": "d4a933", "golden": "d4a933",
	"green": "3f7a3a", "deep green": "275a2e", "dark green": "234a26", "light green": "7aa85a",
	"red": "a8352a", "crimson": "8e1e24", "scarlet": "b8281e", "russet": "8a4a2a",
	"blue": "34548c", "deep blue": "233e70", "light blue": "6b8fbf", "azure": "4a7ab8",
	"brown": "6a4a2c", "dark brown": "4a3220", "tan": "a8885c", "ochre": "b0853a",
	"black": "26221e", "white": "d8d2c4", "cream": "d6caa6", "grey": "7e7a74", "gray": "7e7a74",
	"silver": "a8aab0", "purple": "5e3870", "violet": "6e4a8a", "orange": "c8702a",
	"pink": "c88a8a", "undyed": "a8987a", "plain": "8a7c62", "rough": "7a6a52",
}
const HAIR := {
	"red": "b0442a", "auburn": "8a3b22", "copper": "b85a2a", "ginger": "c0602a",
	"blonde": "d8bc6a", "blond": "d8bc6a", "fair": "d8bc6a", "golden": "c8a040", "yellow": "d4b04a",
	"brown": "5b3a22", "chestnut": "6e3a1e", "dark": "2a1e16", "black": "1c1612",
	"grey": "9a958c", "gray": "9a958c", "white": "dcd8d0", "silver": "b8b8bc",
}
const SKIN := {
	"fair": "edc7a4", "pale": "f0d2b8", "ruddy": "dfa888", "olive": "c49a6c",
	"tan": "c08a5a", "brown": "9a6440", "dark": "6e4428",
}


static func _c(hex_or_name: String, table: Dictionary, fallback: String) -> Color:
	var k := hex_or_name.strip_edges().to_lower()
	if table.has(k):
		return Color(table[k])
	if k.is_valid_html_color():
		return Color(k)
	for name in table:  # "deep green girdle" -> deep green
		if k.contains(name):
			return Color(table[name])
	return Color(fallback)


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), mini(x1, img.get_width())):
			img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


## A person from an appearance dictionary. Keys (all optional):
## sex, age, build, skin, hair, hair_color, beard, garment, garment_color,
## legs_color, belt_color, cloak_color, shoes_color, held, accessory, seed
static func person(a: Dictionary) -> Texture2D:
	var key := "p|" + JSON.stringify(a)
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(a.get("seed", key)))

	var sex := str(a.get("sex", "")).to_lower()
	var female := sex.begins_with("f") or sex == "woman"
	var age := str(a.get("age", "")).to_lower()
	var old := age.contains("old") or age.contains("elder") or age.begins_with("6") or age.begins_with("7") or age.begins_with("8")
	var skin := _c(str(a.get("skin", "")), SKIN, ["edc7a4", "dfa888", "c49a6c", "9a6440"][rng.randi_range(0, 3)])
	var hair_c := _c(str(a.get("hair_color", "grey" if old else "")), HAIR,
		["5b3a22", "2a1e16", "8a3b22", "c8a040"][rng.randi_range(0, 3)])
	var hair := str(a.get("hair", "long" if female else "short")).to_lower()
	var garment := str(a.get("garment", "dress" if female else "tunic")).to_lower()
	var cloth := _c(str(a.get("garment_color", "")), COLORS,
		["8a7c62", "6a4a2c", "3f7a3a", "34548c", "a8352a"][rng.randi_range(0, 4)])
	var legs := _c(str(a.get("legs_color", "")), COLORS, "5a4a36")
	var belt := _c(str(a.get("belt_color", "")), COLORS, "3a2a1a")
	var shoes := _c(str(a.get("shoes_color", "")), COLORS, "4a3220")
	var held := str(a.get("held", "")).to_lower()
	var acc := str(a.get("accessory", "")).to_lower()
	var stout := str(a.get("build", "")).to_lower().contains("stout")
	var cx := 16
	var sh := 5 if female else 6  # half shoulder width
	if stout:
		sh += 1

	# cloak behind everything
	if a.has("cloak_color"):
		var cloak := _c(str(a["cloak_color"]), COLORS, "4a5a3a")
		_rect(img, cx - sh - 2, 18, cx + sh + 2, 50, _shade(cloak, 0.8))

	# legs and shoes
	var skirt := garment in ["dress", "kirtle", "gown", "robe", "habit", "shift", "lein"]
	if not skirt:
		_rect(img, cx - 4, 37, cx - 1, 59, legs)
		_rect(img, cx + 1, 37, cx + 4, 59, _shade(legs, 0.9))
	_rect(img, cx - 5, 59, cx - 1, 62, shoes)
	_rect(img, cx + 1, 59, cx + 5, 62, shoes)

	# body garment
	if skirt:
		for y in range(32, 59):  # flared skirt to the ankles
			var t := float(y - 32) / 26.0
			var half := int(lerpf(sh - 1, sh + 4, t))
			_rect(img, cx - half, y, cx + half, y + 1, cloth if (y % 7 != 0 or garment == "robe") else _shade(cloth, 0.9))
	elif garment == "armor":
		_rect(img, cx - sh, 30, cx + sh, 41, _c("silver", COLORS, "a8aab0"))
	else:
		_rect(img, cx - sh, 30, cx + sh, 41, cloth)  # tunic skirt to mid-thigh
	var top := _c("grey", COLORS, "7e7a74") if garment == "armor" else cloth
	_rect(img, cx - sh, 18, cx + sh, 33, top)
	if female:
		_rect(img, cx - sh + 1, 23, cx + sh - 1, 25, _shade(top, 0.92))
	if garment == "armor":  # mail rings
		for y in range(19, 41, 2):
			for x in range(cx - sh, cx + sh, 2):
				img.set_pixel(x + (y / 2) % 2, y, _shade(top, 0.75))
	_rect(img, cx - sh, 31, cx + sh, 33, belt)  # belt / girdle
	img.set_pixel(cx, 31, _shade(belt, 1.4))

	# arms (sleeves) and hands; the right arm (viewer's left) holds things
	var carries_front := held.contains("tray") or held.contains("basket") or held.contains("harp")
	_rect(img, cx - sh - 3, 19, cx - sh, 31, _shade(top, 0.85))
	_rect(img, cx - sh - 3, 31, cx - sh, 33, skin)
	if carries_front:
		_rect(img, cx + sh, 19, cx + sh + 3, 27, _shade(top, 0.85))
		_rect(img, cx + sh, 27, cx + sh + 7, 30, _shade(top, 0.85))  # forearm out
		_rect(img, cx + sh + 6, 26, cx + sh + 8, 29, skin)
	else:
		_rect(img, cx + sh, 19, cx + sh + 3, 31, _shade(top, 0.85))
		_rect(img, cx + sh, 31, cx + sh + 3, 33, skin)

	# neck and head
	_rect(img, cx - 2, 15, cx + 2, 19, _shade(skin, 0.9))
	_ellipse(img, cx, 10.5, 4.6, 5.6, skin)
	img.set_pixel(cx - 2, 10, Color("1a1410"))
	img.set_pixel(cx + 1, 10, Color("1a1410"))
	img.set_pixel(cx, 13, _shade(skin, 0.75))

	# hair
	if hair != "bald":
		_ellipse(img, cx, 7.5, 5.0, 3.6, hair_c)
		_rect(img, cx - 5, 6, cx - 3, 12, hair_c)
		_rect(img, cx + 3, 6, cx + 5, 12, hair_c)
		if hair.contains("long") or hair.contains("braid"):
			_rect(img, cx - 6, 8, cx - 3, 26 if hair.contains("long") else 30, hair_c)
			_rect(img, cx + 3, 8, cx + 6, 26 if hair.contains("long") else 30, _shade(hair_c, 0.9))
		elif hair.contains("bun"):
			_ellipse(img, cx, 4.0, 2.6, 2.2, _shade(hair_c, 0.9))
	if bool(a.get("beard", false)) or (not female and old and rng.randf() < 0.7):
		_rect(img, cx - 4, 12, cx + 4, 17, hair_c)
		_rect(img, cx - 2, 17, cx + 2, 20, hair_c)
		img.set_pixel(cx, 13, _shade(hair_c, 0.6))

	# accessories
	if acc.contains("hair") and (acc.contains("gold") or acc.contains("ball")):
		img.set_pixel(cx - 5, 6, Color("f2cf4a"))
		img.set_pixel(cx + 4, 6, Color("f2cf4a"))
		img.set_pixel(cx - 5, 7, Color("c49a2a"))
		img.set_pixel(cx + 4, 7, Color("c49a2a"))
	if acc.contains("torc"):
		_rect(img, cx - 3, 17, cx + 3, 18, Color("e0b840"))
	if acc.contains("circlet") or acc.contains("crown"):
		_rect(img, cx - 4, 6, cx + 4, 7, Color("e0b840"))
	if acc.contains("hood"):
		_ellipse(img, cx, 8.5, 5.6, 5.0, _shade(cloth, 0.8))
		_ellipse(img, cx, 11, 3.8, 4.4, skin)

	# what they carry
	if held.contains("tray"):
		# a wooden tray held out in front, with cups on it
		_rect(img, cx - 3, 26, cx + 11, 28, Color("8a6a40"))
		_rect(img, cx - 3, 28, cx + 11, 29, Color("5e4428"))
		for k in [-1, 3, 7]:
			_rect(img, cx + k, 21, cx + k + 3, 26, Color("b8a07a") if k != 3 else Color("7a5a3a"))
			_rect(img, cx + k, 21, cx + k + 3, 22, Color("e8d8b0"))
	elif held.contains("basket"):
		_rect(img, cx + sh + 3, 26, cx + sh + 10, 31, Color("9a7a44"))
		_rect(img, cx + sh + 4, 23, cx + sh + 5, 26, Color("7a5a30"))
		_rect(img, cx + sh + 8, 23, cx + sh + 9, 26, Color("7a5a30"))
	elif held.contains("harp"):
		_rect(img, cx + sh + 2, 18, cx + sh + 4, 32, Color("8a5a2a"))
		_rect(img, cx + sh + 2, 18, cx + sh + 9, 20, Color("8a5a2a"))
		for k in range(4, 9, 2):
			_rect(img, cx + sh + k, 20, cx + sh + k + 1, 31 - k, Color("d8c890"))
	elif held.contains("sword"):
		_rect(img, cx + sh + 1, 33, cx + sh + 2, 52, Color("c8ccd0"))
		_rect(img, cx + sh - 1, 32, cx + sh + 4, 33, Color("8a6a2a"))
	elif held.contains("spear"):
		_rect(img, cx + sh + 1, 2, cx + sh + 2, 62, Color("7a5a30"))
		_rect(img, cx + sh, 0, cx + sh + 3, 4, Color("b8bcc0"))
	elif held.contains("staff"):
		_rect(img, cx + sh + 1, 6, cx + sh + 3, 62, Color("6a4a26"))
	elif held.contains("mug") or held.contains("cup") or held.contains("tankard"):
		_rect(img, cx + sh, 29, cx + sh + 4, 34, Color("8a6a40"))
	elif held.contains("torch"):
		_rect(img, cx + sh + 1, 18, cx + sh + 2, 33, Color("5a3a1e"))
		_ellipse(img, cx + sh + 1.5, 16, 2.0, 3.0, Color("ffb04a"))
	if held.contains("shield") or acc.contains("shield"):
		_ellipse(img, cx - sh - 2, 28, 4.5, 6.5, _shade(cloth, 0.75))
		img.set_pixel(cx - sh - 2, 28, Color("c8a040"))

	_light_and_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Light from the upper left; dark outline around the silhouette.
static func _light_and_outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			var c: Color = src.get_pixel(x, y)
			if c.a > 0.5:
				# darken the far side of each shape a little
				var right_edge: bool = x + 1 >= w or src.get_pixel(x + 1, y).a < 0.5 \
					or (x + 2 < w and src.get_pixel(x + 2, y).a < 0.5)
				if right_edge:
					img.set_pixel(x, y, _shade(c, 0.78))
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, Color("120e0b"))
					break


static func tree(seed_value: int) -> Texture2D:
	var key := "tree|%d" % (seed_value % 6)
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value % 6
	var img := Image.create_empty(48, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 21, 50, 27, 96, Color("4a3524"))
	_rect(img, 25, 50, 27, 96, Color("3a2818"))
	var greens := [Color("2f4a22"), Color("3d5c2a"), Color("4c6e30"), Color("27401c")]
	for i in 26:
		var cx := rng.randf_range(10, 38)
		var cy := rng.randf_range(8, 60)
		var r := rng.randf_range(5, 10)
		_ellipse(img, cx, cy, r, r * 0.85, greens[rng.randi_range(0, 3)])
	for i in 60:
		var x := rng.randi_range(4, 44)
		var y := rng.randi_range(4, 62)
		if img.get_pixel(x, y).a > 0.5:
			img.set_pixel(x, y, Color("5e8040") if x < 24 else Color("1f3418"))
	_light_and_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func bush(seed_value: int) -> Texture2D:
	var key := "bush|%d" % (seed_value % 4)
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value % 4 + 99
	var img := Image.create_empty(32, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 12:
		_ellipse(img, rng.randf_range(7, 25), rng.randf_range(9, 18), rng.randf_range(4, 7), rng.randf_range(3, 6),
			[Color("34502a"), Color("43642e"), Color("2a4220")][rng.randi_range(0, 2)])
	_light_and_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Two side-by-side frames of a crackling fire, for hearths and torches.
static func flame() -> Texture2D:
	if _cache.has("flame"):
		return _cache["flame"]
	var img := Image.create_empty(32, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for frame in 2:
		var ox := frame * 16
		for tongue in 5:
			var cx := ox + 3.0 + tongue * 2.5 + rng.randf_range(-0.6, 0.6)
			var top := rng.randf_range(2, 10)
			for y in range(int(top), 24):
				var t := (y - top) / (24.0 - top)
				var half := lerpf(0.4, 2.6, sqrt(t))
				for x in range(int(cx - half), int(cx + half) + 1):
					if x < ox or x >= ox + 16:
						continue
					var core := absf(x - cx) < half * 0.45 and t > 0.35
					var c := Color("ffe9a0") if core else (Color("ffb347") if t > 0.25 else Color("ff7a24"))
					img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache["flame"] = tex
	return tex


# ---------------------------------------------------------------------------
# Animals, seen side-on (Daggerfall-style). Heights are real-world meters.
# ---------------------------------------------------------------------------

const ANIMALS := {
	# h: sprite height (m); body: length, depth; leg; head; plus features
	"pig":    {"h": 0.75, "len": 26, "depth": 13, "leg": 5, "neck": 0, "head": 8, "snout": 4, "ears": "flop", "tail": "curl", "color": "d9a39a", "belly": "e8b8ae"},
	"boar":   {"h": 0.9,  "len": 26, "depth": 14, "leg": 6, "neck": 0, "head": 9, "snout": 5, "ears": "up", "tail": "short", "color": "4a3a2c", "belly": "5c4a38", "bristle": true, "tusks": true},
	"hound":  {"h": 0.8,  "len": 22, "depth": 9, "leg": 11, "neck": 5, "head": 7, "snout": 5, "ears": "flop", "tail": "long", "color": "8a8478", "belly": "a29c90"},
	"wolf":   {"h": 0.85, "len": 23, "depth": 10, "leg": 11, "neck": 5, "head": 7, "snout": 5, "ears": "up", "tail": "bushy", "color": "6e6a64", "belly": "a8a49c"},
	"fox":    {"h": 0.42, "len": 20, "depth": 8, "leg": 8, "neck": 4, "head": 6, "snout": 5, "ears": "up", "tail": "bushy", "color": "b8602a", "belly": "e8d8c0"},
	"horse":  {"h": 1.9,  "len": 30, "depth": 13, "leg": 18, "neck": 12, "head": 9, "snout": 6, "ears": "up", "tail": "hair", "color": "7a4a2a", "belly": "6a3e22", "mane": true},
	"pony":   {"h": 1.35, "len": 28, "depth": 14, "leg": 14, "neck": 10, "head": 9, "snout": 5, "ears": "up", "tail": "hair", "color": "8a6a44", "belly": "7a5c3a", "mane": true},
	"cow":    {"h": 1.45, "len": 32, "depth": 16, "leg": 13, "neck": 3, "head": 9, "snout": 4, "ears": "side", "tail": "tuft", "color": "6a4028", "belly": "d8ccb8", "horns": "small", "udder": true},
	"bull":   {"h": 1.6,  "len": 32, "depth": 18, "leg": 13, "neck": 3, "head": 10, "snout": 4, "ears": "side", "tail": "tuft", "color": "3a2a20", "belly": "3a2a20", "horns": "big"},
	"sheep":  {"h": 0.85, "len": 22, "depth": 13, "leg": 8, "neck": 2, "head": 6, "snout": 3, "ears": "side", "tail": "short", "color": "d8d0bc", "belly": "c8c0aa", "face": "3a3028", "fluffy": true},
	"goat":   {"h": 0.85, "len": 21, "depth": 10, "leg": 10, "neck": 5, "head": 6, "snout": 3, "ears": "side", "tail": "short", "color": "8a7660", "belly": "c8b8a0", "horns": "swept", "beard": true},
	"cat":    {"h": 0.32, "len": 16, "depth": 7, "leg": 6, "neck": 2, "head": 6, "snout": 1, "ears": "up", "tail": "long", "color": "7a7670", "belly": "a8a49c"},
	"rat":    {"h": 0.2,  "len": 14, "depth": 6, "leg": 3, "neck": 0, "head": 5, "snout": 3, "ears": "round", "tail": "thin", "color": "6a5e52", "belly": "8a7e70"},
	"badger": {"h": 0.4,  "len": 20, "depth": 9, "leg": 4, "neck": 0, "head": 6, "snout": 4, "ears": "round", "tail": "short", "color": "5a5a58", "belly": "2a2a28", "stripe": true},
	"bear":   {"h": 1.4,  "len": 30, "depth": 18, "leg": 10, "neck": 2, "head": 10, "snout": 4, "ears": "round", "tail": "short", "color": "4a3626", "belly": "3e2c1e"},
	"deer":   {"h": 1.35, "len": 24, "depth": 11, "leg": 15, "neck": 9, "head": 7, "snout": 4, "ears": "up", "tail": "short", "color": "9a6a3e", "belly": "d8c4a4"},
	"stag":   {"h": 1.9,  "len": 26, "depth": 12, "leg": 16, "neck": 10, "head": 8, "snout": 4, "ears": "up", "tail": "short", "color": "8a5a32", "belly": "c8b090", "antlers": true},
}
const BIRDS := {
	"hen":   {"h": 0.45, "size": 10, "color": "9a5a2a", "comb": true, "neck": 3},
	"goose": {"h": 0.7,  "size": 12, "color": "e8e4dc", "neck": 8, "beak": "f0a030"},
	"bird":  {"h": 0.3,  "size": 8,  "color": "222020", "neck": 1},
}


static func animal_height(body: String) -> float:
	if ANIMALS.has(body):
		return float(ANIMALS[body]["h"])
	if BIRDS.has(body):
		return float(BIRDS[body]["h"])
	return 0.8


static func animal(body: String, color_name := "", seed_value := 0) -> Texture2D:
	var key := "a|%s|%s|%d" % [body, color_name, seed_value % 3]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D
	if BIRDS.has(body):
		tex = _bird(BIRDS[body], color_name)
	else:
		tex = _quadruped(ANIMALS.get(body, ANIMALS["hound"]), color_name, seed_value)
	_cache[key] = tex
	return tex


static func _quadruped(a: Dictionary, color_name: String, seed_value: int) -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var col := Color(a["color"])
	if color_name != "":
		col = _c(color_name, COLORS, a["color"])
	var belly := Color(a["belly"]) if color_name == "" else _shade(col, 1.15)
	var L: int = a["len"]
	var D: int = a["depth"]
	var leg: int = a["leg"]
	var neck: int = a["neck"]
	var head: int = a["head"]
	var snout: int = a["snout"]
	var extra_top := 10 if a.has("antlers") else (4 if a.has("horns") else 2)
	var W := L + head + snout + 18
	var H := extra_top + neck + D + leg + 2
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body_top := extra_top + neck
	var body_bot := body_top + D
	var bx0 := 10
	var bx1 := bx0 + L
	var dark := _shade(col, 0.7)
	# far legs (darker), then near legs
	for x in [bx0 + 3, bx1 - 6]:
		_rect(img, x + 1, body_bot - 2, x + 3, body_bot + leg, _shade(dark, 0.85))
	for x in [bx0 + 1, bx1 - 4]:
		_rect(img, x, body_bot - 2, x + 3, body_bot + leg, dark)
		_rect(img, x, body_bot + leg - 1, x + 3, body_bot + leg, Color("2a2018"))
	# tail
	match str(a["tail"]):
		"curl":
			_rect(img, bx0 - 2, body_top + 2, bx0, body_top + 4, col)
			img.set_pixel(bx0 - 3, body_top + 1, col)
		"long":
			for i in 6:
				img.set_pixel(bx0 - 1 - i / 2, body_top + 1 + i, col)
		"bushy":
			_ellipse(img, bx0 - 2, body_top + D * 0.6, 3.0, D * 0.45, col)
			_rect(img, bx0 - 4, int(body_top + D * 0.9), bx0 - 1, int(body_top + D * 0.9) + 2, Color("e8e0d0"))
		"hair":
			_rect(img, bx0 - 3, body_top + 1, bx0, body_top + D + 6, _shade(col, 0.55))
		"tuft":
			_rect(img, bx0 - 1, body_top + 1, bx0, body_top + D + 3, dark)
			_rect(img, bx0 - 2, body_top + D + 2, bx0 + 1, body_top + D + 5, _shade(col, 0.5))
		"thin":
			for i in 8:
				img.set_pixel(bx0 - 1 - i, body_top + D - 2 + (i % 3) / 2, Color("b89080"))
		_:
			_rect(img, bx0 - 2, body_top + 1, bx0, body_top + 3, col)
	# body
	_ellipse(img, bx0 + L / 2.0, body_top + D / 2.0, L / 2.0, D / 2.0, col)
	_ellipse(img, bx0 + L / 2.0, body_top + D * 0.75, L / 2.4, D / 4.0, belly)
	if a.get("fluffy", false):
		for i in 40:
			var px := rng.randi_range(bx0 + 1, bx1 - 1)
			var py := rng.randi_range(body_top, body_bot - 1)
			if img.get_pixel(px, py).a > 0.5:
				img.set_pixel(px, py, _shade(col, 0.9 if i % 2 == 0 else 1.08))
	if a.get("udder", false):
		_rect(img, bx0 + L / 2 + 2, body_bot - 1, bx0 + L / 2 + 6, body_bot + 2, Color("e0a8a0"))
	if a.get("bristle", false):
		for x in range(bx0 + 4, bx1 - 2, 2):
			img.set_pixel(x, body_top - 1, _shade(col, 0.6))
	if color_name == "" and str(a["color"]) == "6a4028" and rng.randf() < 0.6:  # piebald cattle
		for i in 3:
			_ellipse(img, rng.randf_range(bx0 + 5, bx1 - 5), rng.randf_range(body_top + 2, body_bot - 3), rng.randf_range(2, 4), rng.randf_range(2, 3), Color("e0d8c8"))
	# neck and head (facing right)
	var hx := bx1 - 2
	var hy := body_top - neck + 1
	if neck > 0:
		for i in neck + 2:
			_rect(img, hx - 3 + i / 3, hy + i, hx + 3 + i / 3, hy + i + 1, col)
		if a.get("mane", false):
			for i in neck + 3:
				_rect(img, hx - 4 + i / 3, hy + i - 1, hx - 2 + i / 3, hy + i, _shade(col, 0.45))
	var head_c := Color(a["face"]) if a.has("face") else col
	var hcx := hx + 3 + neck / 3.0
	var hcy := float(hy) + head / 2.0 - (1.0 if neck > 0 else -1.0)
	_ellipse(img, hcx, hcy, head / 2.0, head / 2.2, head_c)
	_rect(img, int(hcx + head / 2.0) - 1, int(hcy), int(hcx + head / 2.0) + snout, int(hcy + head / 2.6), _shade(head_c, 0.95))
	img.set_pixel(int(hcx + head / 2.0) + snout - 1, int(hcy), Color("1a1410"))
	img.set_pixel(int(hcx + 1), int(hcy - 1), Color("120c08"))
	if a.get("tusks", false):
		img.set_pixel(int(hcx + head / 2.0) + snout - 2, int(hcy + head / 2.6), Color("f0e8d0"))
	if a.get("beard", false):
		_rect(img, int(hcx + head / 2.0) + 1, int(hcy + head / 2.6), int(hcx + head / 2.0) + 3, int(hcy + head / 2.6) + 3, _shade(col, 0.8))
	if a.get("stripe", false):
		_rect(img, int(hcx - head / 2.0), int(hcy - 1), int(hcx + head / 2.0) + snout, int(hcy + 1), Color("e8e8e0"))
	match str(a["ears"]):
		"up":
			_rect(img, int(hcx - 2), int(hcy - head / 2.0) - 3, int(hcx), int(hcy - head / 2.0) + 1, _shade(head_c, 0.85))
		"flop":
			_rect(img, int(hcx - 3), int(hcy - 2), int(hcx - 1), int(hcy + 3), _shade(head_c, 0.75))
		"side":
			_rect(img, int(hcx - 4), int(hcy - 2), int(hcx - 1), int(hcy - 1), _shade(head_c, 0.85))
		"round":
			_ellipse(img, hcx - 1.5, hcy - head / 2.0, 1.6, 1.4, _shade(head_c, 0.85))
	match str(a.get("horns", "")):
		"small":
			_rect(img, int(hcx - 1), int(hcy - head / 2.0) - 2, int(hcx + 1), int(hcy - head / 2.0), Color("d8ccb0"))
		"big":
			for i in 4:
				img.set_pixel(int(hcx - 2) - i, int(hcy - head / 2.0) - i / 2, Color("d8ccb0"))
				img.set_pixel(int(hcx + 1) + i, int(hcy - head / 2.0) - i / 2, Color("d8ccb0"))
		"swept":
			for i in 5:
				img.set_pixel(int(hcx - 1) - i, int(hcy - head / 2.0) - 2 + i / 3, Color("6a5a48"))
	if a.has("antlers"):
		var ax := int(hcx - 1)
		var ay := int(hcy - head / 2.0)
		for i in 9:
			img.set_pixel(ax - i / 3, ay - i, Color("c8b48a"))
			img.set_pixel(ax + 2 + i / 3, ay - i, Color("c8b48a"))
			if i % 3 == 2:
				img.set_pixel(ax - i / 3 - 1, ay - i, Color("c8b48a"))
				img.set_pixel(ax + 3 + i / 3, ay - i, Color("c8b48a"))
	_light_and_outline(img)
	return ImageTexture.create_from_image(img)


static func _bird(b: Dictionary, color_name: String) -> Texture2D:
	var col := Color(b["color"]) if color_name == "" else _c(color_name, COLORS, b["color"])
	var s: int = b["size"]
	var neck: int = b["neck"]
	var W := s * 2 + 8
	var H := s + neck + 8
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := neck + 4 + s / 2.0
	_rect(img, W / 2 - 1, int(cy + s / 2.0) - 1, W / 2, H - 1, Color("c89030"))
	_rect(img, W / 2 + 2, int(cy + s / 2.0) - 1, W / 2 + 3, H - 1, Color("c89030"))
	_ellipse(img, W / 2.0 - 1, cy, s / 1.6, s / 2.2, col)
	_rect(img, 1, int(cy - 2), 5, int(cy + 1), _shade(col, 0.8))  # tail
	var hx := W / 2.0 + s / 2.2
	for i in neck:
		_rect(img, int(hx) - 1, int(cy) - i - 1, int(hx) + 2, int(cy) - i, col)
	var hy := cy - neck - 1
	_ellipse(img, hx + 1, hy, 2.6, 2.4, col)
	_rect(img, int(hx) + 3, int(hy), int(hx) + 6, int(hy) + 1, Color(str(b.get("beak", "d8a030"))))
	img.set_pixel(int(hx) + 1, int(hy) - 1, Color("101010"))
	if b.get("comb", false):
		_rect(img, int(hx), int(hy) - 4, int(hx) + 3, int(hy) - 2, Color("c02020"))
	_light_and_outline(img)
	return ImageTexture.create_from_image(img)
