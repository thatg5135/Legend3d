# Changelog

Legend3D by **Arkhanst**. Newest first. The relay is the Mudlet package
(`mudlet/Legend3D.xml`); when its version changes, reinstall it in Mudlet.

---

## B1: HUD, hands & menu
**Relay v0.4.0** · October 2026

### Added
- **Brass compass** in the bottom left of the 3D view. The card turns as
  you do, so the red N always points north, like a real compass.
- **Health, mana and moves bars** beside it, with the numbers, straight
  from Legend's prompt. Health pulses when it's low.
- **Weapon and light in hand**, first person: the weapon you wield on the
  right (sword, dagger, axe, mace, hammer, spear, staff, bow, whip), your
  light on the left (torch, lantern, candle, glowing orb). They sway as
  you walk and are lit by where you are.
- **A carried light lights the world** around you: torches flicker,
  lanterns burn steady.
- **The menu (Tab)**, styled as parchment scrolls, with a leather-bound
  ledger for settings:
  - Character: Equipment (Look, Remove), Inventory (counted; each item
    shows its description and the commands that suit it: Wear, Wield,
    Eat, Drink, Drop...), Score.
  - Spellbook: Spells (name, words of power, mana and level; click to
    start typing `cast '...'`), Skills.
  - World: Map of everything explored (zoom, pan, levels, click a room),
    Notes, People & things (edit how anyone is drawn without touching
    files).
  - Settings: Video (quality, pixel size, sun rays, frame limit, field of
    view, mouse look speed), Audio (sounds, volume), Controls, Interface
    (HUD size, compass, bars, hands, labels).
  - Help: link status, your keys, the help file.
- **Every key is rebindable**, including mouse buttons, with warnings for
  clashes and for plain letters (which also type).
- **Your own shortcut keys** that send commands to Legend through your
  Mudlet aliases.
- **Settings are saved** in `godot/data/settings.json`.
- **`/note <text>`** saves a note about the room you're in, for mapping
  (`/note`, `/notes`, `/menu` too). Kept in `godot/data/notes.json`.
- **Real upper floors.** Indoor rooms joined by stairs are one building:
  - taller from the street, with a timber band at each floor and windows
    on each storey
  - a real floor overhead with joists, and a stairwell opening with rails
  - stairs that arrive on the upper floor, walkable both ways with no
    jump at the top or bottom
  - upstairs rooms built inside the same walls; a hall that "stretches
    farther than seems possible" fades into darkness at both ends
- **Rushlights** on the walls of rooms with no light of their own.

### Relay
- Passes health, mana and moves from GMCP `char.prompt`.
- Passes inventory and item changes from GMCP `char.inventory` and
  `char.items`.
- Runs `equipment` (on linking and after gear changes) and `spells`,
  `skills`, `score` (when you open those pages) quietly, with their output
  hidden. One at a time, never while fighting or typing.

### Changed
- Saved rooms are refurnished once (indoor stairs moved to make room for
  the upper floors).

---

## A2 hotfix: grey screen
- Starting the project with Run instead of Edit after an update showed
  only a grey window, because Godot hadn't registered a new script file.
  The registration file now ships with every update. Troubleshooting
  added to HELP.md.

---

## A2: look, light & weather
**Relay v0.3.0** · October 2026

### Fixed
- Roofs and walls clipping into each other.
- Walls dark from outside and roofs grey (faces were inside out).
- NPCs shown twice.
- Daylight wrong when seen through doors and windows.
- Sky showing through gaps beside doorways.
- A made-up building drawn at every exit, even in open country.
- Names of people in other rooms showing through walls.
- Stairs poking out through the inn's roof.
- Floor not meeting the wall in round rooms.
- Auto-scan looking at the wrong word ("seeds" for a field mouse, "clump"
  for a clump of flax).

### Added
- **Doors** open or closed, read from Legend's exits line (`[n]` means
  closed), animated when you open or close them, and saved.
- **Walkable stairs** for indoor up and down exits; ladders only where the
  description mentions a ladder, loft or hatch.
- **Outdoor edges from the text:** palisades, fences, hedges, walls,
  treelines, water; otherwise open ground or low scrub.
- **Big places look big from outside:** a dun, a tower, anything "huge".
- **Windows** where the text mentions them; halls get a couple anyway.
- **La Tène art:** spirals and triskeles on painted posts, carved door
  lintels, woven wall hangings.
- **Thick thatch with deep eaves**, rafters and purlins inside, drystone
  footings, daubed walls (bare wattle in huts).
- **Smoke** seeping through the thatch above any fire.
- **Painted textures** throughout, generated in code.
- **Sky:** gradient, sun, a moon showing its phase, stars, two layers of
  drifting clouds.
- **Sun and moon by date**, at Tara's latitude, with seasonal day length.
- **Moon phase from Legend's almanac** sets how bright nights are; a full
  moon casts shadows.
- **Weather from Legend:** clear, cloudy, overcast, rain, snow, fog, wind,
  and storms with lightning; overcast and storms darken the scene.
- **Light through doors and windows** as beams when the sun or moon is
  on that side.
- **Sun rays** (crepuscular rays) toward a low sun.
- **Per-light shadows** from fires and lamps, with a light budget so it
  runs well; fine dither.
- **Grass** that sways.
- **Right-click mouse look**, including up and down.

### Relay
- Quiet background checks: `time` every 4 minutes and `weather` every 2,
  with the output and its prompt hidden from you. Skipped while fighting
  or while you're typing in Mudlet.

---

## Phase A: a persistent, furnished Tara
**Relay v0.2.0**

### Added
- **Saved map:** every room you visit is remembered (description, exits,
  position, last-seen contents, furnishing) and standing when you start.
- **Rooms are furnished once** and look the same every visit; refurnished
  only if Legend's description changes. Hand edits can be locked.
- **Auto-scan:** about a second after you enter a room, Legend3D `look`s
  at anything new. Stops if you leave; never runs during a fight and
  catches up afterwards.
- **Animals drawn as animals,** at real size: pigs, sows, boars, hounds,
  wolves, foxes, horses, ponies, cows, bulls, sheep, goats, cats, rats,
  badgers, bears, deer, stags, hens, geese and birds.
- **Counts:** `(2) A muddy pig is here.` draws two pigs labeled ×2.
- **Building sizes by type:** hut, house, hall, great hall, with words
  like "simple" or "huge" nudging the size; a 24 m grid so rooms have
  space.
- **Furnishings placed where the text says**, each relative to the last
  ("a chair next to a table beside the hearth").
- **Period props:** looms, yarn, wool bales, spindles, rocking chairs, box
  beds, querns, storage jars, forges, hay ricks, casks, firewood,
  hurdles...
- **Clutter** that suits each room, never people or animals, never
  contradicting the text, kept out of walkways.
- **Type without clicking** the command line: any letter starts a command.
- Warm firelight and smoother lighting.

### Relay
- Tells the view when you're fighting (from GMCP `char.prompt`).

---

## Rooms, people and light

### Added
- **Rooms sized and shaped from their descriptions**, bigger rooms, and
  Celtic roundhouses for Celtic Ireland (stone, timber and thatch for the
  Silver Branch Inn).
- **Doorway-style room crossing:** walk to a doorway and the move is sent;
  the way stays shut until Legend agrees, and a refused move no longer
  bounces you back halfway through.
- **People only from the room listing**, as named sprites standing still.
- **NPC catalog and scanning:** `look` results become names (Tika, the
  tired serving maid), clothes, colors and what they hold, saved in
  `npcs.json`, which you can edit. Your own sprites can replace generated
  ones.
- **Lights:** lanterns, torches and hearths with flicker, each casting its
  own pixel-style shadows; outdoor shadows from the sun and moon.
- **Quality setting and FPS readout** for modest hardware.
- **`fake_relay.py`** to try the view without logging in.

---

## First link
**Relay v0.1.0 to v0.1.2**

### Added
- The Mudlet relay: links Mudlet to the 3D view over a private local
  connection, passes room data and every line of text, and runs the
  view's commands through your aliases. `3d`, `3d on`, `3d off`.
- The first 3D view in Godot: rooms laid out from their exits, arrow keys
  to walk, the text log and a command line.
- `test_listener.py` to check the relay works.

### Fixed
- v0.1.1: Mudlet's HTTP events passing their arguments in a different
  order than expected.
- v0.1.2: JSON functions called by the wrong names (`yajl.to_string`).
