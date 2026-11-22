extends "res://scripts/enemies/boss_base.gd"
## TERRA PANGOLIN — armoured mining pangolin of the underground maglev line
## (GDD v0.2 §5). Weakness: Freeze Lance (it freezes the drill gear and the
## scale joints). Moves kinematically and always stays inside `arena`.
##
## Patterns come from a shuffled bag, so every one shows up before any repeats:
##   roll      curls up (spinning amber ring) and rolls the arena rim: floor toward
##             the player -> far wall -> ceiling -> near wall. Phase 2: faster, and
##             it stops above the player (red ring, shake) and drops, sending two
##             floor shards.
##   burrow    digs in; a dirt mound follows the player, locks (red cracks and a red
##             column) and it erupts there, throwing debris. Phase 2: erupts twice.
##   fling     rears up with its scales flared and throws a fan of scale plates
##             (3, phase 2: 5).
##   rockfall  raises its tail and slams; dust marks lanes on the ceiling and rocks
##             fall there (the player's lane always among them, other lanes stay
##             open). Phase 2: a second wave into the lanes the first left open,
##             one lane always safe.
## While curled, the scale armour deflects everything except Freeze Lance, and
## underground it cannot be hit. Every other state takes buster damage.
## A Freeze Lance stagger (base class cooldown) freezes the joints: it falls off
## any wall / ceiling, uncurls, thaws for STAGGER_TIME and drops the pattern.

enum S { INTRO, IDLE, CURL, ROLL, CEIL_HOLD, DROP, UNCURL, DIG, UNDER, WARN, ERUPT,
		REAR, TAIL_UP, ROCK_WAIT, RECOVER, STAGGER_FALL, STAGGER }

const PATTERNS := ["roll", "burrow", "fling", "rockfall"]
## Body centre height above the floor (standing) and ball radius (curled).
const HALF := 12.0
const GRAVITY := 1000.0
const ROLL_SPEED := 230.0
const STAGGER_TIME := 1.0
const LANES := 7

const C_NAVY := Color("101b36")
const C_BLUE := Color("1c375b")
const C_CYAN := Color("00b8be")
const C_RED := Color("e34f5b")
const C_AMBER := Color("f0b84a")
const C_PALE := Color("d7edf3")
const C_SCALE := Color("c07a3e")  # accent: bronze ore-plated scales
const C_SCALE_DARK := Color("6e4325")
const C_DIRT := Color("7a5a3a")
const C_FROST := Color("92dafa")
# Sprite shading tones. Neighbouring scales alternate between tones that differ
# clearly (pixel_shade draws a seam between them); tones inside one plate step
# below the edge threshold so they read as smooth shading.
const C_SCALE_HI := Color("e0a35a")
const C_SCALE_MID := Color("9a5c2c")
const C_STEEL := Color("2b5888")
const C_STEEL_HI := Color("3a6ea0")
const C_GLINT := Color("fff2c2")
const C_DIRT_DARK := Color("553d26")
const C_DIRT_HI := Color("a07c52")

var state := S.INTRO
## Current (or last) pattern name; tests read it.
var pattern := ""
var roll_dir := 1.0
var stagger_count := 0

var _timer := 0.0
var _phase_time := 1.0  # length of the current telegraph (drawing)
var _bag: Array = []
var _leg := 0
var _ceil_run := 0.0
var _vy := 0.0
var _spin := 0.0
var _curl := 1.0  # 0 standing .. 1 ball
var _sink := 0.0  # 0 .. 1 while digging in
var _frost := 0.0
var _erupts_left := 0
## Pending ceiling rocks: {"x": world x, "t": seconds until it falls}.
var _rocks: Array = []


## Scale plates, rocks and debris: an enemy shot with optional gravity and its own look.
class Chunk extends "res://scripts/combat/enemy_shot.gd":
	const Puff = preload("res://scripts/fx/explosion.gd")

	var kind := "rock"  # rock | plate | shard
	var fall_accel := 0.0
	var radius := 4.0
	var _spin := 0.0

	func _ready() -> void:
		super._ready()
		for c in get_children():
			if c is CollisionShape2D:
				c.shape.radius = radius

	func _physics_process(delta: float) -> void:
		velocity.y += fall_accel * delta
		_spin += delta * (14.0 if kind == "plate" else 7.0)
		super._physics_process(delta)

	func hit() -> void:
		if is_queued_for_deletion():
			return
		if kind != "plate":
			var e := Puff.new()
			e.size = 6.0
			e.position = position
			get_parent().add_child.call_deferred(e)
		super.hit()

	func _draw() -> void:
		var r := radius + 1.0
		match kind:
			"plate":
				var pts := PackedVector2Array()
				for i in 4:
					var a := _spin + i * PI / 2.0
					pts.append(Vector2.from_angle(a) * (r + 1.5 if i % 2 == 0 else r * 0.55))
				draw_colored_polygon(pts, Color("c07a3e"))
				draw_line(pts[0], pts[2], Color("f0b84a"), 1.0)
			_:
				var pts := PackedVector2Array()
				for i in 6:
					var a := _spin + i * TAU / 6.0
					pts.append(Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.75))
				draw_colored_polygon(pts, Color("7a5a3a"))
				draw_circle(Vector2(-1, -1), r * 0.35, Color("e34f5b"))


func _init() -> void:
	boss_name = "TERRA PANGOLIN"
	max_hp = 32
	weakness = "freeze_lance"
	contact_damage = 3
	hit_radius = 13.0
	intro_time = 1.3


func _boss_ready() -> void:
	state = S.INTRO
	_curl = 1.0


## Curled up, it drops from the spawn marker and unrolls once it lands.
func _boss_intro(delta: float) -> void:
	var ground := floor_y() - HALF
	if position.y < ground:
		_vy = minf(_vy + GRAVITY * delta, 480.0)
		position.y = minf(position.y + _vy * delta, ground)
		_spin += delta * 12.0
		if position.y >= ground:
			fx(position + Vector2(0, HALF), 12.0)
	else:
		_curl = move_toward(_curl, 0.0, delta * 2.5)
	_face_player()
	clamp_to_arena(1.0)


func _on_active() -> void:
	_curl = 0.0
	_idle(0.5)


# --- public (tests / main) -------------------------------------------------------

func start_pattern(id: String) -> void:
	pattern = id
	collision_layer = Layers.ENEMY
	_face_player()
	match id:
		"roll":
			var dx := player_pos().x - position.x
			roll_dir = signf(dx) if absf(dx) > 1.0 else facing
			_leg = 0
			_set_state(S.CURL, 0.45 if phase2 else 0.6)
		"burrow":
			_erupts_left = 2 if phase2 else 1
			_set_state(S.DIG, 0.45 if phase2 else 0.55)
		"fling":
			_set_state(S.REAR, 0.45 if phase2 else 0.6)
		"rockfall":
			_set_state(S.TAIL_UP, 0.4 if phase2 else 0.5)


## Scale armour is closed (only the weakness gets through).
func is_armored() -> bool:
	return _curl >= 0.6 and state in [S.CURL, S.ROLL, S.CEIL_HOLD, S.DROP]


func is_underground() -> bool:
	return state in [S.UNDER, S.WARN]


func is_vulnerable() -> bool:
	return active and not is_armored() and not is_underground()


# --- fight -------------------------------------------------------------------------

func _boss_process(delta: float) -> void:
	_timer -= delta
	_frost = maxf(_frost - delta, 0.0)
	match state:
		S.IDLE:
			_curl = move_toward(_curl, 0.0, delta * 4.0)
			_face_player()
			if _timer <= 0.0:
				_next_pattern()
		S.CURL:
			_curl = move_toward(_curl, 1.0, delta / 0.35)
			_spin += delta * lerpf(2.0, 20.0, _curl) * roll_dir
			if _timer <= 0.0:
				_curl = 1.0
				state = S.ROLL
		S.ROLL:
			_roll(delta)
		S.CEIL_HOLD:
			_spin += delta * 24.0 * roll_dir
			if _timer <= 0.0:
				_vy = 0.0
				state = S.DROP
		S.DROP:
			_vy = minf(_vy + GRAVITY * delta, 520.0)
			position.y += _vy * delta
			_spin += delta * 14.0
			if position.y >= floor_y() - HALF:
				position.y = floor_y() - HALF
				_floor_shards()
				_set_state(S.UNCURL, 0.35)
		S.UNCURL:
			_curl = move_toward(_curl, 0.0, delta / 0.3)
			if _timer <= 0.0:
				_idle(0.7)
		S.DIG:
			_sink = move_toward(_sink, 1.0, delta / maxf(_phase_time, 0.1))
			if _timer <= 0.0:
				_go_under()
		S.UNDER:
			var target := clampf(player_pos().x, arena.position.x + 20.0, arena.end.x - 20.0)
			position.x = move_toward(position.x, target, _speed(170.0) * delta)
			if _timer <= 0.0:
				_set_state(S.WARN, 0.42 if phase2 else 0.55)
		S.WARN:
			if _timer <= 0.0:
				_erupt()
		S.ERUPT:
			_vy += GRAVITY * delta
			position.y += _vy * delta
			_sink = move_toward(_sink, 0.0, delta * 5.0)
			if _vy > 0.0 and position.y >= floor_y() - HALF:
				position.y = floor_y() - HALF
				fx(position + Vector2(0, HALF), 9.0)
				if _erupts_left > 0:
					_set_state(S.DIG, 0.3)
				else:
					_recover(0.55)
		S.REAR:
			_face_player()
			if _timer <= 0.0:
				_fling()
				_recover(0.55)
		S.TAIL_UP:
			if _timer <= 0.0:
				_slam()
		S.ROCK_WAIT:
			_tick_rocks(delta)
			if _rocks.is_empty() and _timer <= 0.0:
				_recover(0.5)
		S.RECOVER:
			_curl = move_toward(_curl, 0.0, delta * 4.0)
			if _timer <= 0.0:
				_idle(0.7)
		S.STAGGER_FALL:
			_vy = minf(_vy + GRAVITY * delta, 520.0)
			position.y = minf(position.y + _vy * delta, floor_y() - HALF)
			_curl = move_toward(_curl, 0.0, delta * 5.0)
			if position.y >= floor_y() - HALF:
				fx(position + Vector2(0, HALF), 10.0)
				_set_state(S.STAGGER, STAGGER_TIME)
		S.STAGGER:
			_curl = move_toward(_curl, 0.0, delta * 5.0)
			if _timer <= 0.0:
				_idle(0.35)
	clamp_to_arena(1.0)


func _next_pattern() -> void:
	if _bag.is_empty():
		_bag = _shuffled(PATTERNS.duplicate())
		if _bag[0] == pattern:
			_bag.push_back(_bag.pop_front())
	start_pattern(_bag.pop_front())


func _roll(delta: float) -> void:
	var sp := _speed(ROLL_SPEED)
	_spin += sp * delta / HALF * roll_dir
	var left := arena.position.x + HALF
	var right := arena.end.x - HALF
	match _leg:
		0:  # floor, toward the player
			position.x += roll_dir * sp * delta
			if position.x <= left or position.x >= right:
				position.x = clampf(position.x, left, right)
				_leg = 1
		1:  # up the far wall
			position.y -= sp * delta
			if position.y <= arena.position.y + HALF:
				position.y = arena.position.y + HALF
				_leg = 2
				_ceil_run = 0.0
		2:  # back across the ceiling
			position.x -= roll_dir * sp * delta
			_ceil_run += sp * delta
			if phase2 and _ceil_run > 40.0 and absf(position.x - player_pos().x) < 10.0:
				_set_state(S.CEIL_HOLD, 0.4)
				return
			if position.x <= left or position.x >= right:
				position.x = clampf(position.x, left, right)
				_leg = 3
		3:  # down the near wall, then uncurl
			position.y += sp * delta
			if position.y >= floor_y() - HALF:
				position.y = floor_y() - HALF
				_set_state(S.UNCURL, 0.35)


func _go_under() -> void:
	state = S.UNDER
	collision_layer = 0
	position.y = floor_y() - 2.0
	_sink = 1.0
	var first := _erupts_left == (2 if phase2 else 1)
	_timer = (0.8 if phase2 else 1.0) if first else 0.55
	fx(position, 9.0)


func _erupt() -> void:
	_erupts_left -= 1
	collision_layer = Layers.ENEMY
	state = S.ERUPT
	_vy = -430.0
	fx(position, 12.0)
	var spread := [-1.0, 1.0] if not phase2 else [-1.0, -0.45, 0.45, 1.0]
	for d in spread:
		_chunk("rock", Vector2(position.x, floor_y() - 8.0), Vector2(d * 75.0, -290.0), 700.0)


func _fling() -> void:
	var n := 5 if phase2 else 3
	var step := deg_to_rad(15.0 if phase2 else 18.0)
	var origin := position + Vector2(facing * 4.0, -16.0)
	var aim := (player_pos() - origin).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(facing, 0)
	var speed := 175.0 if phase2 else 150.0
	for i in n:
		var dir := aim.rotated((i - (n - 1) / 2.0) * step)
		_chunk("plate", origin, dir * speed)
	fx(origin, 8.0)


## Tail slam: marks rock lanes on the ceiling (they fall after a short warning).
func _slam() -> void:
	fx(position + Vector2(-facing * 18.0, HALF - 2.0), 12.0)
	var lane_w := arena.size.x / LANES
	var mine := clampi(int((player_pos().x - arena.position.x) / lane_w), 0, LANES - 1)
	var order := []
	for i in LANES:
		if i != mine:
			order.append(i)
	order = _shuffled(order)
	order.push_front(mine)
	_rocks.clear()
	for i in 4:
		_add_rock(order[i], lane_w, 0.75)
	if phase2:
		# Second wave into two of the three lanes the first left open.
		for i in [4, 5]:
			_add_rock(order[i], lane_w, 1.3)
	_set_state(S.ROCK_WAIT, 0.2)


func _add_rock(lane: int, lane_w: float, delay: float) -> void:
	var x := arena.position.x + (lane + 0.5) * lane_w + _rng.randf_range(-6.0, 6.0)
	_rocks.append({"x": x, "t": delay})


func _tick_rocks(delta: float) -> void:
	var waiting := []
	for r in _rocks:
		r.t -= delta
		if r.t <= 0.0:
			_chunk("rock", Vector2(r.x, arena.position.y + 7.0), Vector2(0, 60.0), 650.0, 5.0)
		else:
			waiting.append(r)
	_rocks = waiting


func _floor_shards() -> void:
	fx(position + Vector2(0, HALF), 14.0)
	for d in [-1.0, 1.0]:
		_chunk("shard", Vector2(position.x + d * 10.0, floor_y() - 5.0), Vector2(d * 170.0, 0))


func _chunk(kind: String, pos: Vector2, vel: Vector2, accel := 0.0, radius := 4.0):
	var c := Chunk.new()
	c.kind = kind
	c.velocity = vel
	c.fall_accel = accel
	c.radius = radius
	c.damage = 2
	c.position = pos
	get_parent().add_child(c)
	return c


## Fisher-Yates with the boss RNG.
func _shuffled(items: Array) -> Array:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
	return items


func _set_state(s: S, time: float) -> void:
	state = s
	_timer = time
	_phase_time = time


func _idle(time: float) -> void:
	_set_state(S.IDLE, time * (0.65 if phase2 else 1.0))


func _recover(time: float) -> void:
	_set_state(S.RECOVER, time * (0.75 if phase2 else 1.0))


func _speed(base: float) -> float:
	return base * (1.3 if phase2 else 1.0)


func _face_player() -> void:
	var dx := player_pos().x - position.x
	if absf(dx) > 2.0:
		facing = signf(dx)


# --- base hooks ------------------------------------------------------------------------

## Freeze Lance: joints freeze. Falls off walls / ceiling, uncurls, short thaw.
func _on_stagger() -> void:
	stagger_count += 1
	_rocks.clear()
	_erupts_left = 0
	_sink = 0.0
	_vy = 0.0
	_frost = STAGGER_TIME + 0.4
	if collision_layer != Layers.ENEMY:
		set_deferred("collision_layer", Layers.ENEMY)
	if is_underground():
		position.y = floor_y() - HALF
	if position.y < floor_y() - HALF - 1.0:
		_set_state(S.STAGGER_FALL, 0.0)
	else:
		position.y = floor_y() - HALF
		_set_state(S.STAGGER, STAGGER_TIME)


func _on_phase2() -> void:
	_flash = 0.3


func _modify_damage(amount: int, weapon: String) -> int:
	if weapon == weakness:
		return amount
	if is_underground():
		return 0
	if is_armored():
		fx.call_deferred(position + Vector2(_rng.randf_range(-6, 6), -8.0), 5.0)
		return 0
	return amount


func _on_death() -> void:
	_rocks.clear()
	_frost = 0.0


# --- drawing -----------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	_draw_rock_marks()
	if is_underground():
		_draw_mound()
		return
	if _curl >= 0.5:
		_draw_ball(white)
	else:
		_draw_body(white)


func _col(c: Color, white: bool) -> Color:
	if white:
		return Color.WHITE
	if _frost > 0.0:
		return c.lerp(C_FROST, 0.55)
	return c


func _fill(pts: Array, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), c)


## Curled up: two rings of scales spinning around the hub. Each scale is toned by the
## way it faces right now (lit from above), so the ball keeps its light while it rolls.
func _draw_ball(white: bool) -> void:
	var r := HALF
	draw_circle(Vector2.ZERO, r, _col(C_SCALE_DARK, white))
	_scale_ring(8, 6.0, r + 0.6, 0.0, white)
	# drill-gear hub: steel disc with spinning bolts around the core
	draw_circle(Vector2.ZERO, 5.5, _col(C_STEEL, white))
	draw_rect(Rect2(-4, -5, 6, 1), _col(C_STEEL_HI, white))
	for i in 4:
		var b := (Vector2.from_angle(_spin + i * PI / 2.0) * 4.0).round()
		draw_rect(Rect2(b, Vector2.ONE), _col(C_NAVY, white))
	draw_rect(Rect2(-2, -2, 4, 4), C_RED if phase2 else C_CYAN)
	draw_rect(Rect2(-2, -2, 2, 1), _col(C_GLINT, white))
	# fixed specular glint on the upper left (does not spin)
	draw_rect(Rect2(-7, -10, 3, 1), _col(C_GLINT, white))
	draw_rect(Rect2(-9, -8, 1, 2), _col(C_GLINT, white))
	if state == S.CURL:
		var k := clampf(1.0 - _timer / maxf(_phase_time, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, r + 4.0, _spin * 2.0, _spin * 2.0 + PI * (0.4 + k * 1.4), 12,
				Color(C_AMBER, 0.85), 2.0)
	elif state == S.CEIL_HOLD and int(t * 16.0) % 2 == 0:
		draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 20, C_RED, 2.0)


## A ring of `n` scales between radii r0..r1 turning with the ball; the dark base shows
## through the gaps as seams. Bright on top, dark underneath.
func _scale_ring(n: int, r0: float, r1: float, phase: float, white: bool) -> void:
	var da := TAU / n
	for i in n:
		var a := _spin + phase + i * da
		var s := sin(a)
		var tone := C_SCALE_HI if s < -0.45 else (C_SCALE if s < 0.4 else C_SCALE_MID)
		_fill([Vector2.from_angle(a - da * 0.42) * r1, Vector2.from_angle(a) * (r1 + 0.4),
				Vector2.from_angle(a + da * 0.42) * r1, Vector2.from_angle(a + da * 0.3) * r0,
				Vector2.from_angle(a - da * 0.3) * r0], _col(tone, white))


func _draw_body(white: bool) -> void:
	var rot := 0.0
	var squash := 1.0
	var tail_up := 0.0
	var flare := 0.0
	var k := clampf(1.0 - _timer / maxf(_phase_time, 0.01), 0.0, 1.0)
	match state:
		S.REAR:
			rot = -0.45 * k
			flare = k
		S.TAIL_UP:
			tail_up = k
		S.DIG:
			squash = 1.0 - _sink * 0.8
		S.ERUPT:
			rot = lerpf(-PI / 2.0, 0.0, clampf((_vy + 250.0) / 500.0, 0.0, 1.0))
		S.STAGGER, S.STAGGER_FALL:
			rot = 0.12
	if state in [S.INTRO, S.UNCURL, S.IDLE] and _curl > 0.0:
		squash = 1.0 - _curl * 0.5
	var off := Vector2(0, HALF * (1.0 - squash))
	draw_set_transform(off, rot * facing, Vector2(facing, squash))
	_draw_tail(white, tail_up)
	# legs: knee guard, shin, foot and drill claws
	var step := roundf(sin(t * 14.0) * 1.5) if state == S.IDLE else 0.0
	_draw_leg(-7.0 + step, white)
	_draw_leg(7.0 - step, white)
	# armoured dome: rows of overlapping bronze scales (flared while rearing)
	var dome := PackedVector2Array()
	for i in 13:
		dome.append(_arch(PI + PI * i / 12.0, 1.0))
	draw_colored_polygon(dome, _col(C_SCALE_DARK, white))
	var glow := 0.5 * flare * (0.5 + 0.5 * sin(t * 30.0))
	_scale_row(-2.0, -13.0, 5, C_SCALE_MID, flare, glow, white)
	_scale_row(-6.0, -10.0, 4, C_SCALE, flare, glow, white)
	_scale_row(-10.0, -7.0, 2, C_SCALE_HI, flare, glow, white)
	draw_rect(Rect2(Vector2(-5, -7) + _flare_off(Vector2(-4, -7), flare), Vector2(2, 1)), _col(C_GLINT, white))
	if _frost > 0.0:
		for i in 3:
			var p := _arch(PI + 0.8 + i * 0.75, 1.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 1), p + Vector2(0, -5),
					p + Vector2(2, 1)]), Color(C_PALE, 0.9))
	# belly frame with cyan power cells
	_fill([Vector2(-13, 3), Vector2(11, 3), Vector2(12, 7), Vector2(-12, 7)], _col(C_BLUE, white))
	for x in [-8.0, -3.0, 2.0]:
		draw_rect(Rect2(x, 4, 3, 2), _col(C_CYAN, white))
	_draw_head(white)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state == S.DIG:
		for i in 4:
			var ph := fmod(t * 3.0 + i * 0.25, 1.0)
			draw_rect(Rect2(Vector2(-facing * (6.0 + ph * 18.0), HALF - 2.0 - sin(ph * PI) * 12.0),
					Vector2(2, 2)), C_DIRT)


## One row of shingled scales on the dome: `n` shields 6 px wide from x = `x0`, top at
## `y0`, pointed lower edges overlapping the row below; clipped to the dome outline.
## Flared (rearing) scales stand out from the body and flash amber.
func _scale_row(y0: float, x0: float, n: int, tone: Color, flare: float, glow: float, white: bool) -> void:
	var grow := 1.0 + 0.25 * flare
	var c := _col(tone.lerp(C_AMBER, glow), white)
	var seam := _col(C_SCALE_DARK, white)
	for i in n:
		var x := x0 + i * 6.0
		var o := _flare_off(Vector2(x + 3.0, y0 + 3.0), flare)
		var pts := []
		for p in [Vector2(x, y0), Vector2(x + 6, y0), Vector2(x + 6, y0 + 4), Vector2(x + 3, y0 + 6), Vector2(x, y0 + 4)]:
			pts.append(_dome_clip(p + o, grow))
		_fill(pts, c)
	for i in range(1, n):
		var x := x0 + i * 6.0
		var o := _flare_off(Vector2(x, y0 + 2.0), flare)
		var a := _dome_clip(Vector2(x, y0 + 1.0) + o, grow)
		var b := _dome_clip(Vector2(x, y0 + 4.0) + o, grow)
		if b.y - a.y >= 2.0 and absf(a.x - (x + o.x)) < 0.5:
			draw_rect(Rect2(a.x, a.y, 1, b.y - a.y), seam)


## Rearing flare: scales are pushed out from the dome centre.
func _flare_off(p: Vector2, flare: float) -> Vector2:
	return ((p - Vector2(-1, 6)).normalized() * 3.0 * flare).round()


## Keeps a point inside the dome (half ellipse, optionally grown).
func _dome_clip(p: Vector2, grow: float) -> Vector2:
	var top := 6.0 - 16.0 * grow
	var y := maxf(p.y, top)
	var dy := clampf((y - 6.0) / (16.0 * grow), -1.0, 0.0)
	var hw := 13.0 * grow * sqrt(1.0 - dy * dy)
	return Vector2(clampf(p.x, -1.0 - hw, -1.0 + hw), y)


func _draw_leg(x: float, white: bool) -> void:
	_fill([Vector2(x - 3, 6), Vector2(x + 3, 6), Vector2(x + 3, 9), Vector2(x - 3, 9)], _col(C_STEEL, white))
	draw_rect(Rect2(x - 2, 6, 2, 1), _col(C_STEEL_HI, white))
	_fill([Vector2(x - 2, 9), Vector2(x + 2, 9), Vector2(x + 3, 12), Vector2(x - 3, 12)], _col(C_NAVY, white))
	_fill([Vector2(x + 2, 10), Vector2(x + 6, 12), Vector2(x + 2, 12)], _col(C_PALE, white))


## Segmented tail (pivot at the hip, raised for the slam); its tip blinks red when armed.
func _draw_tail(white: bool, tail_up: float) -> void:
	var pivot := Vector2(-9, 5)
	var swing := 1.25 * tail_up
	var rp := func(p: Vector2) -> Vector2: return pivot + (p - pivot).rotated(swing)
	var top := func(u: float) -> Vector2: return Vector2(-9, 1).lerp(Vector2(-26, 9), u)
	var bot := func(u: float) -> Vector2: return Vector2(-8, 9).lerp(Vector2(-20, 12), u)
	var tail := [Vector2(-9, 1), Vector2(-26, 9), Vector2(-27, 12), Vector2(-20, 12), Vector2(-8, 9)]
	var pts := []
	for p in tail:
		pts.append(rp.call(p))
	_fill(pts, _col(C_SCALE_DARK, white))
	var tones := [C_SCALE, C_SCALE_HI, C_SCALE, C_SCALE_HI]
	for j in 4:
		var u0 := 0.04 + j * 0.24
		var u1 := u0 + 0.3
		var m0: Vector2 = top.call(u0).lerp(bot.call(u0), 0.7)
		var m1: Vector2 = top.call(u1).lerp(bot.call(u1), 0.7)
		_fill([rp.call(top.call(u0)), rp.call(top.call(u1)), rp.call(m1), rp.call(m0.lerp(m1, 0.4) + Vector2(0, 1)),
				rp.call(m0)], _col(tones[j], white))
	if tail_up > 0.6 and int(t * 14.0) % 2 == 0:
		draw_circle(pts[2], 2.5, C_RED)


## Head: steel helmet, mining lamp, eye, jaw and the spinning nose drill.
func _draw_head(white: bool) -> void:
	_fill([Vector2(6, -7), Vector2(12, -7), Vector2(17, -4), Vector2(21, -1), Vector2(21, 2), Vector2(16, 4),
			Vector2(9, 5), Vector2(6, 3)], _col(C_STEEL, white))
	_fill([Vector2(7, -7), Vector2(12, -7), Vector2(17, -4), Vector2(16, -3), Vector2(11, -5), Vector2(7, -5)],
			_col(C_STEEL_HI, white))
	_fill([Vector2(10, 2), Vector2(21, 1), Vector2(21, 2), Vector2(16, 4), Vector2(9, 5)], _col(C_BLUE, white))
	# mining lamp
	_fill([Vector2(8, -10), Vector2(13, -10), Vector2(13, -7), Vector2(8, -7)], _col(C_NAVY, white))
	draw_rect(Rect2(9, -9, 3, 2), _col(C_AMBER, white))
	draw_rect(Rect2(9, -9, 1, 1), _col(C_GLINT, white))
	var eye := C_RED if phase2 or state in [S.REAR, S.TAIL_UP] else C_CYAN
	draw_rect(Rect2(12, -3, 3, 2), eye)
	draw_rect(Rect2(13, -3, 1, 1), _col(C_GLINT, white))
	# nose drill with travelling grooves
	draw_rect(Rect2(19, -2, 2, 6), _col(C_NAVY, white))
	_fill([Vector2(21, -2), Vector2(28, 1), Vector2(21, 4)], _col(C_PALE, white))
	var drill := fmod(t * (30.0 if state in [S.DIG, S.ERUPT] else 6.0), 3.0)
	for i in 2:
		var x := 22.0 + drill + i * 3.0
		if x < 27.0:
			draw_line(Vector2(x, -1.0 + (x - 21.0) * 0.4), Vector2(x, 3.0 - (x - 21.0) * 0.4),
					_col(C_CYAN, white), 1.0)


func _arch(a: float, k: float) -> Vector2:
	return Vector2(-1.0 + 13.0 * k * cos(a), 6.0 + 16.0 * k * sin(a))


## Underground: a dirt mound that follows the player, then red cracks and a
## faint red column where it will erupt.
func _draw_mound() -> void:
	var warn := state == S.WARN
	if warn and int(t * 14.0) % 2 == 0:
		draw_rect(Rect2(-13, -96, 26, 98), Color(C_RED, 0.14))
	var wob := sin(t * 30.0) * 1.5
	var pts := PackedVector2Array()
	for i in 9:
		var x := -14.0 + i * 3.5
		pts.append(Vector2(x, 2.0 - (6.0 + wob) * (1.0 - pow(x / 14.0, 2.0))))
	draw_colored_polygon(pts, C_DIRT)
	# packed darker soil at the foot, loose lighter clods and pebbles on the crest
	draw_colored_polygon(PackedVector2Array([Vector2(-14, 2), Vector2(-9, -1), Vector2(9, -1),
			Vector2(14, 2)]), C_DIRT_DARK)
	var crest := roundf(-2.0 - (4.0 + wob) * 0.85)
	draw_rect(Rect2(-5, crest, 4, 2), C_DIRT_HI)
	draw_rect(Rect2(2, crest + 1.0, 3, 2), C_DIRT_HI)
	draw_rect(Rect2(-9, -2, 3, 2), C_SCALE_MID)
	draw_rect(Rect2(6, -2, 2, 2), C_SCALE_MID)
	for i in 3:
		var ph := fmod(t * 2.5 + i * 0.33, 1.0)
		draw_rect(Rect2(Vector2(-8.0 + i * 7.0, -2.0 - sin(ph * PI) * (12.0 if warn else 6.0)),
				Vector2(2, 2)), C_DIRT.lightened(0.2))
	if warn:
		var c := C_RED if int(t * 14.0) % 2 == 0 else C_AMBER
		for d in [-1.0, 1.0]:
			draw_polyline(PackedVector2Array([Vector2(0, 2), Vector2(d * 7, 1), Vector2(d * 12, 3),
					Vector2(d * 18, 2)]), c, 1.0)


## Ceiling dust and a blinking marker over every lane a rock will fall in.
func _draw_rock_marks() -> void:
	for r in _rocks:
		var p := to_local(Vector2(r.x, arena.position.y))
		var a := clampf(1.3 - r.t, 0.35, 1.0)
		for i in 3:
			var ph := fmod(t * 2.0 + i * 0.37, 1.0)
			draw_rect(Rect2(p + Vector2(-5 + i * 4, 2 + ph * 14.0), Vector2(2, 2)), Color(C_DIRT, a))
		if int(t * 12.0) % 2 == 0:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-4, 2), p + Vector2(4, 2),
					p + Vector2(0, 7)]), Color(C_AMBER, a))
