extends RefCounted
## The trick book: 25 air tricks plus spins from 180 to 1080.
##
## In the air, press a trick button with an optional direction (W/A/S/D) and an
## optional Shift:
##   E = flip tricks, F = grabs (hold), R = style tricks, Q = spin (hold).
## Every flip turns the board whole turns (or half turns on the vertical axis), so it
## always lands wheels-down. Land before a trick finishes and you bail.

## Each entry: [name, points, seconds, board roll turns, board yaw turns, board pitch turns, pose]
## For grabs, points are per second held and seconds is the minimum hold.
const BOOK := {
	"flip": {
		"": ["Kickflip", 150, 0.40, 1.0, 0.0, 0.0, 0],
		"W": ["Varial Kickflip", 250, 0.50, 1.0, 0.5, 0.0, 0],
		"A": ["Heelflip", 150, 0.40, -1.0, 0.0, 0.0, 0],
		"S": ["Impossible", 300, 0.55, 0.0, 0.0, 1.0, 0],
		"D": ["Pop Shove-it", 120, 0.35, 0.0, 0.5, 0.0, 0],
	},
	"flip+": {
		"": ["Double Kickflip", 350, 0.60, 2.0, 0.0, 0.0, 0],
		"W": ["360 Flip", 400, 0.60, 1.0, 1.0, 0.0, 0],
		"A": ["Inward Heelflip", 300, 0.50, -1.0, -0.5, 0.0, 0],
		"S": ["Hardflip", 350, 0.55, 1.0, 0.0, 1.0, 0],
		"D": ["Laser Flip", 400, 0.60, -1.0, 1.0, 0.0, 0],
	},
	"grab": {
		"": ["Indy", 180, 0.25, 0.0, 0.0, 0.0, 1],
		"W": ["Nosegrab", 180, 0.25, 0.0, 0.0, 0.0, 2],
		"A": ["Melon", 180, 0.25, 0.0, 0.0, 0.0, 3],
		"S": ["Tailgrab", 180, 0.25, 0.0, 0.0, 0.0, 4],
		"D": ["Method", 220, 0.25, 0.0, 0.0, 0.0, 5],
	},
	"grab+": {
		"": ["Stalefish", 220, 0.25, 0.0, 0.0, 0.0, 6],
		"W": ["Rocket Air", 260, 0.30, 0.0, 0.0, 0.0, 7],
		"A": ["Benihana", 240, 0.25, 0.0, 0.0, 0.0, 8],
		"S": ["Madonna", 260, 0.30, 0.0, 0.0, 0.0, 9],
		"D": ["Christ Air", 300, 0.30, 0.0, 0.0, 0.0, 10],
	},
	"style": {
		"": ["Airwalk", 200, 0.60, 0.0, 0.0, 0.0, 11],
		"W": ["Ollie North", 180, 0.50, 0.0, 0.0, 0.0, 12],
		"A": ["Judo", 220, 0.60, 0.0, 0.0, 0.0, 13],
		"S": ["Body Varial", 250, 0.55, 0.0, 0.0, 0.0, 14],
		"D": ["Superman", 300, 0.65, 0.0, 0.0, 0.0, 15],
	},
}

## Points for a spin, by half turns (1 = 180 ... 6 = 1080).
const SPIN_POINTS: Array[int] = [0, 100, 200, 350, 500, 700, 1000]
const MAX_HALF_TURNS := 6


static func lookup(kind: String, shift: bool, direction: String) -> Array:
	var table: Dictionary = BOOK[kind + ("+" if shift else "")]
	return table.get(direction, table[""])


static func spin_name(half_turns: int) -> String:
	return str(half_turns * 180)


## Every trick as "keys: name", for the in-game trick list.
static func trick_list() -> PackedStringArray:
	var keys := {"flip": "E", "flip+": "Shift+E", "grab": "F", "grab+": "Shift+F", "style": "R"}
	var lines := PackedStringArray()
	for kind in BOOK:
		for direction in BOOK[kind]:
			var combo: String = keys[kind] + ("" if direction == "" else "+" + direction)
			lines.append("%-10s %s" % [combo, BOOK[kind][direction][0]])
	lines.append("Hold Q     Spin 180 - 1080")
	return lines
