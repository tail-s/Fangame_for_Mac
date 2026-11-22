extends RefCounted
## NEUTRAL FRAME IX — original design. Each armor slot changes both colour and
## silhouette (helmet / chest / buster / boots), per GDD §4-2:
##   neutral   white frame, teal core, gold visor, swept fin
##   vanguard  blue + crimson, forward horn, heavy shoulder guards, block buster, thruster boots
##   aero      white + mint, swept wing fins, back wings, slim vented buster, finned boots
##   ultimate  violet + gold, vanguard head / arm / leg shapes with aero wings
## draw(r, j, layer, variant): draws the parts of one depth layer.

const Raster = preload("res://tools/sprites/raster.gd")

const LAYERS := ["wings", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
const VARIANTS := ["neutral", "vanguard", "aero", "ultimate"]
## Which armor slot drives each depth layer.
const LAYER_SLOT := {"wings": "body", "far_arm": "arm", "far_leg": "leg", "body": "body",
		"near_leg": "leg", "head": "head", "near_arm": "arm"}

const ARMOR := {
	"neutral": Color("dfeef5"),
	"vanguard": Color("3a7fe6"),
	"aero": Color("eef8fb"),
	"ultimate": Color("7d58c8"),
}
const ACCENT := {
	"neutral": Color("2fc4cc"),
	"vanguard": Color("e34f5b"),
	"aero": Color("5fd8d0"),
	"ultimate": Color("f0b84a"),
}
## Silhouette family per variant (ultimate borrows vanguard shapes, aero wings).
const SHAPE := {"neutral": "neutral", "vanguard": "vanguard", "aero": "aero", "ultimate": "vanguard"}

const SUIT := Color("33406a")
const CORE := Color("19c8d0")
const VISOR := Color("f0b84a")
const FACE := Color("9fb3cc")
const OUTLINE := Color("0d1428")

## Shoulder-relative point where shots leave the buster (raster space, facing right).
const MUZZLE := Vector2(12.4, 6.2)

var _r: Raster
var _far := false


func ramp(c: Color) -> Array:
	return Raster.ramp_from(c.darkened(0.22) if _far else c)


func has_layer(layer: String, variant: String) -> bool:
	return layer != "wings" or variant in ["aero", "ultimate"]


func draw(r: Raster, j: Dictionary, layer: String, variant: String) -> void:
	_r = r
	_far = layer.begins_with("far")
	match layer:
		"wings":
			if has_layer(layer, variant):
				_wings(j, variant)
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


# --- helpers -------------------------------------------------------------------------

## Local polygon (facing right, origin at `at`, rotated by `angle`) to raster space.
func _pts(at: Vector2, angle: float, local: Array, s := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in local:
		out.append(at + (q * s).rotated(angle))
	return out


# --- parts ---------------------------------------------------------------------------

func _head(j: Dictionary, v: String) -> void:
	var c: Vector2 = j.head
	var a: float = j.head_angle * 0.6
	var s: float = j.scale
	var armor := ramp(ARMOR[v])
	var acc := ramp(ACCENT[v])
	var shape: String = SHAPE[v]
	# Back crest / fins sit behind the helmet.
	match shape:
		"neutral":
			_r.poly(_pts(c, a, [Vector2(-1.2, -5.4), Vector2(-9.0, -8.8), Vector2(-7.6, -6.2), Vector2(-3.6, -2.6)], s), acc)
		"aero":
			_r.poly(_pts(c, a, [Vector2(-1.8, -2.2), Vector2(-11.0, -7.4), Vector2(-9.2, -3.8), Vector2(-3.4, 1.2)], s), acc)
			_r.poly(_pts(c, a, [Vector2(-2.2, -5.2), Vector2(-9.8, -10.8), Vector2(-8.6, -7.2), Vector2(-3.4, -2.2)], s), acc)
	# Helmet shell.
	_r.poly(_pts(c, a, [Vector2(-5.4, 3.0), Vector2(-6.2, -1.0), Vector2(-5.0, -4.6), Vector2(-1.8, -6.4),
			Vector2(2.2, -6.4), Vector2(5.0, -4.6), Vector2(6.2, -1.4), Vector2(6.0, 1.8),
			Vector2(3.8, 4.8), Vector2(-1.8, 5.0)], s), armor)
	# Face plate, visor and its glint.
	_r.poly(_pts(c, a, [Vector2(0.8, -1.6), Vector2(5.8, -1.6), Vector2(5.6, 1.6), Vector2(3.6, 4.2),
			Vector2(1.0, 4.0)], s), ramp(FACE), {"shade": 0.15})
	_r.poly(_pts(c, a, [Vector2(0.4, -2.9), Vector2(6.5, -2.9), Vector2(6.5, -0.4), Vector2(0.4, -0.4)], s),
			Raster.ramp_from(VISOR), {"line": false, "shade": 2.0})
	_r.dot(c + (Vector2(5.0, -2.2) * s).rotated(a), VISOR.lightened(0.75))
	# Ear disc.
	_r.ellipse(c + (Vector2(-2.6, 1.0) * s).rotated(a), 1.6 * s, 2.0 * s, 0.0, ramp(SUIT.lightened(0.3)), {"shade": 0.3})
	_r.dot(c + (Vector2(-2.8, 0.6) * s).rotated(a), (ACCENT[v] if shape != "neutral" else CORE))
	match shape:
		"vanguard":
			# Forward horn crest.
			_r.poly(_pts(c, a, [Vector2(-0.8, -6.0), Vector2(2.4, -6.5), Vector2(8.8, -10.4), Vector2(5.0, -4.4)], s), acc)
		"aero":
			_r.poly(_pts(c, a, [Vector2(-3.0, -6.1), Vector2(1.8, -6.7), Vector2(-1.2, -8.4)], s), acc)


func _body(j: Dictionary, v: String) -> void:
	var p: Vector2 = j.pelvis
	var a: float = j.lean
	var s: float = j.scale
	var armor := ramp(ARMOR[v])
	var acc := ramp(ACCENT[v])
	var shape: String = SHAPE[v]
	if v == "vanguard":
		# Back thruster pack.
		_r.poly(_pts(p, a, [Vector2(-4, -4), Vector2(-7.8, -5), Vector2(-8.4, -9.2), Vector2(-4, -9.2)], s), ramp(SUIT.lightened(0.15)))
		_r.poly(_pts(p, a, [Vector2(-7.4, -4.4), Vector2(-9.0, -2.8), Vector2(-5.6, -3.4)], s), acc)
	# Waist / hips (undersuit) and belt.
	_r.poly(_pts(p, a, [Vector2(-4, 1.6), Vector2(4, 1.6), Vector2(4.2, -2), Vector2(-4.2, -2)], s), ramp(SUIT))
	_r.poly(_pts(p, a, [Vector2(-4.4, -1.2), Vector2(4.6, -1.2), Vector2(4.6, -2.9), Vector2(-4.4, -2.9)], s),
			ramp(SUIT.lightened(0.25)), {"shade": 2.0})
	# Chest plate.
	var chest: Array
	match shape:
		"vanguard":
			chest = [Vector2(-5.0, -2.4), Vector2(5.0, -2.4), Vector2(7.2, -5.8), Vector2(6.2, -9.2),
					Vector2(1.6, -10.0), Vector2(-5.2, -9.4), Vector2(-6.4, -5.6)]
		"aero":
			chest = [Vector2(-4.2, -2.4), Vector2(4.2, -2.4), Vector2(5.8, -6.4), Vector2(4.4, -9.2),
					Vector2(-4.0, -9.2), Vector2(-5.6, -6.2)]
		_:
			chest = [Vector2(-4.6, -2.4), Vector2(4.6, -2.4), Vector2(6.4, -6.2), Vector2(5.2, -9.2),
					Vector2(-4.4, -9.2), Vector2(-6.0, -6.2)]
	_r.poly(_pts(p, a, chest, s), armor)
	# Collar.
	_r.poly(_pts(p, a, [Vector2(-2.8, -8.6), Vector2(2.6, -8.6), Vector2(2.2, -10.2), Vector2(-2.4, -10.2)], s), ramp(SUIT))
	match shape:
		"vanguard":
			_r.poly(_pts(p, a, [Vector2(-1.2, -8.8), Vector2(5.8, -8.0), Vector2(2.6, -5.2)], s), acc)
		"aero":
			_r.poly(_pts(p, a, [Vector2(-3.4, -8.0), Vector2(3.8, -8.0), Vector2(3.4, -7.0), Vector2(-3.4, -7.0)], s), acc, {"shade": 2.0})
	# Core gem.
	_r.ellipse(p + (Vector2(2.2, -5.6) * s).rotated(a), 2.0 * s, 2.0 * s, 0.0, Raster.ramp_from(CORE), {"shade": 0.5})
	_r.dot(p + (Vector2(2.6, -6.6) * s).rotated(a), Color("e8ffff"))


func _wings(j: Dictionary, v: String) -> void:
	var p: Vector2 = j.pelvis + j.up * 7.5 * j.scale
	var spread: float = j.wing
	var acc := ramp(ACCENT[v])
	var s: float = j.scale
	# Two blades fanning out behind the back; spread opens them up.
	var base_a: float = j.lean - 0.2 - spread * 0.5
	for k in 2:
		var ang := base_a - k * (0.35 + spread * 0.45)
		var len := (9.5 + spread * 6.0 - k * 1.5) * s
		var dir := Vector2(-1, 0).rotated(ang)
		var nrm := Vector2(-dir.y, dir.x)
		var root := p + Vector2(-2.0, k * 1.8) * s
		_r.poly(PackedVector2Array([root + nrm * 2.0, root + dir * len + nrm * 1.2,
				root + dir * (len + 3.0), root - nrm * 2.2 + dir * 2.4]), acc)


func _arm(j: Dictionary, side: String, v: String) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	var s: float = j.scale
	var armor := ramp(ARMOR[v])
	var acc := ramp(ACCENT[v])
	var shape: String = SHAPE[v]
	_r.limb(sh, el, 3.6 * s, 3.2 * s, ramp(SUIT))
	var fw := 5.6 if shape == "vanguard" else (4.4 if shape == "aero" else 5.0)
	_r.limb(el, ha, (fw - 0.8) * s, fw * s, armor)
	if shape == "aero":
		var fa: float = j[side + "_fore_angle"]
		var mid := el.lerp(ha, 0.45)
		_r.poly(_pts(mid, -fa, [Vector2(-2.0, -0.5), Vector2(-4.8, -2.8), Vector2(-1.8, 1.6)], s), acc)
	elif shape == "vanguard":
		var band := el.lerp(ha, 0.7)
		_r.ellipse(band, 1.0 * s, 2.6 * s, -j[side + "_fore_angle"], acc, {"line": false, "shade": 2.0})
	_r.ellipse(ha + (ha - el).normalized() * 1.0 * s, 2.0 * s, 2.0 * s, 0.0, ramp(SUIT.lightened(0.35)))
	# Shoulder guard.
	match shape:
		"vanguard":
			_r.poly(_pts(sh, j.lean, [Vector2(-4.0, 1.8), Vector2(-3.8, -2.6), Vector2(0.6, -3.8),
					Vector2(4.3, -1.9), Vector2(4.0, 2.2), Vector2(0, 3.3)], s), armor)
			_r.poly(_pts(sh, j.lean, [Vector2(-1.8, -3.1), Vector2(2.2, -3.6), Vector2(0.2, -1.7)], s), acc, {"line": false})
		"aero":
			_r.ellipse(sh, 2.6 * s, 2.4 * s, 0.0, armor)
		_:
			_r.ellipse(sh, 3.0 * s, 2.8 * s, 0.0, armor)


func _leg(j: Dictionary, side: String, v: String) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = j[side + "_ankle"]
	var s: float = j.scale
	var armor := ramp(ARMOR[v])
	var acc := ramp(ACCENT[v])
	var shape: String = SHAPE[v]
	_r.limb(hip, knee, 4.2 * s, 3.8 * s, ramp(SUIT))
	var sw := 6.0 if shape == "vanguard" else (5.0 if shape == "aero" else 5.4)
	_r.limb(knee, ankle, (sw - 1.4) * s, sw * s, armor)
	_r.ellipse(knee, 2.2 * s, 2.2 * s, 0.0, armor)
	# Boot, anchored at the ankle, tilted by the foot angle.
	var fa: float = -j[side + "_foot"]
	var boot: Array
	match shape:
		"vanguard":
			boot = [Vector2(-4.4, -2.0), Vector2(2.6, -2.0), Vector2(7.0, 2.2), Vector2(7.0, 5.0),
					Vector2(-5.0, 5.0), Vector2(-5.4, 1.2)]
		"aero":
			boot = [Vector2(-3.4, -1.8), Vector2(2.2, -1.8), Vector2(6.8, 2.8), Vector2(6.4, 5.0),
					Vector2(-4.0, 5.0), Vector2(-4.2, 1.2)]
		_:
			boot = [Vector2(-3.8, -1.8), Vector2(2.4, -1.8), Vector2(6.6, 2.4), Vector2(6.6, 5.0),
					Vector2(-4.4, 5.0), Vector2(-4.8, 1.2)]
	_r.poly(_pts(ankle, fa, boot, s), armor)
	# Sole.
	_r.poly(_pts(ankle, fa, [Vector2(-4.6, 3.8), Vector2(6.8, 3.8), Vector2(6.8, 5.0), Vector2(-4.6, 5.0)], s),
			ramp(SUIT), {"shade": 2.0})
	match shape:
		"vanguard":
			_r.poly(_pts(ankle, fa, [Vector2(-5.2, 0.2), Vector2(-7.6, 1.4), Vector2(-7.2, 3.6), Vector2(-5.0, 3.6)], s),
					ramp(SUIT.lightened(0.2)))
			_r.poly(_pts(ankle, fa, [Vector2(-0.6, -1.4), Vector2(2.6, -1.4), Vector2(4.0, 0.2), Vector2(-0.6, 0.2)], s),
					acc, {"shade": 2.0})
		"aero":
			_r.poly(_pts(ankle, fa, [Vector2(-3.0, -0.8), Vector2(-7.8, -3.4), Vector2(-3.6, 1.4)], s), acc)


## Buster arm used while shooting (own sprite, origin = shoulder).
func draw_buster(r: Raster, origin: Vector2, v: String) -> void:
	_r = r
	_far = false
	var armor := ramp(ARMOR[v])
	var acc := ramp(ACCENT[v])
	var shape: String = SHAPE[v]
	var el := origin + Vector2(2.4, 5.8)
	_r.limb(origin, el, 3.6, 3.2, ramp(SUIT))
	match shape:
		"vanguard":
			_r.poly(PackedVector2Array([el + Vector2(-1.8, -3.0), el + Vector2(9.0, -3.4), el + Vector2(10.0, -2.2),
					el + Vector2(10.0, 3.4), el + Vector2(-1.8, 3.4)]), armor)
			_r.poly(PackedVector2Array([el + Vector2(9.0, -3.0), el + Vector2(11.6, -2.4), el + Vector2(11.6, 2.8),
					el + Vector2(9.0, 3.2)]), ramp(SUIT.lightened(0.15)))
			_r.poly(PackedVector2Array([el + Vector2(3.4, -3.2), el + Vector2(5.4, -3.2), el + Vector2(5.4, 3.2),
					el + Vector2(3.4, 3.2)]), acc, {"line": false, "shade": 2.0})
		"aero":
			_r.poly(PackedVector2Array([el + Vector2(-1.8, -2.2), el + Vector2(11.0, -2.0), el + Vector2(11.4, 2.2),
					el + Vector2(-1.8, 2.6)]), armor)
			for k in 2:
				_r.poly(PackedVector2Array([el + Vector2(2.6 + k * 3.2, -2.1), el + Vector2(3.8 + k * 3.2, -2.1),
						el + Vector2(3.8 + k * 3.2, 2.4), el + Vector2(2.6 + k * 3.2, 2.4)]), acc, {"line": false, "shade": 2.0})
			_r.poly(PackedVector2Array([el + Vector2(1, -2.0), el + Vector2(-2.8, -5.2), el + Vector2(4.4, -2.0)]), acc)
		_:
			_r.poly(PackedVector2Array([el + Vector2(-1.8, -2.6), el + Vector2(8.6, -2.8), el + Vector2(9.6, -1.6),
					el + Vector2(9.6, 2.8), el + Vector2(-1.8, 3.0)]), armor)
	var mz := origin + MUZZLE - Vector2(1.6, 0)
	_r.ellipse(mz, 1.1, 2.1, 0.0, Raster.ramp_from(SUIT.darkened(0.3)), {"shade": 2.0})
	_r.dot(mz + Vector2(0.4, 0), CORE.lightened(0.3))


## Arm sprites baked on their own: the buster (forward only).
func extras() -> Array:
	return [{"name": "buster", "cell": Vector2i(24, 20), "origin": Vector2(5, 5), "tip": [MUZZLE.x, MUZZLE.y]}]


func draw_extra(r: Raster, name: String, origin: Vector2, v: String, _angle: float) -> void:
	if name == "buster":
		draw_buster(r, origin, v)
