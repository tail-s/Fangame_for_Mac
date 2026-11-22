extends "res://scripts/enemies/boss_base.gd"
## GRAVITY ALBATROSS — orbital shipyard boss (GDD v0.2 §5). A long-winged dock
## robot with a gravity lens in its chest. Every attack is telegraphed:
##   SWOOP    climbs to an upper corner and flares its wings while a dotted line
##            shows the glide path, then sweeps across the room in a dipping arc
##            aimed at where the player stood. Jump over it at the low point or
##            stay under the high ends. Phase 2: faster, and it swoops back.
##   FEATHER  hovers at jump-shot height, raises its wings (tips glow) and fires
##            a fan of feather missiles at the player. Phase 2: two wider fans.
##   WELL     hangs over the middle, charges its lens (shrinking rings) and pulls
##            the player toward it (walk or dash out of it), then lets go with a
##            ring of debris. Phase 2: the pull ends in a dive-bomb on a floor
##            reticle that throws two shots along the ground.
## Weakness: REFRACTION BEAM — the refracted light breaks its lens lock: the boss
## tumbles for a moment (stagger, capped by boss_base's cooldown).

enum S { INTRO, IDLE, SWOOP_AIM, SWOOP, FEATHER, WELL, DIVE_AIM, DIVE, RISE, STAGGER }

## States that are attacks (tests count how many of these the fight visits).
const PATTERN_STATES := [S.SWOOP, S.FEATHER, S.WELL, S.DIVE]
const ACCENT := Color("8397f1")
# Body palette (flat regions; the Actors shader adds outline and edge light/shadow).
const C_BODY := Color("d7edf3")
const C_BELLY := Color("9fb8cc")
const C_WING := Color("1c375b")
const C_WING_LIGHT := Color("3a66a0")
const C_WING_DARK := Color("0d1a33")
const C_FAR := Color("2a3a5a")
const C_FAR_LIGHT := Color("41557e")
const C_TRIM := Color("00b8be")
const C_METAL := Color("8a9bb4")
const C_BEAK := Color("f0b84a")
const C_BEAK_DARK := Color("b27a2a")
const C_EYE := Color("e34f5b")
const C_SOCKET := Color("131c34")
const C_GLINT := Color("ffffff")
const MARGIN := 12.0

var state := S.INTRO
## Number of weakness staggers so far (for tests / debugging).
var staggers := 0
## True while the gravity well drags the player.
var pulling := false

var _timer := 0.0
var _step := 0
var _bag: Array = []
var _last_pattern := -1
var _home := Vector2.ZERO
var _prev_pos := Vector2.ZERO
var _idle_x := 0.0
var _swoop_from := Vector2.ZERO
var _swoop_to := Vector2.ZERO
var _swoop_low := 0.0
var _swoop_dip := 0.5
var _swoop_u := 0.0
var _swoop_back := false
var _volleys := 0
var _feather_x := 0.0
var _dive_x := 0.0
var _vy := 0.0
var _spin := 0.0
var _roar := 0.0


func _init() -> void:
	boss_name = "GRAVITY ALBATROSS"
	max_hp = 32
	weakness = "refraction_beam"
	contact_damage = 3
	hit_radius = 13.0


func _boss_ready() -> void:
	_home = position
	_prev_pos = position
	# First cycle is fixed (readable opener), later cycles are shuffled.
	_bag = [S.FEATHER, S.SWOOP, S.WELL]


func _boss_intro(_delta: float) -> void:
	position = _home + Vector2(0, sin(t * 3.0) * 4.0)
	_face_player()


func _on_active() -> void:
	_idle(0.4)


func _on_phase2() -> void:
	_roar = 0.6


func _on_stagger() -> void:
	staggers += 1
	pulling = false
	state = S.STAGGER
	_step = 0
	_timer = 0.9
	_spin = 0.0
	fx(position, 8.0)


func _on_death() -> void:
	pulling = false


# --- state machine -----------------------------------------------------------------

func _boss_process(delta: float) -> void:
	_prev_pos = position
	_timer -= delta
	_roar = maxf(_roar - delta, 0.0)
	match state:
		S.IDLE:
			var want := Vector2(_idle_x, _hover_y() + sin(t * 3.0) * 4.0)
			position = position.move_toward(want, 70.0 * delta)
			if _timer <= 0.0:
				_next_pattern()
		S.SWOOP_AIM:
			if _step == 0:
				if _travel(_swoop_from, _speed(260.0), delta):
					_plan_swoop(0.55)
			elif _timer <= 0.0:
				state = S.SWOOP
				_swoop_u = 0.0
		S.SWOOP:
			_swoop_u = minf(_swoop_u + delta / (0.95 if phase2 else 1.3), 1.0)
			position = _swoop_point(_swoop_u)
			if _swoop_u >= 1.0:
				if phase2 and not _swoop_back:
					_swoop_back = true
					var from := _swoop_to
					_swoop_to = _swoop_from
					_swoop_from = from
					state = S.SWOOP_AIM
					_plan_swoop(0.35)
				else:
					_idle(0.8)
		S.FEATHER:
			if _step == 0:
				if _travel(Vector2(_feather_x, _hover_y()), _speed(220.0), delta):
					_step = 1
					_timer = 0.4 if phase2 else 0.5
			elif _step == 1:
				if _timer <= 0.0:
					_feather_volley()
					_volleys -= 1
					if _volleys > 0:
						_timer = 0.5
					else:
						_step = 2
						_timer = 0.45
			elif _timer <= 0.0:
				_idle(0.8)
		S.WELL:
			if _step == 0:
				if _travel(Vector2(arena.get_center().x, floor_y() - 70.0), _speed(220.0), delta):
					_step = 1
					_timer = 0.6
			elif _step == 1:
				if _timer <= 0.0:
					_step = 2
					_timer = 2.5 if phase2 else 2.2
					pulling = true
			else:
				_pull(delta)
				if _timer <= 0.0:
					pulling = false
					if phase2:
						_start_dive()
					else:
						_burst()
						_idle(0.9)
		S.DIVE_AIM:
			position.x = move_toward(position.x, _dive_x, 300.0 * delta)
			position.y = move_toward(position.y, floor_y() - 124.0, 120.0 * delta)
			if _timer <= 0.0:
				state = S.DIVE
				_vy = 0.0
		S.DIVE:
			_vy = minf(_vy + 1500.0 * delta, 480.0)
			position.y += _vy * delta
			position.x = move_toward(position.x, _dive_x, 300.0 * delta)
			if position.y >= floor_y() - 16.0:
				position.y = floor_y() - 16.0
				_impact()
		S.RISE:
			if _step == 0:
				if _timer <= 0.0:
					_step = 1
			elif _travel(Vector2(position.x, _hover_y()), 150.0, delta):
				_idle(0.6)
		S.STAGGER:
			_spin += delta * 14.0
			position.y = minf(position.y + 35.0 * delta, floor_y() - 20.0)
			if _timer <= 0.0:
				_idle(0.45)
	clamp_to_arena(MARGIN)
	_update_facing()


func _next_pattern() -> void:
	if _bag.is_empty():
		_bag = [S.SWOOP, S.FEATHER, S.WELL]
		_bag.shuffle()
		if _bag[0] == _last_pattern:
			_bag.push_back(_bag.pop_front())
	var pattern: int = _bag.pop_front()
	_last_pattern = pattern
	_step = 0
	match pattern:
		S.SWOOP:
			var left := position.x < arena.get_center().x
			_swoop_from = Vector2(_side_x(left), _high_y())
			_swoop_to = Vector2(_side_x(not left), _high_y())
			_swoop_back = false
			state = S.SWOOP_AIM
		S.FEATHER:
			# Hover on the side away from the player, at jump-shot height.
			var player_left := player_pos().x < arena.get_center().x
			_feather_x = lerpf(arena.position.x, arena.end.x, 0.75 if player_left else 0.25)
			_volleys = 2 if phase2 else 1
			state = S.FEATHER
		S.WELL:
			state = S.WELL


func _idle(time: float) -> void:
	state = S.IDLE
	_step = 0
	pulling = false
	_timer = time * (0.65 if phase2 else 1.0)
	_idle_x = clampf(position.x, lerpf(arena.position.x, arena.end.x, 0.2),
			lerpf(arena.position.x, arena.end.x, 0.8))


# --- patterns -------------------------------------------------------------------------

## Locks the swoop path: the dip goes where the player is now.
func _plan_swoop(telegraph: float) -> void:
	_step = 1
	_timer = telegraph * (0.75 if phase2 else 1.0)
	var span := _swoop_to.x - _swoop_from.x
	_swoop_dip = clampf((player_pos().x - _swoop_from.x) / span, 0.2, 0.8)
	_swoop_low = clampf(player_pos().y, _high_y() + 48.0, floor_y() - 16.0)


func _swoop_point(u: float) -> Vector2:
	var k: float
	if u <= _swoop_dip:
		k = sin(PI * 0.5 * u / _swoop_dip)
	else:
		k = sin(PI * 0.5 * (1.0 - u) / (1.0 - _swoop_dip))
	return Vector2(lerpf(_swoop_from.x, _swoop_to.x, u), lerpf(_swoop_from.y, _swoop_low, k))


func _feather_volley() -> void:
	var muzzle := position + Vector2(facing * 8.0, 2.0)
	var aim := (player_pos() - muzzle).normalized()
	var angles := [-0.4, -0.2, 0.0, 0.2, 0.4] if phase2 else [-0.24, 0.0, 0.24]
	var speed := 145.0 if phase2 else 125.0
	for a in angles:
		shoot(muzzle, aim.rotated(a) * speed, 2)


func _pull(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	if not arena.grow(32.0).has_point(player.global_position):
		return
	var strength := 52.0 if phase2 else 40.0
	player.global_position.x = move_toward(player.global_position.x, position.x, strength * delta)


## Debris ring when the lens lets go. One shard falls straight down, so the spot
## the well dragged you to is not safe; stand between the 45° gaps instead.
func _burst() -> void:
	for i in 8:
		shoot(position, Vector2.RIGHT.rotated(TAU * i / 8.0) * 95.0, 2)


func _start_dive() -> void:
	state = S.DIVE_AIM
	_timer = 0.65
	_dive_x = clampf(player_pos().x, arena.position.x + 24.0, arena.end.x - 24.0)


func _impact() -> void:
	fx(position + Vector2(0, 10), 14.0)
	for d in [-1.0, 1.0]:
		shoot(Vector2(position.x + d * 10.0, floor_y() - 6.0), Vector2(d * 150.0, 0), 2)
	state = S.RISE
	_step = 0
	_timer = 0.5


# --- helpers ------------------------------------------------------------------------------

func _travel(target: Vector2, speed: float, delta: float) -> bool:
	position = position.move_toward(target, speed * delta)
	return position.distance_to(target) < 1.0


func _speed(base: float) -> float:
	return base * (1.25 if phase2 else 1.0)


func _hover_y() -> float:
	return floor_y() - 62.0


func _high_y() -> float:
	return arena.position.y + 28.0


func _side_x(left: bool) -> float:
	return arena.position.x + 32.0 if left else arena.end.x - 32.0


func _face_player() -> void:
	var dx := player_pos().x - position.x
	if absf(dx) > 2.0:
		facing = signf(dx)


func _update_facing() -> void:
	if state == S.SWOOP or (state == S.SWOOP_AIM and _step == 1):
		facing = signf(_swoop_to.x - _swoop_from.x)
	elif state in [S.SWOOP_AIM, S.DIVE_AIM, S.DIVE, S.RISE]:
		var dx := position.x - _prev_pos.x
		if absf(dx) > 0.3:
			facing = signf(dx)
	elif state != S.STAGGER:
		_face_player()


# --- drawing ------------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	_draw_telegraphs()
	var rot := 0.0
	var off := Vector2.ZERO
	var wing := 0.35 + 0.6 * sin(t * 9.0)
	var wing_len := 26.0
	var dying := _dying >= 0.0
	if state == S.STAGGER or dying:
		rot = sin(_spin + t * 9.0) * 0.6
		wing = 0.2 + sin(t * 20.0) * 0.8
	elif state == S.SWOOP:
		var v := position - _prev_pos
		rot = clampf(atan2(v.y, maxf(absf(v.x), 0.01)), -0.6, 0.6) * facing
		wing = 0.12
	elif state == S.SWOOP_AIM and _step == 1:
		wing = 1.25 + sin(t * 40.0) * 0.05
		off = Vector2(sin(t * 53.0), cos(t * 47.0))
	elif state == S.FEATHER and _step == 1:
		wing = 1.0
	elif state == S.WELL and _step > 0:
		wing = 0.75 + 0.15 * sin(t * 5.0)
	elif state == S.DIVE or (state == S.DIVE_AIM and _timer < 0.3):
		rot = PI * 0.5 * facing
		wing = -0.1
		wing_len = 17.0
	elif state == S.RISE and _step == 0:
		wing = -0.2
	draw_set_transform(off, rot, Vector2(facing, 1.0))
	var c := func(col: Color) -> Color: return Color.WHITE if white else col

	# far wing (behind the body) and tail fan
	_wing(Vector2(-1, -4), wing + 0.25, wing_len * 0.9, false, white)
	_poly([Vector2(-12, -2), Vector2(-21, -7), Vector2(-21, -3), Vector2(-12, 0)], c.call(C_WING_LIGHT))
	_poly([Vector2(-12, 0), Vector2(-21, -3), Vector2(-19, 1), Vector2(-21, 5), Vector2(-12, 3)],
			c.call(C_WING))
	_poly([Vector2(-17, 1), Vector2(-21, 5), Vector2(-17, 3)], c.call(C_WING_DARK))
	# hover thruster pod + flicker
	if not white:
		var flame := 4.0 + sin(t * 40.0) * 1.5
		draw_colored_polygon(PackedVector2Array([Vector2(-10, 6), Vector2(-7.5, 6 + flame),
				Vector2(-5, 6)]), Color("f0b84a", 0.85))
	draw_rect(Rect2(-11, 2, 7, 4), c.call(C_METAL))
	draw_rect(Rect2(-10, 5, 5, 1), c.call(C_WING_DARK))
	# talons
	for lx in [-3.0, 1.0]:
		draw_line(Vector2(lx, 5), Vector2(lx + 2.0, 8), c.call(C_WING), 2.0)
		draw_rect(Rect2(lx + 0.5, 8, 4, 2), c.call(C_METAL))
	# fuselage: pale side, navy back plate, shaded belly, cyan trim
	_poly([Vector2(-14, 0), Vector2(-9, -5), Vector2(4, -6), Vector2(10, -4), Vector2(12, 0),
			Vector2(10, 3), Vector2(2, 6), Vector2(-8, 5)], c.call(C_BODY))
	_poly([Vector2(-14, 0), Vector2(-9, -5), Vector2(4, -6), Vector2(8, -5), Vector2(3, -4),
			Vector2(-7, -3)], c.call(C_WING))
	_poly([Vector2(-11, 3), Vector2(-3, 4), Vector2(9, 2), Vector2(10, 3), Vector2(2, 6), Vector2(-8, 5)],
			c.call(C_BELLY))
	draw_line(Vector2(-10, 3), Vector2(-3, 3.5), c.call(C_TRIM), 1.0)
	# head: pale helmet, visor in a dark socket, hooked two-tone beak
	draw_circle(Vector2(11, -4), 4.5, c.call(C_BODY))
	draw_rect(Rect2(11, -7, 5, 3), c.call(C_SOCKET))
	draw_rect(Rect2(12, -6, 3, 2), c.call(C_EYE))
	draw_rect(Rect2(12, -6, 1, 1), c.call(C_GLINT))
	_poly([Vector2(14, -5), Vector2(21, -4), Vector2(23, -3), Vector2(22, -1), Vector2(14, -1)],
			c.call(C_BEAK))
	_poly([Vector2(14, -2), Vector2(21, -2), Vector2(19, 0), Vector2(14, 0)], c.call(C_BEAK_DARK))
	draw_rect(Rect2(21, -3, 2, 3), c.call(C_BEAK_DARK))
	# gravity lens in a navy housing
	var lens_r := 3.5
	var lens_core := 1.4
	if state == S.WELL and _step > 0:
		lens_r = 4.0 + sin(t * 18.0) * 0.8
		if _step == 2 and _timer < 0.45:
			# about to let go: the lens flares white
			lens_r = 5.5
			lens_core = 3.5
	draw_circle(Vector2(4, 1), lens_r + 1.5, c.call(C_WING_DARK))
	draw_circle(Vector2(4, 1), lens_r, c.call(ACCENT))
	draw_circle(Vector2(4, 1), lens_core, c.call(C_BODY))
	draw_rect(Rect2(2, -1, 1, 1), c.call(C_GLINT))
	# near wing (in front)
	var tip := _wing(Vector2(0, -2), wing, wing_len, true, white)
	if not white and state == S.FEATHER and _step == 1:
		var glow := 0.6 + 0.4 * sin(t * 30.0)
		draw_circle(tip, 2.5, Color("e34f5b", glow))
		draw_circle(tip + Vector2(4, 3), 1.8, Color("f0b84a", glow))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _poly(pts: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), col)


## A long wing from `root`, swept back and raised by `angle`: one navy blade with
## a feathered trailing edge, a lighter inner (covert) section and a trim line
## along the leading edge. Returns the tip.
func _wing(root: Vector2, angle: float, length: float, near: bool, white: bool) -> Vector2:
	var d := Vector2(-cos(angle), -sin(angle))
	var n := Vector2(-d.y, d.x)
	var p := func(u: float, v: float) -> Vector2: return root + d * (u * length) + n * v
	var c := func(col: Color) -> Color: return Color.WHITE if white else col
	var tip := root + d * length
	_poly([p.call(0.0, 3.0), p.call(0.42, 4.5), tip, p.call(0.88, -1.5), p.call(0.82, -4.0),
			p.call(0.72, -2.0), p.call(0.64, -4.5), p.call(0.54, -2.5), p.call(0.46, -4.5),
			p.call(0.36, -3.0), p.call(0.0, -2.5)], c.call(C_WING if near else C_FAR))
	_poly([p.call(0.0, 3.0), p.call(0.34, 4.3), p.call(0.38, -3.0), p.call(0.0, -2.5)],
			c.call(C_WING_LIGHT if near else C_FAR_LIGHT))
	var trim: Color = c.call(C_TRIM if near else C_FAR_LIGHT)
	draw_line(p.call(0.0, 3.0), p.call(0.42, 4.5), trim, 1.0)
	draw_line(p.call(0.42, 4.5), tip, trim, 1.0)
	if near:
		draw_rect(Rect2(root.x - 1.5, root.y - 1.5, 3, 3), c.call(C_METAL))
	return tip


## Path / reticle / lens rings, in arena-aligned local space (no flip).
func _draw_telegraphs() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _dying >= 0.0:
		return
	match state:
		S.SWOOP_AIM:
			if _step == 1:
				for i in 22:
					var p := _swoop_point(i / 21.0) - position
					var pulse := 0.5 + 0.5 * sin(t * 20.0 - i * 0.6)
					draw_circle(p, 2.0 + pulse * 0.6, Color(ACCENT.lightened(0.35), 0.5 + 0.4 * pulse))
		S.WELL:
			if _step > 0:
				var power := 1.0 if _step == 2 else 0.45
				for i in 3:
					var r := 64.0 - fmod(t * 46.0 + i * 21.0, 64.0)
					draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(ACCENT, power * 0.8 * r / 64.0), 1.5)
				if _step == 2:
					var to := player_pos() - position
					var dash := 0.0
					while dash < to.length() - 6.0:
						var a := to.normalized() * dash
						draw_line(a, a + to.normalized() * 4.0, Color(ACCENT, 0.3), 1.0)
						dash += 10.0
		S.DIVE_AIM, S.DIVE:
			var mark := Vector2(_dive_x, floor_y() - 3.0) - position
			var blink := 0.5 + 0.5 * sin(t * 24.0)
			var c := Color("e34f5b", 0.45 + 0.45 * blink)
			draw_arc(mark, 9.0, 0.0, TAU, 24, c, 1.5)
			draw_line(mark + Vector2(-13, 0), mark + Vector2(13, 0), c, 1.0)
			draw_line(mark + Vector2(0, -13), mark + Vector2(0, 2), c, 1.0)
			var y := 16.0
			while y < mark.y - 14.0:
				draw_line(Vector2(mark.x, y), Vector2(mark.x, y + 4.0), Color("e34f5b", 0.35), 1.0)
				y += 10.0
	if _roar > 0.0:
		var k := 1.0 - _roar / 0.6
		draw_arc(Vector2.ZERO, 14.0 + k * 40.0, 0.0, TAU, 40, Color(ACCENT, 1.0 - k), 2.0)
