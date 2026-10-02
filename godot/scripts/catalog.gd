## The catalog: everything we've learned about the NPCs and objects that
## show up in room listings, kept in data/npcs.json so you can read and edit it.
##
## Each entry is keyed by the line exactly as the room shows it (lowercased),
## e.g. "a tired serving maid is here, thinking quiet thoughts at her overworked feet."
## Fields:
##   kind        "creature" or "object"
##   short       what you'd call it before you know better ("A tired serving maid")
##   name        a proper name learned from `look` ("Tika"), if any
##   keyword     the word `look` worked with ("maid")
##   look        the raw lines `look` returned
##   gear        [{slot, item}] from "X is using:"
##   auto        appearance guessed from the look text and gear
##   appearance  YOUR appearance notes; these win over `auto`
##   notes       free text for you
class_name Catalog
extends RefCounted

const PATH := "res://data/npcs.json"

var entries := {}
var dirty := false


func load_file() -> void:
	entries = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and parsed.get("entries") is Dictionary:
		entries = parsed["entries"]
	elif parsed != null:
		push_warning("Legend3D: couldn't read %s (check the JSON)" % PATH)


func save_file() -> void:
	var out := {
		"_help": [
			"What Legend3D knows about NPCs and objects. Keyed by the room line.",
			"Edit 'appearance' to change how someone looks; it overrides 'auto'.",
			"appearance keys: sex, age, build, skin, hair, hair_color, beard, garment,",
			"garment_color, legs_color, belt_color, cloak_color, shoes_color, held, accessory, height.",
			"'body' is human or an animal: pig boar hound wolf fox horse pony cow bull sheep goat cat hen goose deer stag rat badger bear bird.",
			"Animals take 'color' in appearance, e.g. {\"color\": \"black\"}.",
			"For objects, 'prop' picks the shape: chest, board, mailbox, barrel, crate, shelf, altar...",
			"Save, then press F5 in Legend3D to see changes.",
		],
		"entries": entries,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Legend3D: couldn't write %s" % PATH)
		return
	f.store_string(JSON.stringify(out, "  ", false))
	f.close()
	dirty = false


static func key_of(line: String) -> String:
	return " ".join(line.strip_edges().to_lower().split(" ", false))


func lookup(line: String) -> Dictionary:
	return entries.get(key_of(line), {})


func put(line: String, entry: Dictionary) -> void:
	var k := key_of(line)
	var old: Dictionary = entries.get(k, {})
	# never throw away what you wrote yourself
	for keep in ["appearance", "notes", "prop"]:
		if old.has(keep) and not entry.has(keep):
			entry[keep] = old[keep]
	entries[k] = entry
	dirty = true


# ------------------------------------------------------------------ animals

## word in a description -> body type the sprite generator knows
const SPECIES := {
	"pig": "pig", "piglet": "pig", "sow": "pig", "hog": "pig", "swine": "pig", "boar": "boar",
	"hound": "hound", "dog": "hound", "wolfhound": "hound", "puppy": "hound", "cur": "hound", "mastiff": "hound",
	"wolf": "wolf", "fox": "fox", "vixen": "fox",
	"horse": "horse", "stallion": "horse", "mare": "horse", "steed": "horse", "colt": "pony", "foal": "pony", "pony": "pony",
	"cow": "cow", "cattle": "cow", "heifer": "cow", "calf": "cow", "bull": "bull", "ox": "bull", "oxen": "bull",
	"sheep": "sheep", "ewe": "sheep", "ram": "sheep", "lamb": "sheep",
	"goat": "goat", "kid": "goat", "billy": "goat",
	"cat": "cat", "kitten": "cat", "tomcat": "cat", "wildcat": "cat",
	"hen": "hen", "chicken": "hen", "rooster": "hen", "cock": "hen", "cockerel": "hen", "chick": "hen",
	"goose": "goose", "geese": "goose", "gander": "goose", "duck": "goose", "swan": "goose",
	"deer": "deer", "doe": "deer", "hind": "deer", "fawn": "deer", "stag": "stag", "hart": "stag", "elk": "stag",
	"rat": "rat", "mouse": "rat", "hare": "rat", "rabbit": "rat", "badger": "badger", "otter": "badger",
	"bear": "bear", "raven": "bird", "crow": "bird", "rook": "bird", "magpie": "bird", "owl": "bird",
	"hawk": "bird", "falcon": "bird", "eagle": "bird", "sparrow": "bird", "wren": "bird", "bird": "bird",
}

## "a large black sow is rooting here" -> "pig"
static func body_of(text: String) -> String:
	var low := text.to_lower()
	var best := ""
	var best_at := 1 << 30
	for word in SPECIES:
		var m := RegEx.create_from_string("\\b%s(s|es)?\\b" % word).search(low)
		if m != null and m.get_start() < best_at:
			best_at = m.get_start()
			best = SPECIES[word]
	return best


## "(2) A pig is here." -> [2, "A pig is here."]   (also "... [2]" or "... (2)" at the end)
static func strip_count(line: String) -> Array:
	var t := line.strip_edges()
	var m := RegEx.create_from_string("^\\(\\s*(\\d+)\\s*\\)\\s*(.+)$").search(t)
	if m != null:
		return [int(m.get_string(1)), m.get_string(2)]
	m = RegEx.create_from_string("^(.+?)\\s*[\\(\\[]\\s*(\\d+)\\s*[\\)\\]]$").search(t)
	if m != null:
		return [int(m.get_string(2)), m.get_string(1)]
	return [1, t]


# ------------------------------------------------------------------ room lines

const VERBS := "is|are|sits|sit|stands|stand|lies|lie|rests|rest|hangs|hang|leans|lean|waits|wait|floats|hovers|lurks|grows|has|have|has been|have been|sleeps|kneels|squats|crouches|scurries|scampers|wanders|roams|prowls|paces|pecks|grazes|munches|roots|snuffles|wags|barks|growls|hops|flutters|perches|swims|slithers|crawls|darts|trots|ambles|struts|watches|stares|glares|smiles|sings|hums|whistles|works|sweeps|cleans|polishes|guards|patrols|leaps|flits|buzzes|circles|gnaws|chews|sniffs|lounges|stretches|yawns|preens|bleats|clucks|oinks|moos|neighs|whinnies|blocks|tends|mends|stirs|serves|sells|hawks|lays|lie|towers|looms|rises|dangles|flickers|burns|glows|crackles|stands|rests"
const PLACE_WORDS := ["corner", "wall", "walls", "floor", "ground", "room", "center", "centre", "middle", "side", "back",
	"door", "doorway", "edge", "road", "path", "here", "there", "breeze", "air", "villagers", "people", "folk", "seeds"]
const STOPS := ["holding", "carrying", "wearing", "with", "of", "from", "in", "on", "at", "near", "by", "that", "which", "who", "made", "covered", "full", "filled", "bearing"]
const ARTICLES := ["a", "an", "the", "some", "two", "three", "several", "pair"]

## "A tired serving maid is here, ..." -> "A tired serving maid"
static func subject_of(line: String) -> String:
	var t := line.strip_edges()
	var m := RegEx.create_from_string("(?i)^(.+?)\\s+(%s)\\b" % VERBS).search(t)
	if m == null:
		m = RegEx.create_from_string("(?i)^((?:a|an|the|some)\\s+(?:[\\w\\-',]+\\s+){0,4}?[\\w\\-]+)\\s+[a-z]+(?:s|es)\\b").search(t)
	var s := m.get_string(1) if m != null else t.trim_suffix(".")
	return s.strip_edges()


## "A directory board holding both news..." -> "A directory board"
static func short_of(line: String) -> String:
	var out := []
	for raw in subject_of(line).split(" ", false):
		var wd := raw.to_lower().trim_suffix(",")
		if wd in STOPS and out.size() > 1:
			break
		out.append(raw.trim_suffix(","))
	return " ".join(out)


## Words to try with `look`, best first, at most three. For creatures it's
## the noun of the subject ("a tired serving maid" -> maid). For things lying
## about, it's the thing itself, which is often the last noun ("notices ... on
## a sheepskin tacked here" -> sheepskin, then notices).
static func keywords_for(line: String) -> Array:
	var low := line.to_lower().strip_edges()
	var subj := subject_of(line)
	var has_verb := subj.length() < line.strip_edges().length() - 2
	var out := []
	var subj_words := []
	for raw in subj.to_lower().split(" ", false):
		var wd := RegEx.create_from_string("[^a-z\\-]").sub(raw.trim_suffix(",").trim_suffix("'s"), "", true)
		if wd == "" or wd in STOPS:
			break
		subj_words.append(wd)
	var art_nouns := []
	for m in RegEx.create_from_string("\\b(?:a|an|the|some)\\s+(?:[a-z\\-]+\\s+){0,2}?([a-z\\-]{3,})(?=\\s+(?:is|are|sits|stands|lies|tacked|hangs|here|on|in|to|of|with|that|which|$)|[\\.,]|$)").search_all(low):
		var wd: String = m.get_string(1)
		if not (wd in PLACE_WORDS):
			art_nouns.append(wd)
	# "The Ard-righ has posted notices ... on a sheepskin": the thing is what was posted
	if RegEx.create_from_string("\\b(has|have) (posted|left|placed|set|hung|tacked|carved|painted|scratched)\\b").search(low) != null:
		for i in range(art_nouns.size() - 1, -1, -1):
			if not out.has(art_nouns[i]):
				out.append(art_nouns[i])
		var obj := RegEx.create_from_string("\\b(?:posted|left|placed|set|hung|tacked|carved|painted|scratched)\\s+(?:a |an |the |some )?([a-z\\-]{3,})").search(low)
		if obj != null and not out.has(obj.get_string(1)):
			out.append(obj.get_string(1))
		return out.slice(0, 3)
	# otherwise the subject's head noun, then its other words
	for i in range(subj_words.size() - 1, -1, -1):
		var wd: String = subj_words[i]
		if wd in ARTICLES or wd.length() < 3 or wd in PLACE_WORDS or out.has(wd):
			continue
		out.append(wd)
	# "a clump of flax", "a bundle of reeds": the stuff itself goes first
	var of_m := RegEx.create_from_string("^(?:a|an|the|some)?\\s*(?:[a-z\\-]+\\s+)?[a-z\\-]+\\s+of\\s+([a-z\\-]{3,})").search(subj.to_lower())
	if of_m != null and not (of_m.get_string(1) in PLACE_WORDS) and not out.has(of_m.get_string(1)):
		out.push_front(of_m.get_string(1))
	if not has_verb:
		for wd in art_nouns:
			if not out.has(wd):
				out.push_front(wd)
	return out.slice(0, 3)


## Before anything's been looked at: is this line a person or a thing?
static func guess_kind(line: String) -> String:
	var low := line.to_lower()
	if body_of(subject_of(line)) != "":
		return "creature"
	# plants, heaps and the like "waving in the breeze" are things, not folk
	if RegEx.create_from_string("^(a|an|the|some)?\\s*(\\w+\\s+)?(clump|bunch|patch|tuft|pile|heap|stack|bundle|plant|herb|bush|shrub|flower|flowers|weed|weeds|reeds|rushes|flax|nettle|nettles|fern|ferns|moss|mushroom|mushrooms|tree|sapling|stump|log|rock|boulder|stone|puddle|pool|spring|fire|campfire|bonfire)\\b").search(low.strip_edges()) != null:
		return "object"
	if RegEx.create_from_string("\\b(is|are) (here|standing|sitting|resting|sleeping|kneeling|leaning|waiting|lounging|working)\\b").search(low) != null:
		return "creature"
	if RegEx.create_from_string("\\b(is|are) here,\\s").search(low) != null:
		return "creature"
	return "object"


# ------------------------------------------------------------------ look output

## Make sense of what `look <thing>` returned.
static func parse_look(lines: Array, line: String, keyword: String) -> Dictionary:
	var e := {
		"short": short_of(line),
		"keyword": keyword,
		"look": lines,
		"kind": "object",
	}
	var desc := []
	var gear := []
	var health_re := RegEx.create_from_string("^(.+?) is (in perfect health|in excellent condition|slightly (hurt|wounded|scratched)|.*(wounds|wounded|bleeding|hurt|injured|scratches|bruises|awful|dying|condition))\\.$")
	var using_re := RegEx.create_from_string("^(.+?) is using:$")
	var slot_re := RegEx.create_from_string("^<([^>]+)>\\s+(.+)$")
	var who := ""
	var in_gear := false
	for raw in lines:
		var t := str(raw).strip_edges()
		if t == "":
			continue
		var hm := health_re.search(t)
		if hm != null and who == "":
			who = hm.get_string(1)
			e["kind"] = "creature"
			continue
		var um := using_re.search(t)
		if um != null:
			who = um.get_string(1)
			e["kind"] = "creature"
			in_gear = true
			continue
		var sm := slot_re.search(t)
		if sm != null:
			gear.append({"slot": sm.get_string(1).strip_edges(), "item": sm.get_string(2).strip_edges()})
			e["kind"] = "creature"
			continue
		if not in_gear:
			desc.append(t)
	e["desc"] = " ".join(desc)
	e["gear"] = gear
	# a capitalized name that isn't "The guard" / "A maid" is a proper name
	if who != "":
		var first := who.split(" ")[0].to_lower()
		if not first in ["a", "an", "the", "some"]:
			e["name"] = who
	var body := body_of(subject_of(line))
	if body == "" and e["kind"] == "creature":
		body = body_of(str(e["desc"]))
	if body != "":
		e["kind"] = "creature"
		e["body"] = body
	if e["kind"] == "creature":
		e["auto"] = auto_appearance(e["desc"], gear)
		if body != "":
			var colour := ""
			for cname in SpriteGen.COLORS:
				if RegEx.create_from_string("\\b%s\\b" % cname).search((line + " " + str(e["desc"])).to_lower()) != null and cname.length() > colour.length():
					colour = cname
			if colour != "":
				e["auto"]["color"] = colour
	else:
		e["prop"] = guess_prop(line + " " + str(e["desc"]))
	return e


static func guess_prop(text: String) -> String:
	var low := text.to_lower()
	for pair in [["mailbox", "mailbox"], ["board", "board"], ["sign", "board"], ["notice", "board"],
			["chest", "chest"], ["box", "chest"], ["trunk", "chest"], ["coffer", "chest"],
			["barrel", "barrel"], ["cask", "barrel"], ["keg", "barrel"], ["crate", "crate"],
			["shelf", "shelf"], ["altar", "altar"], ["statue", "statue"], ["fountain", "fountain"],
			["well", "well"], ["cauldron", "cauldron"], ["cart", "cart"], ["wagon", "cart"],
			["stone", "stone"], ["bush", "bush"], ["plant", "bush"], ["herb", "bush"]]:
		if RegEx.create_from_string("\\b%s" % pair[0]).search(low) != null:
			return pair[1]
	return "chest"


## A first guess at someone's look from their description and gear.
static func auto_appearance(desc: String, gear: Array) -> Dictionary:
	var a := {}
	var low := desc.to_lower()
	var she := RegEx.create_from_string("\\b(she|her|hers|herself|woman|girl|lady|maid|maiden)\\b").search_all(low).size()
	var he := RegEx.create_from_string("\\b(he|him|his|himself|man|boy|lad|lord)\\b").search_all(low).size()
	if she > he:
		a["sex"] = "female"
	elif he > she:
		a["sex"] = "male"
	for pair in [["old", "old"], ["elderly", "old"], ["aged", "old"], ["wizened", "old"],
			["young", "young"], ["youth", "young"], ["child", "child"]]:
		if RegEx.create_from_string("\\b%s\\b" % pair[0]).search(low) != null:
			a["age"] = pair[1]
			break
	var hm := RegEx.create_from_string("\\b(red|auburn|copper|ginger|blonde?|fair|golden|brown|chestnut|dark|black|grey|gray|white|silver)[- ](haired|hair|locks|tresses|braids?)").search(low)
	if hm != null:
		a["hair_color"] = hm.get_string(1)
	if RegEx.create_from_string("\\b(beard|bearded)\\b").search(low) != null:
		a["beard"] = true
	for g in gear:
		var item := str(g.get("item", "")).to_lower()
		var slot := str(g.get("slot", "")).to_lower()
		var color := ""
		for cname in SpriteGen.COLORS:
			if RegEx.create_from_string("\\b%s\\b" % cname).search(item) != null and cname.length() > color.length():
				color = cname
		if RegEx.create_from_string("\\b(kirtle|dress|gown|frock|shift|léine|leine)\\b").search(item) != null:
			a["garment"] = "dress"
			if color != "":
				a["garment_color"] = color
		elif RegEx.create_from_string("\\b(robe|habit|cassock)\\b").search(item) != null:
			a["garment"] = "robe"
			if color != "":
				a["garment_color"] = color
		elif RegEx.create_from_string("\\b(mail|hauberk|plate|breastplate|cuirass|armou?r|byrnie)\\b").search(item) != null and slot.contains("body"):
			a["garment"] = "armor"
		elif RegEx.create_from_string("\\b(tunic|shirt|jerkin|vest|doublet)\\b").search(item) != null:
			a["garment"] = "tunic"
			if color != "":
				a["garment_color"] = color
		elif RegEx.create_from_string("\\b(trews|trousers|breeches|leggings|pants)\\b").search(item) != null and color != "":
			a["legs_color"] = color
		elif RegEx.create_from_string("\\b(girdle|belt|sash)\\b").search(item) != null and color != "":
			a["belt_color"] = color
		elif RegEx.create_from_string("\\b(cloak|brat|mantle|cape)\\b").search(item) != null:
			a["cloak_color"] = color if color != "" else "brown"
		elif RegEx.create_from_string("\\b(brogs|boots|shoes|sandals|slippers)\\b").search(item) != null and color != "":
			a["shoes_color"] = color
		elif RegEx.create_from_string("\\bhair\\b").search(item) != null or slot.contains("hair"):
			a["accessory"] = ("hair gold" if color in ["gold", "golden"] or item.contains("gold") else "hair")
		elif item.contains("torc"):
			a["accessory"] = "torc"
		if slot.contains("wield") or slot.contains("hand") or slot.contains("held"):
			for weapon in ["sword", "spear", "staff", "axe", "harp", "torch", "shield", "tray", "mug", "basket"]:
				if item.contains(weapon):
					a["held"] = weapon
	return a


## The look we actually draw: guesses first, then your notes on top.
static func appearance_of(entry: Dictionary) -> Dictionary:
	var a: Dictionary = {}
	if entry.get("auto") is Dictionary:
		a.merge(entry["auto"], true)
	if entry.get("appearance") is Dictionary:
		a.merge(entry["appearance"], true)
	a["seed"] = str(entry.get("name", entry.get("short", "")))
	if not a.has("held") and entry.get("appearance") is Dictionary and entry["appearance"].has("held"):
		a["held"] = entry["appearance"]["held"]
	return a
