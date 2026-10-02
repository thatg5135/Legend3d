## Furnishes a room from its description.
##
## plan() reads the description sentence by sentence: what's there ("a large
## loom"), where ("the entire west side", "into one corner"), how many ("a few
## bales", "balls of yarn litter the floor"), and what's next to what ("a
## rocking chair next to a table beside the hearth"). Then it adds period
## clutter that fits the room without contradicting it. The result is a list
## of plain items (type, position, rotation, options) that gets saved with the
## map, so a room is furnished once and looks the same every visit.
##
## build() turns a list of items into meshes and lights.
class_name Props
extends RefCounted

var w: World
var pack: Dictionary
var shape: Dictionary        # {"kind": "round"|"rect"|"open", center, r | hx,hz}
var outdoor := false
var tier := "house"            # hut | house | hall | great | open
var entrance := Vector2(0, 1)  # direction (x,z) of the main way in
var exits := {}
var lanes: Array = []          # [[Vector3 a, Vector3 b]] walking routes to keep clear
var taken: Array = []          # [[Vector3 pos, float radius]]
var rng := RandomNumberGenerator.new()
var unknown_words: Array = []  # furnishing-ish words we didn't recognize (for tuning)

const DIR2 := {
	"north": Vector2(0, -1), "south": Vector2(0, 1),
	"east": Vector2(1, 0), "west": Vector2(-1, 0),
}

## [type, regex]. Longer, more specific phrases first.
const VOCAB := [
	["rocking_chair", "\\brocking[- ]chairs?\\b"],
	["hearth", "\\b(hearth|fireplace|fire ?pit|firepit|open fire|roaring fire|central fire|cooking fire|hearthstone)\\b"],
	["loom", "\\blooms?\\b"],
	["yarn", "\\b(balls? of yarn|yarn|skeins?|threads?)\\b"],
	["wool", "\\b(bales? of [a-z ]*wool|wool|fleeces?)\\b"],
	["spindle", "\\b(spindles?|distaffs?|spinning wheels?)\\b"],
	["table", "\\b(tables?|trestles?)\\b"],
	["bench", "\\bbench(es)?\\b"],
	["chair", "\\b(chairs?|stools?|seats?)\\b"],
	["bed", "\\b(beds?|cots?|pallets?|bunks?|sleeping (furs|area|platforms?))\\b"],
	["quern", "\\b(querns?|grindstones?|millstones?)\\b"],
	["jar", "\\b(jars?|pots?|amphora[es]?|urns?|crocks?|jugs?|pitchers?|bowls?)\\b"],
	["basket", "\\bbaskets?\\b"],
	["forge", "\\b(forge|furnace|smelter|bellows)\\b"],
	["anvil", "\\banvils?\\b"],
	["counter", "\\b(bar|counter)\\b"],
	["barrel", "\\b(barrels?|casks?|kegs?|vats?|tuns?|hogsheads?)\\b"],
	["crate", "\\bcrates?\\b"],
	["sack", "\\b(sacks?|bags of (grain|flour|meal))\\b"],
	["shelf", "\\b(shelf|shelves|racks?)\\b"],
	["chest", "\\b(chests?|trunks?|coffers?|strongbox(es)?)\\b"],
	["lantern", "\\b(lanterns?|lamps?)\\b"],
	["torch", "\\b(torch|torches|sconces?|brands?)\\b"],
	["candle", "\\bcandles?\\b"],
	["tapestry", "\\b(tapestr(y|ies)|banners?|hangings?)\\b"],
	["fur", "\\b(rugs?|carpets?|furs?|hides?|pelts?|skins?)\\b"],
	["cauldron", "\\b(cauldrons?|kettles?)\\b"],
	["firewood", "\\b(firewood|woodpiles?|logs? (stacked|piled)|kindling|stacked wood)\\b"],
	["hay", "\\b(hay|straw|haystacks?|bales? of (hay|straw))\\b"],
	["herbs", "\\b(herbs|bundles? of (herbs|flowers)|drying (herbs|plants))\\b"],
	["trough", "\\btroughs?\\b"],
	["well", "\\b(a|the|stone|old|deep) well\\b|\\bwell (stands|sits)\\b"],
	["fountain", "\\bfountains?\\b"],
	["tree", "\\b(trees?|oaks?|ash trees?|yews?|willows?|elms?|birch(es)?|alders?|hazels?|rowans?|hawthorns?)\\b"],
	["bush", "\\b(bush(es)?|shrubs?|bracken|brambles?|gorse|heather|ferns?)\\b"],
	["stone", "\\b(boulders?|standing stones?|menhirs?|monoliths?)\\b"],
	["statue", "\\bstatues?\\b"],
	["altar", "\\baltars?\\b"],
	["cart", "\\b(carts?|wagons?|chariots?)\\b"],
	["stall", "\\b(stalls?|booths?|tents?)\\b"],
	["door", "\\b(swinging door|doors?|doorways?|gates?)\\b"],
]

const FOOT := {
	"hearth": 1.5, "loom": 1.2, "yarn": 0.12, "wool": 0.6, "spindle": 0.25, "table": 1.0,
	"bench": 0.9, "chair": 0.45, "rocking_chair": 0.55, "bed": 1.0, "quern": 0.45, "jar": 0.3,
	"basket": 0.3, "forge": 1.1, "anvil": 0.5, "counter": 1.8, "barrel": 0.45, "crate": 0.45,
	"sack": 0.35, "shelf": 0.9, "chest": 0.7, "lantern": 0.0, "torch": 0.3, "candle": 0.1,
	"tapestry": 0.2, "fur": 0.4, "cauldron": 0.5, "firewood": 0.7, "hay": 0.9, "herbs": 0.2,
	"trough": 0.9, "well": 1.4, "fountain": 1.6, "tree": 1.2, "bush": 0.7, "stone": 0.6,
	"statue": 1.0, "altar": 1.0, "cart": 1.5, "stall": 1.5, "door": 0.8, "hurdle": 0.9,
	"log": 0.8, "mushrooms": 0.2, "board": 0.8, "mailbox": 0.4, "object": 0.6, "hanging": 0.2,
}
const WALL_TYPES := ["loom", "bed", "shelf", "counter", "chest", "tapestry", "hanging", "door", "torch",
	"board", "mailbox", "altar", "herbs", "firewood", "object"]
const CORNER_TYPES := ["wool", "hay", "barrel", "crate", "sack", "jar"]
const CENTER_TYPES := ["well", "fountain", "statue"]
const SCATTER_TYPES := ["yarn", "mushrooms"]

## what a room of each kind would plausibly have lying about (never people,
## animals or light sources; never something the description already covers)
const THEMES := [
	["\\b(inn|tavern|alehouse|hostel|common room)\\b", ["barrel", "barrel", "firewood", "herbs", "jar", "crate", "cauldron"]],
	["\\b(weaver|weaving|spinner|dyer)\\b", ["basket", "spindle", "basket", "jar", "herbs"]],
	["\\b(smith|smithy|forge|metalworker)\\b", ["barrel", "firewood", "crate", "sack"]],
	["\\b(kitchen|cook|bakery|baker|larder|pantry)\\b", ["jar", "jar", "sack", "basket", "firewood", "herbs", "cauldron"]],
	["\\b(stable|byre|barn|pen|sty|kennel)\\b", ["hay", "hay", "trough", "basket"]],
	["\\b(cottage|hut|house|home|dwelling|hovel)\\b", ["bed", "quern", "jar", "jar", "firewood", "herbs", "basket"]],
]
const OUTDOOR_THEMES := [
	["\\b(forest|woods?|grove|thicket|glade|wild)\\b", ["log", "stone", "bush", "mushrooms", "log"]],
	["\\b(market|square|plaza|fair)\\b", ["cart", "barrel", "crate", "sack", "basket"]],
	["\\b(path|road|street|lane|track|way|village|town)\\b", ["firewood", "hurdle", "hay", "trough", "cart", "quern", "barrel"]],
]

var _vocab := []


func _init(world: World, p: Dictionary, sh: Dictionary, is_outdoor: bool, room_tier: String, seed_value: int) -> void:
	w = world
	pack = p
	shape = sh
	outdoor = is_outdoor
	tier = room_tier
	rng.seed = seed_value
	for v in VOCAB:
		_vocab.append([v[0], RegEx.create_from_string("(?i)" + v[1])])


# ================================================================== reading

## Mentions of things in one sentence, in order, without overlaps.
func _mentions(sentence: String) -> Array:
	var found := []
	for v in _vocab:
		for m in (v[1] as RegEx).search_all(sentence):
			found.append({"type": v[0], "start": m.get_start(), "end": m.get_end(), "word": m.get_string().to_lower()})
	found.sort_custom(func(a, b): return a["start"] < b["start"] or (a["start"] == b["start"] and a["end"] > b["end"]))
	var out := []
	var last_end := -1
	for f in found:
		if f["start"] >= last_end:
			out.append(f)
			last_end = f["end"]
	return out


func where_of(low: String) -> Dictionary:
	var d := {}
	var m := RegEx.create_from_string("\\b(north|south|east|west)(ern)?\\b").search(low)
	if m != null:
		d["dir"] = m.get_string(1)
	if low.contains("corner"):
		d["corner"] = true
	if RegEx.create_from_string("\\b(center|centre|middle)\\b").search(low) != null:
		d["center"] = true
	if RegEx.create_from_string("\\b(back|far|rear) wall\\b").search(low) != null:
		d["back"] = true
	if RegEx.create_from_string("\\b(entire|whole|all of the|takes up|dominat|fills)").search(low) != null:
		d["wide"] = true
	return d


func _count_for(sentence: String, mention: Dictionary) -> int:
	var before := sentence.substr(maxi(mention["start"] - 22, 0), mini(mention["start"], 22)).to_lower()
	var word: String = mention["word"]
	var plural := (word.ends_with("s") and not word.ends_with("ss")) or word.begins_with("balls") or word.begins_with("bales")
	var low := sentence.to_lower()
	var lots := RegEx.create_from_string("\\b(litter|littered|scattered|strewn|fill|fills|filled|heaps?|piles?|dozens|many|rows of|crowded)\\b").search(low) != null
	if RegEx.create_from_string("\\b(a few|few|several|some|a couple|three|handful)\\s*[a-z ]*$").search(before) != null:
		return 3
	if RegEx.create_from_string("\\btwo\\s*[a-z ]*$").search(before) != null:
		return 2
	if plural and lots:
		return -1  # as many as suit the room
	if plural:
		return 3
	return 1


## Read the description into a list of wants: what, how many, where, next to what.
func read_text(desc: String) -> Array:
	var wants := []
	var flat := " ".join(desc.replace("\r", " ").replace("\n", " ").split(" ", false))
	var sentences := RegEx.create_from_string("[^.!?]+[.!?]?").search_all(flat)
	if RegEx.create_from_string("(?i)\\b(lined with doors|doors line|doors on (either|both) sides?)").search(flat) != null:
		wants.append({"type": "doors_row", "count": 1, "where": {}, "anchor": -1, "on": false, "source": ""})
	var by_type := {}
	for sm in sentences:
		var s: String = sm.get_string().strip_edges()
		var low := s.to_lower()
		var ms := _mentions(s)
		if ms.is_empty():
			continue
		var where := where_of(low)
		var first_index := wants.size()
		var placed_where := false
		for i in ms.size():
			var mt: Dictionary = ms[i]
			var kind: String = mt["type"]
			if kind == "door" and (where.get("dir", "") == "" or exits.has(where.get("dir", ""))):
				continue  # a real exit (it has its own doorway) or we can't tell where
			if kind == "door" and wants.any(func(x): return x["type"] == "doors_row"):
				continue
			# relation to the next thing mentioned: "X next to a Y", "X on the Y"
			var anchor_next := false
			var on_top := false
			if i + 1 < ms.size():
				var between := low.substr(mt["end"], ms[i + 1]["start"] - mt["end"])
				if RegEx.create_from_string("\\b(next to|beside|besides|by|near|alongside|close to|in front of|before|behind|against|around)\\b").search(between) != null:
					anchor_next = true
				elif RegEx.create_from_string("\\b(on|upon|atop|over|above|hangs? (from|over))\\b").search(between) != null and not between.contains("wall") and not between.contains("side"):
					anchor_next = true
					on_top = true
			var want := {"type": kind, "count": _count_for(s, mt), "where": {}, "anchor": -1,
				"anchor_type": ms[i + 1]["type"] if anchor_next else "", "on": on_top,
				"hanging": low.contains("hang") or low.contains("ceiling") or low.contains("rafters"),
				"big": RegEx.create_from_string("\\b(large|huge|great|massive|roaring|big|enormous)\\b").search(low.substr(maxi(mt["start"] - 20, 0), 20 + mt["end"] - mt["start"])) != null,
				"source": s}
			if not placed_where and not anchor_next and not where.is_empty():
				want["where"] = where
				placed_where = true
			if kind == "table" and low.contains("bench"):
				want["benches"] = true
			if kind == "bench" and by_type.has("table"):
				continue  # benches come with the tables
			if by_type.has(kind) and kind != "jar":
				# mentioned before: only add what's new (a place or a neighbor)
				var prev: Dictionary = wants[by_type[kind]]
				if prev["where"].is_empty() and not want["where"].is_empty():
					prev["where"] = want["where"]
				if prev["anchor_type"] == "" and want["anchor_type"] != "":
					prev["anchor_type"] = want["anchor_type"]
				continue
			by_type[kind] = wants.size()
			wants.append(want)
		# resolve "next to the Y" to the Y we already know about
		for k in range(first_index, wants.size()):
			var wk: Dictionary = wants[k]
			if wk["anchor_type"] != "" and by_type.has(wk["anchor_type"]):
				wk["anchor"] = by_type[wk["anchor_type"]]
		# anchors that weren't listed as their own thing yet ("beside the hearth")
		for k in range(first_index, wants.size()):
			var wk: Dictionary = wants[k]
			if wk["anchor_type"] != "" and wk["anchor"] == -1:
				by_type[wk["anchor_type"]] = wants.size()
				wk["anchor"] = wants.size()
				wants.append({"type": wk["anchor_type"], "count": 1, "where": {}, "anchor": -1, "anchor_type": "",
					"on": false, "hanging": false, "big": false, "source": s})
	return wants


# ================================================================== placing

func center() -> Vector3:
	return shape["center"]


func reach() -> float:
	if shape["kind"] == "round":
		return shape["r"]
	return minf(shape["hx"], shape["hz"])


func inside(p: Vector3, margin: float) -> bool:
	var c := center()
	if shape["kind"] == "round":
		return Vector2(p.x - c.x, p.z - c.z).length() <= float(shape["r"]) - margin
	return absf(p.x - c.x) <= float(shape["hx"]) - margin and absf(p.z - c.z) <= float(shape["hz"]) - margin


func wall_point(dir: Vector2, depth: float) -> Vector3:
	var c := center()
	var d := dir.normalized()
	if shape["kind"] == "round":
		return c + Vector3(d.x, 0, d.y) * (float(shape["r"]) - depth)
	var tx: float = INF if absf(d.x) < 0.001 else (float(shape["hx"]) - depth) / absf(d.x)
	var tz: float = INF if absf(d.y) < 0.001 else (float(shape["hz"]) - depth) / absf(d.y)
	return c + Vector3(d.x, 0, d.y) * minf(tx, tz)


func _clear_of_lanes(p: Vector3, rad: float) -> bool:
	if _ignore_lanes:
		return true
	for l in lanes:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (ap - ab * t).length() < rad + 0.9:
			return false
	return true


func _clear_of_things(p: Vector3, rad: float) -> bool:
	for t in taken:
		if Vector2(p.x - t[0].x, p.z - t[0].z).length() < rad + float(t[1]):
			return false
	return true


func occupy(p: Vector3, rad: float) -> void:
	if rad > 0.0:
		taken.append([p, rad])


var _ignore_lanes := false


func free_spot(rad: float, near := Vector3.INF, tries := 90, edge_bias := false) -> Vector3:
	var c := center()
	var lim := reach() - rad - 0.3
	for i in tries:
		var p: Vector3
		if near != Vector3.INF:
			# "next to" means next to: stay within a few meters of it, or not at all
			var spread := 1.2 + 2.2 * float(i) / tries
			p = near + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		elif shape["kind"] != "round":
			var hx: float = float(shape["hx"]) - rad - 0.3
			var hz: float = float(shape["hz"]) - rad - 0.3
			p = c + Vector3(rng.randf_range(-hx, hx), 0, rng.randf_range(-hz, hz))
			if edge_bias and rng.randf() < 0.8:
				if rng.randf() < 0.5:
					p.x = c.x + signf(p.x - c.x + 0.001) * hx * rng.randf_range(0.8, 1.0)
				else:
					p.z = c.z + signf(p.z - c.z + 0.001) * hz * rng.randf_range(0.8, 1.0)
		else:
			var a := rng.randf() * TAU
			var rr := (rng.randf_range(0.75, 1.0) if edge_bias else sqrt(rng.randf())) * lim
			p = c + Vector3(cos(a), 0, sin(a)) * rr
		if inside(p, rad + 0.2) and _clear_of_lanes(p, rad) and _clear_of_things(p, rad):
			return p
	return Vector3.INF


func _wall_dir(where: Dictionary) -> Vector2:
	if where.get("back", false):
		return -entrance
	var d := str(where.get("dir", ""))
	if DIR2.has(d):
		var v: Vector2 = DIR2[d]
		if where.get("corner", false):
			v = (v + Vector2(v.y, -v.x)).normalized()
		return v
	if where.get("corner", false):
		var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
		for k in 8:
			var cv: Vector2 = corners[rng.randi_range(0, 3)].normalized()
			if cv.dot(entrance) < 0.5:  # not the corner by the way in
				return cv
		return corners[0].normalized()
	return Vector2.ZERO


## Somewhere along a wall; returns [position, facing] or [] if nowhere fits.
func _against_wall(dir: Vector2, depth: float, rad: float) -> Array:
	var pick := dir
	for k in 16:
		var spin := 0.0 if k == 0 else rng.randf_range(-0.9, 0.9) * (1.0 + k * 0.08)
		var d := pick.rotated(spin) if pick != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
		var p := wall_point(d, depth)
		if _clear_of_lanes(p, rad * 0.5) and _clear_of_things(p, rad):
			return [p, atan2(d.x, d.y)]
	return []


## Space available along a wall, for things that "take the entire west side".
func _wall_span(depth: float) -> float:
	if shape["kind"] == "round":
		var r := float(shape["r"])
		return 2.0 * sqrt(maxf(r * r - pow(r - depth - 1.2, 2.0), 1.0))
	return minf(float(shape["hx"]), float(shape["hz"])) * 1.8


func _item(kind: String, p: Vector3, rot: float, opts := {}) -> Dictionary:
	var c := center()
	return {"type": kind, "x": snappedf(p.x - c.x, 0.01), "z": snappedf(p.z - c.z, 0.01),
		"rot": snappedf(rot, 0.001), "o": opts}


func _pos(item: Dictionary) -> Vector3:
	return center() + Vector3(float(item["x"]), 0, float(item["z"]))


## Turn wants into placed items.
func place(wants: Array) -> Array:
	var items := []
	var placed_at := {}   # want index -> Vector3 (for anchoring)
	var order := []
	for i in wants.size():
		order.append(i)
	# anchors before the things placed next to them; big fixed things first
	var rank := func(i):
		var t: String = wants[i]["type"]
		var r := 5
		if t in ["doors_row", "hearth", "loom", "forge", "counter", "well", "fountain"]:
			r = 0
		elif t in WALL_TYPES or t in CENTER_TYPES:
			r = 1
		elif t in ["table"]:
			r = 2
		if wants[i]["anchor"] != -1:
			r += 10
		return r
	order.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
	var guard := 0
	while not order.is_empty() and guard < 200:
		guard += 1
		var i: int = order.pop_front()
		var want: Dictionary = wants[i]
		var anchor: int = want["anchor"]
		if anchor != -1 and not placed_at.has(anchor) and order.has(anchor):
			order.append(i)  # wait for its anchor
			continue
		var near: Vector3 = placed_at.get(anchor, Vector3.INF)
		var made := _place_one(want, near)
		if made.is_empty() and want["type"] != "doors_row":
			# it's in the description, so it has to go somewhere: loosen up
			_ignore_lanes = true
			made = _place_one(want, near)
			if made.is_empty() and near != Vector3.INF:
				made = _place_one(want, Vector3.INF)
			_ignore_lanes = false
			if made.is_empty():
				push_warning("Legend3D: no room for '%s' in this room" % want["type"])
		if not made.is_empty():
			placed_at[i] = _pos(made[0])
			items.append_array(made)
	return items


func _place_one(want: Dictionary, near: Vector3) -> Array:
	var kind: String = want["type"]
	var where: Dictionary = want["where"]
	var count: int = want["count"]
	var foot: float = FOOT.get(kind, 0.6)
	var out := []
	match kind:
		"doors_row":
			return _doors_row()
		"hearth":
			var dir := _wall_dir(where)
			var central := dir == Vector2.ZERO and not outdoor
			var big: bool = want["big"] or tier in ["hall", "great"]
			var width := 3.4 if big else 2.2
			if where.get("wide", false):
				width = clampf(reach() * 0.9, 3.0, 5.5)
			if central:
				var p := center()
				occupy(p, 1.6 if not big else 2.0)
				return [_item("hearth", p, 0.0, {"central": true, "big": big})]
			var at := _against_wall(dir if dir != Vector2.ZERO else -entrance, 0.75, width / 2)
			if at.is_empty():
				return []
			occupy(at[0], width / 2 + 0.6)
			return [_item("hearth", at[0], at[1], {"width": width, "big": big})]
		"loom":
			var dir := _wall_dir(where)
			if dir == Vector2.ZERO:
				dir = Vector2.from_angle(rng.randf() * TAU)
			var width := 2.2
			if where.get("wide", false) or want["big"]:
				width = clampf(_wall_span(0.6) * 0.7, 2.4, 3.4)
			var at := _against_wall(dir, 0.55 if shape["kind"] != "round" else 0.9, width / 2)
			if at.is_empty():
				return []
			occupy(at[0], width / 2 + 0.3)
			return [_item("loom", at[0], at[1], {"width": width})]
		"table":
			var n := count
			if n == -1:
				n = {"hut": 1, "house": 2, "hall": 4, "great": 6}.get(tier, 2)
			var benches: bool = want.get("benches", false) or n > 1
			for k in n:
				var p := free_spot(1.7 if benches else 1.0, near)
				if p == Vector3.INF:
					break
				occupy(p, 1.6 if benches else 1.0)
				var rot := rng.randf() * PI
				if shape["kind"] == "round" and n > 1:
					rot = atan2(p.x - center().x, p.z - center().z)
				out.append(_item("table", p, rot, {"benches": benches}))
			return out
		"lantern":
			var n: int = count if count > 0 else {"hut": 1, "house": 2, "hall": 3, "great": 4}.get(tier, 2)
			if count == 1 and want["hanging"] and tier in ["hall", "great"]:
				n = {"hall": 3, "great": 4}[tier]
			if count == 3 and want["hanging"]:
				n = {"hut": 1, "house": 2, "hall": 3, "great": 4}.get(tier, 2)
			var c := center()
			for k in n:
				var p: Vector3
				if n == 1:
					p = c
				elif shape["kind"] == "rect" and float(shape["hx"]) != float(shape["hz"]):
					var along := Vector3(1, 0, 0) if float(shape["hx"]) > float(shape["hz"]) else Vector3(0, 0, 1)
					var span: float = maxf(float(shape["hx"]), float(shape["hz"])) * 0.7
					p = c + along * lerpf(-span, span, float(k) / maxf(n - 1, 1))
				else:
					var a := TAU * k / n + 0.4
					p = c + Vector3(cos(a), 0, sin(a)) * reach() * 0.45
				out.append(_item("lantern", p, 0.0, {"hanging": want["hanging"] or not outdoor}))
			return out
		"yarn", "mushrooms":
			var n := 12 if count == -1 else maxi(count * 2, 3)
			for k in n:
				var p := free_spot(0.12, near, 40)
				if p == Vector3.INF:
					break
				occupy(p, 0.12)
				out.append(_item(kind, p, rng.randf() * TAU, {"hue": rng.randi_range(0, 4)}))
			return out
	# everything else: anchored, wall, corner, center or free
	var n2 := count
	if n2 == -1:
		n2 = 4
	n2 = clampi(n2, 1, 6)
	for k in n2:
		var p := Vector3.INF
		var rot := rng.randf() * TAU
		if near != Vector3.INF and want["on"]:
			p = near
		elif near != Vector3.INF:
			p = free_spot(foot, near, 60)
			if p != Vector3.INF:
				rot = atan2(near.x - p.x, near.z - p.z) + PI  # face the thing it's next to
		elif kind in CENTER_TYPES and not where.has("dir"):
			p = center() if _clear_of_things(center(), foot) else free_spot(foot)
		elif kind in WALL_TYPES or where.has("dir") or where.has("back") or (where.get("corner", false) and not kind in CORNER_TYPES):
			var dir := _wall_dir(where)
			var depth: float = {"tapestry": 0.12, "herbs": 0.35, "torch": 0.2, "shelf": 0.3, "door": 0.12}.get(kind, foot + 0.15)
			var at := _against_wall(dir, depth, foot)
			if not at.is_empty():
				p = at[0]
				rot = at[1]
		elif kind in CORNER_TYPES or where.get("corner", false):
			var dir := _wall_dir({"corner": true} if not where.has("dir") else where)
			var base := wall_point(dir, foot + 0.4) if k == 0 or near == Vector3.INF else near
			p = free_spot(foot, base, 50)
			near = p if p != Vector3.INF else near
		else:
			p = free_spot(foot, near)
		if p == Vector3.INF:
			break
		occupy(p, foot if not want["on"] else 0.0)
		out.append(_item(kind, p, rot, {"big": want["big"], "on": want["on"], "hanging": want["hanging"]}))
	return out


func _doors_row() -> Array:
	if shape["kind"] != "rect":
		return []
	var out := []
	var long_x: bool = float(shape["hx"]) >= float(shape["hz"])
	var length: float = (float(shape["hx"]) if long_x else float(shape["hz"])) * 2.0
	var count := clampi(int(length / 3.4), 2, 7)
	for side: int in [-1, 1]:
		var dir := Vector2(0, side) if long_x else Vector2(side, 0)
		for i in count:
			var t := lerpf(-0.5, 0.5, (i + 0.5) / count) * (length - 1.6)
			var off := Vector3(t, 0, 0) if long_x else Vector3(0, 0, t)
			var p := wall_point(dir, 0.12) + off
			if not _clear_of_lanes(p, 0.4):
				continue
			occupy(p, 0.7)
			out.append(_item("door", p, atan2(dir.x, dir.y)))
	return out


## Period clutter that fits the room and doesn't repeat what's described.
func clutter(name_and_desc: String, have: Array) -> Array:
	var low := name_and_desc.to_lower()
	var pool := []
	for th in (OUTDOOR_THEMES if outdoor else THEMES):
		if RegEx.create_from_string(th[0]).search(low) != null:
			pool = th[1]
			break
	if pool.is_empty():
		pool = ["jar", "basket", "firewood"] if not outdoor else []
	var budget: int = {"hut": 3, "house": 4, "hall": 6, "great": 7, "open": 4}.get(tier, 4)
	var out := []
	# woven La Tène hangings on the walls of bigger houses
	if not outdoor:
		var hangings: int = {"hut": 0, "house": 1 if rng.randf() < 0.5 else 0, "hall": 2, "great": 4}.get(tier, 0)
		for k in hangings:
			var at := _against_wall(Vector2.ZERO, 0.14, 0.9)
			if at.is_empty():
				break
			occupy(at[0], 0.9)
			out.append(_item("hanging", at[0], at[1], {"variant": k % 2}))
	var used := {}
	for t in have:
		used[t] = true
	for kind in pool:
		if out.size() >= budget:
			break
		if used.has(kind) and not kind in ["jar", "barrel", "log", "hay", "basket"]:
			continue
		var foot: float = FOOT.get(kind, 0.6)
		var p: Vector3
		var rot := rng.randf() * TAU
		if kind in WALL_TYPES and not outdoor:
			var at := _against_wall(Vector2.ZERO, foot + 0.15 if kind != "herbs" else 0.35, foot)
			if at.is_empty():
				continue
			p = at[0]
			rot = at[1]
		else:
			p = free_spot(foot, Vector3.INF, 60, true)
		if p == Vector3.INF:
			continue
		occupy(p, foot)
		out.append(_item(kind, p, rot, {"clutter": true}))
	return out


## Everything in one go: what the description says, then clutter.
func plan(name: String, desc: String) -> Array:
	var wants := read_text(desc)
	var items := place(wants)
	var have := []
	for it in items:
		have.append(it["type"])
	items.append_array(clutter(name + ". " + desc, have))
	return items


## A thing listed in the room ("A mailbox sits in the corner here.")
func place_object(kind: String, line: String) -> Dictionary:
	var where := where_of(line.to_lower())
	var made := _place_one({"type": kind, "count": 1, "where": where, "anchor": -1, "on": false,
		"hanging": false, "big": false, "source": line}, Vector3.INF)
	return made[0] if not made.is_empty() else {}


# ================================================================== building

func _m(tex: String, tint := Color.WHITE) -> Material:
	return w.mat(tex, tint)


func build(parent: Node3D, items: Array) -> void:
	for it in items:
		if not (it is Dictionary) or not it.has("type"):
			continue
		var n := Node3D.new()
		n.position = _pos(it)
		n.rotation.y = float(it.get("rot", 0.0))
		parent.add_child(n)
		var o: Dictionary = it.get("o", {}) if it.get("o") is Dictionary else {}
		_piece(n, str(it["type"]), o)


func _light(parent: Node3D, l: Light3D, priority: float, flicker: float) -> void:
	l.shadow_enabled = false
	l.add_to_group("l3d_light")
	l.set_meta("priority", priority)
	l.set_meta("base_energy", l.light_energy)
	l.set_meta("flicker", flicker)
	parent.add_child(l)


func _flames(n: Node3D, y: float, size: float) -> void:
	for i in 3:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(size * (1.3 - i * 0.2), size * (0.95 - i * 0.12))
		f.mesh = q
		f.material_override = w.flame_mat()
		f.position = Vector3(0, y + q.size.y / 2, -0.05 + i * 0.03)
		f.rotation.y = i * PI / 3
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(f)


## One item, built facing local -Z (into the room for wall pieces).
func _piece(n: Node3D, kind: String, o: Dictionary) -> void:
	var wood := _m(str(pack["furniture"]))
	var dark := _m(str(pack["door"]))
	var iron := _m("iron")
	var stone := _m(str(pack["stone"]))
	match kind:
		"hearth":
			if o.get("central", false):
				var big: bool = o.get("big", false)
				var rr := 1.1 if big else 0.8
				for k in 10:  # ring of kerb stones
					var a := TAU * k / 10
					w.box(n, Vector3(0.45, 0.22, 0.32), Vector3(cos(a) * rr, 0.11, sin(a) * rr), stone, k % 3 == 0, -a)
				w.cylinder(n, rr - 0.1, 0.04, Vector3(0, 0.02, 0), _m("rock", Color(0.5, 0.45, 0.4)), false, false)
				_flames(n, 0.03, 1.0 if big else 0.8)
				var key := SpotLight3D.new()
				key.light_color = Color(1.0, 0.74, 0.5)
				key.light_energy = 4.2 if big else 3.0
				key.spot_range = 10.0 if big else 7.5
				key.spot_angle = 85.0
				key.position = Vector3(0, 2.6, 0)
				key.rotation_degrees = Vector3(-90, 0, 0)
				_light(n, key, 10.0, 0.22)
			else:
				var width: float = o.get("width", 2.4)
				w.box(n, Vector3(width, 0.4, 1.3), Vector3(0, 0.2, 0), stone, true)
				w.box(n, Vector3(width + 0.4, 1.3, 0.4), Vector3(0, 0.65, 0.55), stone, true)
				w.box(n, Vector3(0.5, 0.9, 1.3), Vector3(-width / 2 - 0.05, 0.45, 0), stone, true)
				w.box(n, Vector3(0.5, 0.9, 1.3), Vector3(width / 2 + 0.05, 0.45, 0), stone, true)
				_flames(n, 0.4, 1.0)
				w.box(n, Vector3(1.1, 0.14, 0.2), Vector3(0, 0.47, 0), dark, false, 0.4)
				w.box(n, Vector3(1.1, 0.14, 0.2), Vector3(0, 0.47, 0), dark, false, -0.4)
				var key := SpotLight3D.new()
				key.light_color = Color(1.0, 0.74, 0.5)
				key.light_energy = 4.6 if o.get("big", false) else 3.6
				key.spot_range = 14.0
				key.spot_angle = 80.0
				key.position = Vector3(0, 1.1, -0.3)
				key.rotation_degrees = Vector3(-12, 0, 0)
				_light(n, key, 10.0, 0.22)
			# warm bounce: a broad, soft, shadowless glow around the fire
			var fill := OmniLight3D.new()
			fill.light_color = Color(1.0, 0.68, 0.45)
			fill.light_energy = 0.9
			fill.omni_range = 9.0 if o.get("big", false) else 6.5
			fill.omni_attenuation = 1.6
			fill.position = Vector3(0, 0.8, -0.6 if not o.get("central", false) else 0.0)
			_light(n, fill, 0.0, 0.3)
		"loom":
			# upright warp-weighted loom: two posts, beams, warp threads, hanging stones
			var width: float = o.get("width", 2.2)
			for s: int in [-1, 1]:
				var post := w.box(n, Vector3(0.14, 2.3, 0.14), Vector3(s * width / 2, 1.15, 0), wood, true)
				post.rotation.x = -0.12
			w.box(n, Vector3(width + 0.3, 0.14, 0.14), Vector3(0, 2.15, 0.12), wood, false)
			w.box(n, Vector3(width, 0.08, 0.08), Vector3(0, 1.1, -0.06), wood, false)
			var cloth := MeshInstance3D.new()
			var cq := QuadMesh.new()
			cq.size = Vector2(width - 0.3, 0.6)
			cloth.mesh = cq
			cloth.material_override = w.mat("wool_white")
			cloth.position = Vector3(0, 1.75, 0.05)
			cloth.rotation.y = PI
			n.add_child(cloth)
			for k in int(width / 0.12):
				w.box(n, Vector3(0.015, 0.9, 0.015), Vector3(-width / 2 + 0.1 + k * 0.12, 0.62, -0.02 - k % 2 * 0.03), _m("cloth", Color(0.9, 0.85, 0.7)), false)
			for k in int(width / 0.3):
				w.box(n, Vector3(0.1, 0.12, 0.1), Vector3(-width / 2 + 0.15 + k * 0.3, 0.12, -0.05), stone, false)
		"yarn":
			var colors := [Color(0.85, 0.75, 0.55), Color(0.7, 0.3, 0.2), Color(0.35, 0.45, 0.6), Color(0.45, 0.55, 0.3), Color(0.85, 0.85, 0.8)]
			var ball := w.sphere(n, 0.1, Vector3(0, 0.1, 0), w.mat("cloth", colors[int(o.get("hue", 0)) % colors.size()]))
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"wool":
			w.box(n, Vector3(1.0, 0.6, 0.7), Vector3(0, 0.3, 0), w.mat("cloth", Color(0.92, 0.88, 0.78)), true, 0.2)
			w.box(n, Vector3(0.8, 0.45, 0.6), Vector3(0.15, 0.82, 0.05), w.mat("cloth", Color(0.85, 0.8, 0.7)), false, -0.3)
		"spindle":
			w.cylinder(n, 0.03, 0.4, Vector3(0, 0.2, 0), wood, false)
			w.cylinder(n, 0.08, 0.04, Vector3(0, 0.08, 0), stone, false)
			w.sphere(n, 0.09, Vector3(0, 0.3, 0), w.mat("cloth", Color(0.85, 0.8, 0.7)))
		"basket":
			w.cylinder(n, 0.3, 0.35, Vector3(0, 0.175, 0), w.mat("wattle"), true)
		"table":
			w.box(n, Vector3(0.85, 0.08, 1.9), Vector3(0, 0.74, 0), wood, true)
			for sx: int in [-1, 1]:
				for sz: int in [-1, 1]:
					w.box(n, Vector3(0.09, 0.7, 0.09), Vector3(sx * 0.32, 0.35, sz * 0.8), wood, false)
			if o.get("benches", false):
				for sx: int in [-1, 1]:
					w.box(n, Vector3(0.32, 0.06, 1.8), Vector3(sx * 0.8, 0.44, 0), wood, true)
					for sz: int in [-1, 1]:
						w.box(n, Vector3(0.28, 0.41, 0.07), Vector3(sx * 0.8, 0.205, sz * 0.7), wood, false)
			for k in rng.randi_range(1, 3):
				w.cylinder(n, 0.06, 0.12, Vector3(rng.randf_range(-0.3, 0.3), 0.84, rng.randf_range(-0.8, 0.8)), _m("iron"), false, false)
		"bench":
			w.box(n, Vector3(0.32, 0.06, 1.8), Vector3(0, 0.44, 0), wood, true)
			for sz: int in [-1, 1]:
				w.box(n, Vector3(0.28, 0.41, 0.07), Vector3(0, 0.205, sz * 0.7), wood, false)
		"chair":
			w.cylinder(n, 0.22, 0.45, Vector3(0, 0.225, 0), wood, true)
		"rocking_chair":
			w.box(n, Vector3(0.5, 0.06, 0.5), Vector3(0, 0.45, 0), wood, true)
			w.box(n, Vector3(0.5, 0.7, 0.06), Vector3(0, 0.8, 0.24), wood, false)
			for s: int in [-1, 1]:
				w.box(n, Vector3(0.05, 0.45, 0.05), Vector3(s * 0.22, 0.225, 0), wood, false)
				var rocker := w.box(n, Vector3(0.05, 0.06, 0.8), Vector3(s * 0.22, 0.04, 0), wood, false)
				rocker.rotation.x = 0.08
		"bed":
			# box bed against the wall: timber frame, straw mattress, a fur
			w.box(n, Vector3(1.0, 0.4, 2.0), Vector3(0, 0.2, -0.3), wood, true)
			w.box(n, Vector3(0.95, 0.12, 1.9), Vector3(0, 0.46, -0.3), _m("thatch"), false)
			w.box(n, Vector3(0.9, 0.05, 1.2), Vector3(0, 0.54, -0.6), w.mat("cloth", Color(0.55, 0.42, 0.3)), false)
		"quern":
			w.cylinder(n, 0.32, 0.14, Vector3(0, 0.07, 0), stone, true)
			w.cylinder(n, 0.3, 0.12, Vector3(0, 0.2, 0), stone, false)
			w.box(n, Vector3(0.05, 0.25, 0.05), Vector3(0.2, 0.35, 0), wood, false)
		"jar":
			w.cylinder(n, 0.2, 0.5, Vector3(0, 0.25, 0), _m("daub", Color(0.8, 0.55, 0.4)), true)
			w.cylinder(n, 0.12, 0.08, Vector3(0, 0.54, 0), _m("daub", Color(0.7, 0.48, 0.35)), false)
		"forge":
			w.box(n, Vector3(1.6, 0.85, 1.2), Vector3(0, 0.425, 0), stone, true)
			_flames(n, 0.85, 0.6)
			var l := OmniLight3D.new()
			l.light_color = Color("ff7a30")
			l.light_energy = 2.5
			l.omni_range = 7.0
			l.position = Vector3(0, 1.4, 0)
			_light(n, l, 6.0, 0.3)
		"anvil":
			w.box(n, Vector3(0.4, 0.5, 0.4), Vector3(0, 0.25, 0), wood, true)
			w.box(n, Vector3(0.6, 0.22, 0.25), Vector3(0, 0.6, 0), iron, false)
		"counter":
			w.box(n, Vector3(3.2, 1.05, 0.7), Vector3(0, 0.525, 0), wood, true)
		"barrel":
			w.cylinder(n, 0.36, 0.95, Vector3(0, 0.475, 0), wood, true)
			w.cylinder(n, 0.375, 0.05, Vector3(0, 0.2, 0), iron, false)
			w.cylinder(n, 0.375, 0.05, Vector3(0, 0.75, 0), iron, false)
		"crate":
			w.box(n, Vector3(0.7, 0.7, 0.7), Vector3(0, 0.35, 0), wood, true)
		"sack":
			w.box(n, Vector3(0.5, 0.6, 0.4), Vector3(0, 0.3, 0), w.mat("cloth", Color(0.75, 0.68, 0.5)), true, 0.3)
		"shelf":
			w.box(n, Vector3(1.6, 1.9, 0.35), Vector3(0, 0.95, 0), dark, true)
			for y in [0.5, 1.0, 1.5]:
				for k in 3:
					w.box(n, Vector3(0.18, 0.22, 0.18), Vector3(-0.5 + k * 0.45, y + 0.12, -0.05), iron if k % 2 == 0 else wood, false)
		"chest", "object":
			w.box(n, Vector3(1.1, 0.55, 0.6), Vector3(0, 0.275, 0), dark, true)
			w.box(n, Vector3(1.12, 0.06, 0.62), Vector3(0, 0.45, 0), iron, false)
		"lantern":
			var hang_y := 2.3
			var top := w.ceiling_height_at(shape, pack)
			if o.get("hanging", true):
				var chain := top - hang_y - 0.15
				if chain > 0.05:
					w.box(n, Vector3(0.03, chain, 0.03), Vector3(0, hang_y + 0.15 + chain / 2, 0), iron, false)
			else:
				hang_y = 1.6
				w.box(n, Vector3(0.12, hang_y, 0.12), Vector3(0, hang_y / 2, 0), _m(str(pack["post"])), true)
			w.box(n, Vector3(0.3, 0.06, 0.3), Vector3(0, hang_y + 0.17, 0), iron, false)
			w.box(n, Vector3(0.26, 0.05, 0.26), Vector3(0, hang_y - 0.16, 0), iron, false)
			for sx: int in [-1, 1]:
				for sz: int in [-1, 1]:
					w.box(n, Vector3(0.03, 0.32, 0.03), Vector3(sx * 0.12, hang_y, sz * 0.12), iron, false)
			var core := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.2, 0.26, 0.2)
			core.mesh = cm
			core.material_override = w.glow(Color("ffd27a"), 0.4)
			core.position = Vector3(0, hang_y, 0)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(core)
			var l := SpotLight3D.new()
			l.light_color = Color("ffcf8a")
			l.light_energy = 3.0
			l.spot_range = 7.5
			l.spot_angle = 70.0
			l.position = Vector3(0, hang_y - 0.2, 0)
			l.rotation_degrees = Vector3(-90, 0, 0)
			_light(n, l, 5.0, 0.06)
		"torch":
			w.box(n, Vector3(0.08, 0.5, 0.08), Vector3(0, 1.9, 0), dark, false)
			var f := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.25, 0.35)
			f.mesh = q
			f.material_override = w.flame_mat()
			f.position = Vector3(0, 2.3, 0)
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(f)
			var l := OmniLight3D.new()
			l.light_color = Color("ffa04a")
			l.light_energy = 2.2
			l.omni_range = 6.5
			l.position = Vector3(0, 2.2, -0.3)
			_light(n, l, 3.0, 0.25)
		"candle":
			var y := 0.9 if o.get("on", false) else 0.05
			var core := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.05, 0.12, 0.05)
			core.mesh = cm
			core.material_override = w.glow(Color("ffe2a0"), 0.5)
			core.position = Vector3(0, y, 0)
			n.add_child(core)
			var l := OmniLight3D.new()
			l.light_color = Color("ffd08a")
			l.light_energy = 0.7
			l.omni_range = 3.0
			l.position = Vector3(0, y + 0.1, 0)
			_light(n, l, 0.5, 0.15)
		"tapestry":
			var tq := MeshInstance3D.new()
			var tm := QuadMesh.new()
			tm.size = Vector2(1.6, 1.9)
			tq.mesh = tm
			tq.material_override = w.mat("cloth", Color(0.85, 0.55, 0.45))
			tq.position = Vector3(0, 1.5, -0.02)
			tq.rotation.y = PI
			n.add_child(tq)
		"hanging":
			var hq := MeshInstance3D.new()
			var hm := QuadMesh.new()
			hm.size = Vector2(1.3, 1.7)
			hq.mesh = hm
			hq.material_override = w.mat_uv("hanging_a" if int(o.get("variant", 0)) == 0 else "hanging_b", 1.0)
			hq.position = Vector3(0, 1.75, -0.03)
			hq.rotation.y = PI
			n.add_child(hq)
			w.box(n, Vector3(1.5, 0.06, 0.06), Vector3(0, 2.62, -0.05), wood, false)
		"fur":
			w.box(n, Vector3(1.4, 0.03, 1.0), Vector3(0, 0.015, 0), w.mat("cloth", Color(0.55, 0.42, 0.3)), false)
		"cauldron":
			if o.get("on", false):
				# hung over the fire from a tripod
				for k in 3:
					var a := TAU * k / 3
					var leg := w.box(n, Vector3(0.06, 2.0, 0.06), Vector3(cos(a) * 0.55, 0.95, sin(a) * 0.55), iron, false)
					leg.rotation = Vector3(sin(a) * 0.28, 0, -cos(a) * 0.28)
				w.cylinder(n, 0.38, 0.45, Vector3(0, 0.95, 0), iron, false)
			else:
				w.cylinder(n, 0.42, 0.55, Vector3(0, 0.3, 0), iron, true)
		"firewood":
			for k in 7:
				var lg := w.cylinder(n, 0.09, 1.1, Vector3(-0.3 + (k % 4) * 0.18, 0.1 + (k / 4) * 0.17, 0), _m("darktimber"), k == 0)
				lg.rotation.z = PI / 2
		"hay":
			w.cylinder(n, 0.85, 0.9, Vector3(0, 0.45, 0), w.mat_uv("thatch", 2.5), true)
			w.cone(n, 0.95, 1.1, Vector3(0, 0.9, 0), w.mat_uv("thatch", 2.5), false, 10)
		"herbs":
			for k in 4:
				w.box(n, Vector3(0.08, 0.35, 0.08), Vector3(-0.45 + k * 0.3, 2.0, 0), w.mat("hedge", Color(0.75, 0.85, 0.55)), false)
			w.box(n, Vector3(1.4, 0.04, 0.04), Vector3(0, 2.2, 0), wood, false)
		"trough":
			w.box(n, Vector3(1.8, 0.5, 0.6), Vector3(0, 0.25, 0), wood, true)
			w.box(n, Vector3(1.6, 0.02, 0.45), Vector3(0, 0.44, 0), _m("water"), false)
		"hurdle":
			var hb := w.box(n, Vector3(1.8, 1.0, 0.1), Vector3(0, 0.5, 0), _m("wattle"), true)
			hb.rotation.z = 0.04
		"log":
			var lg2 := w.cylinder(n, 0.3, 2.4, Vector3(0, 0.3, 0), _m("darktimber"), true)
			lg2.rotation.z = PI / 2
		"mushrooms":
			for k in 3:
				w.cylinder(n, 0.06, 0.03, Vector3(k * 0.1 - 0.1, 0.09, (k % 2) * 0.08), w.mat("cloth", Color(0.85, 0.3, 0.2)), false, false)
		"well":
			w.cylinder(n, 1.0, 0.85, Vector3(0, 0.425, 0), stone, true)
			w.cylinder(n, 0.8, 0.02, Vector3(0, 0.86, 0), w.void_mat(), false)
			for sx: int in [-1, 1]:
				w.box(n, Vector3(0.14, 2.0, 0.14), Vector3(sx * 0.9, 1.0, 0), wood, false)
			w.box(n, Vector3(2.0, 0.14, 0.14), Vector3(0, 2.0, 0), wood, false)
		"fountain":
			w.cylinder(n, 1.4, 0.6, Vector3(0, 0.3, 0), stone, true)
			w.cylinder(n, 1.25, 0.02, Vector3(0, 0.58, 0), _m("water"), false)
		"statue":
			w.box(n, Vector3(1.0, 0.8, 1.0), Vector3(0, 0.4, 0), stone, true)
			w.box(n, Vector3(0.6, 2.0, 0.5), Vector3(0, 1.8, 0), stone, false)
		"altar":
			w.box(n, Vector3(1.8, 0.95, 0.9), Vector3(0, 0.475, 0), stone, true)
		"board":
			for sx: int in [-1, 1]:
				w.box(n, Vector3(0.1, 1.9, 0.1), Vector3(sx * 0.7, 0.95, 0), wood, true)
			w.box(n, Vector3(1.5, 0.95, 0.07), Vector3(0, 1.35, 0), dark, false)
			for k in 4:
				w.box(n, Vector3(0.25, 0.3, 0.02), Vector3(-0.5 + k * 0.33, 1.35 + (k % 2) * 0.15, -0.05), w.mat("plaster"), false)
		"mailbox":
			w.box(n, Vector3(0.12, 1.1, 0.12), Vector3(0, 0.55, 0), wood, true)
			w.box(n, Vector3(0.45, 0.4, 0.35), Vector3(0, 1.25, 0), dark, false)
			w.box(n, Vector3(0.3, 0.04, 0.02), Vector3(0, 1.35, -0.18), iron, false)
		"tree":
			w.billboard(n, SpriteGen.tree(rng.randi()), Vector3.ZERO, rng.randf_range(5.5, 8.5))
			w.cylinder(n, 0.25, 2.0, Vector3(0, 1.0, 0), _m("darktimber"), true, false)
		"bush":
			w.billboard(n, SpriteGen.bush(rng.randi()), Vector3.ZERO, rng.randf_range(0.9, 1.5))
		"stone":
			var h := 1.2 + absf(sin(n.position.x * 3.1 + n.position.z)) * 1.6
			w.box(n, Vector3(0.9, h, 0.6), Vector3(0, h / 2, 0), stone, true, 0.1)
		"cart":
			w.box(n, Vector3(1.4, 0.5, 2.4), Vector3(0, 0.8, 0), wood, true)
			for sx: int in [-1, 1]:
				var wh := w.cylinder(n, 0.55, 0.12, Vector3(sx * 0.78, 0.55, 0.3), dark, false)
				wh.rotation.z = PI / 2
		"stall":
			for sx: int in [-1, 1]:
				for sz: int in [-1, 1]:
					w.box(n, Vector3(0.1, 2.3, 0.1), Vector3(sx * 1.1, 1.15, sz * 0.7), wood, false)
			w.box(n, Vector3(2.4, 0.06, 1.7), Vector3(0, 2.3, 0), w.mat("cloth", Color(0.8, 0.6, 0.4)), false)
			w.box(n, Vector3(2.1, 0.85, 0.6), Vector3(0, 0.425, -0.4), wood, true)
		"door":
			w.box(n, Vector3(1.2, 2.05, 0.12), Vector3(0, 1.025, 0), dark, true)
			w.box(n, Vector3(0.12, 2.15, 0.18), Vector3(-0.66, 1.075, 0.02), _m(str(pack["post"])), false)
			w.box(n, Vector3(0.12, 2.15, 0.18), Vector3(0.66, 1.075, 0.02), _m(str(pack["post"])), false)
			w.box(n, Vector3(0.1, 0.1, 0.06), Vector3(0.38, 1.0, -0.08), iron, false)
		_:
			w.box(n, Vector3(0.7, 0.7, 0.7), Vector3(0, 0.35, 0), wood, true)
