extends Node2D
## Placeholder vector art for the partner characters (original designs).
##   SABLE — slim dark frame, orange accents, blade crest, energy saber
##   ECHO  — compact teal frame, twin antennae, twin pistols; drone in mini form

const C_FRAME := Color("2a3550")
const C_VISOR := Color("3de0ee")
const SABLE_BODY := Color("3b4262")
const SABLE_ACCENT := Color("f08a3a")
const ECHO_BODY := Color("5ad19a")
const ECHO_ACCENT := Color("b78af3")

var player
var character := "sable"

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
	if character == "echo" and p.mini:
		_draw_mini(p)
		return
	var t: float = p.anim_time
	var on_floor: bool = p.is_on_floor()
	var dashing: bool = p.is_dashing()
	var moving: bool = on_floor and absf(p.velocity.x) > 1.0 and not dashing
	var body := SABLE_BODY if character == "sable" else ECHO_BODY
	var accent := SABLE_ACCENT if character == "sable" else ECHO_ACCENT
	if p.is_hurt() and frame % 4 < 2:
		body = Color.WHITE
	if p.special_kind == "tag_strike":
		for i in 4:
			var y := -24.0 + i * 6.0
			draw_line(Vector2(-_f * 6.0, y), Vector2(-_f * (18.0 + i * 3.0), y), Color(accent, 0.6), 1.0)

	# Legs.
	_oy = 0.0
	var front := 2.0
	var back := -3.0
	var lift_front := 0.0
	var lift_back := 0.0
	if dashing and not p.air_dashing:
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
	_leg(back, lift_back, body.darkened(0.35))
	_leg(front, lift_front, body)
	if p.hovering:
		for x in [back, front]:
			_poly([Vector2(x - 2, -1), Vector2(x + 2, -1), Vector2(x, 3 + fmod(t * 40.0, 2.0))], 0.0, ECHO_ACCENT)

	# Body and head.
	_oy = 3.0 if (dashing and not p.air_dashing) else 0.0
	var lean := 2.0 if dashing else 0.0
	if character == "sable":
		_draw_sable_upper(p, lean, body, accent)
	else:
		_draw_echo_upper(p, lean, body, accent)
	_oy = 0.0


func _draw_sable_upper(p, lean: float, body: Color, accent: Color) -> void:
	_poly([Vector2(-8, -21), Vector2(-3, -21), Vector2(-4, -15), Vector2(-9, -16)], lean, accent.darkened(0.3))
	_poly([Vector2(-4, -10), Vector2(4, -10), Vector2(6, -18), Vector2(3, -21),
			Vector2(-3, -21), Vector2(-5, -18)], lean, body)
	_rect(-1 + lean, -19, 2, 8, accent)
	# Head with a forward blade crest.
	_poly([Vector2(-4, -21), Vector2(4, -21), Vector2(5, -26), Vector2(2, -29),
			Vector2(-3, -29), Vector2(-5, -26)], lean, body.lightened(0.15))
	_poly([Vector2(-1, -29), Vector2(9, -33), Vector2(3, -27)], lean, accent)
	_rect(1 + lean, -26, 4, 2, C_VISOR)
	var atk = p.attack
	var swing: int = atk.swing if atk != null else 0
	if swing == 0:
		_rect(2 + lean, -19, 3, 8, body.darkened(0.2))
		_rect(-1 + lean, -13, 2, 9, Color("9fb8d6"))  # sheathed hilt
	else:
		_draw_slash(atk, lean, accent)
	if atk != null and atk.parry_t > 0.0:
		var mid := 0.0 if _f > 0 else PI
		draw_arc(_v(10 + lean, -15), 11.0, mid - 1.2, mid + 1.2, 12, Color(accent, 0.9), 2.0)


func _draw_slash(atk, lean: float, accent: Color) -> void:
	var k: float = clampf(atk.swing_t / maxf(atk.swing_len, 0.001), 0.0, 1.0)
	var blade := Color(0.85, 1.0, 1.0)
	var center := _v(2 + lean, -16)
	_rect(2 + lean, -18, 6, 4, SABLE_BODY.lightened(0.2))
	match atk.swing:
		4:  # air spin: full circle
			var a0 := k * TAU * 1.5
			draw_arc(center, 16.0, a0, a0 + 4.0, 20, Color(blade, 0.9), 3.0)
			draw_arc(center, 16.0, a0, a0 + 4.0, 20, Color(accent, 0.6), 1.0)
		5:  # dash lunge: thrust
			draw_line(_v(6 + lean, -14), _v(30 + lean, -13), blade, 3.0)
			draw_line(_v(6 + lean, -14), _v(30 + lean, -13), accent, 1.0)
		_:
			var start := -1.6 + k * 2.8
			var span := 1.6
			var a := start if _f > 0 else PI - start - span
			draw_arc(center, 18.0 if atk.swing in [3, 7] else 15.0, a, a + span, 14, Color(blade, 0.95), 3.0)
			draw_arc(center, 13.0, a, a + span, 14, Color(accent, 0.5), 1.0)


func _draw_echo_upper(p, lean: float, body: Color, accent: Color) -> void:
	_poly([Vector2(-4, -10), Vector2(4, -10), Vector2(5, -17), Vector2(-5, -17)], lean, body)
	_rect(-4 + lean, -12, 8, 2, C_FRAME)
	draw_circle(_v(0 + lean, -14), 1.5, accent)
	# Head: round, twin antennae.
	_poly([Vector2(-4, -17), Vector2(4, -17), Vector2(5, -22), Vector2(2, -25),
			Vector2(-3, -25), Vector2(-5, -22)], lean, body.lightened(0.2))
	draw_line(_v(-2 + lean, -25), _v(-5 + lean, -29), accent, 1.0)
	draw_line(_v(1 + lean, -25), _v(-1 + lean, -30), accent, 1.0)
	_rect(1 + lean, -22, 4, 2, Color("f0b84a"))
	# Pistols along the aim direction.
	var aim: Vector2 = p.attack.aim() if p.attack != null else Vector2(_f, 0)
	var shoulder := _v(1 + lean, -15)
	draw_line(shoulder, shoulder + aim * 9.0, body.darkened(0.2), 3.0)
	draw_line(shoulder + aim * 6.0, shoulder + aim * 11.0, C_FRAME, 3.0)
	draw_line(shoulder + Vector2(0, 2), shoulder + Vector2(0, 2) + aim * 8.0, C_FRAME, 2.0)
	var atk = p.attack
	if atk != null and atk.form == "turret":
		draw_arc(shoulder, 13.0, 0.0, TAU, 16, Color(ECHO_ACCENT, 0.5), 1.0)
	elif atk != null and atk.copy != "":
		draw_circle(_v(-6 + lean, -27), 2.0, ECHO_ACCENT)


func _draw_mini(p) -> void:
	var t: float = p.anim_time
	for i in 4:
		var lx := -4.0 + i * 2.6
		draw_line(Vector2(lx, -3), Vector2(lx + sin(t * 18.0 + i) * 1.5, 0), C_FRAME, 1.0)
	draw_circle(Vector2(0, -6), 5.0, ECHO_BODY)
	draw_rect(Rect2(_f * 2.0 - 1.0, -8, 2, 2), Color("f0b84a"))
	draw_line(Vector2(-1, -11), Vector2(-3, -14), ECHO_ACCENT, 1.0)


func _v(x: float, y: float) -> Vector2:
	return Vector2(x * _f, y + _oy)


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
	_rect(x - 1.5, -10 - lift, 3, 7, c)
	_rect(x - 2.5, -4 - lift, 5, 4, c.darkened(0.2))
	_rect(x - 2.5, -1 - lift, 5, 1, C_FRAME)
