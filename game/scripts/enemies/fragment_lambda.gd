extends "res://scripts/enemies/boss_base.gd"
## FRAGMENT Λ — hidden boss (GDD v0.2 §3-5, §5-3). Evolution data scattered in
## an old incident, materialized inside the Eden Link network: a floating crystal
## core wrapped in a shell of orbiting shards.
##
## CORE: no weakness. The shards close into a shell around the core during every
## attack (hits are blocked: white hex flash + spark, 0 damage). After each attack
## the crystal sinks to buster height and the shards splay open — the core is
## exposed for OPEN_TIME. The core opens at least every MAX_CLOSED seconds.
##
## Cycle: TELEPORT (destination marker) -> attack -> OPEN -> IDLE -> ...
##   VOLLEY      shards aim at the player (aim lines), then fire one by one
##   LATTICE     a "Λ" of two laser lines from the core; the legs rotate inward,
##               shrinking the safe pocket under the crystal (final lines shown
##               faintly during the telegraph); phase 2 tilts the whole Λ
##   RING        the shard ring spins up and bursts radially (phase 2: two rings)
##   INVERSION   (phase 2) "gravity inversion": shards fall UP out of marked floor
##               columns in waves while a gravity well pulls the player sideways
##               toward the crystal (walking or dashing beats the pull)
## Moves kinematically (teleports) inside `arena`.

const DamageZone = preload("res://scripts/level/damage_zone.gd")

enum S { INTRO, IDLE, TELEPORT, VOLLEY, LATTICE, RING, INVERSION, OPEN }

const SHELL_R := 14.0
const OPEN_TIME := 1.7
const OPEN_TIME_P2 := 1.4
## Core height above the floor while exposed (inside the buster's reach).
const OPEN_HOVER := 30.0
const SINK_SPEED := 260.0
## Safety net: the core opens at least this often (seconds closed while active).
const MAX_CLOSED := 3.9
const BEAM_W := 4.0
const THETA_WIDE := 1.2
const THETA_NARROW := 0.3
const PULL := 40.0

const C_CORE := Color("eafcff")
const C_DATA := Color("3de0ee")
const C_GLITCH := Color("b78af3")
const C_DEEP := Color("13304f")
const C_P2 := Color("f0b84a")
const C_WARN := Color("e34f5b")

var state := S.INTRO
## True while the core is exposed (damage only lands then).
var core_open := false
## How many times the core has opened (tests / debug).
var open_windows := 0
var shard_count := 6

var _timer := 0.0
var _step := 0
var _next := -1
var _to := Vector2.ZERO
var _tele_total := 0.45
var _fade := 1.0
var _spin := 0.0
var _spread := 0.0  # 0 = shell closed, 1 = shards splayed open
var _ring_k := 0.0
var _ammo := 6
var _shot_timer := 0.0
var _rings := 0
var _aim := Vector2.ZERO
var _closed_for := 0.0
var _bag: Array = []
var _last_pattern := -1
var _beam: Area2D = null
var _beam_hot := false
var _beam_dirs: Array = []
var _beam_len: Array = []
var _theta := THETA_WIDE
var _tilt := 0.0
var _marks: Array = []
var _wave := 0
var _pulling := false
var _block_fx := 0.0
var _p2_fx := 0.0
var _intro_total := 1.0
var _death_t0 := -1.0


## Data shard projectile: a thin crystal oriented along its flight.
class ShardShot extends "res://scripts/combat/enemy_shot.gd":
	var tint := Color("3de0ee")

	func _draw() -> void:
		var d := velocity.normalized() if velocity.length() > 1.0 else Vector2.RIGHT
		var n := Vector2(-d.y, d.x)
		# Two-tone splinter (lit half on top), white core line, glinting tip.
		var up := n.y < 0.0
		var lit := tint.lightened(0.4)
		var shade := tint.darkened(0.3)
		draw_colored_polygon(PackedVector2Array([d * 6.0, n * 2.4, -d * 4.0]), lit if up else shade)
		draw_colored_polygon(PackedVector2Array([d * 6.0, -d * 4.0, -n * 2.4]), shade if up else lit)
		draw_line(-d * 2.0, d * 4.0, Color.WHITE, 1.0)
		draw_rect(Rect2((d * 5.0).floor(), Vector2(1, 1)), Color.WHITE)


func _init() -> void:
	boss_name = "FRAGMENT Λ"
	max_hp = 48
	weakness = ""
	contact_damage = 3
	hit_radius = SHELL_R
	intro_time = 1.4
	death_time = 2.2


func _boss_ready() -> void:
	_intro_total = intro_time
	position = _inside(position, 24.0)
	_ammo = shard_count


func _boss_intro(delta: float) -> void:
	_spin += delta * 1.5


func _on_active() -> void:
	_choose_pattern()


func get_contact_damage() -> int:
	if state == S.TELEPORT:
		return 0
	return super.get_contact_damage()


func _boss_process(delta: float) -> void:
	_timer -= delta
	_block_fx = maxf(_block_fx - delta, 0.0)
	_p2_fx = maxf(_p2_fx - delta, 0.0)
	_spin += delta * (1.0 if core_open else 3.2) * (1.3 if phase2 else 1.0)
	_spread = move_toward(_spread, 1.0 if core_open else 0.0, delta * 4.0)
	_closed_for = 0.0 if core_open else _closed_for + delta
	match state:
		S.IDLE:
			_process_idle(delta)
		S.TELEPORT:
			_process_teleport()
		S.VOLLEY:
			_process_volley(delta)
		S.LATTICE:
			_process_lattice()
		S.RING:
			_process_ring()
		S.INVERSION:
			_process_inversion()
		S.OPEN:
			_process_open(delta)
	if _pulling:
		_pull_player(delta)
	if not core_open and _closed_for > MAX_CLOSED and state != S.TELEPORT:
		_start_open()


# --- cycle ------------------------------------------------------------------------

func _choose_pattern() -> void:
	var pool := [S.VOLLEY, S.LATTICE, S.RING]
	if phase2:
		pool.append(S.INVERSION)
	if _bag.is_empty():
		_bag = pool.duplicate()
		_bag.shuffle()
		if _bag.size() > 1 and _bag[0] == _last_pattern:
			_bag.push_back(_bag.pop_front())
	var p: int = _bag.pop_front()
	_last_pattern = p
	_start_teleport(_anchor_for(p), p)


func _anchor_for(p: int) -> Vector2:
	var c := arena.get_center()
	var away := -1.0 if _player_x() > c.x else 1.0
	match p:
		S.VOLLEY:
			return Vector2(c.x + away * (arena.size.x * 0.5 - 40.0), arena.position.y + 40.0)
		S.LATTICE:
			return Vector2(c.x, arena.position.y + 34.0)
		S.RING:
			return Vector2(c.x + away * 70.0, arena.position.y + arena.size.y * 0.42)
	return Vector2(c.x, arena.position.y + 40.0)


func _start_teleport(dest: Vector2, then: int) -> void:
	state = S.TELEPORT
	core_open = false
	_to = _inside(dest, 20.0)
	_next = then
	_step = 0
	_tele_total = 0.35 if phase2 else 0.45
	_timer = _tele_total


func _process_teleport() -> void:
	if _step == 0:
		_fade = clampf(_timer / _tele_total, 0.0, 1.0)
		if _timer <= 0.0:
			position = _to
			reset_physics_interpolation()
			fx(position, 8.0)
			_step = 1
			_timer = 0.2
	else:
		_fade = clampf(1.0 - _timer / 0.2, 0.0, 1.0)
		if _timer <= 0.0:
			_fade = 1.0
			_start_pattern(_next)


func _start_pattern(p: int) -> void:
	_step = 0
	core_open = false
	match p:
		S.VOLLEY:
			state = S.VOLLEY
			_timer = 0.6
			_ammo = shard_count
		S.LATTICE:
			state = S.LATTICE
			_timer = 0.7
			_theta = THETA_WIDE
			_tilt = 0.0
			_beam_hot = false
			_make_beam()
			_update_beam()
		S.RING:
			state = S.RING
			_timer = 0.65
			_rings = 0
			_ring_k = 0.0
		S.INVERSION:
			state = S.INVERSION
			_timer = 0.5
			_wave = 0
			_marks.clear()
			_pulling = true


func _idle(time: float) -> void:
	state = S.IDLE
	core_open = false
	_timer = time


func _process_idle(delta: float) -> void:
	position.y = move_toward(position.y, floor_y() - OPEN_HOVER - 18.0, 60.0 * delta)
	if _timer <= 0.0:
		_choose_pattern()


## The shell splays open and the crystal sinks to buster height.
func _start_open() -> void:
	_end_attack()
	state = S.OPEN
	core_open = true
	open_windows += 1
	_fade = 1.0
	_ammo = shard_count
	_to = Vector2(clampf(position.x, arena.position.x + 24.0, arena.end.x - 24.0), floor_y() - OPEN_HOVER)
	_timer = (OPEN_TIME_P2 if phase2 else OPEN_TIME) + position.distance_to(_to) / SINK_SPEED


func _process_open(delta: float) -> void:
	position = position.move_toward(_to, SINK_SPEED * delta)
	if _timer <= 0.0:
		_idle(0.25)


func _end_attack() -> void:
	_free_beam()
	_pulling = false
	_marks.clear()
	_ring_k = 0.0


# --- patterns ------------------------------------------------------------------------

func _process_volley(delta: float) -> void:
	match _step:
		0:  # shards turn toward the player (aim lines)
			_aim = player_pos()
			if _timer <= 0.0:
				_step = 1
				_shot_timer = 0.0
		1:
			_shot_timer -= delta
			if _shot_timer <= 0.0 and _ammo > 0:
				_ammo -= 1
				var from := position + _shard_offset(_ammo)
				var ang := (player_pos() - from).angle()
				if phase2:
					ang += 0.14 if _ammo % 2 == 0 else -0.14
				_shoot_shard(from, Vector2.from_angle(ang) * (190.0 if phase2 else 170.0))
				_shot_timer = 0.1 if phase2 else 0.14
				if _ammo == 0:
					_step = 2
					_timer = 0.35
		2:
			if _timer <= 0.0:
				_start_open()


func _process_lattice() -> void:
	match _step:
		0:  # telegraph: flickering lines + the final safe pocket
			if _timer <= 0.0:
				_step = 1
				_timer = 1.5
				_beam_hot = true
		1:  # legs rotate inward
			var k := clampf(1.0 - _timer / 1.5, 0.0, 1.0)
			_theta = lerpf(THETA_WIDE, THETA_NARROW, smoothstep(0.0, 1.0, k))
			if phase2:
				_tilt = sin(t * 2.4) * 0.18
			if _timer <= 0.0:
				_step = 2
				_timer = 0.2
		2:
			if _timer <= 0.0:
				_step = 3
				_timer = 0.2
				_beam_hot = false
		3:
			if _timer <= 0.0:
				_start_open()
				return
	_update_beam()


func _process_ring() -> void:
	match _step:
		0:  # spin up and expand (telegraph)
			_ring_k = clampf(1.0 - _timer / 0.65, 0.0, 1.0)
			if _timer <= 0.0:
				_burst(0.0)
				_ring_k = 0.0
				_step = 1
				_timer = 0.35
		1:
			if _timer <= 0.0:
				if phase2 and _rings < 2:
					_burst(PI / 8.0)
					_timer = 0.3
				else:
					_start_open()


func _process_inversion() -> void:
	match _step:
		0:  # the field inverts (rising streaks), the well starts pulling
			if _timer <= 0.0:
				_step = 1
				_plan_wave()
				_timer = 0.45
		1:  # marked columns erupt upward, wave after wave
			if _timer <= 0.0:
				_erupt()
				_wave += 1
				if _wave >= 3:
					_marks.clear()
					_pulling = false
					_step = 2
					_timer = 0.3
				else:
					_plan_wave()
					_timer = 0.55
		2:
			if _timer <= 0.0:
				_start_open()


func _burst(offset: float) -> void:
	_rings += 1
	var n := 8
	for i in n:
		var d := Vector2.from_angle(_spin + offset + TAU * i / n)
		_shoot_shard(position + d * 16.0, d * 120.0)


## Floor columns that erupt next: always the player's column plus a few others.
func _plan_wave() -> void:
	_marks.clear()
	var lo := arena.position.x + 8.0
	var slots := maxi(int((arena.size.x - 16.0) / 32.0), 2)
	var picks := [clampi(int((_player_x() - lo) / 32.0), 0, slots - 1)]
	var want := mini(5 if phase2 else 4, slots - 1)
	var guard := 0
	while picks.size() < want and guard < 64:
		guard += 1
		var pick := rng().randi_range(0, slots - 1)
		if not picks.has(pick):
			picks.append(pick)
	for slot in picks:
		_marks.append(lo + 16.0 + slot * 32.0)


func _erupt() -> void:
	for x in _marks:
		for dx in [-5.0, 0.0, 5.0]:
			var shard = _shoot_shard(Vector2(x + dx, floor_y() - 6.0), Vector2(0.0, -230.0 if dx == 0.0 else -200.0))
			shard.tint = C_P2
		fx(Vector2(x, floor_y() - 4.0), 6.0)


## Gravity well: nudges the player sideways toward the crystal (walk/dash beats it).
func _pull_player(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return
	var dx: float = position.x - player.global_position.x
	if absf(dx) < 4.0:
		return
	player.move_and_collide(Vector2(signf(dx) * PULL * delta, 0.0))


func _shoot_shard(pos: Vector2, v: Vector2):
	var s := ShardShot.new()
	s.velocity = v
	s.damage = 2
	s.position = pos
	s.tint = C_P2 if phase2 else C_DATA
	get_parent().add_child(s)
	return s


# --- lattice beams (boss-owned hazard) ------------------------------------------------

func _make_beam() -> void:
	_free_beam()
	_beam = DamageZone.new()
	_beam.damage = 3
	_beam.collision_layer = 0
	_beam.collision_mask = 0
	for i in 2:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(8.0, BEAM_W)
		cs.shape = rect
		_beam.add_child(cs)
	add_child(_beam)


func _free_beam() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null
	_beam_hot = false
	_beam_dirs.clear()
	_beam_len.clear()


func _update_beam() -> void:
	_beam_dirs.clear()
	_beam_len.clear()
	for sgn in [-1.0, 1.0]:
		var a: float = sgn * _theta + _tilt
		var d := Vector2(sin(a), cos(a))
		_beam_dirs.append(d)
		_beam_len.append(_ray_len(position, d))
	if _beam == null or not is_instance_valid(_beam):
		return
	_beam.collision_layer = Layers.HAZARD if _beam_hot else 0
	for i in 2:
		var cs: CollisionShape2D = _beam.get_child(i)
		var d: Vector2 = _beam_dirs[i]
		var length: float = _beam_len[i]
		(cs.shape as RectangleShape2D).size = Vector2(maxf(length - SHELL_R, 1.0), BEAM_W)
		cs.position = d * (SHELL_R + length) * 0.5
		cs.rotation = d.angle()


## Distance from `from` along `dir` to the arena edge.
func _ray_len(from: Vector2, dir: Vector2) -> float:
	var best := 10000.0
	if dir.x > 0.0001:
		best = minf(best, (arena.end.x - from.x) / dir.x)
	elif dir.x < -0.0001:
		best = minf(best, (arena.position.x - from.x) / dir.x)
	if dir.y > 0.0001:
		best = minf(best, (arena.end.y - from.y) / dir.y)
	elif dir.y < -0.0001:
		best = minf(best, (arena.position.y - from.y) / dir.y)
	return maxf(best, 0.0)


# --- damage ------------------------------------------------------------------------

## The shell blocks everything while closed.
func _modify_damage(amount: int, _weapon: String) -> int:
	if core_open:
		return amount
	_block_fx = 0.3
	var d := (player_pos() - position).normalized()
	var e := Explosion.new()
	e.size = 5.0
	e.duration = 0.15
	e.position = position + d * SHELL_R
	get_parent().add_child.call_deferred(e)
	return 0


func _on_phase2() -> void:
	shard_count = 8
	_ammo = shard_count
	_p2_fx = 1.0
	var e := Explosion.new()
	e.size = 22.0
	e.position = position
	get_parent().add_child.call_deferred(e)
	_bag.erase(S.INVERSION)
	_bag.push_front(S.INVERSION)  # show the new attack next, then finish the cycle
	if state == S.OPEN:
		_timer = minf(_timer, 0.45)  # core overload: the shell slams shut early


func _on_stagger() -> void:
	pass  # no weakness


func _on_death() -> void:
	_end_attack()
	core_open = false
	_death_t0 = t


# --- helpers ------------------------------------------------------------------------

func _player_x() -> float:
	return player_pos().x


func _inside(p: Vector2, margin: float) -> Vector2:
	return p.clamp(arena.position + Vector2(margin, margin), arena.end - Vector2(margin, margin))


func _shard_offset(i: int) -> Vector2:
	var a := _spin + TAU * i / shard_count
	var r := lerpf(12.0, 28.0, _spread) + 16.0 * _ring_k
	return Vector2(cos(a) * r, sin(a) * r * 0.8)


func _to_local_pt(world: Vector2) -> Vector2:
	return world - position


# --- drawing ------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	var alpha := _fade
	if state == S.INTRO:
		alpha = clampf(1.0 - intro_time / maxf(_intro_total, 0.01), 0.0, 1.0)
	var tint := C_P2 if phase2 else C_DATA
	_draw_telegraphs(tint)

	if _death_t0 >= 0.0:
		_draw_shatter(tint)
		return

	var bob := Vector2(0.0, sin(t * 2.4) * 1.5)
	# Glitch pixels around the crystal (more of them when unstable).
	var n_glitch := 10 if phase2 else 6
	for i in n_glitch:
		var h := fmod(sin(i * 12.9898 + floorf(t * 8.0) * 78.233) * 43758.5453, 1.0)
		var ang := TAU * absf(h) + i
		var at := bob + Vector2(cos(ang), sin(ang)) * (18.0 + 14.0 * absf(fmod(h * 7.0, 1.0)))
		draw_rect(Rect2(at.floor(), Vector2(2, 2)), Color(C_GLITCH if i % 2 == 0 else tint, 0.5 * alpha))

	# Shards behind the core (upper half of the tilted orbit).
	for i in shard_count:
		var o := _shard_offset(i)
		if o.y < 0.0:
			_draw_shard(bob + o, i, white, tint, alpha)

	var glow := 0.5 + 0.5 * sin(t * 10.0)
	var open_k := _spread
	draw_circle(bob, 9.0 + 3.0 * open_k, Color(tint, (0.12 + 0.25 * open_k * glow) * alpha))
	_draw_core(bob, white, tint, alpha)
	_draw_shell(bob, white, tint, alpha)

	if _block_fx > 0.0:
		var k := _block_fx / 0.3
		var hex2 := _hex(bob, SHELL_R + 2.0)
		hex2.append(hex2[0])
		draw_polyline(hex2, Color(1, 1, 1, k), 2.0)
		draw_line(bob + Vector2(-4, -4), bob + Vector2(4, 4), Color(C_WARN, k), 1.0)
		draw_line(bob + Vector2(-4, 4), bob + Vector2(4, -4), Color(C_WARN, k), 1.0)

	# Shards in front.
	for i in shard_count:
		var o := _shard_offset(i)
		if o.y >= 0.0:
			_draw_shard(bob + o, i, white, tint, alpha)

	# Exposed core: pulsing target ring with four brackets.
	if core_open:
		var rr := 11.0 + 2.0 * glow
		draw_arc(bob, rr, 0.0, TAU, 20, Color(C_CORE, 0.6 * alpha), 1.0)
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4.0
			draw_arc(bob, rr + 3.0, a - 0.25, a + 0.25, 4, Color(tint, 0.8 * alpha), 1.0)
	if _p2_fx > 0.0:
		var k := 1.0 - _p2_fx
		draw_arc(Vector2.ZERO, 10.0 + 40.0 * k, 0.0, TAU, 6, Color(C_P2, 1.0 - k), 2.0)


## The crystal core: a turning octahedron seen from the side. Four facets (lit
## upper left to dark lower right) around a ridge that slides with the turn, an
## etched Λ, a pale heart and a glint. Dim while the shell is closed.
func _draw_core(bob: Vector2, white: bool, tint: Color, alpha: float) -> void:
	var open_k := _spread
	var w := 6.0 * absf(cos(t * 2.0)) + 2.0
	var base := C_CORE.lerp(C_DEEP, 0.55 * (1.0 - open_k))
	var c_hi := base.lightened(0.4)
	var c_lo := base.lerp(tint, 0.4).darkened(0.1)
	var c_sh := base.lerp(C_DEEP, 0.5)
	if white:
		base = Color.WHITE
		c_hi = Color.WHITE
		c_lo = Color.WHITE
		c_sh = Color.WHITE
	var top := bob + Vector2(0, -9)
	var bot := bob + Vector2(0, 9)
	var lt := bob + Vector2(-w, 0)
	var rt := bob + Vector2(w, 0)
	if w < 3.5:
		# Edge-on: just a lit and a shaded half.
		_poly([top, bob + Vector2(0, 1), bot, lt], Color(c_hi, alpha))
		_poly([top, rt, bot, bob + Vector2(0, 1)], Color(c_sh, alpha))
	else:
		var ridge := bob + Vector2(signf(sin(t * 2.0)) * (w - 2.0) * 0.45, -1.0)
		_poly([top, ridge, lt], Color(c_hi, alpha))
		_poly([top, rt, ridge], Color(base, alpha))
		_poly([lt, ridge, bot], Color(c_lo, alpha))
		_poly([ridge, rt, bot], Color(c_sh, alpha))
	if white:
		return
	# Heart of light, brighter when exposed.
	var heart := C_CORE if open_k > 0.5 else tint
	draw_rect(Rect2(bob + Vector2(-1, -1), Vector2(2, 3)), Color(heart, alpha))
	# Etched Λ.
	var etch := Color(C_DEEP if open_k > 0.5 else tint, alpha)
	draw_polyline(PackedVector2Array([bob + Vector2(-3, 5), bob + Vector2(0, -4), bob + Vector2(3, 5)]), etch, 1.0)
	draw_line(bob + Vector2(-1, -1), bob + Vector2(-3, 3), etch, 1.0)
	# Glint on the lit facet.
	draw_rect(Rect2(bob + Vector2(-minf(w, 4.0) * 0.5 - 1.0, -5.0), Vector2(1, 2)), Color(1, 1, 1, alpha))


## Closed shell: a hexagonal crystal cage. Translucent panes, a 2 px frame shaded
## per edge (lit on top, dark underneath), pale nodes on the corners.
func _draw_shell(bob: Vector2, white: bool, tint: Color, alpha: float) -> void:
	var shell_a := (1.0 - _spread) * alpha
	if shell_a <= 0.02:
		return
	var outer := _hex(bob, SHELL_R)
	var inner := _hex(bob, SHELL_R - 2.0)
	var shell_fill := Color.WHITE if white else C_DEEP
	draw_colored_polygon(inner, Color(shell_fill, 0.55 * shell_a))
	for i in 6:
		var j := (i + 1) % 6
		draw_line(inner[i], bob + (inner[i] - bob) * 0.45, Color(tint, 0.5 * shell_a), 1.0)
		var mid_y := (outer[i].y + outer[j].y) * 0.5 - bob.y
		var c := tint
		if mid_y < -4.0:
			c = tint.lightened(0.45)
		elif mid_y > 4.0:
			c = tint.darkened(0.4)
		if white:
			c = Color.WHITE
		_poly([outer[i], outer[j], inner[j], inner[i]], Color(c, shell_a))
	for i in 6:
		var p := outer[i].lerp(inner[i], 0.5).floor()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(Color.WHITE if white else C_CORE, shell_a))


func _hex(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := TAU * i / 6.0 + _spin * 0.3
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts


func _poly(points: Array, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), c)


func _draw_shard(at: Vector2, i: int, white: bool, tint: Color, alpha: float) -> void:
	# Fired shards (volley) are missing until the shell re-forms.
	if state == S.VOLLEY and i >= _ammo:
		return
	var d := at.normalized() if at.length() > 0.1 else Vector2.RIGHT
	var hot := state == S.VOLLEY and _step == 0 and int(t * 20.0) % 2 == 0
	if state == S.VOLLEY and _step < 2:
		d = (_to_local_pt(_aim) - at).normalized()  # shards point at the target
	var c := Color.WHITE if white or hot else (tint if i % 2 == 0 else C_GLITCH)
	_crystal(at, d, c, alpha, white or hot)


## Two-tone crystal splinter along `d`: lit and shaded halves, a bright core line
## and a glint on the tip (orbiting shards and the death shatter).
func _crystal(at: Vector2, d: Vector2, c: Color, alpha: float, flat := false) -> void:
	var n := Vector2(-d.y, d.x)
	var tip := at + d * 7.0
	var tail := at - d * 4.0
	var side_a := at + n * 2.6
	var side_b := at - n * 2.6
	# The half facing up is the lit one.
	var up_a := n.y < 0.0
	var lit := c if flat else c.lightened(0.4)
	var shade := c if flat else c.darkened(0.3)
	draw_colored_polygon(PackedVector2Array([tip, side_a, tail]), Color(lit if up_a else shade, alpha))
	draw_colored_polygon(PackedVector2Array([tip, tail, side_b]), Color(shade if up_a else lit, alpha))
	if flat:
		return
	draw_line(at - d * 1.5, at + d * 4.5, Color(1, 1, 1, 0.7 * alpha), 1.0)
	draw_rect(Rect2((at + d * 5.5).floor(), Vector2(1, 1)), Color(1, 1, 1, alpha))


func _draw_telegraphs(tint: Color) -> void:
	var blink := int(t * 16.0) % 2 == 0
	match state:
		S.TELEPORT:
			if _step == 0:
				var m := _to_local_pt(_to)
				var r := 10.0 + 3.0 * sin(t * 12.0)
				var pts := PackedVector2Array([m + Vector2(0, -r), m + Vector2(r, 0), m + Vector2(0, r),
						m + Vector2(-r, 0), m + Vector2(0, -r)])
				draw_polyline(pts, Color(tint, 0.8 if blink else 0.4), 1.0)
				draw_polyline(PackedVector2Array([m + Vector2(-4, 5), m + Vector2(0, -5), m + Vector2(4, 5)]),
						Color(tint, 0.8), 1.0)
		S.VOLLEY:
			if _step == 0 and blink:
				for i in shard_count:
					var o := _shard_offset(i)
					var d := (_to_local_pt(_aim) - o).normalized()
					draw_line(o, o + d * 46.0, Color(C_WARN, 0.45), 1.0)
		S.LATTICE:
			for i in _beam_dirs.size():
				var d: Vector2 = _beam_dirs[i]
				var length: float = _beam_len[i]
				var a := d * SHELL_R
				var b := d * length
				if _step == 0:
					if blink:
						draw_line(a, b, Color(C_WARN, 0.6), 1.0)
					# Where the legs will end up: the safe pocket under the crystal.
					var sgn := -1.0 if i == 0 else 1.0
					var fd := Vector2(sin(sgn * THETA_NARROW), cos(sgn * THETA_NARROW))
					var fl := _ray_len(position, fd)
					var seg := 6.0
					var s := SHELL_R
					while s < fl:
						draw_line(fd * s, fd * minf(s + seg * 0.5, fl), Color(tint, 0.35), 1.0)
						s += seg
				elif _beam_hot:
					var wob := sin(t * 60.0)
					draw_line(a, b, Color(C_WARN, 0.45), BEAM_W + 3.0 + wob)
					draw_line(a, b, Color(tint, 0.9), BEAM_W)
					draw_line(a, b, Color.WHITE, 1.0)
					draw_circle(b, 3.0 + wob, Color(tint, 0.7))
				else:
					draw_line(a, b, Color(tint, 0.4), 1.0)
		S.RING:
			if _ring_k > 0.0:
				draw_arc(Vector2.ZERO, 14.0 + 22.0 * _ring_k, 0.0, TAU, 24, Color(C_WARN, 0.3 + 0.5 * _ring_k), 1.0)
		S.INVERSION:
			_draw_inversion(tint, blink)


func _draw_inversion(tint: Color, blink: bool) -> void:
	# Rising streaks across the room: gravity reads "upside down".
	var floor_l := floor_y() - position.y
	var top_l := arena.position.y - position.y
	var x0 := arena.position.x - position.x
	for i in 12:
		var x := x0 + (i + 0.5) * arena.size.x / 12.0
		var y := floor_l - fmod(t * 140.0 + i * 37.0, arena.size.y)
		if y > top_l:
			draw_line(Vector2(x, y), Vector2(x, maxf(y - 8.0, top_l)), Color(tint, 0.25), 1.0)
	# Erupting columns: chevrons pointing up on the floor.
	for x in _marks:
		var lx: float = x - position.x
		var c := Color(C_WARN, 0.9 if blink else 0.5)
		draw_rect(Rect2(lx - 8.0, floor_l - 3.0, 16.0, 3.0), Color(C_WARN, 0.35))
		for k in 2:
			var y := floor_l - 5.0 - k * 6.0
			draw_polyline(PackedVector2Array([Vector2(lx - 5, y), Vector2(lx, y - 4), Vector2(lx + 5, y)]), c, 1.0)
	# Gravity well arrows next to the player.
	if _pulling and player != null and is_instance_valid(player):
		var pp: Vector2 = player.global_position - position + Vector2(0, -30)
		var dir := signf(-pp.x)
		for k in 2:
			var ax := pp.x + dir * (4.0 + k * 5.0 + fmod(t * 20.0, 5.0))
			draw_polyline(PackedVector2Array([Vector2(ax - dir * 3.0, pp.y - 3.0), Vector2(ax, pp.y),
					Vector2(ax - dir * 3.0, pp.y + 3.0)]), Color(tint, 0.7), 1.0)


func _draw_shatter(tint: Color) -> void:
	var k := t - _death_t0
	var a := clampf(1.0 - k / death_time, 0.0, 1.0)
	for i in shard_count:
		var ang := TAU * i / shard_count + _spin
		var d := Vector2(cos(ang), sin(ang))
		_crystal(d * (14.0 + k * 40.0), d.rotated(k * 6.0 * (1.0 if i % 2 == 0 else -1.0)),
				tint if i % 2 == 0 else C_GLITCH, a)
	if int(t * 20.0) % 2 == 0:
		draw_circle(Vector2.ZERO, 7.0, C_CORE)
		draw_circle(Vector2.ZERO, 3.0, Color(tint, 0.8))
