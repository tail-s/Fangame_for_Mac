extends RefCounted
## SABLE — original design: slim gunmetal swordsman, orange accents, masked face
## with a cyan eye slit, long swept-back blade crest, coat-tail plates and a
## saber worn across the back. The swinging arm + blade is its own sprite
## (16 angles) so slashes rotate cleanly.

const Raster = preload("res://tools/sprites/raster.gd")

const LAYERS := ["back", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
const VARIANTS := ["default"]
const LAYER_SLOT := {"back": "body", "far_arm": "arm", "far_leg": "leg", "body": "body",
		"near_leg": "leg", "head": "head", "near_arm": "arm"}
const OUTLINE := Color("0b0f20")

const ARMOR := Color("7f8ab8")
const PLATE := Color("a3aed6")
const ACCENT := Color("f08a3a")
const VISOR := Color("3de0ee")
const SUIT := Color("2a3156")
const MASK := Color("343c63")
const BLADE := Color("c9fbff")

const ANGLES := 16

## Hand-drawn head (32-bit style), facing right; anchor = head centre (6, 6).
##   1-5 steel  p q s orange  k l m mask / vent  v w x eye slit
const HEAD := [
	"......pqs....",
	"...2344pq45..",
	"..2344444455.",
	".123444444455",
	"1123333333335",
	"1122222vwwwwx",
	"112m22kkkkkkl",
	"112ml2kllllll",
	"112mm2kllllk.",
	".11222kkllk..",
	"..1112kkkk...",
	"...111.......",
]
const HEAD_PAL := {"1": Color("3a4268"), "2": Color("56608a"), "3": Color("7f8ab8"), "4": Color("a3aed6"),
		"5": Color("d6ddf2"), "p": Color("a8501c"), "q": Color("f08a3a"), "s": Color("ffc28a"),
		"k": Color("1e2240"), "l": Color("2c3354"), "m": Color("3c4570"),
		"v": Color("1d8fa0"), "w": Color("3de0ee"), "x": Color("e6ffff")}

var _r: Raster
var _far := false


func ramp(c: Color) -> Array:
	return Raster.ramp_from(c.darkened(0.22) if _far else c)


func has_layer(_layer: String, _variant: String) -> bool:
	return true


func _pts(at: Vector2, angle: float, local: Array, s := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in local:
		out.append(at + (q * s).rotated(angle))
	return out


func draw(r: Raster, j: Dictionary, layer: String, _variant: String) -> void:
	_r = r
	_r.selout = true
	_far = layer.begins_with("far")
	match layer:
		"back":
			_back(j)
		"far_arm":
			_arm(j, "f")
		"near_arm":
			_arm(j, "n")
		"far_leg":
			_leg(j, "f")
		"near_leg":
			_leg(j, "n")
		"body":
			_body(j)
		"head":
			_head(j)


func _back(j: Dictionary) -> void:
	var p: Vector2 = j.pelvis
	var a: float = j.lean
	# Saber across the back: hilt over the far shoulder, sheath down to the hip.
	var top: Vector2 = p + Vector2(-3.5, -11.5).rotated(a)
	var bottom: Vector2 = p + Vector2(-7.5, 1.5).rotated(a)
	_r.limb(top, bottom, 2.4, 2.0, ramp(SUIT.lightened(0.2)))
	_r.limb(top + (top - bottom).normalized() * 0.5, top + (top - bottom).normalized() * 3.5, 1.8, 1.8, ramp(ACCENT))
	# Coat-tail plates hanging from the belt; they trail when moving.
	var sway: float = clampf(j.lean * 1.4, 0.0, 0.9)
	for k in 2:
		var root: Vector2 = p + Vector2(-2.5 - k * 1.5, -1.0).rotated(a)
		var dir := Vector2(0, 1).rotated(0.35 + sway + k * 0.15)
		var len := 7.5 - k * 1.0
		var nrm := Vector2(-dir.y, dir.x)
		_r.poly(PackedVector2Array([root + nrm * 2.0, root - nrm * 2.0, root + dir * len - nrm * 1.2,
				root + dir * (len + 1.0), root + dir * len + nrm * 1.4]), ramp(PLATE if k == 0 else ARMOR))


func _head(j: Dictionary) -> void:
	var c: Vector2 = j.head
	var a: float = j.head_angle * 0.6
	# Long swept-back crest (two blades) behind the helmet.
	_r.poly(_pts(c, a, [Vector2(-1.5, -5.0), Vector2(-13.0, -7.2), Vector2(-10.8, -5.0), Vector2(-3.5, -2.0)]), ramp(ACCENT))
	_r.poly(_pts(c, a, [Vector2(-3.0, -2.5), Vector2(-11.0, -2.6), Vector2(-9.0, -0.8), Vector2(-4.0, 0.5)]), ramp(ACCENT.darkened(0.15)))
	# Hand-drawn helmet: pointed back, orange crest stub, cyan eye slit, mask.
	_r.stamp(HEAD, HEAD_PAL, c.round(), Vector2i(6, 6), {"line": ARMOR.darkened(0.6)})


func _body(j: Dictionary) -> void:
	var p: Vector2 = j.pelvis
	var a: float = j.lean
	_r.poly(_pts(p, a, [Vector2(-3.6, 1.6), Vector2(3.6, 1.6), Vector2(3.8, -2), Vector2(-3.8, -2)]), ramp(SUIT))
	_r.poly(_pts(p, a, [Vector2(-4.0, -1.2), Vector2(4.2, -1.2), Vector2(4.2, -2.7), Vector2(-4.0, -2.7)]),
			ramp(ACCENT.darkened(0.2)), {"shade": 2.0})
	# Slim chest with a diagonal strap.
	_r.poly(_pts(p, a, [Vector2(-3.8, -2.4), Vector2(3.8, -2.4), Vector2(5.4, -6.2), Vector2(4.2, -9.2),
			Vector2(-3.6, -9.2), Vector2(-5.0, -6.0)]), ramp(ARMOR))
	_r.poly(_pts(p, a, [Vector2(-3.0, -8.6), Vector2(-1.6, -8.6), Vector2(4.2, -3.2), Vector2(2.8, -2.6)]),
			ramp(ACCENT), {"line": false, "shade": 2.0})
	_r.poly(_pts(p, a, [Vector2(-2.6, -8.6), Vector2(2.4, -8.6), Vector2(2.0, -10.4), Vector2(-2.2, -10.4)]), ramp(SUIT))


func _arm(j: Dictionary, side: String) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	_r.limb(sh, el, 3.2, 2.8, ramp(SUIT))
	_r.limb(el, ha, 3.6, 4.2, ramp(ARMOR))
	_r.ellipse(el.lerp(ha, 0.75), 0.9, 2.2, -j[side + "_fore_angle"], ramp(ACCENT), {"line": false, "shade": 2.0})
	_r.ellipse(ha + (ha - el).normalized() * 0.8, 1.8, 1.8, 0.0, ramp(MASK))
	# Angular pauldron.
	_r.poly(_pts(sh, j.lean, [Vector2(-3.0, 1.2), Vector2(-2.6, -2.4), Vector2(1.4, -3.0),
			Vector2(3.4, -0.8), Vector2(1.6, 2.2)]), ramp(PLATE))
	_r.poly(_pts(sh, j.lean, [Vector2(-2.6, -2.4), Vector2(1.4, -3.0), Vector2(1.0, -2.0), Vector2(-2.2, -1.5)]),
			ramp(ACCENT), {"line": false, "shade": 2.0})


func _leg(j: Dictionary, side: String) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = j[side + "_ankle"]
	_r.limb(hip, knee, 3.8, 3.4, ramp(SUIT))
	_r.limb(knee, ankle, 3.6, 4.6, ramp(ARMOR))
	# Knee guard with a forward spike.
	var ka: float = -j[side + "_shin_angle"]
	_r.poly(_pts(knee, ka, [Vector2(-1.6, -1.8), Vector2(2.8, -2.6), Vector2(2.0, 1.4), Vector2(-1.6, 1.8)]), ramp(PLATE))
	var fa: float = -j[side + "_foot"]
	_r.poly(_pts(ankle, fa, [Vector2(-3.4, -1.8), Vector2(2.2, -1.8), Vector2(7.6, 3.0), Vector2(7.0, 5.0),
			Vector2(-3.8, 5.0), Vector2(-4.2, 1.0)]), ramp(ARMOR))
	_r.poly(_pts(ankle, fa, [Vector2(-3.8, 3.9), Vector2(7.2, 3.9), Vector2(7.0, 5.0), Vector2(-3.8, 5.0)]),
			ramp(SUIT), {"shade": 2.0})
	_r.poly(_pts(ankle, fa, [Vector2(0.4, -1.2), Vector2(2.4, -1.2), Vector2(4.0, 0.6), Vector2(0.4, 0.6)]),
			ramp(ACCENT), {"shade": 2.0})


## Sword arm: shoulder at the origin, arm + saber pointing along `angle`
## (0 = forward, + = clockwise / downwards).
func extras() -> Array:
	var angles := []
	for i in ANGLES:
		angles.append(snappedf(TAU * i / ANGLES, 0.0001))
	return [{"name": "saber", "cell": Vector2i(56, 56), "origin": Vector2(28, 28), "angles": angles}]


func draw_extra(r: Raster, name: String, origin: Vector2, _v: String, angle: float) -> void:
	if name != "saber":
		return
	_r = r
	_far = false
	var dir := Vector2.RIGHT.rotated(angle)
	var nrm := Vector2(-dir.y, dir.x)
	var el := origin + dir * 4.2 + nrm * 0.6
	var ha := origin + dir * 8.4
	_r.limb(origin, el, 3.2, 2.8, ramp(SUIT))
	_r.limb(el, ha, 3.6, 4.2, ramp(ARMOR))
	# Blade first (behind the fist), then guard and fist.
	var b0 := ha + dir * 2.0
	var b1 := ha + dir * 19.0
	_r.poly(PackedVector2Array([b0 + nrm * 1.6, b1 + nrm * 0.9, b1 + dir * 2.2, b1 - nrm * 0.9, b0 - nrm * 1.6]),
			[Color("1d8fa0"), Color("5fe7f0"), BLADE, Color("eaffff"), Color.WHITE], {"line": false})
	_r.limb(ha + dir * 0.6 - nrm * 2.4, ha + dir * 0.6 + nrm * 2.4, 1.6, 1.6, ramp(ACCENT))
	_r.ellipse(ha, 2.0, 2.0, 0.0, ramp(MASK))
