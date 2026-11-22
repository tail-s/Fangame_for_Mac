extends "res://scripts/enemies/boss_base.gd"
## ECLIPSE — hidden boss (GDD v0.2 §3-5, §5-3). ARCA's anti-hunter prototype,
## built from the hunters' combat records. It mirrors the player's movement kit
## with the same numbers as player.gd (walk 90, dash 210, jump 330, gravity 900):
##   RUN_GUN      strafes toward the mirrored side of the room firing tap shots,
##                copying the player's jumps and dashes as they happen
##   DASH_JUMP    crouch -> dash -> dash jump, aimed shot at the apex (wall bounce)
##   WALL_CLIMB   runs to a wall, climbs it with wall kicks, clings and fires an
##                aimed charged shot, then leaps off
##   CHARGE       stands and charges a big buster shot (large glow telegraph)
##   MIRROR_RUSH  (phase 2) a full-width dash through the player, there and back
## LEARNING: the same weapon id landing LEARN_HITS hits in a row makes it adapt to
## that weapon (x0.25 damage, min 1, hex barrier + "ADAPT") until a different
## weapon hits it. No weakness.
## Phase 2 (HP <= 50%): limiter release — faster, afterimages, air dash at the
## dash-jump apex, spread charge shot, MIRROR_RUSH joins the rotation.
## Moves kinematically inside `arena`; the body centre sits H px above the feet.

const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")

enum S { INTRO, IDLE, RUN_GUN, DASH_JUMP, WALL_CLIMB, CHARGE, MIRROR_RUSH }

# Movement numbers copied from player.gd so the mirror moves like the player.
const WALK := 90.0
const DASH := 210.0
const JUMP := 330.0
const GRAVITY := 900.0
const MAX_FALL := 330.0
const WALL_KICK := 90.0
const WALL_KICK_LOCK := 0.12

const H := 13.0  # body centre to feet
const W := 6.0  # body centre to the wall it touches
const MUZZLE := Vector2(16.5, -2.0)  # buster tip from the body centre, facing right
const RUSH_SPEED := 330.0
const TAP_SPEED := 240.0
const AIM_SPEED := 220.0
const CHARGE_SPEED := 200.0
const KEEP_AWAY := 64.0
const LEARN_HITS := 3
const RESIST_MULT := 0.25

const C_FRAME := Color("1a1228")
const C_ARMOR := Color("45325f")
const C_PLATE := Color("7352a8")
const C_TRIM := Color("c6a6ff")
const C_VISOR := Color("ff4fd8")
const C_HOT := Color("fbe9ff")

var state := S.INTRO
var vel := Vector2.ZERO
var grounded := false
## -1 / 1 while touching the left / right arena wall, else 0.
var wall := 0
## Learning: the weapon it has adapted to ("" = none) and the current hit streak.
var resist_weapon := ""
var streak_weapon := ""
var streak := 0

var _timer := 0.0
var _step := 0
var _side := 1.0
var _shots_left := 0
var _shot_timer := 0.0
var _kicks_left := 0
var _kick_lock := 0.0
var _bounces := 0
var _passes := 0
var _apex_done := false
var _air_dash := 0.0
var _dash_t := 0.0
var _dash_dir := 1.0
var _mirror_cd := 0.0
var _charge := 0.0
var _charge_total := 1.0
var _bag: Array = []
var _last_pattern := -1
var _intro_total := 1.0
var _trail: Array = []
var _trail_clock := 0.0
var _muzzle_fx := 0.0
var _adapt_fx := 0.0
var _break_fx := 0.0
var _release_fx := 0.0
var _death_t0 := -1.0
# draw helpers state
var _df := 1.0
var _doff := Vector2.ZERO
var _flat := Color(0, 0, 0, 0)
var _lean := 0.0
var _uy := 0.0


## Buster round: violet tap shot, or a big charged shot (`big`).
class BusterShot extends "res://scripts/combat/enemy_shot.gd":
	var big := false
	var radius := 3.0
	var _age := 0.0

	func _ready() -> void:
		super._ready()
		if big:
			for c in get_children():
				if c is CollisionShape2D:
					c.shape.radius = radius

	func _physics_process(delta: float) -> void:
		_age += delta
		super._physics_process(delta)

	func _draw() -> void:
		if not big:
			draw_circle(Vector2.ZERO, 3.5, Color("b78af3"))
			draw_circle(Vector2.ZERO, 1.6, Color("fbe9ff"))
			return
		var d := velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT
		for i in 3:
			draw_circle(-d * (5.0 + i * 4.0), radius * (0.7 - i * 0.18), Color("e05cff", 0.35 - i * 0.1))
		var flick := int(_age * 30.0) % 2 == 0
		draw_circle(Vector2.ZERO, radius + 1.5, Color("e05cff", 0.45))
		draw_circle(Vector2.ZERO, radius, Color("b78af3") if flick else Color("e05cff"))
		draw_circle(Vector2.ZERO, radius * 0.5, Color("fbe9ff"))


func _init() -> void:
	boss_name = "ECLIPSE"
	max_hp = 40
	weakness = ""
	contact_damage = 3
	hit_radius = 11.0
	intro_time = 1.4
	death_time = 2.0


func _boss_ready() -> void:
	_intro_total = intro_time
	_clamp()
	facing = -1.0 if position.x > arena.get_center().x else 1.0


func _boss_intro(delta: float) -> void:
	_physics(delta)
	_face_player()


func _on_active() -> void:
	_idle(0.3)


func _boss_process(delta: float) -> void:
	_timer -= delta
	_kick_lock = maxf(_kick_lock - delta, 0.0)
	_mirror_cd = maxf(_mirror_cd - delta, 0.0)
	_muzzle_fx = maxf(_muzzle_fx - delta, 0.0)
	_adapt_fx = maxf(_adapt_fx - delta, 0.0)
	_break_fx = maxf(_break_fx - delta, 0.0)
	_release_fx = maxf(_release_fx - delta, 0.0)
	match state:
		S.IDLE:
			_process_idle(delta)
		S.RUN_GUN:
			_process_run_gun(delta)
		S.DASH_JUMP:
			_process_dash_jump(delta)
		S.WALL_CLIMB:
			_process_wall_climb(delta)
		S.CHARGE:
			_process_charge(delta)
		S.MIRROR_RUSH:
			_process_rush(delta)
	_tick_trail(delta)


# --- patterns ------------------------------------------------------------------------

func _choose_pattern() -> void:
	var pool := [S.RUN_GUN, S.DASH_JUMP, S.WALL_CLIMB, S.CHARGE]
	if phase2:
		pool.append(S.MIRROR_RUSH)
	# Shuffled bag: every move shows up once per cycle, no immediate repeats.
	if _bag.is_empty():
		_bag = pool.duplicate()
		_bag.shuffle()
		if _bag.size() > 1 and _bag[0] == _last_pattern:
			_bag.push_back(_bag.pop_front())
	var p: int = _bag.pop_front()
	_last_pattern = p
	_step = 0
	match p:
		S.RUN_GUN:
			state = S.RUN_GUN
			_timer = 2.3
			_shots_left = 6 if phase2 else 5
			_shot_timer = 0.45
		S.DASH_JUMP:
			state = S.DASH_JUMP
			_timer = 0.22 if phase2 else 0.3  # crouch telegraph
			_face_player()
			_side = facing
			_bounces = 1
			_apex_done = false
		S.WALL_CLIMB:
			state = S.WALL_CLIMB
			# The wall on its own side, so it never runs through the player.
			_side = signf(position.x - _player_x())
			if _side == 0.0:
				_side = -facing
			_kicks_left = 2 if phase2 else 1
			_timer = 1.8
		S.CHARGE:
			state = S.CHARGE
			_charge_total = 0.75 if phase2 else 1.0
			_timer = _charge_total
			_face_player()
		S.MIRROR_RUSH:
			state = S.MIRROR_RUSH
			_timer = 0.55
			_face_player()
			_side = facing
			_passes = 2


func _idle(time: float) -> void:
	state = S.IDLE
	_timer = time * (0.7 if phase2 else 1.0)
	_step = 0
	_charge = 0.0
	_air_dash = 0.0
	_dash_t = 0.0


func _process_idle(delta: float) -> void:
	vel.x = move_toward(vel.x, 0.0, 900.0 * delta)
	_physics(delta)
	if grounded:
		_face_player()
		if _timer <= 0.0:
			_choose_pattern()


## Strafe toward the mirrored x of the player, tap-firing; copy jumps and dashes.
func _process_run_gun(delta: float) -> void:
	var dx := _mirror_x() - position.x
	if _dash_t > 0.0:
		_dash_t -= delta
		vel.x = _dash_dir * DASH
	elif absf(dx) > 3.0:
		vel.x = signf(dx) * WALK * _spd()
	else:
		vel.x = 0.0
	if grounded and _mirror_cd <= 0.0:
		if _player_jumped():
			vel.y = -JUMP
			_mirror_cd = 0.9
		elif _player_dashing():
			_dash_t = 0.3
			_dash_dir = signf(dx) if absf(dx) > 3.0 else -facing
			_mirror_cd = 0.9
	_physics(delta)
	_face_player()
	_shot_timer -= delta
	if _shots_left > 0 and _shot_timer <= 0.0:
		_fire_tap(Vector2(facing, 0.0))
		_shots_left -= 1
		_shot_timer = 0.3 if phase2 else 0.38
	if _timer <= 0.0 and grounded:
		_idle(0.4)


func _process_dash_jump(delta: float) -> void:
	match _step:
		0:  # crouch (telegraph)
			vel.x = 0.0
			_physics(delta)
			if _timer <= 0.0:
				_step = 1
				_timer = 0.32
		1:  # ground dash
			vel.x = _side * DASH * _spd()
			_physics(delta)
			if _timer <= 0.0 or absf(_player_x() - position.x) < 72.0 or wall == int(_side):
				vel.y = -JUMP  # dash jump: keeps the dash speed in the air
				_step = 2
		2:  # air
			if _air_dash > 0.0:
				_air_dash -= delta
				vel.y = 0.0
				_physics(delta, false)
			else:
				_physics(delta)
			if wall != 0 and not grounded and _bounces > 0:
				_bounces -= 1  # wall kick off the arena wall
				vel = Vector2(-wall * DASH * 0.7, -JUMP * 0.75)
				facing = -wall
				_air_dash = 0.0
				fx(position + Vector2(wall * W, 4.0), 6.0)
			if not _apex_done and vel.y >= -30.0:
				_apex_done = true
				_face_player()
				_fire_aimed(3 if phase2 else 1)
				var gap := _player_x() - position.x
				if phase2 and absf(gap) > 60.0:
					_air_dash = 0.22  # learned air dash
					vel = Vector2(signf(gap) * DASH, 0.0)
			if grounded and _apex_done:
				_idle(0.35)


func _process_wall_climb(delta: float) -> void:
	match _step:
		0:  # run to the wall
			vel.x = _side * DASH * _spd()
			facing = _side
			_physics(delta)
			if wall == int(_side):
				vel.y = -JUMP
				_step = 1
				_timer = 2.0
			elif _timer <= 0.0:
				_idle(0.3)
		1:  # wall kicks up the wall
			vel.x = (-_side if _kick_lock > 0.0 else _side) * WALL_KICK
			_physics(delta)
			if wall == int(_side) and _kick_lock <= 0.0:
				if _kicks_left > 0 and vel.y > -120.0:
					_kicks_left -= 1
					vel.y = -JUMP
					_kick_lock = WALL_KICK_LOCK
					fx(position + Vector2(_side * W, 6.0), 6.0)
				elif _kicks_left == 0 and vel.y >= 0.0:
					_step = 2
					_charge_total = 0.55 if phase2 else 0.75
					_timer = _charge_total
			if (grounded and _timer < 1.7) or _timer <= 0.0:
				_idle(0.3)
		2:  # cling and charge
			vel = Vector2(0.0, 22.0)
			facing = -_side
			_physics(delta, false)
			_charge = clampf(1.0 - _timer / _charge_total, 0.0, 1.0)
			if _timer <= 0.0:
				_fire_charge((player_pos() - _muzzle()).normalized())
				_charge = 0.0
				_step = 3
				vel = Vector2(-_side * 120.0, -150.0)
		3:  # leap off
			_physics(delta)
			if grounded:
				_idle(0.4)


func _process_charge(delta: float) -> void:
	vel.x = 0.0
	_physics(delta)
	_face_player()
	_charge = clampf(1.0 - _timer / _charge_total, 0.0, 1.0)
	if _timer <= 0.0:
		_fire_charge(Vector2(facing, 0.0))
		_idle(0.5)


func _process_rush(delta: float) -> void:
	match _step:
		0:  # plant + afterimage streak (telegraph)
			vel.x = 0.0
			_physics(delta)
			if _timer <= 0.0:
				_step = 1
				_timer = 2.0
		1:
			vel.x = _side * RUSH_SPEED
			_physics(delta)
			if wall == int(_side) or _timer <= 0.0:
				vel.x = 0.0
				_passes -= 1
				if _passes > 0:
					_side = -_side
					facing = _side
					_step = 0
					_timer = 0.35
				else:
					_idle(0.5)


# --- combat ------------------------------------------------------------------------

## LEARNING (GDD §5-3): same weapon 3 hits in a row -> adapted (x0.25, min 1)
## until another weapon lands a hit.
func _modify_damage(amount: int, weapon: String) -> int:
	if weapon == streak_weapon:
		streak += 1
	else:
		if resist_weapon != "":
			_break_fx = 0.45
		resist_weapon = ""
		streak_weapon = weapon
		streak = 1
	if resist_weapon != "" and weapon == resist_weapon:
		return maxi(1, floori(amount * RESIST_MULT))
	if streak >= LEARN_HITS:
		resist_weapon = weapon
		_adapt_fx = 0.6
	return amount


func _on_phase2() -> void:
	_release_fx = 0.8
	_fx_deferred(position, 20.0)
	_bag.erase(S.MIRROR_RUSH)
	_bag.push_front(S.MIRROR_RUSH)  # show the new move right away, then finish the cycle
	_idle(0.6)


func _on_stagger() -> void:
	pass  # no weakness


func _on_death() -> void:
	_death_t0 = t
	_charge = 0.0
	_trail.clear()


func _fire_tap(dir: Vector2) -> void:
	var s := BusterShot.new()
	s.velocity = dir.normalized() * TAP_SPEED
	s.damage = 2
	s.position = _muzzle()
	get_parent().add_child(s)
	_muzzle_fx = 0.12


func _fire_aimed(count: int) -> void:
	var base := (player_pos() - _muzzle()).angle()
	for i in count:
		var k := 0.0 if count == 1 else (float(i) / (count - 1) - 0.5) * 2.0
		var s := BusterShot.new()
		s.velocity = Vector2.from_angle(base + k * 0.22) * AIM_SPEED
		s.damage = 2
		s.position = _muzzle()
		get_parent().add_child(s)
	_muzzle_fx = 0.12


func _fire_charge(dir: Vector2) -> void:
	var angles := [0.0, -0.3, 0.3] if phase2 else [0.0]
	for i in angles.size():
		var s := BusterShot.new()
		s.big = true
		s.radius = 7.0 if i == 0 else 4.0
		s.damage = 4 if i == 0 else 2
		s.velocity = dir.normalized().rotated(angles[i]) * CHARGE_SPEED * (1.1 if phase2 else 1.0)
		s.position = _muzzle()
		get_parent().add_child(s)
	fx(_muzzle(), 9.0)
	_muzzle_fx = 0.2


# --- movement helpers ----------------------------------------------------------------

## Kinematic step with the player's gravity; sets `grounded` and `wall`.
func _physics(delta: float, gravity_on := true) -> void:
	if gravity_on:
		vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)
	position += vel * delta
	grounded = false
	wall = 0
	if position.y >= floor_y() - H:
		position.y = floor_y() - H
		vel.y = minf(vel.y, 0.0)
		grounded = true
	elif position.y <= arena.position.y + H:
		position.y = arena.position.y + H
		vel.y = maxf(vel.y, 0.0)
	if position.x <= arena.position.x + W:
		position.x = arena.position.x + W
		wall = -1
	elif position.x >= arena.end.x - W:
		position.x = arena.end.x - W
		wall = 1


func _clamp() -> void:
	position.x = clampf(position.x, arena.position.x + W, arena.end.x - W)
	position.y = clampf(position.y, arena.position.y + H, floor_y() - H)


func _spd() -> float:
	return 1.2 if phase2 else 1.0


func _player_x() -> float:
	return player_pos().x


func _face_player() -> void:
	var dx := _player_x() - position.x
	if absf(dx) > 2.0:
		facing = signf(dx)


## Where the mirror wants to stand: the player's x reflected around the room
## centre, kept on its own side of the player and at least KEEP_AWAY from it.
func _mirror_x() -> float:
	var px := _player_x()
	var lo := arena.position.x + W + 8.0
	var hi := arena.end.x - W - 8.0
	var side := signf(position.x - px)
	if side == 0.0:
		side = -facing
	var dist := maxf(absf(arena.get_center().x * 2.0 - px - px), KEEP_AWAY)
	var target := px + side * dist
	if target < lo or target > hi:
		target = clampf(target, lo, hi)
	return target


func _player_jumped() -> bool:
	return player != null and is_instance_valid(player) and player.velocity.y < -200.0


func _player_dashing() -> bool:
	return player != null and is_instance_valid(player) and player.has_method("is_dashing") \
			and player.is_dashing()


func _muzzle() -> Vector2:
	return position + Vector2(MUZZLE.x * facing, MUZZLE.y)


func _fx_deferred(pos: Vector2, size: float) -> void:
	var e := Explosion.new()
	e.size = size
	e.position = pos
	get_parent().add_child.call_deferred(e)


func _is_dashing() -> bool:
	return (state == S.DASH_JUMP and _step == 1) or (state == S.MIRROR_RUSH and _step == 1) \
			or (state == S.WALL_CLIMB and _step == 0) or _air_dash > 0.0 or _dash_t > 0.0


func _tick_trail(delta: float) -> void:
	_trail_clock -= delta
	if _trail_clock > 0.0:
		return
	_trail_clock = 0.04
	var moving := vel.length() > 20.0
	if _is_dashing() or (phase2 and moving):
		_trail.push_front([position, facing])
		if _trail.size() > 5:
			_trail.pop_back()
	elif not _trail.is_empty():
		_trail.pop_back()


func _weapon_color(id: String) -> Color:
	if WeaponShot.INFO.has(id):
		return WeaponShot.INFO[id].color
	match id:
		"buster":
			return Color("f0b84a")
		"saber":
			return Color("e34f5b")
		"echo", "copy":
			return Color("5ad19a")
	return Color("d7edf3")


# --- drawing ------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	var alpha := 1.0
	if state == S.INTRO:
		alpha = clampf(1.0 - intro_time / maxf(_intro_total, 0.01), 0.0, 1.0)
		# materialize column
		var top := arena.position.y - position.y
		draw_rect(Rect2(-7.0 * (1.0 - alpha) - 3.0, top, 6.0 + 14.0 * (1.0 - alpha), H - top),
				Color(C_VISOR, 0.25 * (1.0 - alpha)))
	if _death_t0 >= 0.0 and int(t * 20.0) % 3 == 0:
		alpha = 0.4

	# Telegraphs behind the body.
	if state == S.MIRROR_RUSH and _step == 0 and int(t * 16.0) % 2 == 0:
		var end_x := (arena.end.x - W if _side > 0.0 else arena.position.x + W) - position.x
		for i in 3:
			var y := -6.0 + i * 6.0
			draw_line(Vector2(0, y), Vector2(end_x, y), Color(C_VISOR, 0.5 - i * 0.12), 1.0)
	if _release_fx > 0.0:
		var k := 1.0 - _release_fx / 0.8
		draw_arc(Vector2.ZERO, 8.0 + 30.0 * k, 0.0, TAU, 24, Color(C_VISOR, 1.0 - k), 2.0)
		draw_arc(Vector2.ZERO, 4.0 + 18.0 * k, 0.0, TAU, 24, Color(C_HOT, 1.0 - k), 1.0)

	# Eclipse corona: a soft violet glow behind the dark body, so it reads on the
	# dark arena background (a ring of light in phase 2).
	var corona := 0.16 + 0.06 * sin(t * 3.0)
	draw_circle(Vector2(0, -2), 16.0, Color(C_PLATE, corona * 0.45 * alpha))
	draw_circle(Vector2(0, -2), 11.0, Color(C_PLATE, corona * 0.6 * alpha))
	if phase2:
		draw_arc(Vector2(0, -2), 16.5, 0.0, TAU, 28, Color(C_VISOR, (0.3 + 0.2 * sin(t * 9.0)) * alpha), 1.0)

	# Afterimages.
	for i in _trail.size():
		var e: Array = _trail[i]
		_draw_body(e[0] - position, e[1], Color(C_VISOR if phase2 else C_TRIM, (0.35 - i * 0.06) * alpha))

	var flat := Color(0, 0, 0, 0)
	if white:
		flat = Color.WHITE
	_draw_body(Vector2.ZERO, facing, flat, alpha)

	_draw_charge()
	_draw_learning()
	if grounded and _is_dashing() and int(t * 20.0) % 2 == 0:
		for i in 3:
			draw_circle(Vector2(-facing * (9.0 + i * 4.0), H - 2.0 - i), 1.5 - i * 0.3, Color(C_TRIM, 0.5 - i * 0.15))


## The mirror hunter: dark violet armor, angular helmet with a forward crest and
## swept back fins, one visor slit, an eclipsed core on the chest, buster arm.
## Design space: feet at y = 0, facing right (x > 0 is forward).
func _draw_body(off: Vector2, f: float, flat := Color(0, 0, 0, 0), alpha := 1.0) -> void:
	_doff = off
	_df = f
	_flat = flat
	var a := func(c: Color) -> Color: return Color(c, c.a * alpha)
	var dashing := _is_dashing()
	var crouch := (state == S.DASH_JUMP and _step == 0) or (state == S.MIRROR_RUSH and _step == 0)
	_lean = 2.0 if dashing else 0.0
	_uy = 3.0 if crouch or (dashing and grounded) else 0.0
	var cling := state == S.WALL_CLIMB and _step == 2
	var moving := grounded and absf(vel.x) > 1.0 and not dashing

	# Legs.
	var front := 2.0
	var back := -3.0
	var lf := 0.0
	var lb := 0.0
	if dashing and grounded:
		front = 5.0
		back = -6.0
		lb = 2.0
	elif not grounded:
		front = 3.0
		back = -2.0
		lf = 4.0
		lb = 1.0
	elif moving:
		var s := sin(t * 14.0)
		front = 1.0 + s * 3.5
		back = -2.0 - s * 3.5
		lf = maxf(0.0, -s) * 2.0
		lb = maxf(0.0, s) * 2.0
	_leg(back, lb, a.call(C_ARMOR))
	_leg(front, lf, a.call(C_PLATE.darkened(0.15)))

	# Back pauldron, chest with a darker V plate, hips.
	_poly_up([Vector2(-5, -21), Vector2(-12, -25), Vector2(-9, -17)], a.call(C_PLATE.darkened(0.2)))
	_poly_up([Vector2(-4, -11), Vector2(4, -11), Vector2(7, -18), Vector2(5, -22), Vector2(-5, -22),
			Vector2(-7, -18)], a.call(C_ARMOR))
	_poly_up([Vector2(-5, -22), Vector2(5, -22), Vector2(2, -14), Vector2(-2, -14)], a.call(C_PLATE.darkened(0.1)))
	_box_up(-5, -12, 10, 2, a.call(C_FRAME))
	# Eclipsed core: a dark disc over a bright corona.
	var core_c := C_HOT if phase2 else C_TRIM
	_circle_up(0.0, -18.5, 2.6, a.call(core_c))
	_circle_up(0.7, -18.7, 2.0, a.call(C_FRAME))

	# Head: back fins, helmet, forward crest, single visor slit, chin guard.
	_poly_up([Vector2(-3, -28), Vector2(-13, -31), Vector2(-6, -24)], a.call(C_PLATE))
	_poly_up([Vector2(-2, -30), Vector2(-10, -35), Vector2(-5, -28)], a.call(C_PLATE.darkened(0.25)))
	_poly_up([Vector2(-5, -21), Vector2(5, -21), Vector2(7, -25), Vector2(5, -30), Vector2(-2, -32),
			Vector2(-6, -27)], a.call(C_PLATE))
	_poly_up([Vector2(-5, -21), Vector2(5, -21), Vector2(6, -23), Vector2(-6, -24)], a.call(C_ARMOR))
	_poly_up([Vector2(-2, -32), Vector2(5, -30), Vector2(4, -29), Vector2(-2, -31)], a.call(C_TRIM))
	_poly_up([Vector2(0, -31), Vector2(9, -35), Vector2(4, -29)], a.call(C_TRIM))
	var visor := C_HOT if phase2 and int(t * 12.0) % 2 == 0 else C_VISOR
	_poly_up([Vector2(-1, -27), Vector2(8, -27.5), Vector2(7, -25), Vector2(-1, -25.5)], a.call(C_FRAME))
	_poly_up([Vector2(0, -26.8), Vector2(8, -27.2), Vector2(7.5, -25.8), Vector2(0, -26)], a.call(visor))
	_poly_up([Vector2(3, -22), Vector2(7, -24), Vector2(6, -21)], a.call(C_PLATE))

	# Front arm: buster forward while aiming, hand on the wall while clinging.
	if cling:
		_box_up(-10, -24, 3, 7, a.call(C_PLATE))
	var aiming := state in [S.RUN_GUN, S.CHARGE] or cling or _muzzle_fx > 0.0 \
			or (state == S.DASH_JUMP and _step == 2)
	if aiming:
		_box_up(2, -17, 9, 4, a.call(C_PLATE))
		_box_up(10, -18, 6, 6, a.call(C_FRAME))
		_box_up(15, -16.5, 1, 3, a.call(C_VISOR))
		if _muzzle_fx > 0.0:
			_circle_up(17.0, -15.0, 3.0, a.call(C_HOT))
		elif state == S.RUN_GUN and _shots_left > 0 and _shot_timer < 0.14 and int(t * 30.0) % 2 == 0:
			_circle_up(17.0, -15.0, 2.0, a.call(C_VISOR))  # glint before each shot
	else:
		_box_up(3, -18, 4, 7, a.call(C_PLATE))
		_box_up(3, -12, 4, 3, a.call(C_FRAME))


func _draw_charge() -> void:
	if _charge <= 0.0:
		return
	var m := _muzzle() - position
	var k := _charge
	var c := C_HOT if k > 0.85 and int(t * 20.0) % 2 == 0 else C_VISOR
	# Converging sparks, a growing orb and a body ring: big, readable telegraph.
	for i in 8:
		var ang := t * 9.0 + i * TAU / 8.0
		var r := 22.0 - 12.0 * fmod(t * 2.5 + i * 0.125, 1.0)
		var at := Vector2(cos(ang), sin(ang)) * r
		draw_line(at, at - at.normalized() * 4.0, Color(c, 0.8), 1.0)
	draw_circle(m, 2.0 + 6.0 * k, Color(C_VISOR, 0.35 + 0.3 * k))
	draw_circle(m, 1.0 + 3.0 * k, C_HOT)
	if k > 0.5:
		draw_arc(Vector2.ZERO, 15.0 + sin(t * 30.0) * 2.0, 0.0, TAU, 24, Color(c, k), 1.0)


func _draw_learning() -> void:
	if resist_weapon != "":
		var c := _weapon_color(resist_weapon)
		var pulse := 0.45 + 0.25 * sin(t * 8.0)
		var pts := PackedVector2Array()
		for i in 7:
			var ang := TAU * i / 6.0 + t * 0.8
			pts.append(Vector2(cos(ang), sin(ang)) * 18.0)
		draw_polyline(pts, Color(c, pulse), 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(-12, -25), "ADAPT", HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
				Color(c, 0.6 + 0.4 * sin(t * 10.0)))
	if _adapt_fx > 0.0:
		var k := 1.0 - _adapt_fx / 0.6
		draw_arc(Vector2.ZERO, 10.0 + 18.0 * k, 0.0, TAU, 6, Color(C_HOT, 1.0 - k), 2.0)
	if _break_fx > 0.0:
		var k := 1.0 - _break_fx / 0.45
		for i in 6:
			var ang := TAU * i / 6.0 + 0.4
			var at := Vector2(cos(ang), sin(ang)) * (18.0 + 14.0 * k)
			draw_line(at, at + Vector2(cos(ang + 1.2), sin(ang + 1.2)) * 4.0, Color(C_HOT, 1.0 - k), 1.0)


func _p(x: float, y: float) -> Vector2:
	return _doff + Vector2(x * _df, y + H)


func _up(x: float, y: float) -> Vector2:
	return _p(x + _lean, y + _uy)


func _col(c: Color) -> Color:
	return Color(_flat, _flat.a * c.a) if _flat.a > 0.0 else c


func _poly_up(points: Array, c: Color) -> void:
	var arr := PackedVector2Array()
	for q in points:
		arr.append(_up(q.x, q.y))
	draw_colored_polygon(arr, _col(c))


func _box_up(x: float, y: float, w: float, h: float, c: Color) -> void:
	var a := _up(x, y)
	var b := _up(x + w, y)
	draw_rect(Rect2(Vector2(minf(a.x, b.x), a.y), Vector2(absf(b.x - a.x), h)), _col(c))


func _circle_up(x: float, y: float, r: float, c: Color) -> void:
	draw_circle(_up(x, y), r, _col(c))


## Leg in design space (not affected by the upper-body crouch / lean).
func _leg(x: float, lift: float, c: Color) -> void:
	var shin := PackedVector2Array([_p(x - 2, -11 - lift), _p(x + 2, -11 - lift), _p(x + 2, -6 - lift),
			_p(x - 2, -6 - lift)])
	draw_colored_polygon(shin, _col(c))
	var boot := PackedVector2Array([_p(x - 3, -7 - lift), _p(x + 3, -7 - lift), _p(x + 6, -lift),
			_p(x - 3, -lift)])
	draw_colored_polygon(boot, _col(c.darkened(0.25)))
	if _flat.a <= 0.0:
		var fin := PackedVector2Array([_p(x - 2, -11 - lift), _p(x + 3, -10 - lift), _p(x - 1, -8 - lift)])
		draw_colored_polygon(fin, Color(C_PLATE, c.a))
