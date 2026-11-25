extends RefCounted
## Move-effect colours: IX's armor families (charge, shots, specials, dash, flight),
## SABLE's sword styles and ECHO's rounds.
## They follow the sprite kit (tools/sprites/ix_kit.gd PAL: armor, trim, energy r/t):
##   neutral   cyan energy, amber full charge (the original identity)
##   vanguard  crimson armor, magenta energy, gold trim   (brawler: claw, rush)
##   aero      white armor, blue energy, gold trim        (knight: lance, wings)
##   ultimate  black-violet armor, gold energy            (nova)
## Every ramp is [dark rim, mid, light, core].

const ENERGY := {
	"neutral": [Color("17869a"), Color("3de0ee"), Color("a6f6fb"), Color("ffffff")],
	"vanguard": [Color("86142a"), Color("ff3d8a"), Color("ffc8e4"), Color("ffffff")],
	"aero": [Color("1f5fb8"), Color("2f8cff"), Color("c8ecff"), Color("ffffff")],
	"ultimate": [Color("a3681a"), Color("f0b84a"), Color("fff0b0"), Color("ffffff")],
}
## Second ramp: neutral amber, vanguard crimson armor, aero white-gold, ultimate violet.
const ACCENT := {
	"neutral": [Color("b4661c"), Color("f0b84a"), Color("ffe08a"), Color("fff6d8")],
	"vanguard": [Color("4a0a16"), Color("c2283c"), Color("ec5a5a"), Color("ffb4a8")],
	"aero": [Color("8a5a10"), Color("e8b040"), Color("fff0b0"), Color("ffffff")],
	"ultimate": [Color("1e1430"), Color("5c4296"), Color("8a6cc8"), Color("c8b4f0")],
}
## Afterimage tint per family (the armor colour, so ghosts read as that suit).
const GHOST := {
	"neutral": Color("3de0ee"),
	"vanguard": Color("e0304a"),
	"aero": Color("6fb4ff"),
	"ultimate": Color("8a63d2"),
}
## Gold trim ramp (Vanguard / Aero trim, Ultimate energy), for sparks and lance heads.
const GOLD := [Color("8a5a10"), Color("e8b040"), Color("fff0b0"), Color("ffffff")]
## SABLE's saber, one ramp per sword style (SaberAttack.style):
##   0 섬광류 flash   cyan-white, thin and long
##   1 파쇄류 crush   ember orange, thick and heavy
##   2 반격류 counter moon violet, calm with a bright edge
const SABER := [
	[Color("17869a"), Color("3de0ee"), Color("b8fbff"), Color("ffffff")],
	[Color("8a2a10"), Color("e0582e"), Color("f8a850"), Color("fff0c8")],
	[Color("3a2a7a"), Color("8a6cd8"), Color("d0c4ff"), Color("ffffff")],
]
## ECHO: green rounds, violet copy data.
const ECHO_GREEN := [Color("2a8c60"), Color("5ad19a"), Color("b8f4d7"), Color("ffffff")]
const ECHO_VIOLET := [Color("7a52c4"), Color("b78af3"), Color("e2d2ff"), Color("ffffff")]
## Which family a full-set special belongs to.
const SPECIAL_FAMILY := {"overdrive": "vanguard", "skybreaker": "aero", "nova": "ultimate"}


static func energy(family: String) -> Array:
	return ENERGY.get(family, ENERGY.neutral)


static func accent(family: String) -> Array:
	return ACCENT.get(family, ACCENT.neutral)


static func ghost(family: String) -> Color:
	return GHOST.get(family, GHOST.neutral)


## Charge colour shown at charge level 1 / 2 (aura, muzzle spark, body tint).
static func charge_color(family: String, level: int) -> Color:
	if family == "neutral" or family == "":
		return Color("f0b84a") if level >= 2 else Color("3de0ee")
	if family == "aero":
		return energy(family)[2] if level >= 2 else energy(family)[1]
	# Vanguard crimson -> magenta, Ultimate violet -> gold.
	return energy(family)[1] if level >= 2 else accent(family)[2]


## Name of the baked charge aura strip (art/fx) for a family and level.
static func charge_strip(family: String, level: int) -> String:
	if family == "neutral" or family == "":
		return "charge_gold" if level >= 2 else "charge"
	return "charge_%s%d" % [family, mini(level, 2)]


## Name of the baked muzzle flash strip for the shot level.
static func muzzle_strip(family: String, level: int) -> String:
	if level < 2:
		return "muzzle"
	if family == "neutral" or family == "":
		return "muzzle_gold"
	return "muzzle_" + family


## Ramp of SABLE's sword style (clamped to the three styles).
static func saber(style: int) -> Array:
	return SABER[clampi(style, 0, SABER.size() - 1)]
