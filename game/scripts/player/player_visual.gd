extends Node2D
## Placeholder vector art for the player (original design, not final art).
## HEAD / BODY / ARM / LEG are separate layers. Each layer changes colour and
## silhouette with the equipped armor (`part_armor`), so mixed loadouts read at a
## glance — the same layering the final sprites will use.
##
## `player` can be the real player or a preview puppet with the same fields.

const C_FRAME := Color("2a3550")
const C_CORE := Color("00b8be")
const C_VISOR := Color("f0b84a")
const C_LV1 := Color("3de0ee")
const C_LV2 := Color("f0b84a")
const C_CRIMSON := Color("e34f5b")
const C_MINT := Color("71dedf")

const BASE_COLOR := {
	"neutral": Color("d7edf3"),
	"vanguard": Color("3a7fe6"),
	"aero": Color("f2fbff"),
}

var player
var part_armor := {"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "neutral"}

var _f := 1
var _oy := 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var p = player
	if p == null:
		return
	var frame := Engine.get_physics_frames()
	modulate.a = 0.35 if (p.invuln_timer > 0.0 and frame % 4 < 2) else 1.0

	_f = p.visual_facing()
	var t: float = p.anim_time
	var on_floor: bool = p.is_on_floor()
	var dashing: bool = p.is_dashing()
	var air_dash: bool = p.air_dashing
	var sliding: bool = p.is_wall_sliding()
	var shooting: bool = p.shoot_pose_timer > 0.0
	var moving: bool = on_floor and absf(p.velocity.x) > 1.0 and not dashing
	var charge: int = p.charge_level()
	var special: String = p.special_kind

	var col := {}
	for slot in part_armor:
		col[slot] = BASE_COLOR[part_armor[slot]]
	if p.is_hurt() and frame % 4 < 2:
		for slot in col:
			col[slot] = Color.WHITE
	elif (charge == 2 or special != "") and frame % 6 < 3:
		for slot in col:
			col[slot] = col[slot].lerp(C_LV2, 0.45)

	# Afterimages for air dash / specials.
	if air_dash or special == "overdrive":
		for i in 4:
			var y := -24.0 + i * 6.0
			var x0 := -_f * (7.0 + (i % 2) * 4.0)
			draw_line(Vector2(x0, y), Vector2(x0 - _f * (10.0 + i * 2.0), y), Color(C_LV1, 0.55 - i * 0.1), 1.0)
	if special == "skybreaker" and p.special_phase == 1:
		draw_rect(Rect2(-5, -60, 10, 40), Color(C_MINT, 0.35))

	# Back wings (Aero BODY) sit behind everything else.
	if part_armor.body == "aero":
		var spread := 1.0 if p.gliding else 0.35
		_poly([Vector2(-3, -18), Vector2(-3 - 14 * spread, -26 - 4 * spread),
				Vector2(-5 - 10 * spread, -14)], 0.0, Color(C_MINT, 0.85))

	# Legs ------------------------------------------------------------------
	_oy = 0.0
	var front := 2.0
	var back := -3.0
	var lift_front := 0.0
	var lift_back := 0.0
	if dashing and not air_dash:
		front = 5.0
		back = -6.0
		lift_back = 2.0
	elif not on_floor:
		front = 3.0
		back = -2.0
		lift_front = 4.0
		lift_back = 1.0
	elif moving:
		var s := sin(t * 14.0)
		front = 1.0 + s * 3.5
		back = -2.0 - s * 3.5
		lift_front = maxf(0.0, -s) * 2.0
		lift_back = maxf(0.0, s) * 2.0
	_leg(back, lift_back, col.leg.darkened(0.35))
	_leg(front, lift_front, col.leg)
	if p.flying:
		for x in [back, front]:
			var flame := 4.0 + fmod(t * 50.0, 3.0)
			_poly([Vector2(x - 2, -1), Vector2(x + 2, -1), Vector2(x, flame)], 0.0, C_VISOR)

	# Upper body (lower and leaning while dashing) --------------------------
	_oy = 3.0 if (dashing and not air_dash) else 0.0
	var lean := 2.0 if dashing else 0.0
	_rect(-8 + lean, -19, 4, 6, col.arm.darkened(0.35))  # back shoulder
	if part_armor.body == "vanguard":
		_poly([Vector2(-9, -19), Vector2(-12, -23), Vector2(-6, -20)], lean, C_CRIMSON)
	_poly([Vector2(-5, -10), Vector2(5, -10), Vector2(7, -17), Vector2(4, -20),
			Vector2(-4, -20), Vector2(-6, -17)], lean, col.body)
	if part_armor.body == "vanguard":
		_poly([Vector2(-3, -19), Vector2(3, -19), Vector2(0, -15)], lean, C_CRIMSON)
	elif part_armor.body == "aero":
		_rect(-4 + lean, -18, 8, 1, C_MINT)
	_rect(-5 + lean, -11, 10, 2, C_FRAME)  # waist
	draw_circle(_v(1 + lean, -15), 2.0, C_CORE)

	# Head: angular helmet, swept antenna, gold visor.
	_poly([Vector2(-3, -28), Vector2(-10, -31), Vector2(-6, -25)], lean,
			C_MINT if part_armor.head == "aero" else C_CORE)
	_poly([Vector2(-5, -20), Vector2(5, -20), Vector2(6, -25), Vector2(3, -29),
			Vector2(-4, -29), Vector2(-6, -25)], lean, col.head)
	if part_armor.head == "vanguard":
		_poly([Vector2(1, -29), Vector2(7, -32), Vector2(4, -27)], lean, C_CRIMSON)
	elif part_armor.head == "aero":
		_poly([Vector2(-4, -24), Vector2(-9, -27), Vector2(-5, -21)], lean, C_MINT)
	_rect(1 + lean, -26, 5, 2, C_VISOR)

	# Front arm: buster forward while shooting, otherwise at the side.
	if sliding:
		_rect(-9 + lean, -24, 3, 7, col.arm)  # hand on the wall
	if shooting or charge > 0:
		_buster(lean, col.arm, charge)
	else:
		_rect(3 + lean, -18, 4, 7, col.arm)
		_rect(3 + lean, -12, 4, 3, C_FRAME)

	# Effects ---------------------------------------------------------------
	_oy = 0.0
	if dashing and on_floor:
		for i in 3:
			var a := 0.5 - i * 0.15
			draw_circle(_v(-9 - i * 4, -2 - fmod(t * 20.0 + i, 3.0)), 1.6 - i * 0.3, Color(1, 1, 1, a))
	if sliding and frame % 6 < 3:
		draw_rect(Rect2(_v(-7, -2) - Vector2(1, 1), Vector2(2, 2)), C_VISOR)
	if charge > 0:
		var cc := C_LV2 if charge == 2 else C_LV1
		var center := Vector2(0, -14)
		for i in 6:
			var ang := t * 9.0 + i * TAU / 6.0
			var r := 13.0 + sin(t * 30.0 + i) * 2.0
			var at := center + Vector2(cos(ang), sin(ang) * 1.2) * r
			draw_line(at, at + Vector2(cos(ang), sin(ang)) * 3.0, cc, 1.0)
		if charge == 2 and frame % 4 < 2:
			draw_arc(center, 16.0, 0.0, TAU, 20, cc, 1.0)


func _buster(lean: float, c: Color, charge: int) -> void:
	match part_armor.arm:
		"vanguard":
			_rect(2 + lean, -18, 9, 6, c)
			_rect(10 + lean, -19, 5, 8, C_FRAME)
			_rect(14 + lean, -17, 1, 4, C_CRIMSON)
		"aero":
			_rect(2 + lean, -17, 9, 4, c)
			_rect(5 + lean, -17, 1, 4, C_MINT)
			_rect(8 + lean, -17, 1, 4, C_MINT)
			_rect(10 + lean, -17.5, 4, 5, C_FRAME)
		_:
			_rect(2 + lean, -17, 8, 4, c)
			_rect(9 + lean, -18, 4, 6, C_FRAME)
	draw_circle(_v(14 + lean, -15), 1.5, C_LV2 if charge == 2 else C_CORE)


func _v(x: float, y: float) -> Vector2:
	return Vector2(x * _f, y + _oy)


## Axis-aligned rect given in "facing right" space (x = near edge).
func _rect(x: float, y: float, w: float, h: float, c: Color) -> void:
	var a := _v(x, y)
	var b := _v(x + w, y)
	draw_rect(Rect2(Vector2(minf(a.x, b.x), a.y), Vector2(absf(b.x - a.x), h)), c)


func _poly(points: Array, dx: float, c: Color) -> void:
	var arr := PackedVector2Array()
	for q in points:
		arr.append(_v(q.x + dx, q.y))
	draw_colored_polygon(arr, c)


func _leg(x: float, lift: float, c: Color) -> void:
	_rect(x - 2, -10 - lift, 4, 7, c)
	match part_armor.leg:
		"vanguard":
			_rect(x - 3, -6 - lift, 7, 6, c.darkened(0.15))
			_rect(x - 1, -9 - lift, 2, 2, C_CRIMSON)
		"aero":
			_rect(x - 3, -4 - lift, 6, 4, c.darkened(0.15))
			_poly([Vector2(x - 3, -4 - lift), Vector2(x - 7, -6 - lift), Vector2(x - 3, -2 - lift)], 0.0, C_MINT)
		_:
			_rect(x - 3, -4 - lift, 6, 4, c.darkened(0.2))
	_rect(x - 3, -1 - lift, 6, 1, C_FRAME)
