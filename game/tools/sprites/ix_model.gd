extends RefCounted
## NEUTRAL FRAME IX — original design, 32-bit sprite style (v3).
## Rigid parts are hand-drawn pixel grids from ix_kit.gd (helmets, chests, boots,
## shoulder guards, busters); the skeleton places them and draws the jointed limbs
## between. Each armor family replaces the part's whole silhouette, not just its
## colours, so a mixed loadout shows which part is which:
##   neutral   white frame, teal fin, open-face helmet with gold brow band
##   vanguard  crimson brawler: closed helm with a big swept gold horn, broad chest
##             with gold V edges, round double-rimmed pauldrons, a giant silver claw
##             on the front arm (palm emitter when shooting), blocky spurred boots
##   aero      white knight: closed knight helm with gold fins and forward spike,
##             gold-trimmed chest, layered pauldrons, blue energy wings, a lance
##             buster, slim pointed boots
##   ultimate  black-violet + gold: knight helm with the brawler horn, brawler chest
##             and claw, gold energy wings, knight boots

const Raster = preload("res://tools/sprites/raster.gd")
const Kit = preload("res://tools/sprites/ix_kit.gd")

const LAYERS := ["wings", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
const VARIANTS := ["neutral", "vanguard", "aero", "ultimate"]
const LAYER_SLOT := {"wings": "body", "far_arm": "arm", "far_leg": "leg", "body": "body",
		"near_leg": "leg", "head": "head", "near_arm": "arm"}
## Shape family per part slot (ultimate mixes both).
const SHAPE := {
	"neutral": {"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "neutral"},
	"vanguard": {"head": "vanguard", "body": "vanguard", "arm": "vanguard", "leg": "vanguard"},
	"aero": {"head": "aero", "body": "aero", "arm": "aero", "leg": "aero"},
	"ultimate": {"head": "ultimate", "body": "vanguard", "arm": "vanguard", "leg": "aero"},
}
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
	match SHAPE[v].head:
		"neutral":
			_st(Kit.HEAD_FIN, c + Vector2(-3, -5), Vector2i(5, 4))
			_st(Kit.HEAD, c, Kit.HEAD_ANCHOR)
		"aero":
			_st(Kit.HEAD_KNIGHT_FINS, c + Vector2(-1, -1), Vector2i(10, 4))
			_st(Kit.HEAD_KNIGHT, c, Vector2i(7, 6))
		"vanguard":
			_st(Kit.HEAD_BRAWLER, c, Vector2i(7, 5))
			_st(Kit.HEAD_HORN_SWEEP, c + Vector2(6, -3), Vector2i(12, 5))
		"ultimate":
			_st(Kit.HEAD_KNIGHT_FINS, c + Vector2(-1, -1), Vector2i(10, 4))
			_st(Kit.HEAD_KNIGHT, c, Vector2i(7, 6))
			_st(Kit.HEAD_HORN_SWEEP, c + Vector2(6, -4), Vector2i(12, 5))


func _body(j: Dictionary, v: String) -> void:
	var p: Vector2 = (j.pelvis as Vector2).round()
	var shear: float = clampf(j.lean, -0.6, 0.8)
	match SHAPE[v].body:
		"vanguard":
			_st(Kit.TORSO_PACK, p + Vector2(-6 + shear * 7.0, -8), Vector2i(3, 0))
			_st(Kit.TORSO_BRAWLER, p, Vector2i(6, 10), {"shear": shear})
		"aero":
			_st(Kit.TORSO_KNIGHT, p, Vector2i(6, 10), {"shear": shear})
		_:
			_st(Kit.TORSO, p, Kit.TORSO_ANCHOR, {"shear": shear})


## Energy wings (aero: blue, ultimate: gold): three long blades fanning back.
func _wings(j: Dictionary) -> void:
	var p: Vector2 = j.pelvis + j.up * 7.5
	var spread: float = j.wing
	var glow := [Color(_pal["r"]).darkened(0.45), Color(_pal["r"]).darkened(0.1), _pal["r"], _pal["t"], Color.WHITE]
	var base_a: float = j.lean - 0.15 - spread * 0.45
	for k in 3:
		var ang := base_a - k * (0.32 + spread * 0.4)
		var len := 12.0 + spread * 7.0 - k * 2.0
		var dir := Vector2(-1, 0).rotated(ang)
		var nrm := Vector2(-dir.y, dir.x)
		var root := p + Vector2(-2.0, k * 1.6)
		_r.poly(PackedVector2Array([root + nrm * 1.8, root + dir * len * 0.55 + nrm * 1.6, root + dir * (len + 2.5),
				root + dir * len * 0.6 - nrm * 1.4, root - nrm * 1.8]), glow, {"shade": 0.7})


func _arm(j: Dictionary, side: String, v: String) -> void:
	var sh: Vector2 = j[side + "_shoulder"]
	var el: Vector2 = j[side + "_elbow"]
	var ha: Vector2 = j[side + "_hand"]
	var suit := _ramp(["k", "l", "m", "m"])
	var armor := _ramp(["1", "3", "4", "5"])
	var fam: String = SHAPE[v].arm
	_r.limb(sh, el, 3.4, 3.0, suit)
	if fam == "vanguard" and side == "n":
		_claw(el, ha, 0.35)
	else:
		# Gauntlet widening to the wrist, dark fist.
		var fw := 7.0 if fam == "vanguard" else (5.2 if fam == "aero" else 6.2)
		_r.limb(el, ha, fw - 1.8, fw, armor)
		if fam == "aero":
			# Gold wrist guard.
			_r.ellipse(el.lerp(ha, 0.8), fw * 0.5, 1.1, -j[side + "_fore_angle"], _ramp(["p", "q", "s", "s"]), {"shade": 2.0})
		_r.ellipse(ha + (ha - el).normalized() * 1.3, 2.1, 2.1, 0.0, _ramp(["k", "l", "m", "m"]))
	match fam:
		"vanguard":
			_st(Kit.PAD_BRAWLER, sh.round(), Vector2i(5, 2))
		"aero":
			_st(Kit.PAD_KNIGHT, sh.round(), Vector2i(4, 2))
		_:
			_st(Kit.PAD, sh.round(), Kit.PAD_ANCHOR)


## Giant silver claw on the forearm (elbow -> hand): armored housing with a red
## top plate, a glowing ring at the wrist and three curved talons. `spread` opens
## the talons (0 = closed fist of claws, 1 = fully open).
func _claw(el: Vector2, ha: Vector2, spread: float) -> void:
	var d := ha - el
	var len := maxf(d.length(), 0.1)
	var dir := d / len
	var n := Vector2(-dir.y, dir.x)
	var silver := _ramp(["a", "b", "c", "c"])
	var at := func(u: float, w: float) -> Vector2:
		return el + dir * u + n * w
	_r.poly(PackedVector2Array([at.call(-0.8, -2.6), at.call(2.0, -4.0), at.call(len + 0.6, -4.6), at.call(len + 1.6, -3.0),
			at.call(len + 1.6, 3.0), at.call(len + 0.6, 4.6), at.call(2.0, 4.0), at.call(-0.8, 2.6)]), silver)
	_r.poly(PackedVector2Array([at.call(0.4, -2.8), at.call(len, -4.2), at.call(len + 0.6, -1.2), at.call(0.6, -0.8)]),
			_ramp(["1", "3", "4", "5"]), {"shade": 2.0})
	var glow := [Color(_pal["r"]).darkened(0.4), _pal["r"], _pal["t"], Color.WHITE, Color.WHITE]
	_r.ellipse(at.call(len + 1.4, 0.0), 1.2, 2.6, dir.angle(), glow, {"line": false, "shade": 2.0})
	for k in [-1, 0, 1]:
		var base: Vector2 = at.call(len + 2.0, k * 2.4)
		var mid: Vector2 = base + dir * 3.0 + n * k * (0.6 + spread * 2.0)
		var tip: Vector2 = mid + dir * 2.6 - n * k * (0.8 - spread * 0.8)
		_r.limb(base, mid, 2.0, 1.8, silver)
		_r.limb(mid, tip, 1.6, 0.7, silver)


func _leg(j: Dictionary, side: String, v: String) -> void:
	var hip: Vector2 = j[side + "_hip"]
	var knee: Vector2 = j[side + "_knee"]
	var ankle: Vector2 = (j[side + "_ankle"] as Vector2).round()
	var suit := _ramp(["k", "l", "m", "m"])
	var armor := _ramp(["1", "3", "4", "5"])
	var fam: String = SHAPE[v].leg
	_r.limb(hip, knee, 4.4, 4.0, suit)
	# Tall boot: the shin guard flares into the foot stamp.
	var sw := 8.0 if fam == "vanguard" else (6.0 if fam == "aero" else 7.0)
	_r.limb(knee, ankle, sw - 2.4, sw, armor)
	if fam == "neutral":
		_r.ellipse(knee, 2.4, 2.4, 0.0, armor)
	else:
		# Knee guard with a forward point (gold-edged for both armor families).
		var ka: float = -j[side + "_shin_angle"]
		var kp := func(x: float, y: float) -> Vector2:
			return knee + Vector2(x, y).rotated(ka)
		var big := 1.25 if fam == "vanguard" else 1.0
		_r.poly(PackedVector2Array([kp.call(-2.4 * big, -2.0), kp.call(2.2 * big, -3.0), kp.call(3.6 * big, -0.4),
				kp.call(2.0 * big, 2.2), kp.call(-2.4 * big, 2.0)]), armor)
		_r.poly(PackedVector2Array([kp.call(2.2 * big, -3.0), kp.call(3.6 * big, -0.4), kp.call(2.6 * big, 0.2),
				kp.call(1.6 * big, -2.2)]), _ramp(["p", "q", "s", "s"]), {"line": false, "shade": 2.0})
	var toe_down: bool = j[side + "_foot"] < -0.3
	if toe_down:
		_st(Kit.BOOT_DOWN, ankle, Kit.BOOT_DOWN_ANCHOR)
	else:
		match fam:
			"vanguard":
				_st(Kit.BOOT_BRAWLER, ankle, Vector2i(5, 1))
			"aero":
				_st(Kit.BOOT_KNIGHT, ankle, Vector2i(4, 1))
			_:
				_st(Kit.BOOT, ankle, Kit.BOOT_ANCHOR)


## Buster arm used while shooting (own sprite, origin = shoulder).
func draw_buster(r: Raster, origin: Vector2, v: String) -> void:
	_r = r
	_r.selout = true
	_far = false
	_pal = _palette(v, false)
	var el := (origin + Vector2(2.4, 5.8)).round()
	_r.limb(origin, el, 3.6, 3.2, _ramp(["k", "l", "m", "m"]))
	match SHAPE[v].arm:
		"vanguard":
			# Claw held out flat, talons spread round the glowing palm emitter.
			_claw(el, el + Vector2(7.0, 0.0), 1.0)
			_r.ellipse(el + Vector2(10.2, 0.0), 1.8, 1.8, 0.0,
					[Color(_pal["r"]).darkened(0.4), _pal["r"], _pal["t"], Color.WHITE, Color.WHITE], {"line": false, "shade": 2.0})
		"aero":
			_st(Kit.BUSTER_LANCE, el, Vector2i(1, 2))
		_:
			_st(Kit.BUSTER, el, Kit.BUSTER_ANCHOR)


func extras() -> Array:
	return [{"name": "buster", "cell": Vector2i(28, 20), "origin": Vector2(5, 5), "tip": [MUZZLE.x, MUZZLE.y]}]


func draw_extra(r: Raster, name: String, origin: Vector2, v: String, _angle: float) -> void:
	if name == "buster":
		draw_buster(r, origin, v)
