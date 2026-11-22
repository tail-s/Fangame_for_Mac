extends "res://scripts/enemies/boss_base.gd"
## PULSE CICADA — boss of the ultra-high-voltage substation (GDD v0.2 §5).
## A cicada-shaped resonator robot that clings to the two transmission pylons on
## the arena walls and fights to its own metronome: every move starts on a beat
## (0.6 s, 0.42 s in phase 2) and its tymbal ribs flash on each beat, so the
## player can read the rhythm before the attacks use it.
##
## Patterns (all telegraphed, all beatable with the plain buster):
##   RING   on a pylon: the tymbals charge for 2 beats (rings contract into the
##          body), then a ring of shots bursts outward and surges on every beat.
##          Phase 2 adds a second ring one beat later, rotated half a step.
##   FLOOR  on a pylon: it drums and the floor lanes charge in a checkerboard —
##          sparks for 1 beat, live for 1 beat, then the other lanes. Phase 2
##          plays it back to back (switch lanes on every beat, or jump).
##   STRIKE hovers mid-arena (jump-shot height) and calls lightning down marked
##          columns, one of them on the player: reticle for 2 beats, then the bolt.
##   HOP    wings buzz until the next beat, then an arcing flight to the other
##          pylon. Phase 2 drops a spark fan on every beat in flight.
## Weakness CORE DRILL "grounds the discharge" (GDD §5-2): a weakness hit knocks
## the cicada off its pylon onto its back for a short daze on the floor and
## cancels its floor / lightning hazards (base class caps it to one per 2.5 s).
## Boss-owned hazards (BeatHazard below, a level/damage_zone.gd) are in the groups
## "boss_hazard" and "pulse_cicada_hazard"; they free themselves and are also
## freed on stagger and on death.

enum S { INTRO, CLING, RING, FLOOR, STRIKE, HOP, STAGGER }

const BEAT := 0.6
const BEAT_P2 := 0.42
## Perch: body centre this far above the floor / from the wall.
const PERCH_UP := 48.0
const WALL_GAP := 14.0
## STRIKE hover height above the floor (reachable with a jump shot).
const HOVER_UP := 78.0
const LANES := 6
const RING_SPOKES := 12
const RING_SPEED := 96.0
const BOLT_WIDTH := 22.0

const C_DARK := Color("101b36")
const C_SHELL := Color("1c375b")
const C_CYAN := Color("00b8be")
const C_VIOLET := Color("6543a2")
const C_RED := Color("e34f5b")
const C_AMBER := Color("f0b84a")
const C_PALE := Color("d7edf3")
## Accent: high-voltage yellow (same family as the electric floor / Pulse Ring).
const C_VOLT := Color("efcf5f")

## Folded fore wing (body frame: +x = head, -y = back, +y = belly / legs).
const WING := [Vector2(8, -7), Vector2(-4, -12), Vector2(-19, -11), Vector2(-28, -6),
		Vector2(-25, -2), Vector2(-6, -4)]
const WING_PIVOT := Vector2(6, -6)
const ABDOMEN := [Vector2(-22, 0), Vector2(-18, -5), Vector2(-6, -7), Vector2(0, -6),
		Vector2(0, 6), Vector2(-8, 7), Vector2(-18, 5)]
const THORAX := [Vector2(0, -7), Vector2(7, -9), Vector2(11, -5), Vector2(11, 5),
		Vector2(6, 7), Vector2(0, 6)]
const HEAD := [Vector2(10, -6), Vector2(15, -7), Vector2(19, -2), Vector2(18, 4), Vector2(11, 6)]

var state := S.INTRO
## Pylon the cicada clings to: -1 left wall, 1 right wall.
var side := 1
var beat_len := BEAT

var _beat_t := 0.0
var _beat_n := 0
var _pulse := 0.0
var _charge := 0.0
var _perched := false
var _hazards: Array = []
## [EnemyShot, direction] pairs; their speed surges on each beat.
var _ring_shots: Array = []
var _ring_angle := 0.0
var _bag: Array = []
var _last_attack := -1
var _volleys_left := 0
var _steps_left := 0
var _lane_set := 0
var _floor_end := 0
var _strike_end := 0
# flight (HOP)
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _fly_t := -1.0
var _fly_time := 0.9
var _takeoff_beat := 1
var _after_fly: int = S.CLING
# stagger
var _vy := 0.0
var _daze := 0.0
var _overdrive := 0.0
var _decor


func _init() -> void:
	boss_name = "PULSE CICADA"
	max_hp = 32
	weakness = "core_drill"
	contact_damage = 3
	hit_radius = 13.0
	intro_time = 1.4


func _boss_ready() -> void:
	facing = 1.0
	_from = position
	_to = _perch(1)
	_decor = ArenaDecor.new()
	_decor.arena = arena
	_decor.z_index = -1
	add_child(_decor)
	_decor.position = -position


func _boss_intro(_delta: float) -> void:
	# Glide from the spawn marker to the right pylon.
	var k := clampf(t / 1.2, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	position = _from.lerp(_to, e) + Vector2(0, -sin(k * PI) * 18.0)
	side = 1
	_perched = k >= 1.0
	clamp_to_arena(12.0)
	_decor.position = -position


func _on_active() -> void:
	state = S.CLING
	side = 1
	_perched = true
	_beat_t = 0.0
	_beat_n = 0
	_pulse = 1.0


func _boss_process(delta: float) -> void:
	_beat_t += delta
	_pulse = maxf(_pulse - delta * 3.0, 0.0)
	_overdrive = maxf(_overdrive - delta, 0.0)
	_steer_ring_shots()
	match state:
		S.HOP:
			_fly(delta)
		S.STAGGER:
			_process_stagger(delta)
		S.RING:
			_charge = clampf((_beat_n + _beat_t / beat_len) / 2.0, 0.0, 1.0) if _beat_n < 2 else 0.0
	if _beat_t >= beat_len:
		_beat_t -= beat_len
		_beat_n += 1
		_pulse = 1.0
		_on_beat()
	if _perched:
		facing = -float(side)
	elif state != S.STAGGER:
		var dx := _player_x() - position.x
		if absf(dx) > 4.0:
			facing = signf(dx)
	clamp_to_arena(12.0)
	_decor.position = -position


func _on_beat() -> void:
	match state:
		S.CLING:
			if _beat_n >= (1 if phase2 else 2):
				_next_attack()
		S.RING:
			if _beat_n == 2:
				_fire_ring(0.0)
			elif _beat_n == 3 and phase2:
				_fire_ring(0.5)
			elif _beat_n >= (5 if phase2 else 4):
				_after_attack()
		S.FLOOR:
			var every := 1 if phase2 else 2
			if _steps_left > 0 and (_beat_n - 1) % every == 0:
				_spawn_lanes(_lane_set)
				_lane_set = 1 - _lane_set
				_steps_left -= 1
				_floor_end = _beat_n + 2
			elif _steps_left <= 0 and _beat_n >= _floor_end:
				_after_attack()
		S.STRIKE:
			if _volleys_left > 0 and _beat_n % 2 == 1:
				_mark_volley()
				_volleys_left -= 1
				_strike_end = _beat_n + 3
			elif _volleys_left <= 0 and _beat_n >= _strike_end:
				_start_hop(_perch(_far_side()), S.CLING)
		S.HOP:
			if _fly_t < 0.0:
				if _beat_n >= _takeoff_beat:
					_fly_t = 0.0
					_perched = false
			elif phase2:
				_drop_sparks()


# --- patterns -----------------------------------------------------------------------

func _next_attack() -> void:
	if _bag.is_empty():
		_bag = [S.RING, S.FLOOR, S.STRIKE]
		_bag.shuffle()
		if _bag[0] == _last_attack:
			_bag.push_back(_bag.pop_front())
	var attack: int = _bag.pop_front()
	_last_attack = attack
	_beat_n = 0
	match attack:
		S.RING:
			state = S.RING
			_charge = 0.0
			_ring_angle = _rng.randf() * TAU
		S.FLOOR:
			state = S.FLOOR
			_steps_left = 5 if phase2 else 3
			_lane_set = _rng.randi_range(0, 1)
			_floor_end = 99
		S.STRIKE:
			_start_hop(Vector2(arena.get_center().x, floor_y() - HOVER_UP), S.STRIKE)


## RING / FLOOR end on the current pylon: fly over to the other one.
func _after_attack() -> void:
	_charge = 0.0
	_start_hop(_perch(-side), S.CLING)


func _start_hop(to: Vector2, after: int) -> void:
	state = S.HOP
	_from = position
	_to = to
	_after_fly = after
	_beat_n = 0
	_fly_t = -1.0
	# Telegraph: buzz until the next beat (or the one after, if it is too close).
	_takeoff_beat = 1 if beat_len - _beat_t > 0.25 else 2
	_fly_time = (0.7 if phase2 else 0.9) * clampf(_from.distance_to(_to) / 300.0, 0.6, 1.0)


func _fly(delta: float) -> void:
	if _fly_t < 0.0:
		return
	_fly_t += delta
	var k := clampf(_fly_t / _fly_time, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var room := minf(_from.y, _to.y) - (arena.position.y + 22.0)
	position = _from.lerp(_to, e) + Vector2(0, -sin(k * PI) * clampf(room, 0.0, 70.0))
	if k >= 1.0:
		position = _to
		_land()


func _land() -> void:
	_fly_t = -1.0
	_beat_n = 0
	if _after_fly == S.STRIKE:
		state = S.STRIKE
		_perched = false
		_volleys_left = 4 if phase2 else 3
		_strike_end = 99
	else:
		state = S.CLING
		side = 1 if position.x > arena.get_center().x else -1
		_perched = true


func _fire_ring(offset: float) -> void:
	var away := Vector2(-side, 0) if _perched else Vector2.ZERO
	for i in RING_SPOKES:
		var dir := Vector2.from_angle(_ring_angle + (i + offset) * TAU / RING_SPOKES)
		if away != Vector2.ZERO and dir.dot(away) < -0.3:
			continue  # would only hit the pylon behind it
		var s = shoot(position + dir * 10.0, dir * RING_SPEED, 2)
		s.life = 6.0
		_ring_shots.append([s, dir])


## Ring shots surge right after each beat, then slow to a crawl until the next.
func _steer_ring_shots() -> void:
	var p := _beat_t / beat_len
	var f := 0.35 + 1.4 * (1.0 - p) * (1.0 - p)
	for i in range(_ring_shots.size() - 1, -1, -1):
		var shot = _ring_shots[i][0]
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			_ring_shots.remove_at(i)
		else:
			shot.velocity = _ring_shots[i][1] * RING_SPEED * f


func _spawn_lanes(lane_set: int) -> void:
	var w := arena.size.x / LANES
	var rects: Array = []
	for i in LANES:
		if i % 2 == lane_set:
			rects.append(Rect2(arena.position.x + i * w + 2.0, floor_y() - 7.0, w - 4.0, 7.0))
	_add_hazard(rects, beat_len, beat_len, 2, false)


func _mark_volley() -> void:
	var xs: Array = [_player_x()]
	var count := 3 if phase2 else 2
	var guard := 0
	while xs.size() < count and guard < 40:
		guard += 1
		var x := _rng.randf_range(arena.position.x + 16.0, arena.end.x - 16.0)
		var ok := true
		for other in xs:
			if absf(x - other) < BOLT_WIDTH * 2.0:
				ok = false
		if ok:
			xs.append(x)
	for x in xs:
		var cx := clampf(x, arena.position.x + BOLT_WIDTH / 2.0, arena.end.x - BOLT_WIDTH / 2.0)
		var r := Rect2(cx - BOLT_WIDTH / 2.0, arena.position.y, BOLT_WIDTH, arena.size.y)
		_add_hazard([r], beat_len * 2.0, 0.3, 3, true)


func _drop_sparks() -> void:
	for vx in [-50.0, 0.0, 50.0]:
		shoot(position + Vector2(0, 8), Vector2(vx, 150.0), 2)


func _add_hazard(rects: Array, warn: float, live: float, damage: int, bolt: bool) -> void:
	_hazards = _hazards.filter(func(h) -> bool: return is_instance_valid(h))
	var h := BeatHazard.new()
	h.rects = rects
	h.warn = warn
	h.live = live
	h.damage = damage
	h.bolt = bolt
	h.floor_y = floor_y()
	get_parent().add_child(h)
	_hazards.append(h)


func _clear_hazards() -> void:
	for h in _hazards:
		if is_instance_valid(h):
			h.queue_free()
	_hazards.clear()


# --- stagger / phase 2 / death ------------------------------------------------------

func _on_stagger() -> void:
	# Grounded: drops off the pylon onto its back; its hazards fizzle out.
	_clear_hazards()
	_charge = 0.0
	_fly_t = -1.0
	_perched = false
	state = S.STAGGER
	_vy = -70.0
	_daze = 1.2
	fx(position, 14.0)


func _process_stagger(delta: float) -> void:
	var ground := floor_y() - 12.0
	if position.y < ground or _vy < 0.0:
		_vy = minf(_vy + 900.0 * delta, 420.0)
		position.y = minf(position.y + _vy * delta, ground)
		position.x = move_toward(position.x, arena.get_center().x, 40.0 * delta)
		if position.y >= ground:
			_vy = 0.0
		return
	_daze -= delta
	if _daze <= 0.0:
		_start_hop(_perch(_far_side()), S.CLING)


func _on_phase2() -> void:
	beat_len = BEAT_P2
	_overdrive = 0.8
	_pulse = 1.0


func _on_death() -> void:
	_clear_hazards()
	_ring_shots.clear()
	_charge = 0.0


func _exit_tree() -> void:
	_clear_hazards()


func get_contact_damage() -> int:
	if active and state == S.STAGGER:
		return 2
	return super()


# --- helpers ------------------------------------------------------------------------

func _perch(s: int) -> Vector2:
	var x := arena.position.x + WALL_GAP if s < 0 else arena.end.x - WALL_GAP
	return Vector2(x, floor_y() - PERCH_UP)


## The pylon farther from the player (so a landing never drops onto them).
func _far_side() -> int:
	return 1 if _player_x() < arena.get_center().x else -1


func _player_x() -> float:
	return player_pos().x


func _rib_color() -> Color:
	return C_RED if phase2 else C_VOLT


# --- drawing ------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	var accent := _rib_color()
	# Metronome: a faint ring leaves the body on every beat.
	if _pulse > 0.0 and active:
		draw_arc(Vector2.ZERO, 16.0 + (1.0 - _pulse) * 24.0, 0.0, TAU, 28, Color(accent, _pulse * 0.45), 1.5)
	if _overdrive > 0.0:
		draw_arc(Vector2.ZERO, 20.0 + (0.8 - _overdrive) * 60.0, 0.0, TAU, 32, Color(C_RED, _overdrive), 2.0)
	# RING telegraph: rings contract into the tymbals while it charges.
	if state == S.RING and _charge > 0.0:
		for i in 3:
			var k := fposmod(_charge * 2.0 + i / 3.0, 1.0)
			draw_arc(Vector2.ZERO, 12.0 + 40.0 * (1.0 - k), 0.0, TAU, 32, Color(accent, 0.15 + k * 0.6), 1.5)

	var spread := not _perched and state != S.STAGGER
	var buzzing := state == S.HOP and _fly_t < 0.0
	if _perched:
		# Head up, belly (legs) against the pylon.
		draw_set_transform(Vector2.ZERO, -PI / 2.0, Vector2(1.0, float(side)))
	elif state == S.STAGGER:
		draw_set_transform(Vector2(0, 3), sin(t * 9.0) * 0.08, Vector2(facing, -1.0))
	else:
		draw_set_transform(Vector2(0, sin(t * 14.0) * 1.5), 0.0, Vector2(facing, 1.0))

	var shell := Color.WHITE if white else C_SHELL
	var dark := Color.WHITE if white else C_DARK
	var pale := Color.WHITE if white else C_PALE
	var rib := Color.WHITE if white else accent
	var glow := clampf(0.25 + _pulse * 0.6 + _charge * 0.8, 0.0, 1.0)

	# hind + fore wings (behind the body)
	if spread or buzzing:
		var flap := 0.5 + 0.5 * sin(t * 70.0)
		var lift := 0.55 + 0.45 * flap if spread else 0.15 + 0.2 * flap
		_draw_wing(lift - 0.3, Color(pale, 0.22), white)
		_draw_wing(lift, Color(pale, 0.38), white)
	else:
		_draw_wing(-0.06, Color(pale, 0.22), white)
		_draw_wing(0.0, Color(pale, 0.4), white)

	# legs (belly side)
	for i in 3:
		var hip := Vector2(2.0 + i * 3.5, 6.0)
		var knee: Vector2
		var foot: Vector2
		if _perched:
			var tap := _pulse * 2.0 if state == S.FLOOR and i == 0 else 0.0
			knee = hip + Vector2(-3.0, 4.0)
			foot = Vector2(hip.x - 1.0 + i, 13.5 - tap)
		elif state == S.STAGGER:
			var kick := sin(t * 24.0 + i * 2.0) * 3.0
			knee = hip + Vector2(-2.0 + kick, 5.0)
			foot = knee + Vector2(2.0 - kick, 4.0)
		else:
			knee = hip + Vector2(-2.0, 3.0)
			foot = knee + Vector2(-4.0, 1.0)
		draw_polyline(PackedVector2Array([hip, knee, foot]), dark, 1.5)

	# abdomen with glowing tymbal ribs
	draw_colored_polygon(PackedVector2Array(ABDOMEN), shell)
	for i in 4:
		var x := -16.0 + i * 4.0
		draw_line(Vector2(x, -5), Vector2(x, 5), Color(rib, glow), 2.0)
	draw_polyline(PackedVector2Array([Vector2(-18, -5), Vector2(-6, -7), Vector2(0, -6)]),
			Color.WHITE if white else C_CYAN, 1.0)
	# thorax + pronotum plate
	draw_colored_polygon(PackedVector2Array(THORAX), Color.WHITE if white else C_VIOLET)
	draw_polyline(PackedVector2Array([Vector2(1, -7), Vector2(7, -9), Vector2(11, -5)]),
			Color.WHITE if white else C_CYAN, 1.5)
	draw_rect(Rect2(3, -3, 5, 2), Color(rib, 0.5 + glow * 0.5))
	# head, compound eye, antenna
	draw_colored_polygon(PackedVector2Array(HEAD), shell.lightened(0.12))
	draw_circle(Vector2(14.5, -3.0), 3.4, Color.WHITE if white else C_RED)
	draw_circle(Vector2(15.4, -4.0), 1.2, pale)
	draw_line(Vector2(17, -6), Vector2(21, -10), pale, 1.0)
	draw_circle(Vector2(21, -10), 1.0, Color(rib, 0.6 + glow * 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Dazed: sparks fizzle out into the floor and circle overhead.
	if state == S.STAGGER and active:
		for i in 3:
			var a := t * 6.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 11.0, -16.0 + sin(a) * 3.0), 1.5, C_AMBER)
		if int(t * 20.0) % 2 == 0:
			for i in 2:
				var x0 := _rng.randf_range(-10.0, 10.0)
				draw_polyline(PackedVector2Array([Vector2(x0, 4), Vector2(x0 + 3, 7), Vector2(x0 - 2, 9),
						Vector2(x0 + 1, 12)]), Color(C_VOLT, 0.7), 1.0)
	# Phase 2: stray arcs crawl over the shell.
	if phase2 and active and int(t * 15.0) % 3 == 0:
		var a0 := _rng.randf() * TAU
		var p0 := Vector2.from_angle(a0) * 12.0
		draw_polyline(PackedVector2Array([p0, p0 * 1.4 + Vector2(3, -2), p0 * 1.8 + Vector2(-2, 2)]),
				Color(C_VOLT, 0.8), 1.0)


func _draw_wing(angle: float, color: Color, white: bool) -> void:
	var pts := PackedVector2Array()
	for p in WING:
		pts.append(WING_PIVOT + (p - WING_PIVOT).rotated(angle))
	draw_colored_polygon(pts, Color(Color.WHITE, 0.6) if white else color)
	var vein := Color(C_CYAN, 0.55)
	var root := WING_PIVOT
	for tip in [Vector2(-26, -5), Vector2(-18, -10), Vector2(-12, -5)]:
		draw_line(root, WING_PIVOT + (tip - WING_PIVOT).rotated(angle), vein, 1.0)


# --- inner nodes --------------------------------------------------------------------

## Boss-owned hazard: shows a warning for `warn` s, hurts for `live` s, then frees
## itself. A charged floor lane (thin strip) or a lightning column (`bolt`).
class BeatHazard extends "res://scripts/level/damage_zone.gd":
	const LayerBits = preload("res://scripts/core/layers.gd")
	const VOLT := Color("efcf5f")
	const MARK := Color("e34f5b")

	var rects: Array = []
	var warn := 0.6
	var live := 0.6
	var bolt := false
	var floor_y := 0.0
	var _t := 0.0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		super()
		add_to_group("boss_hazard")
		add_to_group("pulse_cicada_hazard")
		collision_layer = 0
		collision_mask = 0
		for r in rects:
			var cs := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = r.size
			cs.shape = shape
			cs.position = r.get_center()
			add_child(cs)

	func is_live() -> bool:
		return _t >= warn

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t >= warn + live:
			queue_free()
			return
		collision_layer = LayerBits.HAZARD if is_live() else 0
		queue_redraw()

	func _draw() -> void:
		for r in rects:
			if bolt:
				_draw_bolt(r)
			else:
				_draw_lane(r)

	func _draw_lane(r: Rect2) -> void:
		var base_y: float = r.end.y
		if not is_live():
			var k := _t / warn
			var on := int(_t * 18.0) % 2 == 0
			draw_rect(Rect2(r.position.x, base_y - 2.0, r.size.x, 2.0), Color(VOLT, 0.25 + 0.4 * k))
			var x := r.position.x + 3.0
			var i := 0
			while x < r.end.x - 2.0:
				if on or i % 2 == 0:
					draw_line(Vector2(x, base_y - 1.0), Vector2(x + 1.5, base_y - 2.0 - 3.0 * k), Color(VOLT, 0.7), 1.0)
				x += 6.0
				i += 1
			return
		draw_rect(Rect2(r.position.x, base_y - 10.0, r.size.x, 10.0), Color(VOLT, 0.16))
		var pts := PackedVector2Array()
		var x2 := r.position.x
		while x2 <= r.end.x:
			pts.append(Vector2(x2, base_y - _rng.randf_range(1.0, 8.0)))
			x2 += 4.0
		draw_polyline(pts, VOLT, 2.0)
		draw_polyline(pts, Color.WHITE, 1.0)

	func _draw_bolt(r: Rect2) -> void:
		var cx := r.get_center().x
		var top := r.position.y
		var bottom := r.end.y
		if not is_live():
			var k := clampf(_t / warn, 0.0, 1.0)
			# Dashed guide fills from the ceiling down as the strike charges.
			var y := top
			while y < bottom:
				var filled := y < top + (bottom - top) * k
				draw_line(Vector2(cx, y), Vector2(cx, minf(y + 5.0, bottom)), Color(VOLT, 0.55 if filled else 0.18), 1.0)
				y += 9.0
			# Floor reticle.
			var blink := 0.5 + 0.5 * float(int(_t * 12.0) % 2)
			var hw := r.size.x / 2.0
			var c := Color(MARK, 0.5 + 0.5 * blink * k)
			draw_line(Vector2(cx - hw, bottom - 1.0), Vector2(cx - hw + 5.0, bottom - 1.0), c, 2.0)
			draw_line(Vector2(cx + hw, bottom - 1.0), Vector2(cx + hw - 5.0, bottom - 1.0), c, 2.0)
			draw_line(Vector2(cx - hw, bottom - 1.0), Vector2(cx - hw, bottom - 6.0), c, 2.0)
			draw_line(Vector2(cx + hw, bottom - 1.0), Vector2(cx + hw, bottom - 6.0), c, 2.0)
			draw_arc(Vector2(cx, bottom - 3.0), 4.0 + 8.0 * (1.0 - k), 0.0, TAU, 16, Color(MARK, 0.6), 1.0)
			return
		draw_rect(Rect2(cx - r.size.x / 2.0, top, r.size.x, bottom - top), Color(VOLT, 0.12))
		var pts := PackedVector2Array()
		var y2 := top
		while y2 < bottom:
			pts.append(Vector2(cx + _rng.randf_range(-6.0, 6.0), y2))
			y2 += 12.0
		pts.append(Vector2(cx, bottom))
		draw_polyline(pts, VOLT, 4.0)
		draw_polyline(pts, Color.WHITE, 1.5)
		draw_circle(Vector2(cx, bottom - 2.0), 7.0, Color(VOLT, 0.6))


## The two lattice pylons the cicada clings to, plus a sagging cable. Drawn behind
## the level (child of the boss, counter-moved so it stays put in level space).
class ArenaDecor extends Node2D:
	var arena := Rect2()

	func _draw() -> void:
		var rail := Color("1c375b")
		var brace := Color("00b8be", 0.2)
		for s in [-1, 1]:
			var x: float = arena.position.x + 2.0 if s < 0 else arena.end.x - 12.0
			draw_rect(Rect2(x, arena.position.y, 2.0, arena.size.y), rail)
			draw_rect(Rect2(x + 8.0, arena.position.y, 2.0, arena.size.y), rail)
			var y := arena.position.y
			while y < arena.end.y:
				draw_line(Vector2(x + 1.0, y), Vector2(x + 9.0, y + 16.0), brace, 1.0)
				draw_line(Vector2(x + 9.0, y), Vector2(x + 1.0, y + 16.0), brace, 1.0)
				y += 16.0
			# insulator discs below the perch
			for i in 3:
				draw_rect(Rect2(x - 1.0, arena.end.y - 30.0 + i * 5.0, 12.0, 3.0), Color("d7edf3", 0.25))
		var pts := PackedVector2Array()
		for i in 25:
			var k := i / 24.0
			pts.append(Vector2(lerpf(arena.position.x + 7.0, arena.end.x - 7.0, k),
					arena.position.y + 10.0 + sin(k * PI) * 20.0))
		draw_polyline(pts, Color("00b8be", 0.3), 1.0)
