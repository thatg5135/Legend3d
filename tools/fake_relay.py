#!/usr/bin/env python3
"""Fake Mudlet relay: drives Legend3D without Mudlet or the MUD.

Speaks the same protocol as the real relay (PROTOCOL.md) and serves a
tiny pretend Tara. The Main Path and The Reception use real LegendMUD
data; every other room here is INVENTED just so there's somewhere to walk.

    python3 fake_relay.py                 # start at the Main Path, afternoon
    python3 fake_relay.py --time "11:30 pm"

Start Legend3D first (or after; this keeps retrying), then walk around
with the arrow keys. Ctrl+C to stop.
"""
import argparse
import json
import re
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:7359"

ROOMS = {
    11663: {  # real
        "vnum": 11663, "name": "The Main Path to the Dun", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "You travel along the main path of Tara on the way to Gwyn's Dun. The way is\r\n"
                "thick with people who call out a pleasant greeting to you.\r\n",
        "exits": [{"dir": "north", "to_vnum": 11664}, {"dir": "east", "to_vnum": 11662},
                  {"dir": "south", "to_name": "The Silver Branch Inn", "to_vnum": 11677},
                  {"dir": "west", "to_vnum": 11656}],
        "here": ["A wandering bard is here, singing softly to himself.",
                 "A grey wolfhound lies here, watching the road.",
                 "A clump of flax is here, waving gently in the breeze."],
        "looks": {
            "bard": ["", "(Invented for testing.) A lean young man with a russet beard and a small",
                     "harp slung at his hip. He hums under his breath.",
                     "The wandering bard is in perfect health.", "The wandering bard is using:",
                     "<worn on body>       a saffron tunic", "<worn about body>   a green brat",
                     "<held>               a small harp"],
            "flax": ["", "A clump of flax is here, waving gently in the breeze."],
            "wolfhound": ["", "(Invented for testing.) A huge, rough-coated grey hound.",
                          "The grey wolfhound is in perfect health."],
        },
    },
    11677: {  # real (from Bobby's paste)
        "vnum": 11677, "name": "The Silver Branch Inn", "area": "Celtic Ireland",
        "type": "indoors", "is_inn": True,
        "desc": "A huge common room fills three quarters of the first floor of this building.\r\n"
                "A roaring hearth takes up the south wall of the room. A swinging door leads\r\n"
                "to the kitchen on the west side of the building. Tables and benches fill the\r\n"
                "remaining space. Lanterns hang from the ceiling to brighten the room.\r\n",
        "exits": [{"dir": "north", "to_vnum": 11663}, {"dir": "up", "to_name": "The Reception", "to_vnum": 11683}],
        "here": ["A mailbox sits in the corner here.",
                 "A box sits against the back wall serving as storage for lost and found items.",
                 "A directory board holding both news and 'welcome' information stands here.",
                 "A tired serving maid is here, thinking quiet thoughts at her overworked feet."],
        "looks": {
            "maid": ["", "A warm, but tired smile draws your eyes from her amply displayed bosom.",
                     "Tika is in perfect health.", "Tika is using:",
                     "<worn on body>       a yellow kirtle", "<worn on feet>       a pair of brogs",
                     "<worn about waist>   a deep green girdle", "<clasping hair>      a golden hair ball",
                     "<clasping hair>      a golden hair ball"],
            "box": ["", "The box looks large enough to keep clutter from littering the room. It would",
                    "also probably keep the items safer from wandering thieves than if they were",
                    "just lying about."],
            "mailbox": ["", "You see nothing special."],
            "board": ["", "These boards share information with the entire mud. The welcome board",
                      "contains information for newbies and announcements from the immortal staff,",
                      "while the news board covers an assortment of player postings."],
        },
    },
    11683: {  # real
        "vnum": 11683, "name": "The Reception", "area": "Celtic Ireland",
        "type": "indoors", "is_inn": True,
        "desc": "A long hall lined with doors stretches farther than seems possible in both\r\n"
                "directions. You get the feeling that there is something wrong with this\r\n"
                "corridor. It simply shouldn't fit inside a building this size.\r\n",
        "exits": [{"dir": "down", "to_name": "The Silver Branch Inn", "to_vnum": 11677}],
        "here": [],
    },
    11664: {  # invented
        "vnum": 11664, "name": "The Main Path, North", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "(Invented for testing.) The path runs on north toward the dun.\r\n",
        "exits": [{"dir": "south", "to_vnum": 11663}, {"dir": "north", "to_vnum": 11666}],
        "here": [],
    },
    11666: {  # invented
        "vnum": 11666, "name": "Before Gwyn's Dun", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "(Invented for testing.) Tall trees crowd in around the path here, oaks and\r\n"
                "hazels leaning over the way to the dun.\r\n",
        "exits": [{"dir": "south", "to_vnum": 11664}, {"dir": "north", "to_vnum": 11667}],
        "here": [],
    },
    11667: {  # real (from Bobby)
        "vnum": 11667, "name": "The Door to the Dun", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "Two huge ironbound doors set in the walls of the Dun tower before you. Faint\r\n"
                "sounds of a bustling household leak around the edges of the tremendous doors.\r\n",
        "exits": [{"dir": "north", "to_vnum": 11690}, {"dir": "south", "to_vnum": 11666}],
        "here": ["The Ard-righ has posted notices to the villagers on a sheepskin tacked here.",
                 "A scrawny, dirt-covered whining brat is here.",
                 "A large hound is panting here, slowly creating a lake of drool.",
                 "A field mouse scurries about, looking for seeds.",
                 "An old, seasoned warrior is here, guarding the dun."],
        "closed": {"north": "The doors are closed."},
    },
    11690: {  # invented: just inside the dun
        "vnum": 11690, "name": "Inside the Dun Gate", "area": "Celtic Ireland",
        "type": "indoors", "is_inn": False,
        "desc": "(Invented for testing.) A torchlit entry hall of the Ard-righ's dun, its\r\n"
                "great doors to the south.\r\n",
        "exits": [{"dir": "south", "to_vnum": 11667}],
        "here": [],
    },
    11662: {  # invented
        "vnum": 11662, "name": "A Narrow Lane", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "(Invented for testing.) A muddy lane between wattle houses.\r\n",
        "exits": [{"dir": "west", "to_vnum": 11663}, {"dir": "east", "to_vnum": 11670},
                  {"dir": "north", "to_name": "The Weaver's Cottage", "to_vnum": 11668}],
        "here": ["(2) A muddy pig is here, rooting through the refuse."],
        "looks": {
            "pig": ["", "(Invented for testing.) A stout pink pig caked in mud snuffles about,",
                    "hunting for scraps.", "The muddy pig is in perfect health."],
        },
        "closed": {"east": "The door is closed."},
    },
    11668: {  # description is real (from Bobby); contents invented
        "vnum": 11668, "name": "The Weaver's Cottage", "area": "Celtic Ireland",
        "type": "indoors", "is_inn": False,
        "desc": "Balls of yarn litter the floor of this simple cottage like jumbo marbles\r\n"
                "scattered inside a circle. A large loom dominates the room, taking the entire\r\n"
                "west side for its own personal space. A few bales of uncarded wool have been\r\n"
                "tossed into one corner. A small rocking chair creaks next to a table beside\r\n"
                "the hearth.\r\n",
        "exits": [{"dir": "south", "to_vnum": 11662}],
        "here": ["An old weaver is here, working at her loom."],
        "looks": {
            "weaver": ["", "(Invented for testing.) A stooped old woman with grey hair pinned up,",
                       "her fingers flying across the threads.",
                       "The old weaver is in perfect health.", "The old weaver is using:",
                       "<worn on body>       a dark blue gown", "<worn about body>   a russet brat"],
        },
    },
    11656: {  # invented
        "vnum": 11656, "name": "The Market of Tara", "area": "Celtic Ireland",
        "type": "outdoors", "is_inn": False,
        "desc": "(Invented for testing.) Stalls ring a cobbled market square, busy with\r\n"
                "traders and their customers.\r\n",
        "exits": [{"dir": "east", "to_vnum": 11663}],
        "here": ["A fishwife is here, hawking her wares."],
    },
}
SHORT = {"n": "north", "s": "south", "e": "east", "w": "west", "u": "up", "d": "down",
         "ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest"}
SHORTEN = {v: k for k, v in SHORT.items()}
PROMPT = ">< Hp:708/708 Mana:526/526 MV:393/393 $766 ((TNL:1036020 )) >< "

# Invented answers for the quiet checks the menu asks for (not real Legend text).
GEAR = {
    "sword": "a long iron sword", "dagger": "a bronze dagger", "axe": "a bearded axe",
    "spear": "an ash-hafted spear", "staff": "a gnarled oak staff", "mace": "a flanged mace",
    "none": None,
}
LIGHTS = {"torch": "a pitch-soaked torch", "lantern": "an iron lantern", "candle": "a tallow candle", "none": None}
QUIET = {
    "spells": ["(Invented for testing.) You know the following spells:",
               "  armor                 (50:25)    bal ignis",
               "  cure light wounds     (15:5)     lux minor",
               "  detect magic          (20:10)    oculus",
               "  fireball              (75:40)    ignis magna"],
    "skills": ["(Invented for testing.) You know the following skills:",
               "  bash          superb", "  kick          good", "  parry         excellent", "  rescue        fair"],
    "score": ["(Invented for testing.) You are Arkhanst the wanderer, level 47.",
              "Hit points: 708/708   Mana: 526/526   Moves: 393/393",
              "You are standing.  You are carrying 12 items."],
}
INVENTORY = {"items": [
    {"short": "a bunch of oregano", "name": "oregano short green plant oval leaves", "type": "FOOD",
     "desc": "A short, green plant with oval leaves is growing here.", "weight": 0, "oid": "0x1"},
    {"short": "a bunch of oregano", "name": "oregano short green plant oval leaves", "type": "FOOD",
     "desc": "A short, green plant with oval leaves is growing here.", "weight": 0, "oid": "0x2"},
    {"short": "a bundle of rosemary", "name": "rosemary bundle needle leaves", "type": "FOOD", "bundle": {"count": 16},
     "desc": "A bunch of silvery-green, needle-shaped leaves and pale blue flowers is here.", "weight": 1, "oid": "0x3"},
    {"short": "a woollen cloak", "name": "cloak woollen", "type": "ARMOR", "wearFlags": ["ABOUT"],
     "desc": "(Invented for testing.) A heavy cloak of undyed wool.", "weight": 4, "oid": "0x4",
     "condition": {"dam": 2, "damMax": 14}},
]}


class Relay:
    def __init__(self, start, game_time, moon="waxing gibbous", weather="The sky is filled with puffy white clouds on this spring day.",
                 weapon="sword", light="torch"):
        self.weapon = GEAR.get(weapon, weapon)
        self.light = LIGHTS.get(light, light)
        self.room = start
        self.time = game_time
        self.moon = moon
        self.weather = weather
        self.seq = 0
        self.session = None

    def post(self, path, payload):
        req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.read()

    def ev(self, kind, data):
        self.seq += 1
        return {"seq": self.seq, "type": kind, "data": data}

    def room_info(self, vnum):
        r = dict(ROOMS[vnum])
        r.pop("here")
        r.pop("closed", None)
        r.pop("looks", None)
        return r

    def room_events(self, vnum):
        r = ROOMS[vnum]
        evs = [self.ev("room", self.room_info(vnum)), self.ev("line", {"text": r["name"], "prompt": False})]
        for line in r["desc"].split("\r\n"):
            if line:
                evs.append(self.ev("line", {"text": line, "prompt": False}))
        closed = r.get("closed", {})
        exits = " ".join(("[%s]" if e["dir"] in closed else "%s") % SHORTEN.get(e["dir"], e["dir"]) for e in r["exits"])
        evs.append(self.ev("line", {"text": f"[Exits: {exits}]", "prompt": False}))
        for line in r["here"]:
            evs.append(self.ev("line", {"text": line, "prompt": False}))
        evs.append(self.ev("line", {"text": PROMPT, "prompt": False}))
        return evs

    def hello(self):
        self.session = f"{int(time.time())}-fake"
        self.post("/hello", self.ev("hello", {
            "client": "fake_relay", "version": "test", "session": self.session,
            "room": self.room_info(self.room), "time": {"game": self.time},
            "vitals": {"h": 650, "H": 708, "m": 401, "M": 526, "v": 380, "V": 393},
            "inventory": INVENTORY}))
        self.post("/events", self.room_events(self.room))
        self.post("/events", [self.ev("quiet", {"cmd": "time", "lines": [
            f"It is {self.time} on Thursday, May 26, 300 BC.",
            f"The almanac indicates there will be a {self.moon} moon tonight."]}),
            self.ev("quiet", {"cmd": "weather", "lines": [self.weather]})])
        print(f"linked; standing in {self.room} {ROOMS[self.room]['name']}")

    def quiet(self, cmd):
        if cmd in ("equipment", "eq"):
            lines = ["You are using:"]
            if self.light:
                lines.append("<used as light>       " + self.light)
            lines.append("<worn about body>     a woollen cloak")
            if self.weapon:
                lines.append("<wielded>             " + self.weapon)
        else:
            lines = QUIET.get(cmd, [f"(fake relay) no canned answer for '{cmd}'"])
        self.post("/events", [self.ev("quiet", {"cmd": cmd, "lines": lines})])

    def handle(self, cmd):
        word = SHORT.get(cmd.strip().lower(), cmd.strip().lower())
        print(f"  <- {cmd!r}")
        if word == "look":
            self.post("/events", self.room_events(self.room))
            return
        if word == "time":
            self.post("/events", [self.ev("line", {"text": t, "prompt": False}) for t in [
                "", f"It is {self.time} on Thursday, May 26, 300 BC.",
                f"The almanac indicates there will be a {self.moon} moon tonight.", "",
                "MUD started up at Wed Sep 30 19:40:36 2026.",
                "The system time is Thu Oct  1 19:57:58 2026.",
                "-" * 79]] + [self.ev("line", {"text": PROMPT, "prompt": False})])
            return
        if word == "weather":
            self.post("/events", [self.ev("line", {"text": "", "prompt": False}),
                                  self.ev("line", {"text": self.weather, "prompt": False}),
                                  self.ev("line", {"text": PROMPT, "prompt": False})])
            return
        m = re.match(r"^(open|close) (?:the )?(?:\w+ )?(north|south|east|west|n|s|e|w)$", word)
        if m:
            d = SHORT.get(m.group(2), m.group(2))
            closed = ROOMS[self.room].setdefault("closed", {})
            msg = "You open the doors." if m.group(1) == "open" else "You close the doors."
            if m.group(1) == "open":
                closed.pop(d, None)
            else:
                closed[d] = "The doors are closed."
            # the other side shares the door
            ex = next((e for e in ROOMS[self.room]["exits"] if e["dir"] == d), None)
            if ex and ex["to_vnum"] in ROOMS:
                back = {"north": "south", "south": "north", "east": "west", "west": "east"}[d]
                oc = ROOMS[ex["to_vnum"]].setdefault("closed", {})
                if m.group(1) == "open":
                    oc.pop(back, None)
                else:
                    oc[back] = "The doors are closed."
            print(f"     {msg}")
            self.post("/events", [self.ev("line", {"text": msg, "prompt": False}),
                                  self.ev("line", {"text": PROMPT, "prompt": False})])
            return
        if word in ("fight", "flee"):
            self.post("/events", [self.ev("status", {"fighting": word == "fight"}),
                                  self.ev("line", {"text": f"(fake relay) You {word}.", "prompt": False}),
                                  self.ev("line", {"text": PROMPT, "prompt": False})])
            return
        if word.startswith("look "):
            target = word[5:].strip()
            if "." in target:
                target = target.split(".", 1)[1]
            out = ROOMS[self.room].get("looks", {}).get(target, ["You do not see that here."])
            evs = [self.ev("line", {"text": t, "prompt": False}) for t in out]
            evs.append(self.ev("line", {"text": PROMPT, "prompt": False}))
            self.post("/events", evs)
            return
        here = ROOMS[self.room]
        ex = next((e for e in here["exits"] if e["dir"] == word), None)
        if word in SHORT.values() and ex and ex["to_vnum"] in ROOMS and word not in here.get("closed", {}):
            self.room = ex["to_vnum"]
            print(f"     moved to {self.room} {ROOMS[self.room]['name']}")
            self.post("/events", self.room_events(self.room))
        elif word in SHORT.values():
            msg = here.get("closed", {}).get(word, "Alas, you cannot go that way.")
            print(f"     refused: {msg}")
            self.post("/events", [self.ev("line", {"text": msg, "prompt": False}),
                                  self.ev("line", {"text": PROMPT, "prompt": False})])
        else:
            self.post("/events", [self.ev("line", {"text": f"(fake relay) You {cmd}.", "prompt": False}),
                                  self.ev("line", {"text": PROMPT, "prompt": False})])

    def run(self):
        while True:
            try:
                if self.session is None:
                    self.hello()
                with urllib.request.urlopen(f"{BASE}/commands?s={self.session}", timeout=30) as r:
                    for c in json.loads(r.read() or b"[]"):
                        if c.get("kind") == "raw":
                            self.handle(c.get("cmd", ""))
                        elif c.get("kind") == "quiet":
                            self.quiet(c.get("cmd", ""))
                        elif c.get("kind") == "resync":
                            self.post("/events", [self.ev("snapshot", {"room": self.room_info(self.room)})])
            except urllib.error.HTTPError as e:
                if e.code == 409:
                    self.session = None
                else:
                    raise
            except (urllib.error.URLError, ConnectionError, TimeoutError):
                if self.session is not None:
                    print("lost Legend3D; retrying")
                self.session = None
                time.sleep(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--time", default="2:30 pm", help='game clock, e.g. "11:30 pm"')
    ap.add_argument("--start", type=int, default=11663, help="starting vnum")
    ap.add_argument("--moon", default="waxing gibbous", help='e.g. "full", "waning crescent"')
    ap.add_argument("--weather", default="The sky is filled with puffy white clouds on this spring day.")
    ap.add_argument("--weapon", default="sword", help="sword, dagger, axe, spear, staff, mace or none")
    ap.add_argument("--light", default="torch", help="torch, lantern, candle or none")
    args = ap.parse_args()
    print("fake relay: waiting for Legend3D on", BASE)
    try:
        Relay(args.start, args.time, args.moon, args.weather, args.weapon, args.light).run()
    except KeyboardInterrupt:
        print("bye")


if __name__ == "__main__":
    main()
