## Making sense of what you wear, carry and know, from Legend's own output:
## `equipment` (worn gear, what's in your hands), GMCP inventory, `spells`.
class_name Gear
extends RefCounted

const WEAPON_WORDS := [
	["dagger", "\\b(dagger|knife|dirk|sgian|stiletto|kris|athame|shiv)\\b"],
	["axe", "\\b(axe|hatchet|tomahawk|bardiche|halberd)\\b"],
	["mace", "\\b(mace|morning ?star|flail|cudgel|club|shillelagh|bludgeon|truncheon)\\b"],
	["hammer", "\\b(hammer|maul|mallet)\\b"],
	["spear", "\\b(spear|lance|pike|javelin|trident|harpoon|glaive|partisan)\\b"],
	["staff", "\\b(staff|quarterstaff|stave|rod|cane|crook|wand|sceptre|scepter)\\b"],
	["bow", "\\b(bow|longbow|shortbow|crossbow)\\b"],
	["sling", "\\b(sling)\\b"],
	["whip", "\\b(whip|lash|scourge)\\b"],
	["sword", "\\b(sword|blade|longsword|broadsword|claymore|scimitar|sabre|saber|rapier|falchion|cutlass|katana|gladius|spatha|kopis)\\b"],
]
const LIGHT_WORDS := "\\b(torch|lantern|lamp|candle|rushlight|brand|glowstone|lightstone|orb|globe)\\b"
const TOOL_WORDS := [
	["shield", "\\b(shield|buckler|targe)\\b"],
	["book", "\\b(book|tome|grimoire|scroll)\\b"],
]


## "<wielded>   a long iron sword" lines -> [{slot, item}]
static func parse_slots(lines: Array) -> Array:
	var re := RegEx.create_from_string("^\\s*<([^>]+)>\\s+(.+?)\\s*$")
	var out := []
	for l in lines:
		var m := re.search(str(l))
		if m != null:
			out.append({"slot": m.get_string(1).strip_edges(), "item": m.get_string(2)})
	return out


## What's in your hands: {"weapon": {name, kind}, "light": {name, kind, lit}, "off": {name, kind}}
static func hands_of(slots: Array) -> Dictionary:
	var out := {}
	for s in slots:
		var slot := str(s["slot"]).to_lower()
		var item := str(s["item"])
		var low := item.to_lower()
		var is_light := RegEx.create_from_string(LIGHT_WORDS).search(low) != null
		if slot.contains("light"):
			out["light"] = {"name": item, "kind": light_kind(low), "lit": true}
		elif slot.contains("wield") or slot.contains("primary") or slot.contains("weapon"):
			if is_light:
				out["light"] = {"name": item, "kind": light_kind(low), "lit": low.contains("lit") or low.contains("burning")}
			else:
				out["weapon"] = {"name": item, "kind": weapon_kind(low)}
		elif slot.contains("held") or slot.contains("hold") or slot.contains("hand") or slot.contains("second") or slot.contains("shield"):
			if is_light:
				out["light"] = {"name": item, "kind": light_kind(low), "lit": true}
			elif not out.has("off"):
				var k := weapon_kind(low)
				for t in TOOL_WORDS:
					if RegEx.create_from_string(t[1]).search(low) != null:
						k = t[0]
				out["off"] = {"name": item, "kind": k}
	return out


static func weapon_kind(low: String) -> String:
	for wk in WEAPON_WORDS:
		if RegEx.create_from_string(wk[1]).search(low) != null:
			return wk[0]
	return "sword"


static func light_kind(low: String) -> String:
	if low.contains("lantern") or low.contains("lamp"):
		return "lantern"
	if low.contains("candle") or low.contains("rushlight"):
		return "candle"
	if RegEx.create_from_string("\\b(glowstone|lightstone|orb|globe)\\b").search(low) != null:
		return "orb"
	return "torch"


## Spell lines: anything with "(50:25)" in it. The first number is the mana
## it costs and the second its level (best guess; Legend doesn't say).
static func parse_spells(lines: Array) -> Array:
	var re := RegEx.create_from_string("^(.*?)\\s*\\((\\d+)\\s*:\\s*(\\d+)\\)\\s*(.*)$")
	var glue := RegEx.create_from_string("\\s{2,}(\\(\\d+\\s*:\\s*\\d+\\))")
	var cols := RegEx.create_from_string("\\s{3,}")
	var out := []
	for l in lines:
		# "armor     (50:25)    bal ignis" -> "armor (50:25)" + "bal ignis"
		var t := glue.sub(str(l).strip_edges(), " $1", true)
		var last := {}
		for part in cols.sub(t, "\t", true).split("\t", false):
			var m := re.search(part)
			if m == null:
				# a column without numbers: the words of power for the spell before it
				if not last.is_empty() and str(last["words"]) == "":
					last["words"] = part.strip_edges()
				continue
			var name := m.get_string(1).strip_edges().trim_suffix(":").strip_edges()
			if name == "":
				continue
			last = {"name": name, "mana": int(m.get_string(2)), "level": int(m.get_string(3)), "words": m.get_string(4).strip_edges()}
			out.append(last)
	return out


## Group GMCP inventory items: identical ones counted once.
static func group_items(items: Array) -> Array:
	var by := {}
	var order := []
	for it in items:
		if not (it is Dictionary):
			continue
		var short := str(it.get("short", it.get("name", "?")))
		var n := 1
		if it.get("bundle") is Dictionary:
			n = int(it["bundle"].get("count", 1))
		if by.has(short):
			by[short]["count"] += n
			by[short]["items"].append(it)
		else:
			by[short] = {"short": short, "count": n, "items": [it]}
			order.append(short)
	var out := []
	for k in order:
		out.append(by[k])
	return out


## The word to type to mean this item ("oregano short green plant" -> oregano).
static func keyword_of(it: Dictionary) -> String:
	var name := str(it.get("name", "")).strip_edges()
	if name != "":
		return name.split(" ", false)[0]
	var short := str(it.get("short", "thing")).to_lower()
	var words := short.split(" ", false)
	return words[words.size() - 1] if words.size() > 0 else "thing"


## Commands that make sense for an item, by its type and where it can be worn.
static func actions_for(it: Dictionary) -> Array:
	var kw := keyword_of(it)
	var t := str(it.get("type", "")).to_upper()
	var out := [["Look", "look " + kw]]
	var wear: Array = it.get("wearFlags", []) if it.get("wearFlags") is Array else []
	if t == "WEAPON":
		out.append(["Wield", "wield " + kw])
	elif t == "LIGHT":
		out.append(["Hold as light", "hold " + kw])
	elif not wear.is_empty() or t in ["ARMOR", "CLOTHING", "WORN"]:
		out.append(["Wear", "wear " + kw])
	if t in ["FOOD"]:
		out.append(["Eat", "eat " + kw])
	if t in ["DRINK", "DRINKCON", "DRINK_CONTAINER", "POTION"]:
		out.append(["Drink", "drink " + kw])
	if t in ["SCROLL"]:
		out.append(["Recite", "recite " + kw])
	if t in ["CONTAINER"]:
		out.append(["Look inside", "look in " + kw])
	out.append(["Drop", "drop " + kw])
	return out
