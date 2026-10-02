## Style packs: what an area's buildings, walls and floors are made of.
## The room description decides *what* is where; the pack decides how it looks.
class_name Style
extends RefCounted

const PACKS := {
	# Iron Age Ireland, around 300 BC: roundhouses of wattle and daub on a
	# drystone footing, conical thatch, packed-earth floors strewn with rushes.
	"celtic": {
		"ground": "grass",
		"street": "dirt",
		"plaza": "dirt",
		"boundary": "drystone",       # low field walls where there's no way through
		"boundary_h": 1.1,
		"wild_boundary": "hedge",     # woods and wild places
		"yard_fence": "wattle",
		"ext_wall": "daub",
		"ext_base": "drystone",
		"base_h": 0.8,
		"int_wall": "wattle",
		"int_floor": "earth",
		"int_ceiling": "darktimber",  # flat ceilings (halls, corridors)
		"roof": "thatch",
		"post": "timber",
		"door": "darktimber",
		"furniture": "timber",
		"stone": "hearthstone",
		"round": true,
		"wall_h": 2.5,
		"roof_pitch": 0.95,
	},
	# Fallback until an area gets its own pack.
	"default": {
		"ground": "grass",
		"street": "dirt",
		"plaza": "cobble",
		"boundary": "stone",
		"boundary_h": 1.4,
		"wild_boundary": "hedge",
		"yard_fence": "wattle",
		"ext_wall": "plaster",
		"ext_base": "stone",
		"base_h": 0.6,
		"int_wall": "plaster",
		"int_floor": "wood",
		"int_ceiling": "beams",
		"roof": "thatch",
		"post": "timber",
		"door": "darktimber",
		"furniture": "wood",
		"stone": "stone",
		"round": false,
		"wall_h": 3.2,
		"roof_pitch": 0.6,
	},
}

const AREA_PACK := {
	"Celtic Ireland": "celtic",
}


static func for_area(area: String, overrides: Dictionary = {}) -> Dictionary:
	var name: String = AREA_PACK.get(area, "default")
	var ov = overrides.get(area)
	if ov is Dictionary and ov.has("pack"):
		name = str(ov["pack"])
	var p: Dictionary = PACKS.get(name, PACKS["default"]).duplicate()
	if ov is Dictionary:
		for k in ov:
			if k != "pack":
				p[k] = ov[k]
	return p
