extends RefCounted
## NEUTRAL FRAME IX — original design, 32-bit sprite style (v2).
## Rigid parts are hand-drawn pixel grids from ix_kit.gd (helmet, chest, boots,
## shoulder guards, buster); the skeleton only places them and draws the jointed
## limbs between. As in 32-bit armor sprites, the base body is shared and each armor
## family swaps the palette and adds its own pieces:
##   neutral   white frame, teal fin, gold visor
##   vanguard  blue + crimson: horn crest, chest chevron, back thruster, big guards, block buster, heel thrusters
##   aero      white + mint: wing fins, collar stripe, back wings, finned guards, vented buster, ankle fins
##   ultimate  violet + gold: vanguard pieces with aero wings

const Raster = preload("res://tools/sprites/raster.gd")
const Kit = preload("res://tools/sprites/ix_kit.gd")

const LAYERS := ["wings", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
const VARIANTS := ["neutral", "vanguard", "aero", "ultimate"]
const LAYER_SLOT := {"wings": "body", "far_arm": "arm", "far_leg": "leg", "body": "body",
		"near_leg": "leg", "head": "head", "near_arm": "arm"}
const SHAPE := {"neutral": "neutral", "vanguard": "vanguard", "aero": "aero", "ultimate": "vanguard"}
const OUTLINE := Color("0d1428")
## Shoulder-relative point where shots leave the buster (raster space, facing right).
const MUZZLE := Vector2(14.0, 6.0)

var _r: Raster
var _pal := {}
var _far := false


func has_layer(layer: String, variant: String) -> bool:
	return layer != "wings" or variant in ["aero", "ultimate"]


func _palette(variant: String, far: bool) -> Dictionary:
	var p := Kit.palette(variant)
	if far:
		for k in p:
			p[k] = Color(p[k]).darkened(0.24)
	return p


func _ramp(keys: Array) -> Array:
	return [Color(_pal[keys[0]]).darkened(0.4), _pal[keys[0]], _pal[keys[1]], _pal[keys[2]], _pal[keys[3]]]


func _line() -> Color:
	return Color(_pal["1"]).darkened(0.45)


func draw(r: Raster, j: Dictionary, layer: String, variant: String) -> void:
	_r = r
	_r.selout = true
	_far = layer.begins_with("far")
	_pal = _palette(variant, _far)
	match layer:
		"wings":
			if has_layer(layer, variant):
				_wings(j)
		"far_arm":
			_arm(j, "f", variant)
		"near_arm":
			_arm(j, "n", variant)
		"far_leg":
			_leg(j, "f", variant)
		"near_leg":
			_leg(j, "n", variant)
		"body":
			_body(j, variant)
		"head":
			_head(j, variant)


func _st(grid: Array, at: Vector2, anchor: Vector2i, opts := {}) -> void:
	if not opts.has("line"):
		opts["line"] = _line()
	_r.stamp(grid, _pal, at, anchor, opts)


# --- parts ---------------------------------------------------------------------------------

func _head(j: Dictionary, v: String) -> void:
	var c: Vector2 = (j.head as Vector2).round()
	match SHAPE[v]:
		"neutral":
			_st(Kit.HEAD_FIN, c + Vector2(-3, -5), Vector2i(5, 4))
		"aero":
			_st(Kit.HEAD_WINGS, c + Vector2(-2, -1), Vector2i(6, 3))
	_st(Kit.HEAD, c, Kit.HEAD_ANCHOR)
	if SHAPE[v] == "vanguard":
		_st(Kit.HEAD_HORN, c + Vector2(1, -5), Vector2i(1, 4))


func _body(j: Dictionary, v: String) -> void:
	var p: Vector2 = (j.pelvis as Vector2).round()
	var shear: float = clampf(j.lean, -0.6, 0.8)
	if v == "vanguard":
		_st(Kit.TORSO_PACK, p + Vector2(-5 + shear * 7.0, -8), Vector2i(3, 0))
	_st(Kit.TORSO, p, Kit.TORSO_ANCHOR, {"shear": shear})
	match SHAPE[v]:
		"vanguard":
			_st(Kit.TORSO_CHEVRON, p + Vector2(3 + roundf(shear * 8.0), -8), Vector2i(4, 0))
		"aero":
			_st(Kit.TORSO_STRIPE, p + Vector2(-1 + roundf(shear * 7.0), -7), Vector2i.ZERO)


func _wings(j: Dictionary) -> void:
	var p: Vector2 = j.pelvis + j.up * 7.5
	var spread: float = j.wing
	var acc := _ramp(["p", "q", "s", "s"])
	var base_a: float = j.lean - 0.2 - spread * 0.5
	for k in 2:
		var ang := base_a - k * (0.35 + spread * 0.45)
		var len := 9.5 + spread * 6.0 - k * 1.5
		var dir := Vector2(-1, 0).rotated(ang)
		var nrm := Vector2(-dir.y, dir.x)
		var root := p + Vector2(-2.0, k * 1.8)
		_r.poly(PackedVector2Array([root + nrm * 2.0, root + dir * len + nrm * 1.2,
				root + dir * (len + 3.0), root - nrm * 2.2 + dir * 2.4]), acc)


func _arm(j: Dictionary, side: String, v: String) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	var suit := _ramp(["k", "l", "m", "m"])
	var armor := _ramp(["1", "3", "4", "5"])
	_r.limb(sh, el, 3.6, 3.2, suit)
	var fw := 5.6 if SHAPE[v] == "vanguard" else (4.4 if SHAPE[v] == "aero" else 5.0)
	_r.limb(el, ha, fw - 0.8, fw, armor)
	if SHAPE[v] == "vanguard":
		_r.ellipse(el.lerp(ha, 0.7), 1.0, 2.6, -j[side + "_fore_angle"], _ramp(["p", "q", "s", "s"]), {"line": false, "shade": 2.0})
	_r.ellipse(ha + (ha - el).normalized(), 2.0, 2.0, 0.0, _ramp(["l", "m", "m", "h"]))
	match SHAPE[v]:
		"vanguard":
			_st(Kit.PAD_VANGUARD, sh.round(), Vector2i(4, 2))
		"aero":
			_st(Kit.PAD_AERO, sh.round(), Vector2i(2, 2))
		_:
			_st(Kit.PAD, sh.round(), Kit.PAD_ANCHOR)


func _leg(j: Dictionary, side: String, v: String) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = (j[side + "_ankle"] as Vector2).round()
	var suit := _ramp(["k", "l", "m", "m"])
	var armor := _ramp(["1", "3", "4", "5"])
	_r.limb(hip, knee, 4.2, 3.8, suit)
	var sw := 6.0 if SHAPE[v] == "vanguard" else (5.0 if SHAPE[v] == "aero" else 5.4)
	_r.limb(knee, ankle, sw - 1.4, sw, armor)
	_r.ellipse(knee, 2.2, 2.2, 0.0, armor)
	var toe_down: bool = j[side + "_foot"] < -0.3
	if toe_down:
		_st(Kit.BOOT_DOWN, ankle, Kit.BOOT_DOWN_ANCHOR)
	else:
		_st(Kit.BOOT, ankle, Kit.BOOT_ANCHOR)
	match SHAPE[v]:
		"vanguard":
			if not toe_down:
				_st(Kit.BOOT_THRUSTER, ankle + Vector2(-5, 0), Vector2i(1, 0))
		"aero":
			_st(Kit.BOOT_FIN, ankle + Vector2(-2, 1), Vector2i(4, 2))


## Buster arm used while shooting (own sprite, origin = shoulder).
func draw_buster(r: Raster, origin: Vector2, v: String) -> void:
	_r = r
	_r.selout = true
	_far = false
	_pal = _palette(v, false)
	var el := (origin + Vector2(2.4, 5.8)).round()
	_r.limb(origin, el, 3.6, 3.2, _ramp(["k", "l", "m", "m"]))
	match SHAPE[v]:
		"vanguard":
			_st(Kit.BUSTER_VANGUARD, el, Vector2i(1, 3))
		"aero":
			_st(Kit.BUSTER_AERO, el, Vector2i(1, 2))
		_:
			_st(Kit.BUSTER, el, Kit.BUSTER_ANCHOR)


func extras() -> Array:
	return [{"name": "buster", "cell": Vector2i(28, 20), "origin": Vector2(5, 5), "tip": [MUZZLE.x, MUZZLE.y]}]


func draw_extra(r: Raster, name: String, origin: Vector2, v: String, _angle: float) -> void:
	if name == "buster":
		draw_buster(r, origin, v)
