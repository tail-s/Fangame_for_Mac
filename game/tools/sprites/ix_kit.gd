extends RefCounted
## Hand-drawn pixel parts for IX (32-bit sprite style, original design).
## Grids are palette-indexed, facing right, "." = empty:
##   1-5  armor ramp (dark -> highlight)      p q s  accent (dark, base, light)
##   k l m  undersuit (dark -> light)         v w x  visor (dark, base, glint)
##   f g h  face (shadow, base, light)        y z    core gem (base, glint)
##   e i o  eye (lash line, iris, glint)     a b c  silver (claw arm)
##   r t    energy glow (base, bright, also the brow gem)
## Each armor family has its own grid for every part (helm, chest, pauldron, boot,
## buster), so the silhouette changes with the armor, not just the palette; see
## ix_model.gd for how they are placed.

## Per armor family: 1-5 armor ramp, p q s trim, r t energy glow, E G eye glow.
const PAL := {
	"neutral": {"1": "34466a", "2": "62799e", "3": "9fb4cf", "4": "d3e2f0", "5": "ffffff",
			"p": "0f6f7a", "q": "22b3be", "s": "93f0f2", "r": "13b9c2", "t": "b8ffff", "E": "0f6f7a", "G": "7ff6ff"},
	# Crimson brawler: red plate, gold trim, magenta energy, green eyes.
	"vanguard": {"1": "4a0a16", "2": "86142a", "3": "c2283c", "4": "ec5a5a", "5": "ffb4a8",
			"p": "8a5a10", "q": "e8b040", "s": "fff0b0", "r": "ff3d8a", "t": "ffc8e4", "E": "1f8a3a", "G": "8dff7a"},
	# White knight: white plate, gold trim, blue energy, green eyes.
	"aero": {"1": "56628a", "2": "95a3c4", "3": "cfd9ea", "4": "eef3fa", "5": "ffffff",
			"p": "8a5a10", "q": "e8b040", "s": "fff0b0", "r": "2f8cff", "t": "c8ecff", "E": "1f8a3a", "G": "8dff7a"},
	# Both at once: black-violet plate, gold trim, gold energy and eyes.
	"ultimate": {"1": "1e1430", "2": "3a2860", "3": "5c4296", "4": "8a6cc8", "5": "c8b4f0",
			"p": "8a5a10", "q": "f0b84a", "s": "ffe7a8", "r": "f0b84a", "t": "fff3c4", "E": "a3681a", "G": "ffe070"},
}
const COMMON := {"k": "1a2242", "l": "2e3b64", "m": "4a5a8a", "v": "a3681a", "w": "f0b84a", "x": "fff3c4",
		"f": "c98a6a", "g": "f0bd94", "h": "ffdcc0", "y": "13b9c2", "z": "e6ffff",
		"e": "142040", "i": "27b6d6", "o": "ffffff", "a": "4c5468", "b": "9aa4b8", "c": "e6ecf4"}

# --- head (anchor = head centre) --------------------------------------------------------

const HEAD_ANCHOR := Vector2i(8, 10)
## X6-era head (3/4 view, facing right), Gundam-style: the brow rim drops in a V
## from both temples to a teal energy gem over the nose, so the eyes sit under
## a scowl; round ear sensor on the side, cheek guard, stern mouth.
const HEAD := [
	".....11233445...",
	"...11233344445..",
	"..1122333444455.",
	".112233344444445",
	"1122333q444r44q5",
	"1123322fqq4r4qg4",
	"12pqp32feeqtqeg4",
	"13qsq32fioegeig3",
	"12pqp32fiigggih3",
	"1123322fgggghfg2",
	"1111112fggggggf.",
	".111111fggffgf..",
	"........fgggf...",
]
## Gundam-style V-fin rising from the brow gem above the helmet: the near blade
## longer, the far one foreshortened (anchor = its root on the gem).
const HEAD_VFIN := [
	"ss..........s",
	"qqs........sq",
	".pqqs.....sqp",
	"..ppqs...sqp.",
	"....pqs.sqp..",
	".....pqrqp...",
	"......prp....",
]
## Knight fins: two long gold blades swept back from the temple (drawn behind).
const HEAD_KNIGHT_FINS := [
	"qs..........",
	"pqqs........",
	".ppqqqs.....",
	"...pppqqqs..",
	"qs....ppqqq.",
	"pqqs....pqq.",
	".ppqqqs.....",
	"...ppqqq....",
]
## Big gold horn: root on the brow, blade sweeping up and back over the helm.
const HEAD_HORN_SWEEP := [
	"ss...........",
	".sqq.........",
	"..sqqq.......",
	"...psqqqq....",
	".....ppqqqqs.",
	".......ppqqqq",
]

# --- torso (anchor = pelvis) ------------------------------------------------------------

const TORSO_ANCHOR := Vector2i(6, 10)
## Collar ring and belt in the accent colour, core gem in the chest plate.
const TORSO := [
	"....kllmmk....",
	"..12pqqqqs45..",
	".1233444444455",
	".1233444444455",
	".12233yyz44445",
	".12233yyy34445",
	"..1223333344..",
	"...11222223...",
	"...kllmmmlk...",
	"..pqqqqqqqqs..",
	"..1223k42334..",
]
## Knight chest: gold trim lines meeting in a V under a blue energy core.
const TORSO_KNIGHT := [
	"....kllmmk....",
	"..12pqqqqs45..",
	".1233444444455",
	".12p344444p455",
	".12p33rrt4p445",
	".122p3rrr3p445",
	"..1223pqp344..",
	"...11222223...",
	"...kllmmmlk...",
	"..pqqqqqqqqs..",
	"..1223k42334..",
]
## Brawler chest: broad red plate, gold V edges, magenta core.
const TORSO_BRAWLER := [
	"....kllmmk.....",
	"..1qqqqqqqs45..",
	".1q3444444q4455",
	"12q33444444q445",
	"12q334rtt44q445",
	"122q33rrr4q3445",
	".1222q333q3344.",
	"..111222q2233..",
	"...kllmmmllk...",
	"..qqqqqqqqqqs..",
	"..1223kk42334..",
]
const TORSO_PACK := [  # vanguard back thruster
	".lmm",
	"klmm",
	"klmm",
	"klml",
	".pq.",
	".qs.",
]

# --- boots (anchor = ankle) ---------------------------------------------------------------

const BOOT_ANCHOR := Vector2i(4, 1)
## Accent collar round the ankle, toe cap catching the light.
const BOOT := [
	"..pqqqqs....",
	".1pqqqqs5...",
	".1233444455.",
	"1122333444S5",
	"112223334445",
	".1112222333.",
	".kkkkkkkkkk.",
]
const BOOT_DOWN_ANCHOR := Vector2i(3, 1)
const BOOT_DOWN := [
	".pqqqs...",
	".1pqqqs..",
	".1233445.",
	".11233445",
	"..1122344",
	"...112234",
	"....1122k",
	".....11k.",
]
## Brawler boot: blocky, gold toe cap and heel spur, thick sole.
const BOOT_BRAWLER := [
	"...qqqqqs....",
	"..1pqqqqs5...",
	".1123344445..",
	"q112233344qqs",
	"pq11222334qqs",
	".p1112222pqq.",
	"..kkkkkkkkkk.",
]
## Knight boot: slim, pointed gold toe, raised gold heel spur.
const BOOT_KNIGHT := [
	"..pqqqs......",
	".1pqqqs5.....",
	".123344445...",
	"q1223334444qs",
	"pq1122233344q",
	"..kkkkkkkkk..",
]

# --- arms (anchor = shoulder / elbow) -----------------------------------------------------

const PAD_ANCHOR := Vector2i(3, 2)
const PAD := [
	"..2445.",
	".234455",
	"1233445",
	"1123344",
	".pqqqs.",
]

## Brawler pauldron: big round red shell with a double gold rim.
const PAD_BRAWLER := [
	"sq........",
	"pq3445....",
	".12344455.",
	".123344445",
	".112333444",
	".pqqqqqqqs",
	"..ppppppp.",
]
## Knight pauldron: two layered plates swept up at the back, gold edges.
const PAD_KNIGHT := [
	"qs.......",
	"pq34455..",
	".p2344455",
	".12333444",
	".pqqqqqqs",
	"..111111.",
]

const BUSTER_ANCHOR := Vector2i(1, 3)
const BUSTER := [
	".23s44444445..",
	"123q444444455k",
	"123q44444444km",
	"122q3333344kqm",
	"112p222223344k",
	".11p111112222.",
]

## Knight buster: long slim lance barrel, gold rings, blue glow at the tip.
const BUSTER_LANCE := [
	".234q444q44445.....",
	"1234q444q4444455rt.",
	"1223q333q3333344ttt",
	"1122p222p2222233rt.",
	".111p111p11111.....",
]

static func palette(variant: String) -> Dictionary:
	var out := {}
	for k in COMMON:
		out[k] = Color(COMMON[k])
	var p: Dictionary = PAL.get(variant, PAL.neutral)
	for k in p:
		out[k] = Color(p[k])
	# "S" = a lighter armor glint used on boot toes.
	out["S"] = out["5"]
	return out
