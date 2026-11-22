extends RefCounted
## ECLIPSE — ARCA's anti-hunter prototype built on the original IX frame: IX's dark
## twin (original design). Graphite armor with violet-red trim, a crescent crest
## swept back over the helmet, a full mask with one visor slit, spiked pauldrons,
## back vanes, an "eclipsed" chest core (dark disc over a ring of light) and a
## long-barrelled buster.
##
## Unlike the player models each sheet layer is a finished composite: the depth
## parts below are rasterised one by one (own outline each, like IX's layers) and
## flattened into a single cell, so the boss draws one opaque sprite per frame.
## That keeps every pixel at the same alpha inside the enemy CanvasGroup, whose
## shader leaves pre-shaded sprites alone only at alpha ~0.98 (stacked layers
## would add up past it).
##   full   the whole body with the animated near arm
##   aim    the same body with the buster arm at the frame's shoulder
## Variants (rows):
##   eclipse  phase 1
##   limit    phase 2 limiter release: trim, visor and core run hot
##   flat     white silhouette (outline included) for hit flash / afterimages, tinted at runtime

const Raster = preload("res://tools/sprites/raster.gd")

const LAYERS := ["full", "aim"]
const VARIANTS := ["eclipse", "limit", "flat"]
const LAYER_SLOT := {"full": "body", "aim": "body"}
## Depth order of the parts inside each composite (back to front).
const PARTS := ["back", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]

const ARMOR := Color("524d72")
const PLATE := Color("857ca8")
const SUIT := Color("25202f")
const MASK := Color("332e48")
const TRIM := {"eclipse": Color("c42a64"), "limit": Color("ff4f96")}
const VISOR := {"eclipse": Color("ff4fd8"), "limit": Color("ffc4f2")}
const RING := {"eclipse": Color("e05cff"), "limit": Color("fbe9ff")}
const DARK := Color("120c1a")
const LINE := Color("07050c")

## Shoulder-relative point where shots leave the buster (raster space, facing right).
## Matches eclipse.gd's MUZZLE for the standing / clinging frames.
const MUZZLE := Vector2(15.6, 6.6)

## Outer outline of the current variant (read by the baker after each draw call):
## the flat variant's outline is part of the white silhouette.
var OUTLINE := LINE

var _r: Raster
var _far := false
var _v := "eclipse"


func has_layer(_layer: String, _variant: String) -> bool:
	return true


func _use(v: String) -> void:
	_v = v
	OUTLINE = Color.WHITE if v == "flat" else LINE


func _flat() -> bool:
	return _v == "flat"


func ramp(c: Color) -> Array:
	if _flat():
		return [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
	return Raster.ramp_from(c.darkened(0.14) if _far else c, LINE)


func _trim() -> Color:
	return TRIM.get(_v, TRIM.eclipse)


func _visor() -> Color:
	return VISOR.get(_v, VISOR.eclipse)


func _ring() -> Color:
	return RING.get(_v, RING.eclipse)


func _dot(p: Vector2, c: Color) -> void:
	_r.dot(p, Color.WHITE if _flat() else c)


## Glowing parts: flat ramp (base tone with a lit tone on top only).
func _glow(c: Color) -> Array:
	if _flat():
		return ramp(c)
	return [c.darkened(0.45), c.darkened(0.2), c, c.lightened(0.45), c.lightened(0.7)]


func draw(r: Raster, j: Dictionary, layer: String, variant: String) -> void:
	_use(variant)
	for part in PARTS:
		var sub := Raster.new(r.w, r.h)
		_r = sub
		_far = part.begins_with("far")
		match part:
			"back":
				_back(j)
			"far_arm":
				_arm(j, "f")
			"far_leg":
				_leg(j, "f")
			"body":
				_body(j)
			"near_leg":
				_leg(j, "n")
			"head":
				_head(j)
			"near_arm":
				if layer == "aim":
					_buster(j.n_shoulder)
				else:
					_arm(j, "n")
		sub.finish(OUTLINE)
		r.img.blend_rect(sub.img, Rect2i(0, 0, r.w, r.h), Vector2i.ZERO)
	_r = r


# --- helpers -------------------------------------------------------------------------

## Local polygon (facing right, origin at `at`, rotated by `angle`) to raster space.
func _pts(at: Vector2, angle: float, local: Array, s := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in local:
		out.append(at + (q * s).rotated(angle))
	return out


# --- parts ---------------------------------------------------------------------------

func _head(j: Dictionary) -> void:
	var c: Vector2 = j.head
	var a: float = j.head_angle * 0.6
	var s: float = j.scale
	var armor := ramp(ARMOR)
	var trim := ramp(_trim())
	# Crescent crest behind the helmet: a short horn up over the brow and a long
	# one sweeping back, the two tips of one crescent.
	_r.poly(_pts(c, a, [Vector2(5.4, -11.6), Vector2(4.8, -8.6), Vector2(2.4, -6.2), Vector2(-1.0, -5.4),
			Vector2(-4.8, -6.4), Vector2(-8.4, -9.4), Vector2(-11.6, -13.2), Vector2(-6.8, -11.2),
			Vector2(-3.6, -9.4), Vector2(-0.6, -9.0), Vector2(2.2, -9.6)], s), trim)
	# Helmet shell: angular, a little taller at the back than IX's.
	_r.poly(_pts(c, a, [Vector2(-5.6, 3.2), Vector2(-6.6, -1.0), Vector2(-5.8, -4.6), Vector2(-2.6, -6.8),
			Vector2(2.4, -6.8), Vector2(5.6, -4.8), Vector2(6.6, -1.4), Vector2(6.4, 2.0),
			Vector2(4.2, 5.0), Vector2(-1.8, 5.2)], s), armor)
	# Brow ridge (lighter plate over the mask).
	_r.poly(_pts(c, a, [Vector2(-0.6, -5.6), Vector2(4.8, -5.0), Vector2(6.6, -2.4), Vector2(0.2, -2.4)], s),
			ramp(PLATE), {"shade": 2.0})
	# Full mask, one visor slit and its glint, a trim cheek line.
	_r.poly(_pts(c, a, [Vector2(0.6, -2.4), Vector2(6.6, -2.4), Vector2(6.4, 1.8), Vector2(4.2, 4.6),
			Vector2(0.8, 4.4)], s), ramp(MASK), {"shade": 0.2})
	_r.poly(_pts(c, a, [Vector2(0.6, -1.6), Vector2(6.9, -1.6), Vector2(6.9, 0.2), Vector2(0.6, 0.2)], s),
			_glow(_visor()), {"line": false, "shade": 2.0, "spec": false})
	_dot(c + (Vector2(5.6, -1.0) * s).rotated(a), _visor().lightened(0.8))
	# Chin guard.
	_r.poly(_pts(c, a, [Vector2(1.4, 2.0), Vector2(6.0, 1.4), Vector2(4.2, 4.6), Vector2(1.2, 4.4)], s),
			ramp(PLATE), {"shade": 0.6})
	# Hex ear disc with a glowing pin.
	_r.poly(_pts(c, a, [Vector2(-4.4, 0.0), Vector2(-3.4, -1.6), Vector2(-1.6, -1.6), Vector2(-0.6, 0.2),
			Vector2(-1.6, 2.4), Vector2(-3.6, 2.4)], s), ramp(PLATE), {"shade": 0.3})
	_dot(c + (Vector2(-2.6, 0.4) * s).rotated(a), _visor())


func _back(j: Dictionary) -> void:
	# One stiff vane angled down behind the back (thruster fin), trim on its upper edge.
	var p: Vector2 = j.pelvis + j.up * 6.0 * j.scale
	var s: float = j.scale
	var a: float = j.lean
	_r.poly(_pts(p, a, [Vector2(-2.4, -2.6), Vector2(-9.4, -1.0), Vector2(-11.2, 2.4), Vector2(-3.0, 3.2)], s),
			ramp(ARMOR))
	_r.poly(_pts(p, a, [Vector2(-2.4, -2.6), Vector2(-9.4, -1.0), Vector2(-10.2, 0.6), Vector2(-3.0, -0.8)], s),
			ramp(_trim()), {"line": false, "shade": 2.0})


func _body(j: Dictionary) -> void:
	var p: Vector2 = j.pelvis
	var a: float = j.lean
	var s: float = j.scale
	var armor := ramp(ARMOR)
	var trim := ramp(_trim())
	# Waist (undersuit) and belt with a trim buckle.
	_r.poly(_pts(p, a, [Vector2(-4, 1.6), Vector2(4, 1.6), Vector2(4.2, -2), Vector2(-4.2, -2)], s), ramp(SUIT))
	_r.poly(_pts(p, a, [Vector2(-4.6, -1.0), Vector2(4.8, -1.0), Vector2(4.8, -3.0), Vector2(-4.6, -3.0)], s),
			ramp(PLATE), {"shade": 2.0})
	_r.poly(_pts(p, a, [Vector2(1.2, -0.8), Vector2(4.4, -0.8), Vector2(4.4, -3.2), Vector2(1.2, -3.2)], s), trim,
			{"shade": 2.0})
	# Chest: wider and more angular than IX's, a dark lower plate.
	_r.poly(_pts(p, a, [Vector2(-5.0, -2.6), Vector2(5.0, -2.6), Vector2(7.0, -6.0), Vector2(5.8, -9.6),
			Vector2(1.0, -10.4), Vector2(-5.2, -9.8), Vector2(-6.6, -5.8)], s), armor)
	_r.poly(_pts(p, a, [Vector2(-4.6, -2.6), Vector2(4.8, -2.6), Vector2(5.8, -4.2), Vector2(-5.6, -4.2)], s),
			ramp(SUIT.lightened(0.12)), {"shade": 2.0})
	# Upper chest plate.
	_r.poly(_pts(p, a, [Vector2(-4.6, -9.4), Vector2(5.6, -9.2), Vector2(6.6, -6.4), Vector2(3.6, -5.0),
			Vector2(-5.0, -5.8)], s), ramp(PLATE), {"shade": 0.7})
	# Collar with a trim band.
	_r.poly(_pts(p, a, [Vector2(-2.8, -8.8), Vector2(2.8, -8.8), Vector2(2.4, -10.6), Vector2(-2.4, -10.6)], s),
			ramp(SUIT))
	_r.poly(_pts(p, a, [Vector2(-4.4, -8.4), Vector2(5.6, -8.4), Vector2(6.2, -9.6), Vector2(-4.8, -9.6)], s),
			trim, {"shade": 2.0})
	# Eclipsed core: a ring of light with a dark disc shifted forward over it.
	var core := p + (Vector2(1.6, -5.8) * s).rotated(a)
	_r.ellipse(core, 2.9 * s, 2.9 * s, 0.0, _glow(_ring()), {"shade": 2.0, "spec": false})
	_r.ellipse(core + Vector2(0.9, -0.5) * s, 1.8 * s, 1.8 * s, 0.0, ramp(DARK), {"line": false, "shade": 2.0})
	_dot(core + Vector2(-1.9, 1.0) * s, _ring().lightened(0.7))


func _arm(j: Dictionary, side: String) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	var s: float = j.scale
	var armor := ramp(ARMOR)
	_r.limb(sh, el, 3.6 * s, 3.2 * s, ramp(SUIT))
	_r.limb(el, ha, 4.2 * s, 5.0 * s, armor)
	# Trim cuff near the wrist.
	var cuff := el.lerp(ha, 0.72)
	_r.ellipse(cuff, 1.0 * s, 2.4 * s, -j[side + "_fore_angle"], ramp(_trim()), {"line": false, "shade": 2.0})
	_r.ellipse(ha + (ha - el).normalized() * 1.0 * s, 2.0 * s, 2.0 * s, 0.0, ramp(SUIT.lightened(0.2)))
	_pauldron(sh, j.lean, s)


## Spiked pauldron: angular guard with a back spike and a trim rim.
func _pauldron(sh: Vector2, lean: float, s: float) -> void:
	_r.poly(_pts(sh, lean, [Vector2(-3.4, 2.2), Vector2(-5.0, -2.8), Vector2(-1.8, -3.0), Vector2(1.6, -3.8),
			Vector2(3.8, -1.4), Vector2(3.4, 2.4), Vector2(0.0, 3.2)], s), ramp(ARMOR))
	_r.poly(_pts(sh, lean, [Vector2(-3.2, 1.6), Vector2(3.4, 1.6), Vector2(3.4, 2.4), Vector2(0.0, 3.2),
			Vector2(-3.4, 2.2)], s), ramp(_trim()), {"line": false, "shade": 2.0})


func _leg(j: Dictionary, side: String) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = j[side + "_ankle"]
	var s: float = j.scale
	var armor := ramp(ARMOR)
	var trim := ramp(_trim())
	_r.limb(hip, knee, 4.2 * s, 3.8 * s, ramp(SUIT))
	_r.limb(knee, ankle, 4.2 * s, 5.6 * s, armor)
	# Shin front plate (local +y runs down the shin, +x is forward).
	var ka: float = -j[side + "_shin_angle"]
	_r.poly(_pts(knee, ka, [Vector2(0.2, 0.8), Vector2(2.4, 1.0), Vector2(2.9, 4.6), Vector2(0.2, 4.6)], s),
			ramp(PLATE), {"shade": 2.0})
	# Knee guard with a short forward spike.
	_r.poly(_pts(knee, ka, [Vector2(-2.2, -1.8), Vector2(1.6, -2.4), Vector2(4.2, -0.6), Vector2(1.8, 1.0),
			Vector2(-2.2, 1.8)], s), ramp(ARMOR))
	# Boot: pointed toe, trim stripe, dark sole, heel spur.
	var fa: float = -j[side + "_foot"]
	_r.poly(_pts(ankle, fa, [Vector2(-4.0, -2.0), Vector2(2.2, -2.0), Vector2(5.0, 0.6), Vector2(8.0, 3.4),
			Vector2(7.4, 5.0), Vector2(-4.6, 5.0), Vector2(-5.2, 1.2)], s), armor)
	_r.poly(_pts(ankle, fa, [Vector2(-0.4, -1.6), Vector2(2.0, -1.6), Vector2(4.6, 1.0), Vector2(2.0, 1.0)], s),
			trim, {"shade": 2.0})
	_r.poly(_pts(ankle, fa, [Vector2(-4.8, 3.8), Vector2(7.6, 3.8), Vector2(7.4, 5.0), Vector2(-4.8, 5.0)], s),
			ramp(SUIT), {"shade": 2.0})
	_r.poly(_pts(ankle, fa, [Vector2(-4.8, 0.6), Vector2(-7.4, 2.8), Vector2(-4.8, 3.8)], s), ramp(PLATE))


## Buster arm (own sprite, origin = shoulder): a long angular cannon, trim bands,
## narrower barrel and a glowing muzzle.
func _buster(origin: Vector2) -> void:
	var armor := ramp(ARMOR)
	var trim := ramp(_trim())
	var el := origin + Vector2(2.4, 5.8)
	_r.limb(origin, el, 3.6, 3.2, ramp(SUIT))
	# Cannon body.
	_r.poly(PackedVector2Array([el + Vector2(-2.0, -2.8), el + Vector2(7.4, -3.4), el + Vector2(9.4, -2.0),
			el + Vector2(9.4, 3.0), el + Vector2(-2.0, 3.2)]), armor)
	# Dark underside rail and a top fin.
	_r.poly(PackedVector2Array([el + Vector2(-1.4, 1.6), el + Vector2(9.4, 1.6), el + Vector2(9.4, 3.0),
			el + Vector2(-1.4, 3.2)]), ramp(SUIT.lightened(0.12)), {"shade": 2.0})
	_r.poly(PackedVector2Array([el + Vector2(0.4, -2.9), el + Vector2(-2.8, -5.4), el + Vector2(4.0, -3.2)]), trim)
	# Trim bands.
	_r.poly(PackedVector2Array([el + Vector2(2.6, -3.1), el + Vector2(4.2, -3.2), el + Vector2(4.2, 1.6),
			el + Vector2(2.6, 1.6)]), trim, {"line": false, "shade": 2.0})
	# Barrel.
	_r.poly(PackedVector2Array([el + Vector2(9.0, -1.8), el + Vector2(13.4, -1.6), el + Vector2(13.4, 2.2),
			el + Vector2(9.0, 2.4)]), ramp(PLATE))
	var mz := origin + MUZZLE - Vector2(1.6, 0)
	_r.ellipse(mz, 1.1, 2.0, 0.0, ramp(DARK), {"shade": 2.0})
	_dot(mz + Vector2(0.4, 0), _visor())
	_pauldron(origin, 0.0, 1.0)


## The buster on its own, like IX's extra (the composite "aim" layer already has it).
func extras() -> Array:
	return [{"name": "buster", "cell": Vector2i(30, 20), "origin": Vector2(8, 6), "tip": [MUZZLE.x, MUZZLE.y]}]


func draw_extra(r: Raster, name: String, origin: Vector2, v: String, _angle: float) -> void:
	_use(v)
	_r = r
	_far = false
	if name == "buster":
		_buster(origin)
