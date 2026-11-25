extends RefCounted
## ECHO — original design: compact teal gunner with a purple core, spiky violet
## hair with gold goggles pushed up over it, a teal ear headset, big violet eyes,
## twin pistols. The
## aiming arm + pistol is its own sprite (16 angles); the small crawler form
## used by the copy ability is a separate 2-frame sprite.

const Raster = preload("res://tools/sprites/raster.gd")

const LAYERS := ["back", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
const VARIANTS := ["default"]
const LAYER_SLOT := {"back": "body", "far_arm": "arm", "far_leg": "leg", "body": "body",
		"near_leg": "leg", "head": "head", "near_arm": "arm"}
const OUTLINE := Color("0c1426")
const RIG_SCALE := 0.92

const ARMOR := Color("4fcf98")
const PLATE := Color("2f8e78")
const ACCENT := Color("b78af3")
const VISOR := Color("f0b84a")
const SUIT := Color("2b3a5e")
const GUN := Color("3a4466")

const ANGLES := 16

## Hand-drawn head (X6-era 3/4 view), facing right; anchor (8, 10) at the head joint.
## Spiky violet hair swept back with gold goggles pushed up on top, bangs that dip
## in a V over the brow so the violet eyes scowl, teal ear headset (purple centre).
##   a b c hair  1-5 teal  q s purple  v w gold  f g h face  e i o eye  k suit
const HEAD := [
	"...a....a.......",
	"..aba..vwwvvwwv.",
	".abba.awqswwqsw.",
	".abbbbbvwwvvwwv.",
	"abbbbbbbbbbccbba",
	"abbbbbbfbbbbbbg.",
	"ab12332feebabeg.",
	"ab2qsq3fioegeig.",
	"ab2qqq3fiigggih.",
	".a12332fgggghfg.",
	"..ab..kfggggggf.",
	"...a..kfggffgf..",
	"........fgggf...",
]
const HEAD_PAL := {"1": Color("1e6650"), "2": Color("2f8e78"), "3": Color("4fcf98"), "4": Color("82e6b8"),
		"5": Color("c8fbe2"), "q": Color("b78af3"), "s": Color("e2d0ff"), "v": Color("a3681a"),
		"w": Color("f0b84a"), "x": Color("fff3c4"), "f": Color("c98a6a"), "g": Color("f0bd94"),
		"h": Color("ffdcc0"), "e": Color("1a1030"), "i": Color("a070f0"), "o": Color("ffffff"),
		"k": Color("2b3a5e"), "a": Color("2a1d4f"), "b": Color("4a3384"), "c": Color("7d62c4")}

var _r: Raster
var _far := false


func ramp(c: Color) -> Array:
	return Raster.ramp_from(c.darkened(0.22) if _far else c)


func has_layer(layer: String, _variant: String) -> bool:
	return layer != "back"


func _pts(at: Vector2, angle: float, local: Array, s := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in local:
		out.append(at + (q * s).rotated(angle))
	return out


func draw(r: Raster, j: Dictionary, layer: String, _variant: String) -> void:
	_r = r
	_r.selout = true
	_far = layer.begins_with("far")
	var s: float = j.scale
	match layer:
		"far_arm":
			_arm(j, "f", s)
		"near_arm":
			_arm(j, "n", s)
		"far_leg":
			_leg(j, "f", s)
		"near_leg":
			_leg(j, "n", s)
		"body":
			_body(j, s)
		"head":
			_head(j, s)


func _head(j: Dictionary, s: float) -> void:
	var c: Vector2 = j.head + Vector2(0, -0.5)
	_r.stamp(HEAD, HEAD_PAL, c.round(), Vector2i(8, 10), {"line": ARMOR.darkened(0.6)})


func _body(j: Dictionary, s: float) -> void:
	var p: Vector2 = j.pelvis
	var a: float = j.lean
	# Hip armor (short skirt plates).
	_r.poly(_pts(p, a, [Vector2(-4.0, 2.4), Vector2(4.0, 2.4), Vector2(4.2, -2), Vector2(-4.2, -2)], s), ramp(PLATE))
	_r.poly(_pts(p, a, [Vector2(-4.2, -1.0), Vector2(4.4, -1.0), Vector2(4.4, -2.6), Vector2(-4.2, -2.6)], s),
			ramp(SUIT.lightened(0.2)), {"shade": 2.0})
	# Vest.
	_r.poly(_pts(p, a, [Vector2(-4.0, -2.4), Vector2(4.0, -2.4), Vector2(5.2, -6.0), Vector2(4.0, -8.8),
			Vector2(-3.8, -8.8), Vector2(-5.0, -6.0)], s), ramp(ARMOR))
	_r.poly(_pts(p, a, [Vector2(-2.6, -8.4), Vector2(2.4, -8.4), Vector2(2.0, -9.8), Vector2(-2.2, -9.8)], s), ramp(SUIT))
	# Diamond core.
	var cc: Vector2 = p + Vector2(1.6, -5.4).rotated(a) * s
	_r.poly(PackedVector2Array([cc + Vector2(0, -2.2) * s, cc + Vector2(2.0, 0) * s, cc + Vector2(0, 2.2) * s,
			cc + Vector2(-2.0, 0) * s]), Raster.ramp_from(ACCENT), {"shade": 0.4})
	_r.dot(cc + Vector2(0.2, -1.0) * s, Color("f3e8ff"))


func _arm(j: Dictionary, side: String, s: float) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	_r.limb(sh, el, 3.0 * s, 2.8 * s, ramp(SUIT))
	_r.limb(el, ha, 4.0 * s, 5.0 * s, ramp(ARMOR))
	# Purple cuff ring (ellipse x = across the forearm).
	_r.ellipse(el.lerp(ha, 0.74), 2.3 * s, 0.9 * s, -j[side + "_fore_angle"], ramp(ACCENT), {"line": false, "shade": 2.0})
	_r.ellipse(ha + (ha - el).normalized() * 1.1 * s, 1.9 * s, 1.9 * s, 0.0, ramp(SUIT.lightened(0.3)))
	if side == "f":
		# Second pistol in the far hand, along the forearm.
		var d := (ha - el).normalized()
		_r.limb(ha + d * 0.5, ha + d * 5.0, 2.6 * s, 2.2 * s, ramp(GUN))
	_r.ellipse(sh, 2.4 * s, 2.2 * s, 0.0, ramp(PLATE))


func _leg(j: Dictionary, side: String, s: float) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = j[side + "_ankle"]
	_r.limb(hip, knee, 3.8 * s, 3.4 * s, ramp(SUIT))
	_r.limb(knee, ankle, 4.2 * s, 6.0 * s, ramp(ARMOR))
	_r.ellipse(knee, 2.0 * s, 2.0 * s, 0.0, ramp(PLATE))
	var fa: float = -j[side + "_foot"]
	_r.poly(_pts(ankle, fa, [Vector2(-3.6, -1.6), Vector2(2.4, -1.6), Vector2(6.2, 2.4), Vector2(6.2, 5.0),
			Vector2(-4.0, 5.0), Vector2(-4.4, 1.0)], s), ramp(ARMOR))
	_r.poly(_pts(ankle, fa, [Vector2(-4.2, 3.8), Vector2(6.2, 3.8), Vector2(6.2, 5.0), Vector2(-4.2, 5.0)], s),
			ramp(SUIT), {"shade": 2.0})
	_r.poly(_pts(ankle, fa, [Vector2(-3.8, 0.4), Vector2(-1.8, 0.4), Vector2(-1.8, 3.0), Vector2(-3.8, 3.0)], s),
			ramp(ACCENT), {"line": false, "shade": 2.0})


## Pistol arm (shoulder at the origin, 16 angles) and the crawler form (2 frames).
func extras() -> Array:
	var angles := []
	for i in ANGLES:
		angles.append(snappedf(TAU * i / ANGLES, 0.0001))
	return [
		{"name": "pistol", "cell": Vector2i(32, 32), "origin": Vector2(16, 16), "angles": angles},
		{"name": "mini", "cell": Vector2i(20, 16), "origin": Vector2(10, 15), "angles": [0.0, 1.0]},
	]


func draw_extra(r: Raster, name: String, origin: Vector2, _v: String, angle: float) -> void:
	_r = r
	_far = false
	if name == "pistol":
		var dir := Vector2.RIGHT.rotated(angle)
		var nrm := Vector2(-dir.y, dir.x)
		# Elbow bent down so the gun sits at chest height, like the shots.
		var el := origin + dir.rotated(0.9) * 4.0
		var ha := el + dir * 4.5
		_r.limb(origin, el, 3.0, 2.8, ramp(SUIT))
		_r.limb(el, ha, 4.0, 5.0, ramp(ARMOR))
		# Pistol: body, barrel, purple sight.
		_r.limb(ha - dir * 0.5, ha + dir * 5.5, 3.4, 3.0, ramp(GUN))
		_r.limb(ha + dir * 5.0, ha + dir * 8.0, 1.8, 1.8, ramp(GUN.lightened(0.2)))
		_r.ellipse(ha + dir * 2.5 - nrm * 1.6, 0.9, 0.9, 0.0, ramp(ACCENT), {"line": false, "shade": 2.0})
		_r.ellipse(ha, 1.8, 1.8, 0.0, ramp(SUIT.lightened(0.3)))
	elif name == "mini":
		var step := int(angle)
		# Little crawler: round shell, gold eye, antenna, four legs.
		for k in 4:
			var lx := origin.x - 5.0 + k * 3.3
			var lift := 1.0 if (k + step) % 2 == 0 else 0.0
			_r.limb(Vector2(lx, origin.y - 5.0), Vector2(lx + (1.5 if k >= 2 else -1.5), origin.y - 0.6 - lift),
					1.6, 1.4, ramp(SUIT.lightened(0.2)))
		_r.ellipse(origin + Vector2(0, -6.5), 6.0, 4.6, 0.0, ramp(ARMOR))
		_r.poly(PackedVector2Array([origin + Vector2(1.5, -8.0), origin + Vector2(5.4, -8.0),
				origin + Vector2(5.4, -6.0), origin + Vector2(1.5, -6.0)]), Raster.ramp_from(VISOR), {"line": false, "shade": 2.0})
		_r.limb(origin + Vector2(-1.5, -10.0), origin + Vector2(-4.5, -13.5), 1.4, 1.0, ramp(ACCENT))
