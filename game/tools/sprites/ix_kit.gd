extends RefCounted
## Hand-drawn pixel parts for IX (32-bit sprite style, original design).
## Grids are palette-indexed, facing right, "." = empty:
##   1-5  armor ramp (dark -> highlight)      p q s  accent (dark, base, light)
##   k l m  undersuit (dark -> light)         v w x  visor (dark, base, glint)
##   f g h  face (shadow, base, light)        y z    core gem (base, glint)
##   e i o  eye (lash line, iris, glint)
## As in 32-bit armor sprites, one base body is shared and each armor family adds
## its own pieces on top (and swaps the palette): see ix_model.gd.

const PAL := {
	"neutral": {"1": "34466a", "2": "62799e", "3": "9fb4cf", "4": "d3e2f0", "5": "ffffff",
			"p": "0f6f7a", "q": "22b3be", "s": "93f0f2"},
	"vanguard": {"1": "262c40", "2": "434d6b", "3": "66729a", "4": "95a1c6", "5": "d0d9f0",
			"p": "8a5a10", "q": "f0b84a", "s": "ffe7a8"},
	"aero": {"1": "587690", "2": "93b3c8", "3": "cde3ee", "4": "eef8fb", "5": "ffffff",
			"p": "1f8c84", "q": "5fd8d0", "s": "b8fff9"},
	"ultimate": {"1": "36206a", "2": "583a9e", "3": "7d58c8", "4": "a483e0", "5": "d4c2f6",
			"p": "8a5a10", "q": "f0b84a", "s": "ffe7a8"},
}
const COMMON := {"k": "1a2242", "l": "2e3b64", "m": "4a5a8a", "v": "a3681a", "w": "f0b84a", "x": "fff3c4",
		"f": "c98a6a", "g": "f0bd94", "h": "ffdcc0", "y": "13b9c2", "z": "e6ffff",
		"e": "142040", "i": "27b6d6", "o": "ffffff"}

# --- head (anchor = head centre) --------------------------------------------------------

const HEAD_ANCHOR := Vector2i(7, 6)
## Swept helmet (3/4 view, facing right): crown peaks toward the front, gold brow
## band ending in a forward point, accent sensor on the side plate, jaw guard
## wrapping forward under the face, both eyes visible.
const HEAD := [
	"......123455...",
	"....1233444455.",
	"..112334444445.",
	".11223344444445",
	"1122333vwwwwwwx",
	"11222222fhhhhh.",
	"1122qs22geegeh.",
	"1122pq22goigih.",
	"11122222giigig.",
	".11122223fggg..",
	"..1111222334f..",
	"...1111122.....",
]
## Neutral: swept fin off the back of the helmet.
const HEAD_FIN := [
	"q.......",
	"pq......",
	".pqq....",
	"..pqqs..",
	"...pqq..",
]
## Vanguard / Ultimate: forward horn crest.
const HEAD_HORN := [
	"........sq",
	"......sqq.",
	"....pqqq..",
	"..ppqq....",
	".ppq......",
]
## Aero: two swept wing fins.
const HEAD_WINGS := [
	"qs........",
	"pqqs......",
	".ppqqs....",
	"...ppqq...",
	"qs...pq...",
	"pqqs......",
	".ppqqs....",
	"...ppq....",
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
const TORSO_CHEVRON := [  # vanguard chest plate edge
	"..pqqqs.",
	"...pqqs.",
	"....pq..",
]
const TORSO_PACK := [  # vanguard back thruster
	".lmm",
	"klmm",
	"klmm",
	"klml",
	".pq.",
	".qs.",
]
const TORSO_STRIPE := [  # aero collar stripe
	"pqqqqqs",
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
const BOOT_THRUSTER := [  # vanguard heel thruster
	"lm",
	"km",
	"km",
	"pq",
]
const BOOT_FIN := [  # aero ankle fin
	"...sq",
	".sqqp",
	"qqp..",
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
const PAD_VANGUARD := [
	"..34455.",
	".2344455",
	"12334445",
	"1123344q",
	"11223344",
	".111222.",
]
const PAD_AERO := [
	"s....",
	"q245.",
	"23445",
	"12334",
	".112.",
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
const BUSTER_VANGUARD := [
	".234444pq44444455..",
	"1234444pq444444555k",
	"1233444pq4444445kmk",
	"1223333pq3333444kqm",
	"1122222pq2222333kmk",
	"1112222pq222222k...",
	".111111111111111...",
]
const BUSTER_AERO := [
	".2344q44q4444445..",
	"12344q44q44444455k",
	"12233q33q3333344kq",
	"11222q22q22222333k",
	".1111p11p11111111.",
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
