extends RefCounted
## Hand-drawn pixel parts for IX (32-bit sprite style, original design).
## Grids are palette-indexed, facing right, "." = empty:
##   1-5  armor ramp (dark -> highlight)      p q s  accent (dark, base, light)
##   k l m  undersuit (dark -> light)         v w x  visor (dark, base, glint)
##   f g h  face plate                        y z    core gem (base, glint)
## As in 32-bit armor sprites, one base body is shared and each armor family adds
## its own pieces on top (and swaps the palette): see ix_model.gd.

const PAL := {
	"neutral": {"1": "4f6584", "2": "8ea5c0", "3": "c4d6e6", "4": "e6f1f7", "5": "ffffff",
			"p": "147a85", "q": "2fc4cc", "s": "a5f5f7"},
	"vanguard": {"1": "18377a", "2": "2856ad", "3": "3a7fe6", "4": "6aa4f3", "5": "bcd9ff",
			"p": "8a1f2c", "q": "e34f5b", "s": "ff9aa3"},
	"aero": {"1": "587690", "2": "93b3c8", "3": "cde3ee", "4": "eef8fb", "5": "ffffff",
			"p": "1f8c84", "q": "5fd8d0", "s": "b8fff9"},
	"ultimate": {"1": "36206a", "2": "583a9e", "3": "7d58c8", "4": "a483e0", "5": "d4c2f6",
			"p": "8a5a10", "q": "f0b84a", "s": "ffe7a8"},
}
const COMMON := {"k": "1a2242", "l": "2e3b64", "m": "4a5a8a", "v": "a3681a", "w": "f0b84a", "x": "fff3c4",
		"f": "5f7493", "g": "97acc6", "h": "c9d7e7", "y": "13b9c2", "z": "e6ffff"}

# --- head (anchor = head centre) --------------------------------------------------------

const HEAD_ANCHOR := Vector2i(6, 6)
const HEAD := [
	"....234445...",
	"..123444444..",
	".12344444445.",
	".123444444455",
	"1123333333345",
	"1122222vvwwwx",
	"112qqm2vwwwww",
	"112qmq2ffgggh",
	"112mqm2fgggh.",
	".1122222ffgg.",
	"..11122fffh..",
	"...1111......",
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
const TORSO := [
	"...kllmmk....",
	"..2344444455.",
	".123444444455",
	".123344444445",
	".1233yyz44445",
	".1223yyy34445",
	"..1222333344.",
	"...11222233..",
	"...lmmmmmml..",
	"...kllmllk...",
	"...kkllllk...",
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
const BOOT := [
	"..234444....",
	".12344445...",
	".123344455..",
	"1123334444S5",
	"112233344445",
	".11222223333",
	".kkkkkkkkkkk",
]
const BOOT_DOWN_ANCHOR := Vector2i(3, 1)
const BOOT_DOWN := [
	".23444...",
	".123445..",
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
	".2445.",
	"234455",
	"123445",
	"112334",
	".1122.",
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
	".23444444445..",
	"1234444444455k",
	"123344444444km",
	"12233333344kqm",
	"1122222223344k",
	".111111112222.",
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
