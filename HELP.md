# Legend3D Help

By Arkhanst. See [README.md](README.md) for the overview and
[CHANGELOG.md](CHANGELOG.md) for the full history.

A Meridian 59-style 3D view for LegendMUD that runs alongside Mudlet.
Mudlet stays connected to Legend and keeps all your scripts. Legend3D
draws the world and talks to Mudlet over a private link on your own
computer.

Current versions: **relay v0.4.0** (Mudlet) · **view B1: HUD, hands & menu** (Godot 4.7.2)

---

## 1. Quick start

1. **Install the relay in Mudlet:** drag `mudlet/Legend3D.xml` onto the
   Mudlet window, or use Package Manager → Install. You should see
   `[Legend3D] relay v0.4.0 loaded.`
2. **Open the view in Godot** (first time only): Project Manager →
   **Import** → `legend3d/godot/project.godot` → **Import & Edit**.
3. **Run it:** press **▶ Run Project** (top right) or **F5**.
4. Within a couple of seconds the status bar says **linked**.
5. **Type `look`** once so it learns what's in the room. After that,
   rooms fill themselves in as you walk.

Start Mudlet and Legend3D in either order.

**Updating to a new version:**
1. Close Godot.
2. Unzip over your `legend3d` folder. Your data files aren't in the zip,
   so they're safe.
3. If the relay version changed, remove `Legend3D` in Mudlet's Package
   Manager and install the new `Legend3D.xml`.
4. Reopen Godot and run.

---

## 2. Commands

### In Mudlet

| Command | What it does |
|---------|--------------|
| `3d` | Shows the relay version and whether it's linked |
| `3d on` | Turns the relay on and looks for Legend3D |
| `3d off` | Turns the relay off (Legend3D stops getting updates) |

**Background checks:** while linked, the relay quietly sends `time` about
every 4 minutes and `weather` about every 2. It also asks for
`equipment` when it links and after you change gear, and for `spells`,
`skills` or `score` when you open those pages in the menu. You never see
these: the output and its prompt are hidden. They're skipped while
you're fighting or while you have something half-typed in Mudlet.
Typing any of them yourself works as normal.

### In Legend3D's command line

| Command | What it does |
|---------|--------------|
| anything else | Sent to Legend through Mudlet, exactly as if you typed it there. Your aliases and mapper still apply. |
| `/note <text>` | Saves a note about the room you're in, for mapping (e.g. `/note this touches the inn on the west`) |
| `/note` | Shows this room's notes |
| `/notes` | Opens your notes in the menu |
| `/menu` | Opens the menu |
| `/scan all` | Looks again at everything in the room and updates the catalog |
| `/scan` | Looks at anything in the room not yet in the catalog (normally automatic) |

Commands starting with `/` stay in Legend3D and never reach the MUD.

---

## 3. Keys

**Every key can be changed** in the menu: Settings → Controls. These are
the defaults.

| Key | What it does |
|-----|--------------|
| Up / Down arrows | Walk forward / back |
| Left / Right arrows | Turn |
| Right mouse button | Mouse look on/off: move the mouse to look around and up and down |
| Shift (held) | Run |
| Alt + Left / Right | Sidestep |
| Tab | Opens and closes the menu |
| Ctrl + I | Character (equipment, inventory, score) |
| Ctrl + B | Spellbook |
| Ctrl + M | World (map, notes, people & things) |
| Ctrl + O | Settings |
| F1 | Help |
| Any letter | Starts typing a command (no clicking needed) |
| Enter | Sends the command |
| Ctrl + Up / Down | Steps through command history |
| Esc | Closes the menu, lets go of the mouse, or clears the command line |
| Page Up / Page Down | Scrolls the text log |
| F2 | Sound on/off (off by default, so it doesn't double up with Mudlet) |
| F3 | Pixel size: chunkier or finer |
| F4 | Quality: low / medium / high (starts on high) |
| F5 | Reloads your edited data files |

**Your own shortcuts:** Settings → Controls → *Add a shortcut* binds a key
to a command for Legend (F6 → `cast 'heal'`). It goes through your
Mudlet aliases like anything you type.

**About plain letters:** you can bind a plain letter (say `I` for
inventory), but since letters also start typing, it only works when the
command line is empty. Controls warns you when that applies, or when two
things share a key.

---

## 4. Features

### Moving between rooms

- **Walk toward a doorway** or across the open edge between outdoor
  rooms, and Legend3D sends the direction (`north` and so on) as you get
  close.
- **The way stays shut until Legend agrees,** then you step through.
- **If Legend refuses** (a closed door, no exit), you just can't pass.
  It sends the command once, not over and over. Step back to try again.
- **Stairs:** indoor up and down exits are real staircases. Walk up
  them, or down through the opening in the floor. Ladders only appear
  when the description mentions a ladder, loft or hatch.
- **Diagonal exits, and up/down outdoors,** are gold pads on the ground.
  Walk onto the pad.
- **Moving by typing** (in Mudlet or Legend3D) works too; the view
  follows.

### Doors

- Legend shows a closed door in brackets: `[Exits: [n] s]` means north is
  closed. The view draws that door shut.
- **Type `open north`** (or close, lock, unlock) and the door swings to
  match once Legend says it happened.
- Doors are remembered in your saved map, so a door you left open is
  still drawn open next time, until Legend says otherwise.

### Outdoors

- Open ground between outdoor rooms stays open. A building only appears
  where Legend says there is one: an indoor room next door, a name like
  "inn" or "cottage", or a door in a wall.
- The edge of an outdoor room follows its description: a palisade or
  fence, a hedge, a wall, a treeline, water. Otherwise low scrub.
- Big places seen from outside (a dun, a tower, anything "huge") are
  drawn big until you go in and Legend tells us more.
- Grass sways a little.

### Who and what is in a room

Everything Legend lists after a room's `[Exits: ...]` line shows up:

- **People** as sprites with their name above them.
- **Animals as animals,** at real size: pig, sow, boar, hound, wolf,
  fox, horse, pony, cow, bull, sheep, goat, cat, rat, badger, bear, deer,
  stag, hen, goose and birds.
- **Things** as props: a mailbox, a chest, a notice board and so on.
- **Counts:** `(2) A muddy pig is here.` draws two pigs, labeled "×2".

Names over people are hidden behind walls and nudged apart so they don't
overlap.

### Auto-scan and the NPC catalog

About a second after you enter a room, Legend3D `look`s once at anything
it hasn't seen before:
- It stops if you leave the room.
- It **never runs while you're fighting,** and catches up afterward.
- Each look shows in Mudlet's scrollback.

What it learns is saved in `godot/data/npcs.json`:
- **Real names:** "A tired serving maid" becomes **Tika** once she's
  been looked at.
- **Looks:** sex, clothing, colors and what they're holding, from their
  description and equipment.
- **Body:** human or which animal.

### How rooms are built

Each room is built from its own description:

- **Size from what it is:** huts and cottages are small, houses medium,
  inns and halls large, royal and great halls the largest. Words like
  "simple" or "huge" nudge it.
- **Shape:** Celtic Ireland is round; "long hall", "corridor" or "lined
  with doors" makes a long hall.
- **Furnishings where the text says:** "a loom taking the entire west
  side", "wool tossed into one corner", "a chair next to a table beside
  the hearth" (each placed relative to the last).
- **Clutter:** period odds and ends that suit the room (spindles and
  baskets at a weaver's, casks and firewood at the inn, hay ricks in the
  village). It never adds people or animals, never contradicts the
  description, and stays out of walkways.
- **Style:** Celtic Ireland is built as it was around 300 BC: round
  houses with drystone footings, daubed walls (bare wattle in huts),
  timber posts, thick conical thatch with deep eaves, and earth floors
  strewn with rushes.
- **Windows** where the text mentions them; halls get a couple anyway.
- **Celtic art:** La Tène spirals and triskeles on painted posts, carved
  door lintels, and woven wall hangings in bigger rooms.
- **Smoke** rises through the thatch of any building with a fire inside
  (no chimneys in 300 BC; the smoke seeps out through the roof).
- **Painted textures:** everything is hand-painted-looking at low
  resolution, a bit like Daggerfall but softer.

### Buildings with more than one floor

When an indoor room's way up leads to another indoor room, they're one
building:

- **The outside is as tall as the inside:** a two-storey inn is two
  storeys from the street, with a timber band where the upper floor sits
  and windows on each floor.
- **There's a real upper floor.** From downstairs you see its joists and
  planks overhead; the stairs climb through an opening with a rail round
  it. From the top you can look back down into the room below.
- **Upstairs rooms sit inside the same walls.** A long hall upstairs (like
  the Reception) runs alongside the stairwell. If Legend says it goes on
  further than it should, its ends fade into the dark.
- **Rooms with no light of their own** get a couple of rushlights on the
  walls.
- Before you've been inside, a building seen from the street is a
  one-storey guess. Once you've gone up, it's rebuilt at its real height.

**Rooms are furnished once and saved.** They look the same every visit
and every session; nothing pops in or rearranges. A room is only
refurnished if Legend's description of it changes.

### Light, sky and weather

- **The sun and moon move with Legend's clock and calendar.** Days are
  long in summer and short in winter, as they are in Ireland.
- **The moon follows Legend's almanac:** a full moon lights the night and
  casts shadows; a new moon leaves it dark.
- **The sky** has clouds, stars and a moon you can see the phase of.
- **Weather follows Legend's `weather`:** clear, puffy clouds, overcast,
  rain, snow, fog, wind, and storms with lightning. Overcast and storms
  darken the whole scene.
- **Light through doorways and windows:** daylight or moonlight falls in
  as a beam when the sun or moon is on that side, and the view outside
  matches the time of day.
- **Sun rays:** looking toward a low sun, light streams past roofs and
  trees.
- **Indoors,** hearths, lanterns and torches light the room. Hearths
  flicker, and each light casts its own shadows. "Dim" or "dark" in a
  description makes a room darker.
- **Quality (F4):**
  - **low:** no shadows from lamps or fires, no sun rays
  - **medium:** the nearest fire or lamp casts shadows; sun rays on
  - **high:** the two nearest do (the default)
- **The status bar shows frames per second.** Aim for 30 or better;
  drop quality or press F3 if it's lower.

### The HUD

Bottom left of the 3D view:

- **A brass compass.** Its card turns as you do, so the red N always
  points north, like a real compass. Your heading is under the little
  pointer at the top.
- **Health, mana and moves** bars beside it, with the numbers, straight
  from Legend's prompt. Health pulses when it's low.
- **What's in your hands,** first person: the weapon you're wielding on
  the right and your light on the left. A torch, lantern or candle you
  carry lights the scene around you and flickers. They sway as you walk.

Size and each part can be turned off in Settings → Interface.

### The menu (Tab)

Parchment scrolls, and a ledger for settings:

- **Character:**
  - *Equipment:* what you're wearing, with Look and Remove.
  - *Inventory:* what you carry, counted. Pick an item to read it and
    get the commands that suit it (Wear, Wield, Eat, Drop...).
  - *Score:* Legend's score sheet.
- **Spellbook:**
  - *Spells:* name, words of power, mana and level (Legend's `(50:25)`
    is read as mana:level). Click a spell to start typing `cast '...'`.
  - *Skills:* your skill list.
- **World:**
  - *Map:* everything you've explored, from above. Wheel zooms, drag
    moves, the arrows change level, click a room for its notes.
  - *Notes:* your `/note`s by room. Add or delete them here.
  - *People & things:* the NPC catalog. Pick someone to change how
    they're drawn (hair, clothes, what they hold) without editing files.
- **Settings:**
  - *Video:* quality, pixel size, sun rays, frame limit, field of view,
    mouse look speed.
  - *Audio:* Legend's sounds on/off, volume.
  - *Controls:* every key, and your own shortcuts.
  - *Interface:* HUD size, compass, bars, hands, labels.
- **Help:** link status, your keys, and this file.

Settings save as you change them. You can still type commands while the
menu is open.

### Notes for mapping (`/note`)

Some things Legend's text can't tell Legend3D: that two rooms touch
without an exit between them, or that a street is longer than the
others. Note them as you walk:

    /note this touches the inn on the west
    /note this street is twice as long as the others

Each note is saved with the room it was made in. Nothing is sent to
Legend. Notes are what Tara will be laid out from, as one village.

### The saved map

Every room you visit is remembered: Legend's description and exits,
where it sits, what was last seen in it, and its furnishings. When you
start Legend3D, everything you've explored is already standing.

### Sound

**F2** plays Legend's ambient sounds (tavern noise and so on) in
Legend3D. It's off by default because Mudlet already plays them.

---

## 5. Your files

All in `godot/data/`. **Back these up**; they're your explored world.

| File | What it holds |
|------|---------------|
| `map.json` | Every room you've visited and its furnishing |
| `npcs.json` | Everything learned about NPCs and objects |
| `room_overrides.json` | Your quick fixes for how rooms look |
| `notes.json` | Your `/note`s, by room |
| `settings.json` | Your keys, shortcuts and settings (easiest to change in the menu) |
| `sprites/` | Your own hand-drawn sprites (optional) |

**Starting fresh?** `room_overrides.example.json` and `npcs.example.json`
show the format. Copy one to `room_overrides.json` / `npcs.json` if you
don't have that file yet; Legend3D also creates `npcs.json` on its own.

**Editing:** close Legend3D or press **F5** after saving. If a file has
a typo, Legend3D says it couldn't read it and carries on without it.

### Changing how someone looks (`npcs.json`)

Find them and fill in `appearance`. It always beats the automatic
guess, and re-scanning never erases it. For example:

    "appearance": {"age": "20s", "hair_color": "red", "hair": "long", "held": "tray with drinks"}

Options: `sex`, `age`, `build`, `skin`, `hair` (long, short, braid, bun,
bald), `hair_color`, `beard`, `garment` (dress, tunic, robe, armor),
`garment_color`, `legs_color`, `belt_color`, `cloak_color`,
`shoes_color`, `held` (tray, basket, harp, sword, spear, staff, mug,
torch, shield), `accessory`, `height`.

**For animals,** set `"body"` (pig, hound, horse...) and an
`appearance` `color`, e.g. `{"color": "black"}`.

### Fixing a room

- **Quick fixes** go in `room_overrides.json`, keyed by the room's vnum:
  - `size`: hut, house, hall or great
  - `shape`: round, square or long
  - `light`: 0.1 for dark up to 1.0 for bright
  - `props`: things to add, e.g. `[{"type": "hearth", "at": "on the north wall"}]`
  - `no_auto_props`: true to use only your own props

  The file lists every option.
- **Exact fixes** go in `map.json`: edit the room's `layout` (each item
  is a type, a position in meters from the room's center, and a
  rotation), then set `"layout_locked": true` so it's never redone.
- **Start a room over:** delete its entry in `map.json`.

### Your own sprites

Put a PNG in `godot/data/sprites/` named after the NPC (`tika.png`) or
their short description (`a_tired_serving_maid.png`). Use a transparent
background, about twice as tall as wide. It replaces the generated
sprite.

---

## 6. Troubleshooting

**It won't link.**
1. Type `3d` in Mudlet. It should say *on*, then *linked* within a few
   seconds of Legend3D starting.
2. If it says `off`, type `3d on`.
3. Make sure only one thing is using the link: close `test_listener.py`,
   `fake_relay.py`, or a second copy of Legend3D.

**"Can't open port 7359"** means something else is already using the
link. Close the other program (see above) and restart Legend3D.

**My changes don't show up** (or it's still the old version): Godot may
be opening an old copy. Check the FileSystem panel in the editor. If
the files you expect aren't there, use Project → Quit to Project List →
Import, and pick the right `project.godot`.

**Just a grey window** (and it won't close): Godot couldn't load the
scripts, usually because a new version added files it hasn't registered.
Close it with **Alt+F4**, or open a terminal (**Ctrl+Alt+T**) and type
`pkill -f Godot`. Then in the Project Manager, click **Edit** (not Run),
wait for it to finish loading, and press **F5**. Once is enough.

**No health bars, compass needle stuck, or empty equipment page:**
Mudlet still has an older relay. Type `3d` in Mudlet; it should say
v0.4.0. If not, reinstall `Legend3D.xml`.

**A key does nothing:** check Settings → Controls. A plain letter only
works with the command line empty, and two things on one key show a
warning.

**Nobody shows up in a room.** Type `look` once after linking.

**A room looks wrong.** See *Fixing a room*, or report it with the
room's description so the builder can learn from it.

**It's slow.** Check the FPS on the status bar. Press F4 for lower
quality, or F3 for chunkier pixels.

---

## 7. Test tools (no MUD needed)

In a terminal, from the `legend3d` folder:

| Command | What it does |
|---------|--------------|
| `python3 tools/test_listener.py` | Stands in for Legend3D to check the Mudlet relay works |
| `python3 tools/fake_relay.py` | Stands in for Mudlet and Legend with a pretend bit of Tara |
| `python3 tools/fake_relay.py --time "11:30 pm"` | Same, at night |
| `... --moon full` | Sets the moon phase (new, waxing crescent, full...) |
| `... --weather "It is raining heavily."` | Sets the weather sentence |
| `... --weapon axe --light lantern` | What you're holding (sword, dagger, axe, spear, staff, mace, none; torch, lantern, candle, none) |

The fake relay mixes real Legend text (the Silver Branch Inn, Tika, the
Main Path, the Reception, the Weaver's Cottage description, the Door to
the Dun with its closed door) with invented stand-ins. In it, `fight` and
`flee` test the combat pause, and `open north` / `close north` work at
the Door to the Dun. Its equipment, inventory, spells and score are
invented.

**Note:** the fake relay adds its pretend rooms to your saved map. Move
`godot/data/map.json` somewhere safe before using it, and put it back
after.

---

## 8. What's coming

In this order:
1. **Real terrain:** hills, cliffs, flying and falling, hell areas; and
   strange places that are bigger inside than out, laid out around
   wherever you are.
2. **Tara as a village:** timber palisade and main gate, the dun at
   center-north with the path around it, and the enchanted forest beyond.
   Rooms get their own sizes and touch where your notes say. (Needs Tara
   mapped, with notes.)
3. **Gwyn's Dun** as a real three-level building, the outside matching
   the inside.
4. **Daggerfall-style character sprites** built from what NPCs wear.
5. **Other players.**
6. **Interaction prompts** ("sit here").

---

## 9. Changelog

The full history is in [CHANGELOG.md](CHANGELOG.md). The latest:

**B1: HUD, hands & menu** (relay v0.4.0)
- Brass compass that turns as you do; health, mana and moves bars.
- Your weapon and light in hand, first person; a carried light lights the
  scene.
- The menu: Character (equipment, inventory, score), Spellbook, World
  (map, notes, people & things), Settings ledger (video, audio, controls,
  interface), Help.
- Every key rebindable, plus your own command shortcuts; settings saved.
- `/note` for mapping.
- Buildings with an upper floor are built as one: taller outside, a real
  floor overhead, stairs that arrive somewhere, upstairs rooms inside the
  same walls.
- Unlit rooms get rushlights.
- Relay: passes health/mana/moves and inventory from GMCP; runs
  equipment/spells/score checks quietly when the view asks.
- Your saved rooms are refurnished once with this update (indoor stairs
  moved to make room for the upper floors).
