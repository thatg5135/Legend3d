## The 3D world. MUD rooms go on a grid laid out from their exits; each one
## is built from its description (size, shape, furnishings) in its area's
## style. Movement between rooms happens through portals: doorways, open
## edges between outdoor rooms, and stair/ladder pads.
class_name World
extends Node3D

const C := 24.0          # one grid cell, meters
const FLOOR_H := 3.4     # height of one storey (rooms above and below)
const DOOR_W := 2.2
const DOOR_H := 2.15
const VIEW_RANGE := 6    # cells around you that stay built and shown

const DIRS := {
	"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1),
	"east": Vector3i(1, 0, 0), "west": Vector3i(-1, 0, 0),
	"northeast": Vector3i(1, 0, -1), "northwest": Vector3i(-1, 0, -1),
	"southeast": Vector3i(1, 0, 1), "southwest": Vector3i(-1, 0, 1),
	"up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0),
}
const CARDINAL := ["north", "south", "east", "west"]
const REVERSE := {
	"north": "south", "south": "north", "east": "west", "west": "east",
	"northeast": "southwest", "southwest": "northeast", "northwest": "southeast",
	"southeast": "northwest", "up": "down", "down": "up",
}
const OVERRIDES_PATH := "res://data/room_overrides.json"
const SPRITE_DIR := "res://data/sprites/"

## How big a building is: from what it's called, nudged by how it's described.
const TIER_NAMES := [
	["\\b(great hall|royal|throne|king'?s|queen'?s|ard[- ]?r[ií]gh?|high king|chieftain'?s|banquet(ing)? hall|feasting hall)\\b", "great"],
	["\\b(inn|tavern|alehouse|hostel|bruiden|hall|longhouse|meeting house|assembly|temple|shrine)\\b", "hall"],
	["\\b(cottage|hut|hovel|shack|shed|byre|sty|pen|kennel|outhouse|privy|cell|lean-to|bothy)\\b", "hut"],
]
const TIER_UP := "\\b(huge|enormous|vast|immense|great|cavernous|sprawling|massive|grand|spacious)\\b"
const TIER_DOWN := "\\b(small|tiny|cramped|little|simple|humble|modest|narrow|poky)\\b"
const TIERS := ["hut", "house", "hall", "great"]
const TIER_RADIUS := {"hut": 4.3, "house": 5.4, "hall": 7.8, "great": 10.4}
const TIER_WALL := {"hut": 2.1, "house": 2.4, "hall": 3.0, "great": 3.6}
const LAYOUT_VERSION := 7
## Exit names that mean "a building is through there".
const BUILDING_RE := "\\b(inn|tavern|alehouse|cottage|hut|house|home|hall|shop|smithy|forge|stable|barn|byre|temple|shrine|tower|dun|keep|fort|fortress|lodge|workshop|store|storehouse|bakery|kitchen|mill|chapel|church|room|chamber|reception|guild|jail|prison|cell|hostel|bruiden|dwelling|hovel|shed|granary)\\b"
const LADDER_RE := "\\b(ladder|loft|hatch|trap ?door)\\b"
const FIRE_RE := "\\b(hearth|fire|fireplace|forge|furnace|kitchen|oven|cooking|smoke|smoky|embers)\\b"
const LONG_WORDS := "\\b(long hall|corridor|hallway|passage|passageway|tunnel|gallery|stretches|lined with doors)\\b"
const LIGHT_UP := "\\b(brightly|bright|well lit|well-lit|lanterns?|lamps?|torches|candles|roaring|blazing|sunlit|airy)\\b"
const LIGHT_DOWN := "\\b(dim|dimly|dark|darkness|gloomy|gloom|shadowy|shadows|unlit|pitch|murky|single candle)\\b"


class Portal:
	var dir := ""
	var to_vnum := -1
	var kind := "edge"          # edge | door | pad | stairs | well
	var a := Vector3.ZERO       # ends of the opening at floor level (pads: both = center)
	var b := Vector3.ZERO
	var normal := Vector3.ZERO  # points out of this room
	var body: StaticBody3D = null
	var shape: CollisionShape3D = null
	var door_key := ""          # set when there's a door in this opening
	var door_node: Node3D = null
	var land := Vector3.INF     # where you stand when arriving through this way
	var land_face := Vector3.ZERO

	func mid() -> Vector3:
		return (a + b) * 0.5

	## distance on the floor plane from p to the opening
	func distance(p: Vector3) -> float:
		if kind in ["pad", "stairs", "well", "stairs_down"]:
			return Vector2(p.x - a.x, p.z - a.z).length()
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		return (ap - ab * t).length()

	func set_blocking(on: bool) -> void:
		if shape != null:
			shape.set_deferred("disabled", not on)


class Room:
	var vnum := -1
	var data := {}
	var cell := Vector3i.ZERO
	var pack := {}
	var kit := {}
	var shape := {}
	var node: Node3D = null
	var occ_node: Node3D = null
	var props: Props = null
	var base_taken: Array = []
	var portals: Array = []      # [Portal]
	var contents: Array = []     # [{line, count, kind, entry}]
	var layout: Array = []       # saved furnishing (see Props)
	var layout_key := ""
	var layout_locked := false   # you edited it by hand: never regenerate
	var apex := Vector3.INF      # top of the roof (for smoke)
	var shafts: Array = []       # [Node3D] light shafts through openings

	func is_outdoor() -> bool:
		return str(data.get("type", "")) == "outdoors"

	func room_name() -> String:
		return str(data.get("name", "?"))

	func exits() -> Array:
		var e = data.get("exits", [])
		return e if e is Array else []

	func exit(dir: String) -> Dictionary:
		for e in exits():
			if e is Dictionary and str(e.get("dir", "")) == dir:
				return e
		return {}

	func portal_to(vnum_to: int, dir := "") -> Portal:
		for p: Portal in portals:
			if p.to_vnum == vnum_to and (dir == "" or p.dir == dir):
				return p
		for p: Portal in portals:
			if p.to_vnum == vnum_to:
				return p
		return null


var rooms := {}
var by_cell := {}
var current: Room = null
var overrides := {"rooms": {}, "areas": {}}
var catalog: Catalog = null

var _islands := 0
var _mats := {}
var _container := Node3D.new()
var _ground: MeshInstance3D = null
var _retro: Shader = preload("res://shaders/retro.gdshader")
var _sprite: Shader = preload("res://shaders/sprite.gdshader")
var _glow: Shader = preload("res://shaders/glow.gdshader")
var _tier_res := []
var _tier_up: RegEx
var _tier_down: RegEx
var _long_re: RegEx
var _up_re: RegEx
var _down_re: RegEx
var light_steps := 6.0
var light_band := 0.3
var dirty := false   # the map changed and should be saved
var doors := {}      # "lowvnum|highvnum" -> true when closed
var _building_re: RegEx
var _ladder_re: RegEx
var _fire_re: RegEx
var _foliage: Shader = preload("res://shaders/foliage.gdshader")


func _ready() -> void:
	add_child(_container)
	for tw in TIER_NAMES:
		_tier_res.append([RegEx.create_from_string("(?i)" + tw[0]), tw[1]])
	_tier_up = RegEx.create_from_string("(?i)" + TIER_UP)
	_building_re = RegEx.create_from_string("(?i)" + BUILDING_RE)
	_ladder_re = RegEx.create_from_string("(?i)" + LADDER_RE)
	_fire_re = RegEx.create_from_string("(?i)" + FIRE_RE)
	_tier_down = RegEx.create_from_string("(?i)" + TIER_DOWN)
	_long_re = RegEx.create_from_string("(?i)" + LONG_WORDS)
	_up_re = RegEx.create_from_string("(?i)" + LIGHT_UP)
	_down_re = RegEx.create_from_string("(?i)" + LIGHT_DOWN)
	load_overrides()


func _exit_tree() -> void:
	for r in rooms.values():
		if r.node != null and r.node.get_parent() == null:
			r.node.free()
			r.node = null


func load_overrides() -> void:
	overrides = {"rooms": {}, "areas": {}}
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OVERRIDES_PATH))
	if parsed is Dictionary:
		for k in ["rooms", "areas"]:
			if parsed.get(k) is Dictionary:
				overrides[k] = parsed[k]
	else:
		push_warning("Legend3D: couldn't read %s (check the JSON)" % OVERRIDES_PATH)


func rebuild_all() -> void:
	for r in rooms.values():
		_rebuild(r)
	_update_visible()


# ---------------------------------------------------------------- the saved map

## Everything worth keeping between sessions, as plain JSON.
func export_doors() -> Dictionary:
	return doors.duplicate()


func import_doors(d: Dictionary) -> void:
	for k in d:
		doors[str(k)] = bool(d[k])


func export_map() -> Dictionary:
	var out := {}
	for r in rooms.values():
		var lines := []
		for it in r.contents:
			lines.append(str(it.get("raw", it.get("line", ""))))
		out[str(r.vnum)] = {
			"data": r.data,
			"cell": [r.cell.x, r.cell.y, r.cell.z],
			"contents": lines,
			"layout": r.layout,
			"layout_key": r.layout_key,
			"layout_locked": r.layout_locked,
		}
	return out


## Rooms come back exactly where they were; they get built as you come near.
func import_map(saved: Dictionary, contents_fn: Callable) -> int:
	var n := 0
	for k in saved:
		var e = saved[k]
		if not (e is Dictionary) or not (e.get("data") is Dictionary) or not (e.get("cell") is Array):
			continue
		var r := Room.new()
		r.vnum = int(k)
		r.data = e["data"]
		var c: Array = e["cell"]
		r.cell = Vector3i(int(c[0]), int(c[1]), int(c[2]))
		if by_cell.has(r.cell):
			continue
		if e.get("layout") is Array:
			r.layout = e["layout"]
		r.layout_key = str(e.get("layout_key", ""))
		r.layout_locked = bool(e.get("layout_locked", false))
		if e.get("contents") is Array:
			r.contents = contents_fn.call(e["contents"])
		rooms[r.vnum] = r
		by_cell[r.cell] = r.vnum
		if absi(r.cell.x) >= 500:
			_islands = maxi(_islands, int(round(r.cell.x / 1000.0)))
		n += 1
	return n


# ---------------------------------------------------------------- queries

func room(vnum: int) -> Room:
	return rooms.get(vnum)


func room_at(cell: Vector3i) -> Room:
	return rooms.get(by_cell.get(cell, -1))


static func center_of(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * C, cell.y * FLOOR_H, cell.z * C)


static func door_key_of(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


func door_closed(a: int, b: int) -> bool:
	return bool(doors.get(door_key_of(a, b), false))


func door_known(a: int, b: int) -> bool:
	return doors.has(door_key_of(a, b))


## Legend says the door between a and b is open/closed: remember it and show it.
func set_door(a: int, b: int, closed: bool) -> void:
	var key := door_key_of(a, b)
	var had := doors.has(key)
	if had and bool(doors[key]) == closed:
		return
	doors[key] = closed
	dirty = true
	var found := false
	for r in rooms.values():
		for p: Portal in r.portals:
			if p.door_key == key and p.door_node != null:
				Arch.set_door_open(p.door_node, not closed, true)
				found = true
	if not found or not had:
		# a door we didn't know about: rebuild so it appears
		for v in [a, b]:
			var rr: Room = rooms.get(v)
			if rr != null and rr.node != null:
				_rebuild(rr)


static func flat(v: Vector3i) -> Vector3:
	return Vector3(v.x, 0, v.z)


# ---------------------------------------------------------------- rooms in

func upsert(data: Dictionary, via_dir := "", from_vnum := -1) -> Room:
	var vnum := int(data.get("vnum", -1))
	var r: Room = rooms.get(vnum)
	if r != null:
		var changed := JSON.stringify(r.data) != JSON.stringify(data)
		r.data = data
		if changed:
			dirty = true
			_rebuild(r)
		elif r.node == null:
			_rebuild(r)
		return r
	r = Room.new()
	r.vnum = vnum
	r.data = data
	r.cell = _place(r, via_dir, from_vnum)
	rooms[vnum] = r
	by_cell[r.cell] = vnum
	dirty = true
	_rebuild(r)
	for d in CARDINAL:
		var n := room_at(r.cell + DIRS[d])
		if n != null and n.node != null:
			_rebuild(n)
	# a new storey changes the whole building: its height, windows, floors
	if not r.is_outdoor():
		for x in stack_of(r):
			if x != r and x.node != null:
				_rebuild(x)
	return r


func set_current(r: Room) -> void:
	current = r
	_update_visible()


func set_contents(r: Room, contents: Array) -> void:
	r.contents = contents
	dirty = true
	_build_occupants(r)


func _free_cell(cell: Vector3i) -> bool:
	return not by_cell.has(cell)


func _place(r: Room, via_dir: String, from_vnum: int) -> Vector3i:
	if via_dir != "" and DIRS.has(via_dir) and rooms.has(from_vnum):
		var base: Vector3i = rooms[from_vnum].cell
		for k in [1, 2, 3]:
			var want: Vector3i = base + DIRS[via_dir] * k
			if _free_cell(want):
				return want
	for e in r.exits():
		var to := int(e.get("to_vnum", -1))
		var d := str(e.get("dir", ""))
		if rooms.has(to) and DIRS.has(d):
			var want: Vector3i = rooms[to].cell - DIRS[d]
			if _free_cell(want):
				return want
	for other in rooms.values():
		for e in other.exits():
			if int(e.get("to_vnum", -1)) == r.vnum and DIRS.has(str(e.get("dir", ""))):
				var want: Vector3i = other.cell + DIRS[str(e["dir"])]
				if _free_cell(want):
					return want
	if rooms.is_empty():
		return Vector3i.ZERO
	_islands += 1
	return Vector3i(_islands * 1000, 0, 0)


func _update_visible() -> void:
	if current == null:
		return
	var building := stack_of(current) if not current.is_outdoor() else []
	var ground := current.cell.y
	if not building.is_empty():
		ground = (building[0] as Room).cell.y
	for r in rooms.values():
		# your own level around you, plus every storey of the building you're in;
		# standing upstairs you still see the street level outside the windows
		var near: bool = (r.cell.y == current.cell.y or r.cell.y == ground or building.has(r)) \
			and absi(r.cell.x - current.cell.x) <= VIEW_RANGE \
			and absi(r.cell.z - current.cell.z) <= VIEW_RANGE
		if r.node == null:
			if near:
				r.node = _build(r)
				_container.add_child(r.node)
			continue
		if near and r.node.get_parent() == null:
			_container.add_child(r.node)
		elif not near and r.node.get_parent() != null:
			_container.remove_child(r.node)


func _rebuild(r: Room) -> void:
	if r.node != null:
		if r.node.get_parent() != null:
			_container.remove_child(r.node)
		r.node.free()
	r.node = _build(r)
	if current == null or r == current:
		_container.add_child(r.node)
	_update_visible()
	if r == current:
		set_barriers(r, null)


# ---------------------------------------------------------------- reading a room

func room_text(r: Room) -> String:
	return "%s. %s" % [r.data.get("name", ""), r.data.get("desc", "")]


func _override(r: Room) -> Dictionary:
	var ov = overrides["rooms"].get(str(r.vnum))
	return ov if ov is Dictionary else {}


func tier_of(r: Room) -> String:
	var ov := _override(r)
	if ov.has("size"):
		var sz := str(ov["size"])
		return {"small": "hut", "medium": "house", "large": "hall", "huge": "great"}.get(sz, sz)
	return tier_of_text(str(r.data.get("name", "")), str(r.data.get("desc", "")))


## "The Weaver's Cottage" + "this simple cottage" -> hut; "The Silver Branch Inn" + "A huge common room" -> great
func tier_of_text(name: String, desc: String) -> String:
	var t := "house"
	for tr in _tier_res:
		if tr[0].search(name) != null:
			t = tr[1]
			break
	if t == "house":
		for tr in _tier_res:
			if tr[0].search(desc) != null:
				t = tr[1]
				break
	var i := TIERS.find(t)
	var first := desc.split(".")[0]  # how the room is introduced matters most
	if _tier_up.search(first) != null:
		i += 1
	elif _tier_down.search(first) != null:
		i -= 1
	return TIERS[clampi(i, 0, TIERS.size() - 1)]


func light_of(r: Room) -> float:
	var ov := _override(r)
	if ov.has("light"):
		return float(ov["light"])
	var text := room_text(r)
	var v := 0.5
	v += 0.12 * _up_re.search_all(text).size()
	v -= 0.18 * _down_re.search_all(text).size()
	return clampf(v, 0.1, 1.0)


func choose_kit(r: Room) -> Dictionary:
	var p := r.pack
	var text := room_text(r).to_lower()
	var ov := _override(r)
	var k := {"floor_mode": "none", "floor": str(p["street"]), "boundary": str(p["boundary"]),
		"boundary_h": float(p["boundary_h"])}
	if r.is_outdoor():
		if RegEx.create_from_string("\\b(square|plaza|market|courtyard|cobbled?)\\b").search(text) != null:
			k["floor_mode"] = "full"
			k["floor"] = str(p["plaza"])
		elif RegEx.create_from_string("\\b(path|road|street|lane|track|trail|way|avenue)\\b").search(text) != null:
			k["floor_mode"] = "strips"
		if RegEx.create_from_string("\\b(forest|woods?|grove|thicket|wilderness|wild)\\b").search(text) != null:
			k["boundary"] = str(p["wild_boundary"])
			k["boundary_h"] = 2.2
		if RegEx.create_from_string("\\b(beach|sand|sandy|dunes?)\\b").search(text) != null:
			k["floor_mode"] = "full"
			k["floor"] = "sand"
	for key in ["floor_mode", "floor", "boundary", "boundary_h", "wall", "ext_wall", "int_wall", "int_floor", "roof"]:
		if ov.has(key):
			k[key] = ov[key]
	return k


func shape_of(r: Room) -> Dictionary:
	var ctr := center_of(r.cell)
	if r.is_outdoor():
		return {"kind": "open", "center": ctr, "hx": C / 2 - 0.8, "hz": C / 2 - 0.8, "tier": "open"}
	if is_upper(r):
		return _upper_shape(r)
	var tier := tier_of(r)
	var rad: float = TIER_RADIUS.get(tier, 4.9)
	var ov := _override(r)
	var text := room_text(r)
	var kind := str(ov.get("shape", ""))
	if kind == "":
		if _long_re.search(text) != null:
			kind = "long"
		elif bool(r.pack.get("round", false)) and RegEx.create_from_string("(?i)\\b(cave|cavern|tunnel|mine)\\b").search(text) == null:
			kind = "round"
		else:
			kind = "square"
	if kind == "long":
		var ew := 0
		var ns := 0
		for e in r.exits():
			var d := str(e.get("dir", ""))
			if d in ["east", "west"]:
				ew += 1
			elif d in ["north", "south"]:
				ns += 1
		var length := minf(rad * 1.7, C / 2 - 1.0)
		var width := clampf(rad * 0.38, 1.8, 3.2)
		if ew > ns:
			return {"kind": "rect", "center": ctr, "hx": length, "hz": width, "tier": tier}
		return {"kind": "rect", "center": ctr, "hx": width, "hz": length, "tier": tier}
	if kind == "round":
		return {"kind": "round", "center": ctr, "r": rad, "tier": tier}
	return {"kind": "rect", "center": ctr, "hx": rad, "hz": rad, "tier": tier}


## An upper storey: the building's own footprint, or a hall running inside it.
func _upper_shape(r: Room) -> Dictionary:
	var ctr := center_of(r.cell)
	var base := stack_base(r)
	var bsh := shape_of(base)
	var tier := tier_of(r)
	if str(bsh["kind"]) == "round" and _long_re.search(room_text(r)) != null:
		# a hall that runs alongside the stairs, wide enough to hold their opening
		var g := stair_geom(below_of(r))
		var rr := float(bsh["r"])
		var w := clampf(float(TIER_RADIUS.get(tier, 5.0)) * 0.38, 1.9, 3.0)
		var co := float(g["dd"]) + 1.3 - w
		var half := sqrt(maxf(rr * rr - pow(absf(co) + w, 2.0), 0.0)) - 0.3
		if half > w + 1.0:
			var side: Vector3 = g["side"]
			var along: Vector3 = g["along"]
			var center := ctr + side * co
			if absf(along.x) > 0.5:
				return {"kind": "rect", "center": center, "hx": half, "hz": w, "tier": tier, "upper": true, "endless": true}
			return {"kind": "rect", "center": center, "hx": w, "hz": half, "tier": tier, "upper": true, "endless": true}
	if str(bsh["kind"]) == "round":
		return {"kind": "round", "center": ctr, "r": float(bsh["r"]), "tier": tier, "upper": true}
	return {"kind": "rect", "center": ctr, "hx": float(bsh["hx"]), "hz": float(bsh["hz"]), "tier": tier, "upper": true}


static func wall_point(sh: Dictionary, dir: Vector3, inset := 0.0) -> Vector3:
	var c: Vector3 = sh["center"]
	var d := Vector2(dir.x, dir.z).normalized()
	if str(sh["kind"]) == "round":
		return c + Vector3(d.x, 0, d.y) * (float(sh["r"]) - inset)
	var tx := INF if absf(d.x) < 0.001 else (float(sh["hx"]) - inset) / absf(d.x)
	var tz := INF if absf(d.y) < 0.001 else (float(sh["hz"]) - inset) / absf(d.y)
	return c + Vector3(d.x, 0, d.y) * minf(tx, tz)


func ceiling_height_at(sh: Dictionary, pack: Dictionary) -> float:
	if sh.has("ceiling"):
		return float(sh["ceiling"])
	var wall_h := float(pack.get("wall_h", 2.6))
	if str(sh["kind"]) == "round":
		return wall_h + float(sh["r"]) * 0.45
	if str(sh["kind"]) == "open":
		return 3.0
	return wall_h


# ---------------------------------------------------------------- building

func _build(r: Room) -> Node3D:
	var n := Node3D.new()
	n.name = "room_%d" % r.vnum
	r.pack = Style.for_area(str(r.data.get("area", "")), overrides["areas"])
	r.shape = shape_of(r)
	if not r.is_outdoor():
		r.pack["wall_h"] = TIER_WALL.get(str(r.shape["tier"]), float(r.pack["wall_h"]))
	if has_upper(r):
		r.shape["ceiling"] = FLOOR_H - 0.2   # the floor above
	r.kit = choose_kit(r)
	r.portals = []
	r.shafts = []
	r.apex = Vector3.INF
	var arch := Arch.new(self)
	var reserved := []   # [Vector3, radius]: keep furniture off stairs and wells
	var vertical := _plan_vertical(r)
	if r.is_outdoor():
		_build_outdoor(n, r, arch)
	else:
		_build_indoor(n, r, arch, vertical)
	_build_vertical(n, r, arch, vertical, reserved)

	# furnish from the description, or from the saved layout if we have one
	var pr := Props.new(self, r.pack, r.shape, r.is_outdoor(), str(r.shape["tier"]), r.vnum)
	for e in r.exits():
		pr.exits[str(e.get("dir", ""))] = true
	for p: Portal in r.portals:
		pr.lanes.append([p.mid(), r.shape["center"]])
		if p.kind in ["edge", "door"] and pr.entrance == Vector2(0, 1):
			pr.entrance = Vector2(p.normal.x, p.normal.z)
	for rs in reserved:
		pr.occupy(rs[0], rs[1])
	var key := layout_key(r)
	if r.layout.is_empty() or (r.layout_key != key and not r.layout_locked):
		r.layout = pr.plan(str(r.data.get("name", "")), str(r.data.get("desc", "")))
		var ov := _override(r)
		if bool(ov.get("no_auto_props", false)):
			r.layout = []
		if ov.get("props") is Array:
			for item in ov["props"]:
				if item is Dictionary and item.has("type"):
					r.layout.append_array(pr.place([{"type": str(item["type"]), "count": int(item.get("count", 1)),
						"where": pr.where_of(str(item.get("at", "")).to_lower()), "anchor": -1, "anchor_type": "",
						"on": false, "hanging": bool(item.get("hanging", false)), "big": bool(item.get("big", false)),
						"benches": true, "source": str(item.get("at", ""))}]))
		# nobody lives in the dark: a room with no light of its own gets rushlights
		if not r.is_outdoor() and not bool(ov.get("no_auto_props", false)):
			var lit := false
			for it in r.layout:
				if it is Dictionary and str(it.get("type", "")) in ["hearth", "forge", "lantern", "torch", "candle", "brazier"]:
					lit = true
			if not lit:
				r.layout.append_array(pr.place([{"type": "torch", "count": 2, "where": pr.where_of(""), "anchor": -1,
					"anchor_type": "", "on": false, "hanging": false, "big": false, "benches": false, "source": ""}]))
		r.layout_key = key
		dirty = true
	else:
		for it in r.layout:
			if it is Dictionary:
				pr.occupy(pr._pos(it), float(Props.FOOT.get(str(it.get("type", "")), 0.5)))
	pr.build(n, r.layout)
	r.props = pr
	r.base_taken = pr.taken.duplicate()

	# a fire inside means smoke out through the thatch
	if not r.is_outdoor() and r.apex != Vector3.INF and _has_fire(r):
		arch.smoke(n, r.apex + Vector3(0, 0.1, 0), str(r.shape["tier"]) in ["hall", "great"])
	if r.is_outdoor() and str(r.kit["floor_mode"]) != "full":
		_grass(n, r, pr)

	for p: Portal in r.portals:
		_portal_body(n, p)
	_merge_static(n)
	r.occ_node = Node3D.new()
	r.occ_node.name = "occupants"
	n.add_child(r.occ_node)
	_build_occupants(r)
	return n


func _has_fire(r: Room) -> bool:
	for it in r.layout:
		if it is Dictionary and str(it.get("type", "")) in ["hearth", "forge"]:
			return true
	return _fire_re.search(room_text(r)) != null


## Changes to any of these mean the room is furnished again from scratch.
func layout_key(r: Room) -> String:
	var dirs := []
	for e in r.exits():
		dirs.append(str(e.get("dir", "")))
	dirs.sort()
	return str(hash([LAYOUT_VERSION, r.data.get("name", ""), r.data.get("desc", ""), dirs, _override(r)]))


## Fold every static piece of a room into one mesh per material: a few draw
## calls instead of hundreds, which matters a lot on integrated graphics.
func _merge_static(root: Node3D) -> void:
	var groups := {}
	var victims := []
	_collect_static(root, Transform3D.IDENTITY, groups, victims)
	for key in groups:
		var g: Array = groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g[0] as SurfaceTool).commit()
		mi.material_override = g[1]
		mi.cast_shadow = g[2]
		root.add_child(mi)
	for v in victims:
		v.get_parent().remove_child(v)
		v.free()


func _collect_static(node: Node, xf: Transform3D, groups: Dictionary, victims: Array) -> void:
	for ch in node.get_children():
		if not (ch is Node3D):
			continue
		var cx: Transform3D = xf * (ch as Node3D).transform
		if ch is MeshInstance3D and ch.has_meta("static") and ch.material_override is ShaderMaterial \
				and (ch.material_override as ShaderMaterial).shader == _retro and ch.get_child_count() == 0:
			var key := "%d|%d" % [ch.material_override.get_instance_id(), ch.cast_shadow]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, ch.material_override, ch.cast_shadow]
			(groups[key][0] as SurfaceTool).append_from(ch.mesh, 0, cx)
			victims.append(ch)
			continue
		_collect_static(ch, cx, groups, victims)


func _build_outdoor(n: Node3D, r: Room, arch: Arch) -> void:
	var ctr := center_of(r.cell)
	var k := r.kit
	var p := r.pack
	_ground_body(n, ctr)
	var street := mat(str(k["floor"]))
	match str(k["floor_mode"]):
		"full":
			box(n, Vector3(C, 0.02, C), ctr + Vector3(0, 0.01, 0), street, false)
		"strips":
			box(n, Vector3(5, 0.02, 5), ctr + Vector3(0, 0.012, 0), street, false)
			for d in CARDINAL:
				if r.exit(d).is_empty():
					continue
				var dv := flat(DIRS[d])
				var along := Vector3(absf(dv.x), 0, absf(dv.z))
				var across := Vector3(absf(dv.z), 0, absf(dv.x))
				box(n, along * (C / 2) + across * 3.4 + Vector3(0, 0.02, 0), ctr + dv * (C / 4) + Vector3(0, 0.011, 0), street, false)

	for d in CARDINAL:
		var dv := flat(DIRS[d])
		var e := r.exit(d)
		if e.is_empty():
			_border(n, r, d)
			continue
		var to := int(e.get("to_vnum", -1))
		var nb := room_at(r.cell + DIRS[d])
		var portal := Portal.new()
		portal.dir = d
		portal.to_vnum = to
		portal.normal = dv
		if _is_building(r, d, e, nb):
			var bsh: Dictionary
			if nb != null:
				bsh = nb.shape if not nb.shape.is_empty() else shape_of(nb)
			else:
				bsh = _placeholder_shape(r.cell + DIRS[d], p, str(e.get("to_name", "")), str(r.data.get("desc", "")))
				var bp := p.duplicate()
				bp["wall_h"] = TIER_WALL.get(str(bsh["tier"]), float(p["wall_h"]))
				portal.door_node = _placeholder_building(n, r, r.cell + DIRS[d], REVERSE[d], bsh, bp, str(e.get("to_name", "")), to, arch)
			var door := wall_point(bsh, -dv, 0.0)
			var across := Vector3(absf(dv.z), 0, absf(dv.x))
			portal.kind = "door"
			portal.a = door - across * (DOOR_W / 2)
			portal.b = door + across * (DOOR_W / 2)
			portal.door_key = door_key_of(r.vnum, to)
		else:
			var edge := ctr + dv * (C / 2)
			var across := Vector3(absf(dv.z), 0, absf(dv.x))
			portal.kind = "edge"
			portal.a = edge - across * (C / 2)
			portal.b = edge + across * (C / 2)
			if door_known(r.vnum, to) and (nb == null or nb.is_outdoor()):
				# a gate in a fence along this edge
				portal.a = edge - across * (DOOR_W / 2)
				portal.b = edge + across * (DOOR_W / 2)
				portal.door_key = door_key_of(r.vnum, to)
				portal.door_node = _gate(n, r, d, arch)
		r.portals.append(portal)


## Is the room through this exit a building (rather than more open ground)?
func _is_building(r: Room, d: String, e: Dictionary, nb: Room) -> bool:
	if nb != null:
		return not nb.is_outdoor()
	if _building_re.search(str(e.get("to_name", ""))) != null:
		return true
	# "two huge ironbound doors set in the walls of the Dun tower before you"
	if door_known(r.vnum, int(e.get("to_vnum", -1))):
		var low := str(r.data.get("desc", "")).to_lower()
		if RegEx.create_from_string("\\bdoors?\\b").search(low) != null and _building_re.search(low + " " + room_text(r)) != null:
			return true
		if RegEx.create_from_string("\\b(walls?|building|tower|house|hall)\\b").search(low) != null:
			return true
	return false


func _ground_body(n: Node3D, ctr: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(C + 0.2, 1.0, C + 0.2)
	cs.shape = bs
	body.add_child(cs)
	body.position = ctr + Vector3(0, -0.5, 0)
	n.add_child(body)


func _floor_body(n: Node3D, sh: Dictionary) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if str(sh["kind"]) == "round":
		var cy := CylinderShape3D.new()
		cy.radius = float(sh["r"]) + 0.3
		cy.height = 0.4
		cs.shape = cy
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(sh["hx"]) * 2 + 0.6, 0.4, float(sh["hz"]) * 2 + 0.6)
		cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(sh["center"]) + Vector3(0, -0.2, 0)
	n.add_child(body)


## What lies along an edge with no way through, going by the description.
func _border(n: Node3D, r: Room, d: String) -> void:
	var ctr := center_of(r.cell)
	var low := room_text(r).to_lower()
	var dv := flat(DIRS[d])
	var along := Vector3(absf(dv.z), 0, absf(dv.x))
	var mid := ctr + dv * (C / 2 - 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([r.vnum, d])
	var p := r.pack
	# always solid, whatever it looks like
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = along * C + Vector3(absf(dv.x), 0, absf(dv.z)) * 0.6 + Vector3(0, 4.0, 0)
	cs.shape = bs
	body.add_child(cs)
	body.position = mid + Vector3(0, 2.0, 0)
	n.add_child(body)
	if RegEx.create_from_string("\\b(palisade|stockade|stakes|fence)\\b").search(low) != null:
		box(n, along * C + Vector3(absf(dv.x), 0, absf(dv.z)) * 0.4 + Vector3(0, 3.2, 0), mid + Vector3(0, 1.6, 0), mat("palisade"), false)
	elif RegEx.create_from_string("\\b(hedge|hedges|hedgerow)\\b").search(low) != null:
		box(n, along * C + Vector3(absf(dv.x), 0, absf(dv.z)) * 1.0 + Vector3(0, 1.8, 0), mid + Vector3(0, 0.9, 0), mat("hedge", Color.WHITE, 0.4), false)
	elif RegEx.create_from_string("\\b(stone walls?|walls?|dyke)\\b").search(low) != null:
		box(n, along * C + Vector3(absf(dv.x), 0, absf(dv.z)) * 0.8 + Vector3(0, 1.2, 0), mid + Vector3(0, 0.6, 0), mat(str(p["boundary"])), false)
	elif RegEx.create_from_string("\\b(forest|woods?|trees|grove|thicket|wood's edge|oaks|wilderness)\\b").search(low) != null:
		for i in 7:
			var t := (i + rng.randf_range(0.1, 0.9)) / 7.0 - 0.5
			var at := mid + along * t * C + dv * rng.randf_range(0.0, 2.5)
			billboard(n, SpriteGen.tree(rng.randi()), at, rng.randf_range(6.0, 9.5))
			cylinder(n, 0.28, 2.2, at + Vector3(0, 1.1, 0), mat("darktimber"), false)
		for i in 6:
			var at := mid + along * rng.randf_range(-0.5, 0.5) * C - dv * rng.randf_range(0.0, 1.2)
			billboard(n, SpriteGen.bush(rng.randi()), at, rng.randf_range(1.0, 1.7))
	elif RegEx.create_from_string("\\b(river|stream|brook|lake|pond|water's edge|shore)\\b").search(low) != null:
		box(n, along * C + Vector3(absf(dv.x), 0, absf(dv.z)) * 3.0 + Vector3(0, 0.02, 0), mid + dv * 1.0 + Vector3(0, 0.02, 0), mat("water"), false)
	else:
		# open country: just a scatter of scrub and stones to mark the edge
		for i in 5:
			var at := mid + along * rng.randf_range(-0.48, 0.48) * C + dv * rng.randf_range(-0.4, 1.0)
			if rng.randf() < 0.6:
				billboard(n, SpriteGen.bush(rng.randi()), at, rng.randf_range(0.8, 1.4))
			else:
				var hh := rng.randf_range(0.3, 0.7)
				box(n, Vector3(0.7, hh, 0.5), at + Vector3(0, hh / 2, 0), mat(str(p["boundary"])), false, rng.randf())


## A fence with a wicker gate in the middle of an edge.
func _gate(n: Node3D, r: Room, d: String, arch: Arch) -> Node3D:
	var ctr := center_of(r.cell)
	var dv := flat(DIRS[d])
	var along := Vector3(absf(dv.z), 0, absf(dv.x))
	var edge := ctr + dv * (C / 2 - 0.3)
	var side := (C - DOOR_W - 0.4) / 2
	for s: int in [-1, 1]:
		box(n, along * side + Vector3(absf(dv.x), 0, absf(dv.z)) * 0.15 + Vector3(0, 1.3, 0),
			edge + along * s * (DOOR_W / 2 + 0.2 + side / 2) + Vector3(0, 0.65, 0), mat("wattle"), true)
		box(n, Vector3(0.22, 1.8, 0.22), edge + along * s * (DOOR_W / 2 + 0.1) + Vector3(0, 0.9, 0), mat(str(r.pack["post"])), true)
	var pk := r.pack.duplicate()
	pk["door"] = "wattle"
	var leaf := arch.door_leaf(n, edge, dv, pk, true, false)
	leaf.scale = Vector3(1, 0.6, 1)
	return leaf


func _placeholder_shape(cell: Vector3i, p: Dictionary, name := "", seen_from := "") -> Dictionary:
	var ctr := center_of(cell)
	var tier := tier_of_text(name, "")
	# what the room outside says about it: "the walls of the Dun tower", "tremendous doors"
	var low := seen_from.to_lower()
	if RegEx.create_from_string("\\b(dun|tower|fort|fortress|keep|palace|stronghold|tremendous|enormous|massive|huge)\\b").search(low) != null:
		tier = "great"
	elif tier == "house" and RegEx.create_from_string("\\b(hut|cottage|hovel|shed)\\b").search(low) != null:
		tier = "hut"
	var rad: float = TIER_RADIUS.get(tier, 4.9)
	if bool(p.get("round", false)):
		return {"kind": "round", "center": ctr, "r": rad, "tier": tier}
	return {"kind": "rect", "center": ctr, "hx": rad, "hz": rad, "tier": tier}


## A building we've only seen from outside: shell, roof, door, sign, yard.
func _placeholder_building(n: Node3D, from: Room, cell: Vector3i, door_dir: String, sh: Dictionary, p: Dictionary,
		sign: String, to_vnum: int, arch: Arch) -> Node3D:
	var c: Vector3 = sh["center"]
	var dv := flat(DIRS[door_dir])
	var ang := atan2(dv.z, dv.x)
	var tier := str(sh["tier"])
	var low := room_text(from).to_lower()
	var wide := RegEx.create_from_string("\\b(doors|double doors|great doors|huge doors|gates)\\b").search(low) != null or tier == "great"
	var iron := low.contains("iron")
	if str(sh["kind"]) == "round":
		var info := arch.roundhouse(n, sh, p, {"doors": [ang], "windows": [], "outside": true, "inside": false,
			"art": tier != "hut"})
		var inner := cylinder(n, float(sh["r"]) - 0.05, float(p["wall_h"]), c + Vector3(0, float(p["wall_h"]) / 2, 0), void_mat(), false, false)
		(inner.mesh as CylinderMesh).cap_top = false
		cylinder(n, float(sh["r"]) - 0.05, 0.02, c + Vector3(0, 0.02, 0), void_mat(), false, false)
		if tier in ["hall", "great"] or _fire_re.search(sign) != null or RegEx.create_from_string("(?i)\\b(inn|tavern|house|home|cottage)\\b").search(sign) != null:
			arch.smoke(n, Vector3(info["apex"]) + Vector3(0, 0.1, 0), tier in ["hall", "great"])
	else:
		_walls(n, sh, [door_dir], p, true, false)
		_roof(n, sh, p, false, arch)
		box(n, Vector3(float(sh["hx"]) * 2 - 0.2, float(p["wall_h"]), float(sh["hz"]) * 2 - 0.2), c + Vector3(0, float(p["wall_h"]) / 2, 0), void_mat(), false)
	var at := wall_point(sh, dv, -0.12)
	var leaf := arch.door_leaf(n, at, dv, p, wide, iron)
	Arch.set_door_open(leaf, not door_closed(from.vnum, to_vnum), false)
	if sign != "":
		var m := Marker3D.new()
		m.position = wall_point(sh, dv, -0.6) + Vector3(0, DOOR_H + 0.45, 0)
		m.set_meta("text", sign)
		m.set_meta("kind", "sign")
		m.add_to_group("l3d_label")
		n.add_child(m)
	_yard(n, cell, sh, [door_dir], [], p)
	return leaf


func _build_indoor(n: Node3D, r: Room, arch: Arch, vertical: Dictionary) -> void:
	var sh := r.shape
	var p := r.pack
	var c: Vector3 = sh["center"]
	var ground := r.cell.y == 0
	var tier := str(sh["tier"])
	var door_dirs := []
	var outside_dirs := []
	var corridor_dirs := []
	for d in CARDINAL:
		var e := r.exit(d)
		if e.is_empty():
			continue
		door_dirs.append(d)
		var nb := room_at(r.cell + DIRS[d])
		if nb != null and nb.is_outdoor():
			outside_dirs.append(d)
		elif nb == null and ground:
			outside_dirs.append(d)  # unexplored: on the ground floor it's most likely outdoors
		else:
			corridor_dirs.append(d)
	var art := tier in ["hall", "great"]
	var low := str(r.data.get("desc", "")).to_lower()
	var wide := RegEx.create_from_string("\\b(doors|double doors|great doors|huge doors)\\b").search(low) != null or tier == "great"
	var iron := low.contains("ironbound") or low.contains("iron-bound")
	var upper := bool(sh.get("upper", false))
	var storeys := 1 if upper else storeys_of(r)
	var shell_h := float(p["wall_h"]) + FLOOR_H * (storeys - 1)
	var floors := []
	for k in range(1, storeys):
		floors.append(FLOOR_H * k)

	if upper:
		# the walls and roof belong to the floor below; this storey is just what's in it
		if str(sh["kind"]) == "rect":
			var hp := p.duplicate()
			if str(hp["int_wall"]) == "wattle":
				hp["int_wall"] = "daub"   # plastered partitions, like the walls downstairs
			_walls(n, sh, door_dirs, hp, false, true)
			box(n, Vector3(float(sh["hx"]) * 2, 0.12, float(sh["hz"]) * 2), c + Vector3(0, float(p["wall_h"]) + 0.06, 0), mat(str(p["int_ceiling"])), false)
			if bool(sh.get("endless", false)):
				_endless_ends(n, sh, float(p["wall_h"]))
	elif str(sh["kind"]) == "round":
		var door_angles := []
		for d in door_dirs:
			var dv: Vector3i = DIRS[d]
			door_angles.append(atan2(float(dv.z), float(dv.x)))
		var wins := _window_angles(r, door_angles, vertical)
		var all_wins := wins.duplicate()
		# windows for each storey above, from that room's own description if we've been up
		var upper_wins := []
		for k in range(1, storeys):
			var rk := storey_room(r, k)
			var avoid := door_angles.duplicate()
			if vertical.has("up"):
				avoid.append(float(vertical["up"]["angle"]))
			for a in _window_angles(rk if rk != null else r, avoid, {}):
				all_wins.append([a, FLOOR_H * k])
				upper_wins.append([a, FLOOR_H * k])
		var info := arch.roundhouse(n, sh, p, {"doors": door_angles, "windows": all_wins, "outside": ground,
			"inside": true, "art": tier != "hut", "height": shell_h, "floors": floors})
		r.apex = info["apex"]
		if float(sh["r"]) >= 6.0:
			_post_ring(n, sh, p, art, FLOOR_H - 0.12 if storeys > 1 else -1.0)
		for uw in upper_wins:
			var ua: float = uw[0]
			_shaft(n, r, c + Vector3(cos(ua), 0, sin(ua)) * float(sh["r"]) + Vector3(0, float(uw[1]) + (Arch.WINDOW_SILL + Arch.WINDOW_TOP) / 2, 0),
				Vector3(cos(ua), 0, sin(ua)), Vector2(Arch.WINDOW_W, Arch.WINDOW_TOP - Arch.WINDOW_SILL))
		var floor_m := mat(str(r.kit.get("int_floor", p["int_floor"])))
		# a faceted disc sits inside its radius between corners; oversize it to reach under the wall
		cylinder(n, (float(sh["r"]) + 0.05) / cos(PI / 12.0), 0.04, c + Vector3(0, 0.0, 0), floor_m, false, false)
		for a in wins:
			_shaft(n, r, c + Vector3(cos(a), 0, sin(a)) * float(sh["r"]) + Vector3(0, (Arch.WINDOW_SILL + Arch.WINDOW_TOP) / 2, 0),
				Vector3(cos(a), 0, sin(a)), Vector2(Arch.WINDOW_W, Arch.WINDOW_TOP - Arch.WINDOW_SILL))
	else:
		var tall := p.duplicate()
		tall["wall_h"] = shell_h
		_walls(n, sh, door_dirs, tall, ground, true)
		var floor_m := mat(str(r.kit.get("int_floor", p["int_floor"])))
		box(n, Vector3(float(sh["hx"]) * 2, 0.04, float(sh["hz"]) * 2), c, floor_m, false)
		if storeys == 1:
			box(n, Vector3(float(sh["hx"]) * 2, 0.12, float(sh["hz"]) * 2), c + Vector3(0, float(p["wall_h"]) + 0.06, 0), mat(str(p["int_ceiling"])), false)
		if ground:
			_roof(n, sh, tall, false, arch)
			r.apex = c + Vector3(0, shell_h + minf(float(sh["hx"]), float(sh["hz"])) * float(p["roof_pitch"]), 0)
	if not upper:
		_floor_body(n, sh)
	if ground:
		_ground_body(n, center_of(r.cell))

	for d in door_dirs:
		var dv := flat(DIRS[d])
		var e := r.exit(d)
		var to := int(e.get("to_vnum", -1))
		var door := wall_point(sh, dv, 0.0)
		var across := Vector3(absf(dv.z), 0, absf(dv.x))
		var portal := Portal.new()
		portal.dir = d
		portal.to_vnum = to
		portal.normal = dv
		if d in outside_dirs:
			portal.kind = "door"
			portal.a = door - across * (DOOR_W / 2)
			portal.b = door + across * (DOOR_W / 2)
			portal.door_key = door_key_of(r.vnum, to)
			portal.door_node = arch.door_leaf(n, wall_point(sh, dv, -0.12), dv, p, wide, iron)
			Arch.set_door_open(portal.door_node, not door_closed(r.vnum, to), false)
			if str(sh["kind"]) == "round":
				_shaft(n, r, door + Vector3(0, DOOR_H / 2, 0), dv, Vector2(DOOR_W, DOOR_H))
		else:
			var edge := c + dv * (C / 2)
			_corridor(n, door, edge, dv, p, room_at(r.cell + DIRS[d]) == null)
			portal.kind = "edge"
			portal.a = edge - across * (DOOR_W / 2)
			portal.b = edge + across * (DOOR_W / 2)
			if door_known(r.vnum, to):
				portal.door_key = door_key_of(r.vnum, to)
				portal.door_node = arch.door_leaf(n, wall_point(sh, dv, -0.12), dv, p, false, iron)
				Arch.set_door_open(portal.door_node, not door_closed(r.vnum, to), false)
		r.portals.append(portal)
	if ground:
		_yard(n, r.cell, sh, outside_dirs, corridor_dirs, p)


## Where windows go: as many as the description mentions; halls get a couple
## of small shuttered openings anyway. Away from doors and stairs.
func _window_angles(r: Room, door_angles: Array, vertical: Dictionary) -> Array:
	var low := str(r.data.get("desc", "")).to_lower()
	var want := 0
	if RegEx.create_from_string("\\bwindows\\b").search(low) != null:
		want = 3
	elif RegEx.create_from_string("\\b(window|shutter|shutters)\\b").search(low) != null:
		want = 1
	elif tier_of(r) in ["hall", "great"]:
		want = 2
	if want == 0:
		return []
	var avoid := door_angles.duplicate()
	for k in vertical:
		avoid.append(float(vertical[k]["angle"]))
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = r.vnum * 31
	for i in want:
		var best := 0.0
		var best_score := -1.0
		for k in 32:
			var a := k * TAU / 32 + rng.randf() * 0.05
			var score := PI
			for b in avoid + out:
				score = minf(score, absf(angle_difference(a, float(b))))
			if score > best_score:
				best_score = score
				best = a
		if best_score < 0.5:
			break
		out.append(best)
	return out


## A soft beam of daylight or moonlight through an opening (shown by the view
## when the sun or moon is on that side).
func _shaft(n: Node3D, r: Room, at: Vector3, outward: Vector3, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 1.0)
	mi.mesh = bm
	mi.material_override = _shaft_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.visible = false
	mi.set_meta("outward", outward)
	mi.set_meta("size", size)
	mi.add_to_group("l3d_shaft")
	n.add_child(mi)
	r.shafts.append(mi)


func _shaft_mat() -> Material:
	if _mats.has("shaft"):
		return _mats["shaft"]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/shaft.gdshader")
	_mats["shaft"] = m
	return m


# ---------------------------------------------------------------- storeys

## The indoor room straight above r that its "up" exit leads to, if we've been there.
func above_of(r: Room) -> Room:
	var e := r.exit("up")
	if e.is_empty():
		return null
	var nb: Room = rooms.get(int(e.get("to_vnum", -1)))
	if nb == null or nb.is_outdoor() or nb.cell != r.cell + Vector3i(0, 1, 0):
		return null
	return nb


## The indoor room straight below r that its "down" exit leads to.
func below_of(r: Room) -> Room:
	var e := r.exit("down")
	if e.is_empty():
		return null
	var nb: Room = rooms.get(int(e.get("to_vnum", -1)))
	if nb == null or nb.is_outdoor() or nb.cell != r.cell - Vector3i(0, 1, 0):
		return null
	return nb


## r has stairs up to another storey of the same building.
func has_upper(r: Room) -> bool:
	if r.is_outdoor() or r.exit("up").is_empty() or _ladder_re.search(room_text(r)) != null:
		return false
	var to: Room = rooms.get(int(r.exit("up").get("to_vnum", -1)))
	return to == null or above_of(r) != null


## r is an upper storey inside the building below it.
func is_upper(r: Room) -> bool:
	if r.is_outdoor():
		return false
	var b := below_of(r)
	return b != null and has_upper(b)


## The ground floor of the building r is in.
func stack_base(r: Room) -> Room:
	var x := r
	for i in 12:
		if not is_upper(x):
			break
		x = below_of(x)
	return x


## How many storeys tall the building standing on `base` is.
func storeys_of(base: Room) -> int:
	var n := 1
	var x := base
	for i in 12:
		if x == null or not has_upper(x):
			break
		n += 1
		x = above_of(x)
	return n


## Every room in the building we've seen, bottom up.
func stack_of(r: Room) -> Array:
	var out := []
	var x := stack_base(r)
	for i in 12:
		if x == null:
			break
		out.append(x)
		x = above_of(x) if has_upper(x) else null
	return out


## The room `k` storeys above `base` (null if we haven't been up there).
func storey_room(base: Room, k: int) -> Room:
	var x := base
	for i in k:
		if x == null:
			return null
		x = above_of(x)
	return x


## Where the stairs from r up to the storey above run. Shared by r (which
## builds them) and the room above (which has the opening at their top).
func stair_geom(r: Room) -> Dictionary:
	var sh := shape_of(r)
	var c: Vector3 = sh["center"]
	var plan := _plan_vertical(r)
	var a: float = plan["up"]["angle"] if plan.has("up") else 0.0
	var side := Vector3(cos(a), 0, sin(a))
	var along := Vector3(-side.z, 0, side.x)
	var run := FLOOR_H / tan(deg_to_rad(37.0))
	var total := run + 1.2
	var reach := float(sh.get("r", minf(float(sh.get("hx", 4.0)), float(sh.get("hz", 4.0)))))
	var dd := 0.0
	if str(sh["kind"]) == "round":
		# a few steps in from the wall, so the floor above has room round the opening
		dd = clampf(reach - 3.0, 0.0, sqrt(maxf(reach * reach - pow(total / 2 + 0.3, 2.0), 0.0)))
	else:
		dd = maxf(reach - 1.6, 0.0)
	var line_mid := c + side * dd
	var bottom := line_mid - along * (total / 2)
	return {"side": side, "along": along, "dd": dd, "run": run, "total": total, "bottom": bottom,
		"top": bottom + along * (run + 0.6) + Vector3(0, FLOOR_H, 0), "center": c}


## The floor of the storey above r: planks on joists, with the stairwell
## opening where r's stairs come up. Built by the room below so it's there
## (and walkable) from either floor.
func _deck(n: Node3D, r: Room, g: Dictionary) -> void:
	var sh := r.shape
	var c: Vector3 = sh["center"]
	var y := c.y + FLOOR_H
	var floor_poly := PackedVector2Array()
	if str(sh["kind"]) == "round":
		var rr := (float(sh["r"]) + 0.05) / cos(PI / 40.0)
		for i in 40:
			var a := i * TAU / 40.0
			floor_poly.append(Vector2(c.x + cos(a) * rr, c.z + sin(a) * rr))
	else:
		var hx := float(sh["hx"]) + 0.05
		var hz := float(sh["hz"]) + 0.05
		for q: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
			floor_poly.append(Vector2(c.x, c.z) + q)
	var along: Vector3 = g["along"]
	var side: Vector3 = g["side"]
	var b: Vector3 = g["bottom"]
	var u0 := 1.2
	var u1 := float(g["run"]) + 0.05
	var vh := 0.72
	var big := 60.0
	var corner := func(u: float, v: float) -> Vector2:
		var q := b + along * u + side * v
		return Vector2(q.x, q.z)
	var regions := [
		[corner.call(-big, -big), corner.call(big, -big), corner.call(big, -vh), corner.call(-big, -vh)],
		[corner.call(-big, vh), corner.call(big, vh), corner.call(big, big), corner.call(-big, big)],
		[corner.call(-big, -vh), corner.call(u0, -vh), corner.call(u0, vh), corner.call(-big, vh)],
		[corner.call(u1, -vh), corner.call(big, -vh), corner.call(big, vh), corner.call(u1, vh)],
	]
	var mb := Arch.MB.new()
	var top_m := mat("wood")
	var under_m := mat("beams")
	var faces := PackedVector3Array()
	var drop := Vector3(0, 0.14, 0)
	for reg in regions:
		var rp := PackedVector2Array(reg)
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(floor_poly, rp):
			var idx := Geometry2D.triangulate_polygon(piece)
			for t in range(0, idx.size(), 3):
				var p0 := Vector3(piece[idx[t]].x, y, piece[idx[t]].y)
				var p1 := Vector3(piece[idx[t + 1]].x, y, piece[idx[t + 1]].y)
				var p2 := Vector3(piece[idx[t + 2]].x, y, piece[idx[t + 2]].y)
				if (p1 - p0).cross(p2 - p0).y < 0.0:
					var tmp := p1
					p1 = p2
					p2 = tmp
				mb.tri(top_m, p0, p1, p2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				mb.tri(under_m, p0 - drop, p2 - drop, p1 - drop, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				faces.append_array([p0, p1, p2])
	mb.commit(n)
	# walkable
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	shp.set_faces(faces)
	cs.shape = shp
	body.add_child(cs)
	n.add_child(body)
	# joists underneath, stopping at the opening
	var post := mat(str(r.pack["post"]))
	var reach := float(sh.get("r", maxf(float(sh.get("hx", 4.0)), float(sh.get("hz", 4.0))))) + 0.1
	var v := -reach * 2.0
	while v <= reach * 2.0:
		for sp in _chord_spans(c, sh, b, along, side, v):
			var pieces := [[sp[0], sp[1]]]
			if absf(v) < vh + 0.1:
				pieces = [[sp[0], minf(sp[1], u0)], [maxf(sp[0], u1), sp[1]]]
			for pc in pieces:
				var la: float = pc[0]
				var lb: float = pc[1]
				if lb - la < 0.3:
					continue
				var mid := b + along * ((la + lb) * 0.5) + side * v + Vector3(0, FLOOR_H - 0.25, 0)
				var bx := box(n, Vector3(0.16, 0.22, lb - la), mid, post, false)
				bx.rotation.y = atan2(along.x, along.z)
		v += 1.1
	# a trim round the opening, seen from below
	for s2: int in [-1, 1]:
		var mid2 := b + along * ((u0 + u1) * 0.5) + side * (s2 * (vh + 0.06)) + Vector3(0, FLOOR_H - 0.2, 0)
		var trim := box(n, Vector3(0.12, 0.3, u1 - u0), mid2, post, false)
		trim.rotation.y = atan2(along.x, along.z)


## Along the line `bottom + side*v`, the stretches inside the floor: [[u_from, u_to]].
func _chord_spans(c: Vector3, sh: Dictionary, b: Vector3, along: Vector3, side: Vector3, v: float) -> Array:
	var o := b + side * v - c
	if str(sh["kind"]) == "round":
		var rr := float(sh["r"]) - 0.1
		var bb := 2.0 * (o.x * along.x + o.z * along.z)
		var cc := o.x * o.x + o.z * o.z - rr * rr
		var disc := bb * bb - 4.0 * cc
		if disc <= 0.0:
			return []
		var sq := sqrt(disc)
		return [[(-bb - sq) / 2.0, (-bb + sq) / 2.0]]
	var lo := -1000.0
	var hi := 1000.0
	for ax in [[o.x, along.x, float(sh["hx"]) - 0.1], [o.z, along.z, float(sh["hz"]) - 0.1]]:
		var o1: float = ax[0]
		var d1: float = ax[1]
		var lim: float = ax[2]
		if absf(d1) < 0.0001:
			if absf(o1) > lim:
				return []
			continue
		var t0 := (-lim - o1) / d1
		var t1 := (lim - o1) / d1
		lo = maxf(lo, minf(t0, t1))
		hi = minf(hi, maxf(t0, t1))
	return [[lo, hi]] if hi > lo else []


## Rails round the stairwell opening, on the floor above.
func _hole_rails(n: Node3D, g: Dictionary, p: Dictionary) -> void:
	var along: Vector3 = g["along"]
	var side: Vector3 = g["side"]
	var b: Vector3 = Vector3(g["bottom"]) + Vector3(0, FLOOR_H, 0)
	var u0 := 1.2
	var u1 := float(g["run"]) + 0.05
	var vh := 0.8
	var wood := mat(str(p["furniture"]))
	var yaw := atan2(along.x, along.z)
	for s2: int in [-1, 1]:
		var mid := b + along * ((u0 + u1) * 0.5) + side * (s2 * vh)
		var rail := box(n, Vector3(0.07, 0.07, u1 - u0), mid + Vector3(0, 0.95, 0), wood, false)
		rail.rotation.y = yaw
		for k in 5:
			box(n, Vector3(0.06, 0.95, 0.06), b + along * lerpf(u0, u1, k / 4.0) + side * (s2 * vh) + Vector3(0, 0.47, 0), wood, false)
	var end := box(n, Vector3(0.07, 0.07, vh * 2), b + along * u0 + Vector3(0, 0.95, 0), wood, false)
	end.rotation.y = atan2(side.x, side.z)
	box(n, Vector3(0.06, 0.95, 0.06), b + along * u0 + Vector3(0, 0.47, 0), wood, false)
	# a solid rail you can't walk through (the opening is still open at the stair end)
	for s2: int in [-1, 1]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.12, 1.0, u1 - u0)
		cs.shape = bs
		body.add_child(cs)
		body.position = b + along * ((u0 + u1) * 0.5) + side * (s2 * vh) + Vector3(0, 0.5, 0)
		body.rotation.y = yaw
		n.add_child(body)
	var body2 := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(vh * 2, 1.0, 0.12)
	cs2.shape = bs2
	body2.add_child(cs2)
	body2.position = b + along * u0 + Vector3(0, 0.5, 0)
	body2.rotation.y = yaw
	n.add_child(body2)


## Dark that deepens toward each end of a hall that goes on further than it can.
func _endless_ends(n: Node3D, sh: Dictionary, h: float) -> void:
	var c: Vector3 = sh["center"]
	var hx := float(sh["hx"])
	var hz := float(sh["hz"])
	var long_x := hx > hz
	var half := hx if long_x else hz
	var wide := hz if long_x else hx
	var dir := Vector3(1, 0, 0) if long_x else Vector3(0, 0, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.01, 0.008, 0.006, 0.2)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s2: int in [-1, 1]:
		for k in 5:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(wide * 2, h)
			mi.mesh = q
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = c + dir * (s2 * (half - 0.15 - k * 0.7)) + Vector3(0, h / 2, 0)
			mi.rotation.y = PI / 2 if long_x else 0.0
			n.add_child(mi)


## Stairs and wells: which way each up/down exit goes and where it sits.
func _plan_vertical(r: Room) -> Dictionary:
	var out := {}
	if r.is_outdoor():
		return out
	var text := room_text(r)
	if _ladder_re.search(text) != null:
		return out
	var door_angles := []
	for d in CARDINAL:
		if not r.exit(d).is_empty():
			var dv: Vector3i = DIRS[d]
			door_angles.append(atan2(float(dv.z), float(dv.x)))
	var used := []
	for d in ["up", "down"]:
		if r.exit(d).is_empty():
			continue
		var best := 0.0
		var best_score := -1.0
		# stairs inside a building of several storeys run square to it, so the
		# rooms above line up with them
		var square: bool = d == "up" and has_upper(r)
		for k in (4 if square else 8):
			var a := k * TAU / 4 if square else k * TAU / 8 + 0.2
			var score := PI
			for b in door_angles + used:
				score = minf(score, absf(angle_difference(a, float(b))))
			if score > best_score:
				best_score = score
				best = a
		used.append(best)
		out[d] = {"angle": best}
	return out


func _build_vertical(n: Node3D, r: Room, arch: Arch, vertical: Dictionary, reserved: Array) -> void:
	var c := center_of(r.cell)
	var sh := r.shape
	var reach := 0.0
	if not sh.is_empty():
		reach = float(sh.get("r", minf(float(sh.get("hx", 4.0)), float(sh.get("hz", 4.0)))))
	var spots := {"up": Vector3(-0.55, 0, 0.55), "down": Vector3(0.55, 0, 0.55)}
	for e in r.exits():
		var d := str(e.get("dir", ""))
		if d in CARDINAL or not DIRS.has(d):
			continue
		var portal := Portal.new()
		portal.dir = d
		portal.to_vnum = int(e.get("to_vnum", -1))
		if d == "up" and has_upper(r):
			var g := stair_geom(r)
			var along_s: Vector3 = g["along"]
			var top_s := arch.stairs(n, g["bottom"], along_s, FLOOR_H, r.pack)
			portal.kind = "stairs"
			portal.a = top_s
			portal.b = top_s
			portal.normal = along_s
			portal.land = Vector3(g["bottom"]) - along_s * 0.9 + Vector3(0, 0.05, 0)
			portal.land_face = -along_s
			for k in 7:
				reserved.append([Vector3(g["bottom"]) + along_s * (float(g["total"]) * k / 6.0), 1.1])
			reserved.append([Vector3(g["bottom"]) - along_s * 1.0, 0.9])
			_deck(n, r, g)
			r.portals.append(portal)
			continue
		if d == "down" and is_upper(r):
			var g := stair_geom(below_of(r))
			var along_s: Vector3 = g["along"]
			var top_s: Vector3 = Vector3(g["top"])
			top_s.y = center_of(r.cell).y
			portal.kind = "stairs_down"
			portal.a = top_s
			portal.b = top_s
			portal.normal = -along_s
			portal.land = top_s + along_s * 0.5 + Vector3(0, 0.05, 0)
			portal.land_face = along_s
			_hole_rails(n, g, r.pack)
			var bt: Vector3 = Vector3(g["bottom"])
			bt.y = center_of(r.cell).y
			for k in 6:
				reserved.append([bt + along_s * (float(g["run"]) * k / 5.0), 1.2])
			reserved.append([top_s + along_s * 0.6, 1.0])
			r.portals.append(portal)
			continue
		if vertical.has(d):
			var a: float = vertical[d]["angle"]
			var side := Vector3(cos(a), 0, sin(a))
			var along := Vector3(-side.z, 0, side.x)
			var total := FLOOR_H / tan(deg_to_rad(37.0)) + 1.2
			var dd := 0.0
			if str(sh["kind"]) == "round":
				dd = minf(reach - 1.0, sqrt(maxf(reach * reach - pow(total / 2 + 0.3, 2.0), 0.0)))
				if d == "up":
					# keep the top of the flight under the thatch with headroom:
					# the roof's underside drops toward the eaves
					var pk := r.pack
					var eave_r := reach + 0.24 + 0.95
					var under_eave := float(pk["wall_h"]) - 0.25 - 0.42
					var rho_max := eave_r - (FLOOR_H + 2.0 - under_eave) / maxf(float(pk["roof_pitch"]), 0.3)
					var fit := sqrt(maxf(rho_max * rho_max - pow(total / 2, 2.0), 0.0))
					dd = clampf(fit, 0.0, dd)
			else:
				dd = reach - 1.0
			var line_mid := c + side * dd
			if d == "up":
				var bottom := line_mid - along * (total / 2)
				var top := arch.stairs(n, bottom, along, FLOOR_H, r.pack)
				portal.kind = "stairs"
				portal.a = top
				portal.b = top
				portal.normal = along
				portal.land = top - along * 0.2
				portal.land_face = -along
				for k in 6:
					reserved.append([bottom + along * (total * k / 5.0), 1.0])
			else:
				arch.stairwell(n, line_mid, along, r.pack)
				portal.kind = "well"
				portal.a = line_mid
				portal.b = line_mid
				portal.normal = -along
				portal.land = line_mid + along * 2.0
				portal.land_face = along
				reserved.append([line_mid, 1.6])
				reserved.append([line_mid + along * 1.6, 0.8])
			r.portals.append(portal)
			continue
		# ladders, outdoor climbs and diagonal ways: a marked spot on the ground
		var off: Vector3 = spots.get(d, flat(DIRS[d]).normalized()) * maxf(reach - 1.6, 1.5)
		var pos := c + off
		portal.kind = "pad"
		portal.a = pos
		portal.b = pos
		portal.normal = off.normalized()
		r.portals.append(portal)
		reserved.append([pos, 1.0])
		box(n, Vector3(1.4, 0.04, 1.4), pos + Vector3(0, 0.02, 0), mat("pad"), false)
		if d == "up" or d == "down":
			var lad := Node3D.new()
			lad.position = pos + off.normalized() * 0.55
			lad.rotation.y = atan2(off.x, off.z)
			n.add_child(lad)
			var lh := 3.2 if d == "up" else 1.2
			for s: int in [-1, 1]:
				var rail := box(lad, Vector3(0.08, lh, 0.08), Vector3(s * 0.28, lh / 2, 0), mat("timber"), false)
				rail.rotation.x = -0.18
			for k in int(lh / 0.35):
				var y := 0.3 + k * 0.35
				box(lad, Vector3(0.6, 0.05, 0.05), Vector3(0, y, -(y - lh / 2) * 0.18), mat("timber"), false)
		var m := Marker3D.new()
		m.position = pos + Vector3(0, 0.6, 0)
		m.set_meta("text", d.to_upper())
		m.set_meta("kind", "exit")
		m.add_to_group("l3d_label")
		n.add_child(m)


## Scattered tufts of grass over open ground, swaying a little.
func _grass(n: Node3D, r: Room, pr: Props) -> void:
	var ctr := center_of(r.cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = r.vnum * 977
	var strips := str(r.kit["floor_mode"]) == "strips"
	var pts := []
	for i in 300:
		var p := ctr + Vector3(rng.randf_range(-C / 2 + 0.5, C / 2 - 0.5), 0, rng.randf_range(-C / 2 + 0.5, C / 2 - 0.5))
		var lx := absf(p.x - ctr.x)
		var lz := absf(p.z - ctr.z)
		if strips:
			var on_path := lx < 2.6 and lz < 2.6
			for d in CARDINAL:
				if r.exit(d).is_empty():
					continue
				var dv := flat(DIRS[d])
				if dv.x != 0 and lz < 1.9 and (p.x - ctr.x) * dv.x > 0:
					on_path = true
				if dv.z != 0 and lx < 1.9 and (p.z - ctr.z) * dv.z > 0:
					on_path = true
			if on_path:
				continue
		if not pr._clear_of_things(p, 0.3):
			continue
		pts.append(p)
	if pts.is_empty():
		return
	for variant in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.42)
		q.center_offset = Vector3(0, 0.2, 0)
		mm.mesh = q
		var mine := []
		for i in pts.size():
			if i % 3 == variant:
				mine.append(pts[i])
		mm.instance_count = mine.size() * 2
		for i in mine.size():
			var s := rng.randf_range(0.7, 1.3)
			var yaw := rng.randf() * PI
			for k in 2:
				var b := Basis(Vector3.UP, yaw + k * PI / 2).scaled(Vector3(s, s, s))
				mm.set_instance_transform(i * 2 + k, Transform3D(b, mine[i] - ctr))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = ctr
		var m := ShaderMaterial.new()
		m.shader = _foliage
		m.set_shader_parameter("tex", Tex.tuft(variant))
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 30.0
		n.add_child(mmi)


## Walls around a footprint with gaps toward `door_dirs`.
func _walls(n: Node3D, sh: Dictionary, door_dirs: Array, p: Dictionary, outside: bool, inside: bool) -> void:
	var c: Vector3 = sh["center"]
	var h := float(p["wall_h"])
	var base_h := float(p["base_h"])
	var ext := mat(str(p["ext_wall"]))
	var base := mat(str(p["ext_base"]))
	var inn := mat(str(p["int_wall"]))
	if str(sh["kind"]) == "round":
		var r := float(sh["r"])
		var segs := 28
		var chord := 2.0 * r * sin(PI / segs) + 0.06
		var gap := asin(clampf((DOOR_W / 2 + 0.05) / r, 0.0, 1.0))
		var door_angles := []
		for d in door_dirs:
			var dv: Vector3i = DIRS[d]
			door_angles.append(atan2(float(dv.z), float(dv.x)))
		for i in segs:
			var a := (i + 0.5) * TAU / segs
			var skip := false
			for da in door_angles:
				if absf(angle_difference(a, da)) < gap + PI / segs * 0.5:
					skip = true
			if skip:
				continue
			var dir := Vector3(cos(a), 0, sin(a))
			var rot := -(a + PI / 2)
			if outside:
				box(n, Vector3(chord, h - base_h, 0.22), c + dir * (r + 0.12) + Vector3(0, base_h + (h - base_h) / 2, 0), ext, false, rot)
				box(n, Vector3(chord + 0.05, base_h, 0.36), c + dir * (r + 0.16) + Vector3(0, base_h / 2, 0), base, false, rot)
			if inside:
				box(n, Vector3(chord * 0.97, h, 0.14), c + dir * (r - 0.05) + Vector3(0, h / 2, 0), inn, false, rot)
			if true:  # one solid body per segment
				var body := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(chord, h, 0.4)
				cs.shape = bs
				body.add_child(cs)
				body.position = c + dir * (r + 0.05) + Vector3(0, h / 2, 0)
				body.rotation.y = rot
				n.add_child(body)
		# lintels above the doorways
		for da in door_angles:
			var dir := Vector3(cos(da), 0, sin(da))
			if h > DOOR_H:
				box(n, Vector3(DOOR_W + 0.3, h - DOOR_H, 0.3), c + dir * r + Vector3(0, DOOR_H + (h - DOOR_H) / 2, 0), ext if outside else inn, false, -(da + PI / 2))
		return
	# rectangular
	var hx := float(sh["hx"])
	var hz := float(sh["hz"])
	for d in CARDINAL:
		var dv := flat(DIRS[d])
		var along := Vector3(absf(dv.z), 0, absf(dv.x))
		var length := hx * 2 if dv.z != 0 else hz * 2
		var off := hz if dv.z != 0 else hx
		var mid := c + dv * off
		var pieces := []
		if d in door_dirs:
			var side := (length - DOOR_W) / 2
			pieces.append([mid - along * (DOOR_W / 2 + side / 2), side])
			pieces.append([mid + along * (DOOR_W / 2 + side / 2), side])
		else:
			pieces.append([mid, length + 0.3])
		for pc in pieces:
			var pos: Vector3 = pc[0]
			var ln: float = pc[1]
			var thick := Vector3(absf(dv.x), 0, absf(dv.z))
			if outside:
				box(n, along * ln + thick * 0.22 + Vector3(0, h - base_h, 0), pos + dv * 0.12 + Vector3(0, base_h + (h - base_h) / 2, 0), ext, false)
				box(n, along * ln + thick * 0.36 + Vector3(0, base_h, 0), pos + dv * 0.16 + Vector3(0, base_h / 2, 0), base, false)
			if inside:
				box(n, along * ln + thick * 0.14 + Vector3(0, h, 0), pos - dv * 0.05 + Vector3(0, h / 2, 0), inn, false)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = along * ln + thick * 0.45 + Vector3(0, h, 0)
			cs.shape = bs
			body.add_child(cs)
			body.position = pos + Vector3(0, h / 2, 0)
			n.add_child(body)
		if d in door_dirs and h > DOOR_H:
			box(n, along * (DOOR_W + 0.2) + Vector3(absf(dv.x), 0, absf(dv.z)) * 0.4 + Vector3(0, h - DOOR_H, 0),
				mid + Vector3(0, DOOR_H + (h - DOOR_H) / 2, 0), ext if outside else inn, false)


func _roof(n: Node3D, sh: Dictionary, p: Dictionary, inside: bool, arch: Arch) -> void:
	arch.hip_roof(n, sh, p)


func _post_ring(n: Node3D, sh: Dictionary, p: Dictionary, painted: bool, height := -1.0) -> void:
	var c: Vector3 = sh["center"]
	var r := float(sh["r"]) * 0.58
	var h := float(p["wall_h"]) + float(sh["r"]) * 0.42
	if height > 0.0:
		h = height   # holding up the floor above
	var count := 6 if float(sh["r"]) < 8.0 else 8
	var m := mat("post_painted") if painted else mat(str(p["post"]))
	for i in count:
		var a := (i + 0.5) * TAU / count
		box(n, Vector3(0.3, h, 0.3), c + Vector3(cos(a), 0, sin(a)) * r + Vector3(0, h / 2, 0), m, true, -a)


## Ground around a building inside its cell: a path to each street door,
## and a low wattle fence on the sides that don't open onto anything.
func _yard(n: Node3D, cell: Vector3i, sh: Dictionary, street_dirs: Array, corridor_dirs: Array, p: Dictionary) -> void:
	var ctr := center_of(cell)
	var street := mat(str(p["street"]))
	for d in street_dirs:
		var dv := flat(DIRS[d])
		var door := wall_point(sh, dv, 0.0)
		var edge := ctr + dv * (C / 2)
		var length := door.distance_to(edge)
		var along := Vector3(absf(dv.x), 0, absf(dv.z))
		var across := Vector3(absf(dv.z), 0, absf(dv.x))
		box(n, along * length + across * 2.6 + Vector3(0, 0.02, 0), (door + edge) / 2 + Vector3(0, 0.013, 0), street, false)
	for d in CARDINAL:
		if d in street_dirs:
			continue
		var gap := DOOR_W + 0.6 if d in corridor_dirs else 0.0
		_edge_wall(n, ctr, d, str(p["yard_fence"]), 1.0, 0.4, gap, false)


## A low wall/fence/hedge along one edge of a cell, optionally with a gap.
func _edge_wall(n: Node3D, ctr: Vector3, d: String, tex: String, h: float, inset: float, gap := 0.0, solid := true) -> void:
	var dv := flat(DIRS[d])
	var along := Vector3(absf(dv.z), 0, absf(dv.x))
	var thick := Vector3(absf(dv.x), 0, absf(dv.z))
	var mid := ctr + dv * (C / 2 - inset)
	var m := mat(tex, Color.WHITE, 0.4 if tex == "hedge" else 0.0)
	if gap <= 0.0:
		box(n, along * C + thick * 0.5 + Vector3(0, h, 0), mid + Vector3(0, h / 2, 0), m, true)
		return
	var side := (C - gap) / 2
	for s: int in [-1, 1]:
		box(n, along * side + thick * 0.5 + Vector3(0, h, 0), mid + along * s * (gap / 2 + side / 2) + Vector3(0, h / 2, 0), m, true)


func _corridor(n: Node3D, from: Vector3, to: Vector3, dv: Vector3, p: Dictionary, dead_end: bool) -> void:
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var along := Vector3(absf(dv.x), 0, absf(dv.z))
	var across := Vector3(absf(dv.z), 0, absf(dv.x))
	var mid := (from + to) / 2
	var h := minf(float(p["wall_h"]), DOOR_H + 0.4)
	var inn := mat(str(p["int_wall"]))
	box(n, along * length + across * DOOR_W + Vector3(0, 0.02, 0), mid + Vector3(0, 0.012, 0), mat(str(p["int_floor"])), false)
	for s: int in [-1, 1]:
		box(n, along * length + across * 0.25 + Vector3(0, h, 0), mid + across * s * (DOOR_W / 2 + 0.12) + Vector3(0, h / 2, 0), inn, true)
	box(n, along * length + across * (DOOR_W + 0.5) + Vector3(0, 0.15, 0), mid + Vector3(0, h + 0.075, 0), mat(str(p["int_ceiling"])), false)
	if dead_end:
		box(n, across * DOOR_W + along * 3.0 + Vector3(0, h, 0), to + dv * 1.5 + Vector3(0, h / 2, 0), void_mat(), false)


func _portal_body(n: Node3D, p: Portal) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	if p.kind in ["pad", "stairs", "well", "stairs_down"]:
		bs.size = Vector3(0.1, 0.1, 0.1)
	else:
		var length := p.a.distance_to(p.b) + 0.4
		bs.size = Vector3(length, 3.5, 0.3)
		body.rotation.y = -atan2(p.b.z - p.a.z, p.b.x - p.a.x)
	cs.shape = bs
	cs.disabled = true
	body.add_child(cs)
	body.position = p.mid() + Vector3(0, 1.75, 0)
	n.add_child(body)
	p.body = body
	p.shape = cs


## Close every way out of `r` except `open_portal` (the one you're walking through).
func set_barriers(r: Room, open_portal: Portal) -> void:
	for other in rooms.values():
		for p: Portal in other.portals:
			p.set_blocking(other == r and p != open_portal and not (p.kind in ["pad", "stairs", "well", "stairs_down"]))


# ---------------------------------------------------------------- who and what is here

func _build_occupants(r: Room) -> void:
	if r.occ_node == null or r.props == null:
		return
	for ch in r.occ_node.get_children():
		ch.free()
	var pr := r.props
	pr.taken = r.base_taken.duplicate()
	pr.rng.seed = r.vnum * 7919
	var objects := []
	var creatures := []
	for item in r.contents:
		if str(item.get("kind", "")) == "creature":
			creatures.append(item)
		else:
			objects.append(item)
	var placed := []
	for item in objects:
		var entry: Dictionary = item.get("entry", {})
		var line := str(item.get("line", ""))
		var kind := str(entry.get("prop", Catalog.guess_prop(line)))
		for k in int(item.get("count", 1)):
			var it := pr.place_object(kind, line)
			if not it.is_empty():
				placed.append(it)
	pr.build(r.occ_node, placed)
	for item in creatures:
		var entry: Dictionary = item.get("entry", {})
		var line := str(item.get("line", ""))
		var a := Catalog.appearance_of(entry) if not entry.is_empty() else {"seed": Catalog.short_of(line)}
		var body := str(entry.get("body", Catalog.body_of(Catalog.subject_of(line))))
		if a.has("body"):
			body = str(a["body"])
		var count := int(item.get("count", 1))
		var group_at := Vector3.INF
		for k in count:
			var animal := body != "" and body != "human"
			var foot := 0.6 if not animal else clampf(SpriteGen.animal_height(body) * 0.6, 0.3, 1.2)
			var pos := pr.free_spot(foot, group_at)
			if pos == Vector3.INF:
				pos = r.shape["center"] + Vector3(pr.rng.randf_range(-1, 1), 0, pr.rng.randf_range(-1, 1))
			if group_at == Vector3.INF:
				group_at = pos
			pr.occupy(pos, foot + 0.1)
			var tex := _custom_sprite(entry, line)
			var height := 1.75
			if tex == null and animal:
				tex = SpriteGen.animal(body, str(a.get("color", "")), hash(line) + k)
				height = SpriteGen.animal_height(body)
			elif tex == null:
				tex = SpriteGen.person(a)
				if str(a.get("age", "")) == "child":
					height = 1.25
			if a.has("height"):
				height = float(a["height"])
			billboard(r.occ_node, tex, pos, height)
			if k == 0:
				var label := str(entry.get("name", Catalog.short_of(line)))
				if count > 1:
					label += "  ×%d" % count
				var m := Marker3D.new()
				m.position = pos + Vector3(0, height + 0.15, 0)
				m.set_meta("text", label)
				m.set_meta("kind", "name")
				m.set_meta("vnum", r.vnum)
				m.add_to_group("l3d_label")
				r.occ_node.add_child(m)


## data/sprites/<name>.png or data/sprites/<short description>.png, if you've drawn one.
func _custom_sprite(entry: Dictionary, line: String) -> Texture2D:
	var names := []
	if entry.has("name"):
		names.append(str(entry["name"]))
	names.append(Catalog.short_of(line))
	for nm in names:
		var slug := RegEx.create_from_string("[^a-z0-9]+").sub(str(nm).to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
		var path := SPRITE_DIR + slug + ".png"
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				return ImageTexture.create_from_image(img)
	return null


# ---------------------------------------------------------------- ground

func update_ground(around: Vector3) -> void:
	if _ground == null:
		_ground = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(420, 420)
		_ground.mesh = pm
		add_child(_ground)
	var area := str(current.data.get("area", "")) if current != null else ""
	var p := Style.for_area(area, overrides["areas"])
	_ground.material_override = mat(str(p["ground"]))
	_ground.position = Vector3(snappedf(around.x, C), -0.02, snappedf(around.z, C))
	_ground.visible = current == null or current.cell.y == 0


# ---------------------------------------------------------------- materials and shapes

func mat(tex: String, tint := Color.WHITE, wrap := 0.0) -> Material:
	var key := "%s|%s|%s" % [tex, tint.to_html(), wrap]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _retro
	m.set_shader_parameter("albedo_tex", Tex.get_tex(tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_scale", 0.5)
	m.set_shader_parameter("steps", light_steps)
	m.set_shader_parameter("band", light_band)
	m.set_shader_parameter("wrap", wrap)
	_mats[key] = m
	return m


## Same look, but using the mesh's own UVs (in meters) instead of world projection.
func mat_uv(tex: String, scale: float) -> Material:
	var key := "uv|%s|%s" % [tex, scale]
	if _mats.has(key):
		return _mats[key]
	var m := mat(tex).duplicate() as ShaderMaterial
	m.set_shader_parameter("use_uv", true)
	m.set_shader_parameter("uv_scale", scale)
	_mats[key] = m
	return m


func set_light_style(steps: float, band: float) -> void:
	light_steps = steps
	light_band = band
	for m in _mats.values():
		if m is ShaderMaterial and m.shader == _retro:
			m.set_shader_parameter("steps", steps)
			m.set_shader_parameter("band", band)


func glow(color: Color, flicker := 0.0) -> Material:
	var key := "glow|%s|%s" % [color.to_html(), flicker]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _glow
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("flicker", flicker)
	_mats[key] = m
	return m


func flame_mat() -> Material:
	if _mats.has("flame"):
		return _mats["flame"]
	var m := ShaderMaterial.new()
	m.shader = _glow
	m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("flame_tex", SpriteGen.flame())
	_mats["flame"] = m
	return m


func void_mat() -> Material:
	if _mats.has("void"):
		return _mats["void"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("0c0907")
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["void"] = m
	return m


func box(parent: Node3D, size: Vector3, center: Vector3, m: Material, collide: bool, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = center
	mi.rotation.y = rot_y
	mi.set_meta("static", true)
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.position = center
		body.rotation.y = rot_y
		parent.add_child(body)
	return mi


## A box that moves (door leaves): never merged into the room's static mesh.
func box_dyn(parent: Node3D, size: Vector3, center: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = center
	parent.add_child(mi)
	return mi


func cylinder(parent: Node3D, radius: float, height: float, center: Vector3, m: Material, collide: bool, cast := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = center
	mi.set_meta("static", true)
	if not cast:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		body.position = center
		parent.add_child(body)
	return mi


## A cone sitting on `base` (its bottom center). flip shows it from inside.
func cone(parent: Node3D, radius: float, height: float, base: Vector3, m: Material, flip: bool, segments := 22) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cm.flip_faces = flip
	mi.mesh = cm
	mi.material_override = m
	mi.position = base + Vector3(0, height / 2, 0)
	mi.set_meta("static", true)
	if flip:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func sphere(parent: Node3D, radius: float, center: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = m
	mi.position = center
	mi.set_meta("static", true)
	parent.add_child(mi)
	return mi


func billboard(parent: Node3D, tex: Texture2D, foot: Vector3, height: float) -> MeshInstance3D:
	var key := "spr|%d" % tex.get_instance_id()
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _sprite
		m.set_shader_parameter("sprite_tex", tex)
		_mats[key] = m
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(height * float(tex.get_width()) / float(tex.get_height()), height)
	mi.mesh = q
	mi.material_override = m
	mi.position = foot + Vector3(0, height / 2, 0)
	parent.add_child(mi)
	return mi
