extends "res://scripts/enemies/boss_base.gd"
## SOLAR FENNEC — boss of the desert solar power plant (GDD v0.2 §5-1).
## A fennec-fox robot whose oversized ears are solar panels. Every attack is
## telegraphed and every one can be beaten with the plain buster:
##   SAND DASH    crouch + sand kick -> dash along the floor to the far wall and
##                skid. Jump over it. Phase 2: dashes there and back, faster.
##   HEAT MIRAGE  shimmering crouch -> dash; 2 (phase 2: 3) heat-mirage
##                afterimages wait at the start, then replay the dash one by one
##                while the fennec vents heat at the far wall (open to shots).
##   SUN PILLARS  ears charge -> floor markers -> light pillars drop from the
##                ceiling. Phase 1: 3 pillars around IX. Phase 2: 3 waves across
##                the whole floor, each re-aimed at IX (step aside every wave).
##   SOLAR LANCE  phase 2 only. From a wall, 3 horizontal beams with a visible
##                aim line: low beams are jumped, high beams are walked under.
## HP <= 50%: SOLAR FLARE pose (hazards cleared), then phase 2.
## Weakness GRAVITY WING lifts it off the sand: the pattern is interrupted into a
## short float-and-drop recovery, at most once per `stagger_cooldown`.

const DamageZone = preload("res://scripts/level/damage_zone.gd")

enum S { INTRO, IDLE, HOP, DASH_WIND, DASH, SKID, VENT, MIRAGE_WIND, PILLAR_CHARGE, PILLARS,
		LANCE_CHARGE, LANCE, FLARE, STAGGER }

## Body centre to the sand (the boss stands with its centre this far above the floor).
const FEET := 12.0
const GRAVITY := 900.0
const WALL_MARGIN := 16.0
const SKID_DIST := 34.0
const HOP_HEIGHT := 64.0
## Tunables indexed by int(phase2).
const DASH_SPEED := [290.0, 350.0]
const DASH_WIND_TIME := [0.6, 0.42]
const MIRAGE_WIND_TIME := 0.8
const MIRAGE_COUNT := [2, 3]
const MIRAGE_FIRST := [0.85, 0.75]
const MIRAGE_GAP := [0.95, 0.8]
const PILLAR_CHARGE_TIME := [0.75, 0.55]
const PILLAR_WARN := [0.75, 0.7]
const PILLAR_WAVES := [1, 3]
const IDLE_TIME := [0.6, 0.4]
const PILLAR_ON := 0.42
const PILLAR_FADE := 0.2
const PILLAR_WAVE_GAP := 0.8
const PILLAR_SPACING := 96.0
const PILLAR_W := 26.0
const PILLAR_HIT_W := 20.0
const LANCE_WARN := 0.6
const LANCE_ON := 0.35
const LANCE_GAP := 0.25
const BEAM_H := 8.0
## Beam centre heights above the sand: LOW is jumped over, HIGH passes over a standing IX.
const LOW_BEAM := 9.0
const HIGH_BEAM := 36.0
const STAGGER_TIME := 1.0
const STAGGER_LIFT := 0.45
## Panel ears: [base, tip] in body space (facing right), and half the base width.
const EAR_BACK := [Vector2(8, -8), Vector2(-1, -28)]
const EAR_FRONT := [Vector2(14, -9), Vector2(21, -30)]
const EAR_HALF_W := 6.5

const C_SAND := Color("d9a560")
const C_SAND_LIGHT := Color("ecc888")
const C_SAND_DARK := Color("a8743a")
const C_NAVY := Color("1c375b")
const C_INK := Color("101b36")
const C_CYAN := Color("00b8be")
const C_PURPLE := Color("6543a2")
const C_RED := Color("e34f5b")
const C_GOLD := Color("f0b84a")
const C_PALE := Color("d7edf3")
const C_HEAT := Color("ef9352")
const C_GRAVITY := Color("8397f1")
# Drawing-only shades (body regions; the Actors shader adds outline and edges).
const C_PANEL := Color("2a5c9a")
const C_LEG := Color("2c4f7c")
const C_LEG_FAR := Color("152540")
const C_PAW := Color("8a9bb4")
const C_PAW_FAR := Color("3b4a66")
const C_GLINT := Color("fffbea")


class Mirage:
	var x := 0.0
	var dir := 1.0
	var stop := 0.0
	var delay := 0.0
	var t := 0.0
	var phase := 0  # 0 shimmer at the start (harmless), 1 dashing, 2 fading
	var zone: Area2D = null


class Pillar:
	var x := 0.0
	var t := 0.0
	var zone: Area2D = null


var state := S.INTRO
## Current attack: "dash", "mirage", "pillars", "lance" or "" (idle / recovery).
var pattern := ""
var stagger_count := 0

var _timer := 0.0
var _vx := 0.0
var _vy := 0.0
var _landed := false
var _ears := 0.0
var _ear_tilt := 0.0
var _glow := 0.0
var _crouch := 0.0
var _flare := 0.0
var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
var _hop_t := 0.0
var _hop_time := 0.6
var _after_hop := ""
var _mirage := false
var _dash_stop := 0.0
var _dashes_left := 0
var _waves_left := 0
var _wave_timer := 0.0
var _beams: Array = []
var _beam_t := 0.0
var _beam_zone: Area2D = null
var _mirages: Array = []
var _pillars: Array = []
var _zones: Array = []
var _bag: Array = []
var _last := ""


func _init() -> void:
	boss_name = "SOLAR FENNEC"
	max_hp = 48  # was 32 (balance pass, docs/balance.md): always exposed, died in ~9 s
	weakness = "gravity_wing"
	weak_mult = 5.0  # was 2.5: one slow Gravity Wing orb at a time was slower than the buster
	contact_damage = 3
	hit_radius = 14.0
	intro_time = 1.4


func _boss_ready() -> void:
	state = S.INTRO
	facing = -1.0 if player_pos().x < position.x else 1.0


func _exit_tree() -> void:
	_clear_hazards()


# --- intro / phase hooks ---------------------------------------------------------------

## Drops from the spawn marker, lands in a sand puff and unfolds its panel ears.
func _boss_intro(delta: float) -> void:
	if not _landed:
		_vy = minf(_vy + GRAVITY * delta, 420.0)
		position.y += _vy * delta
		if position.y >= _ground_y():
			position.y = _ground_y()
			_landed = true
			_vy = 0.0
			fx(Vector2(position.x, floor_y() - 2.0), 12.0)
	else:
		_ears = minf(_ears + delta * 2.2, 1.0)
	position.x = clampf(position.x, arena.position.x + 14.0, arena.end.x - 14.0)


func _on_active() -> void:
	_landed = true
	_ears = 1.0
	_vy = 0.0
	position.y = _ground_y()
	_idle(0.5)


func _on_phase2() -> void:
	_clear_hazards()
	_bag.push_front("lance")
	pattern = ""
	state = S.FLARE
	_timer = 0.9
	_flare = 0.9
	_vx = 0.0
	_vy = 0.0
	_crouch = 0.0


## Gravity Wing: hazards vanish, the fennec floats up helplessly and drops.
func _on_stagger() -> void:
	_clear_hazards()
	stagger_count += 1
	pattern = ""
	state = S.STAGGER
	_timer = STAGGER_TIME
	_vx = 0.0
	_vy = -150.0
	_crouch = 0.0
	_glow = 0.0
	_mirage = false
	_dashes_left = 0


func _on_death() -> void:
	_clear_hazards()


# --- fight ---------------------------------------------------------------------------

func _boss_process(delta: float) -> void:
	_flare = maxf(_flare - delta, 0.0)
	match state:
		S.IDLE:
			_face_player()
			_relax(delta)
			_timer -= delta
			if _timer <= 0.0:
				_next_pattern()
		S.HOP:
			_process_hop(delta)
		S.DASH_WIND, S.MIRAGE_WIND:
			_crouch = move_toward(_crouch, 1.0, delta * 6.0)
			_ear_tilt = move_toward(_ear_tilt, 1.0, delta * 5.0)
			_timer -= delta
			if _timer <= 0.0:
				_begin_dash()
		S.DASH:
			position.x += _vx * delta
			if (_dash_stop - position.x) * facing <= SKID_DIST:
				state = S.SKID
		S.SKID:
			_process_skid(delta)
		S.VENT:
			_relax(delta)
			if _mirages.is_empty():
				_idle(IDLE_TIME[_p()])
		S.PILLAR_CHARGE:
			_glow = move_toward(_glow, 1.0, delta * 2.5)
			_ear_tilt = move_toward(_ear_tilt, -0.3, delta * 3.0)
			_timer -= delta
			if _timer <= 0.0:
				state = S.PILLARS
				_waves_left = PILLAR_WAVES[_p()]
				_wave_timer = 0.0
		S.PILLARS:
			_process_pillars(delta)
		S.LANCE_CHARGE:
			_glow = move_toward(_glow, 1.0, delta * 3.0)
			_ear_tilt = move_toward(_ear_tilt, -0.6, delta * 3.0)
			_timer -= delta
			if _timer <= 0.0:
				state = S.LANCE
				_beam_t = 0.0
		S.LANCE:
			_process_lance(delta)
		S.FLARE:
			_glow = 1.0
			_fall(delta)
			_timer -= delta
			if _timer <= 0.0 and _on_ground():
				_idle(0.3)
		S.STAGGER:
			_process_stagger(delta)
	_update_mirages(delta)
	_clamp()


## Shuffled bag: every pattern once per cycle, never the same one twice in a row.
func _next_pattern() -> void:
	if _bag.is_empty():
		_bag = ["dash", "mirage", "pillars"]
		if phase2:
			_bag.append("lance")
		for i in range(_bag.size() - 1, 0, -1):
			var j := rng().randi_range(0, i)
			var tmp = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
		if _bag[0] == _last:
			_bag.append(_bag.pop_front())
	var next: String = _bag.pop_front()
	_last = next
	_start_pattern(next)


func _start_pattern(name: String, hopped := false) -> void:
	pattern = name
	_mirage = name == "mirage"
	match name:
		"dash", "mirage":
			var dir := _dir_to_player()
			if not hopped and absf(_wall_x(dir) - position.x) < 120.0:
				_hop(_far_wall_x(), name)  # too close to run: reposition first
				return
			facing = dir
			_dashes_left = 2 if phase2 and not _mirage else 1
			state = S.MIRAGE_WIND if _mirage else S.DASH_WIND
			_timer = MIRAGE_WIND_TIME if _mirage else DASH_WIND_TIME[_p()]
		"pillars":
			_face_player()
			state = S.PILLAR_CHARGE
			_timer = PILLAR_CHARGE_TIME[_p()]
		"lance":
			var wall := _far_wall_x()
			if not hopped and absf(wall - position.x) > 24.0:
				_hop(wall, name)
				return
			facing = 1.0 if position.x < arena.get_center().x else -1.0
			state = S.LANCE_CHARGE
			_timer = 0.55
			_beams = [LOW_BEAM, HIGH_BEAM, LOW_BEAM] if rng().randf() < 0.5 \
					else [HIGH_BEAM, LOW_BEAM, HIGH_BEAM]
			_beam_t = 0.0
		_:
			_idle(0.3)


func _idle(time: float) -> void:
	state = S.IDLE
	pattern = ""
	_timer = time
	_mirage = false
	_dashes_left = 0


func _hop(x: float, next: String) -> void:
	state = S.HOP
	_hop_from = position
	_hop_to = Vector2(clampf(x, arena.position.x + WALL_MARGIN, arena.end.x - WALL_MARGIN), _ground_y())
	_hop_t = 0.0
	_hop_time = 0.5 + absf(_hop_to.x - _hop_from.x) / 1000.0
	_after_hop = next
	if absf(_hop_to.x - position.x) > 1.0:
		facing = signf(_hop_to.x - position.x)


func _process_hop(delta: float) -> void:
	_hop_t += delta
	var k := clampf(_hop_t / _hop_time, 0.0, 1.0)
	position = _hop_from.lerp(_hop_to, k) + Vector2(0, -sin(k * PI) * HOP_HEIGHT)
	_ear_tilt = move_toward(_ear_tilt, 0.6, delta * 4.0)
	_crouch = move_toward(_crouch, 0.0, delta * 6.0)
	if k >= 1.0:
		position = _hop_to
		fx(Vector2(position.x, floor_y() - 2.0), 7.0)
		var next := _after_hop
		_after_hop = ""
		_start_pattern(next, true)


func _begin_dash() -> void:
	state = S.DASH
	_vx = facing * _dash_speed()
	_dash_stop = _wall_x(facing)
	_crouch = 0.6
	if not _mirage:
		return
	for k in MIRAGE_COUNT[_p()]:
		var m := Mirage.new()
		m.x = position.x
		m.dir = facing
		m.stop = _dash_stop
		m.delay = MIRAGE_FIRST[_p()] + MIRAGE_GAP[_p()] * k
		_mirages.append(m)


func _process_skid(delta: float) -> void:
	var speed := _dash_speed()
	_vx = move_toward(_vx, 0.0, speed * speed / (2.0 * SKID_DIST) * delta)
	position.x += _vx * delta
	var past := (position.x - _dash_stop) * facing >= 0.0
	if past:
		position.x = _dash_stop
	if not past and _vx != 0.0:
		return
	_vx = 0.0
	if _mirage:
		state = S.VENT  # wait at the wall while the afterimages replay the dash
		facing = -facing
	elif _dashes_left > 1:
		_dashes_left -= 1
		facing = -facing
		state = S.DASH_WIND
		_timer = 0.3
	else:
		_idle(IDLE_TIME[_p()])


func _update_mirages(delta: float) -> void:
	for m in _mirages.duplicate():
		m.t += delta
		match m.phase:
			0:
				if m.t >= m.delay:
					m.phase = 1
					m.zone = _zone(_body_rect(m.x), 2)
			1:
				m.x += m.dir * _dash_speed() * delta
				if (m.stop - m.x) * m.dir <= 0.0:
					m.x = m.stop
					m.phase = 2
					m.t = 0.0
					_drop_zone(m.zone)
					m.zone = null
				elif is_instance_valid(m.zone):
					m.zone.position = _body_rect(m.x).get_center()
			2:
				if m.t >= 0.3:
					_mirages.erase(m)


func _process_pillars(delta: float) -> void:
	_wave_timer -= delta
	if _waves_left > 0 and _wave_timer <= 0.0:
		_spawn_wave()
		_waves_left -= 1
		_wave_timer = PILLAR_WAVE_GAP
	var warn: float = PILLAR_WARN[_p()]
	for p in _pillars.duplicate():
		p.t += delta
		if p.zone == null and p.t >= warn and p.t < warn + PILLAR_ON:
			p.zone = _zone(Rect2(p.x - PILLAR_HIT_W / 2.0, arena.position.y, PILLAR_HIT_W, arena.size.y), 3)
			fx(Vector2(p.x, floor_y() - 3.0), 8.0)
		elif p.zone != null and p.t >= warn + PILLAR_ON:
			_drop_zone(p.zone)
			p.zone = null
		if p.t >= warn + PILLAR_ON + PILLAR_FADE:
			_pillars.erase(p)
	if _waves_left == 0 and _pillars.is_empty():
		_idle(IDLE_TIME[_p()])


## Phase 1: three pillars on and around IX. Phase 2: a full-width row aimed at IX.
func _spawn_wave() -> void:
	var lo := arena.position.x + PILLAR_W / 2.0
	var hi := arena.end.x - PILLAR_W / 2.0
	var px := clampf(_player_x(), lo, hi)
	var xs: Array = []
	if phase2:
		for k in range(-4, 5):
			var x: float = px + PILLAR_SPACING * k
			if x >= lo - 4.0 and x <= hi + 4.0:
				xs.append(clampf(x, lo, hi))
	else:
		xs.append(px)
		for side in [-1.0, 1.0]:
			var x: float = px + side * PILLAR_SPACING
			if x < lo or x > hi:
				x = px - side * PILLAR_SPACING * 2.0  # no room on this side: go the other way
			xs.append(clampf(x, lo, hi))
	for x in xs:
		var p := Pillar.new()
		p.x = x
		_pillars.append(p)


func _process_lance(delta: float) -> void:
	_beam_t += delta
	if _beams.is_empty():
		_idle(IDLE_TIME[_p()])
		return
	var h: float = _beams[0]
	if _beam_zone == null and _beam_t >= LANCE_WARN and _beam_t < LANCE_WARN + LANCE_ON:
		_beam_zone = _zone(_beam_rect(h), 3)
	elif _beam_t >= LANCE_WARN + LANCE_ON:
		_drop_zone(_beam_zone)
		_beam_zone = null
		_beams.pop_front()
		_beam_t = -LANCE_GAP
		if _beams.is_empty():
			_idle(IDLE_TIME[_p()])


func _process_stagger(delta: float) -> void:
	_timer -= delta
	if _timer > STAGGER_TIME - STAGGER_LIFT:
		_vy = move_toward(_vy, 0.0, 330.0 * delta)
		position.y += _vy * delta
	else:
		_fall(delta)
	if _timer <= 0.0 and _on_ground():
		_idle(0.35)


# --- hazards -----------------------------------------------------------------------------

## A damaging area in the parent's (level) space, on the hazard layer the player's
## hurtbox watches (group "damaging" via DamageZone).
func _zone(rect: Rect2, damage: int) -> Area2D:
	var z := DamageZone.new()
	z.damage = damage
	z.collision_layer = Layers.HAZARD
	z.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	z.add_child(cs)
	z.position = rect.get_center()
	get_parent().add_child(z)
	_zones.append(z)
	return z


func _drop_zone(z) -> void:
	if z != null and is_instance_valid(z):
		z.queue_free()
	_zones.erase(z)


func _clear_hazards() -> void:
	for z in _zones:
		if is_instance_valid(z):
			z.queue_free()
	_zones.clear()
	_mirages.clear()
	_pillars.clear()
	_beams.clear()
	_beam_zone = null
	_waves_left = 0


func _body_rect(x: float) -> Rect2:
	return Rect2(x - 11.0, _ground_y() - 11.0, 22.0, 22.0)


func _beam_rect(h: float) -> Rect2:
	var y := floor_y() - h - BEAM_H / 2.0
	if facing > 0.0:
		var x0 := position.x + 16.0
		return Rect2(x0, y, arena.end.x - x0, BEAM_H)
	return Rect2(arena.position.x, y, position.x - 16.0 - arena.position.x, BEAM_H)


# --- helpers -----------------------------------------------------------------------------

func _p() -> int:
	return 1 if phase2 else 0


func _dash_speed() -> float:
	return DASH_SPEED[_p()]


func _ground_y() -> float:
	return floor_y() - FEET


func _on_ground() -> bool:
	return position.y >= _ground_y() - 0.5


func _fall(delta: float) -> void:
	if _on_ground():
		_vy = 0.0
		position.y = _ground_y()
		return
	_vy = minf(_vy + GRAVITY * delta, 420.0)
	position.y = minf(position.y + _vy * delta, _ground_y())


func _clamp() -> void:
	position.x = clampf(position.x, arena.position.x + 14.0, arena.end.x - 14.0)
	position.y = clampf(position.y, arena.position.y + 34.0, _ground_y())


func _relax(delta: float) -> void:
	_crouch = move_toward(_crouch, 0.0, delta * 4.0)
	_ear_tilt = move_toward(_ear_tilt, 0.0, delta * 3.0)
	_glow = move_toward(_glow, 0.25 if phase2 else 0.0, delta * 2.0)


func _player_x() -> float:
	return player_pos().x


func _dir_to_player() -> float:
	var d := _player_x() - position.x
	return facing if absf(d) < 1.0 else signf(d)


func _face_player() -> void:
	facing = _dir_to_player()


func _wall_x(dir: float) -> float:
	return arena.end.x - WALL_MARGIN if dir > 0.0 else arena.position.x + WALL_MARGIN


## The wall farther from IX (where the fennec sets up ranged attacks).
func _far_wall_x() -> float:
	return _wall_x(1.0 if _player_x() < arena.get_center().x else -1.0)


# --- drawing -----------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	_draw_pillars()
	for m in _mirages:
		_draw_mirage(m)
	_draw_lance()
	# shadow on the sand (reads the hop / lift height)
	var shadow_y := floor_y() - position.y
	draw_set_transform(Vector2(0, shadow_y - 1.0), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_dust()
	if state == S.STAGGER:
		_draw_gravity_rings(false)
	var charge := _glow if state in [S.PILLAR_CHARGE, S.LANCE_CHARGE, S.FLARE] else 0.0
	_draw_fennec(Vector2.ZERO, facing, _crouch, _ear_tilt, _glow, white, Color(0, 0, 0, 0), 1.0,
			lerpf(0.35, 1.0, _ears), charge)
	if state in [S.MIRAGE_WIND, S.VENT]:
		_draw_heat(Vector2(0, -14), 0.7)
	if state == S.STAGGER:
		_draw_gravity_rings(true)
	if _flare > 0.0:
		var k := 1.0 - _flare / 0.9
		draw_arc(Vector2(0, -10), 10.0 + k * 70.0, 0.0, TAU, 32, Color(C_GOLD, 1.0 - k), 3.0)
		draw_arc(Vector2(0, -10), 6.0 + k * 40.0, 0.0, TAU, 24, Color(C_HEAT, 1.0 - k), 2.0)


## The fennec around `o`, facing `dir`. `tint` (alpha > 0) draws a one-colour
## silhouette (heat mirages). `ears` scales the panel ears (folded in the intro).
## Flat-colour regions; the Actors shader adds the outline and edge light/shadow.
func _draw_fennec(o: Vector2, dir: float, crouch: float, tilt: float, glow: float, white: bool,
		tint: Color, alpha: float, ears := 1.0, charge := 0.0) -> void:
	draw_set_transform(o + Vector2(0, crouch * 3.0), 0.0, Vector2(dir, 1.0 - crouch * 0.12))
	var col := func(c: Color) -> Color:
		if white:
			return Color(1, 1, 1, alpha)
		if tint.a > 0.0:
			return Color(tint, tint.a * alpha)
		return Color(c, c.a * alpha)
	# Silhouettes (hit flash, mirages) skip the inner detail regions so the
	# translucent layers do not stack up.
	var detail := not white and tint.a <= 0.0
	var run := sin(t * 30.0) * 3.0 if state in [S.DASH, S.SKID] or tint.a > 0.0 else 0.0
	# far legs and back ear (behind the body)
	for lx in [-4.0, 9.0]:
		_fennec_leg(lx, -run if lx < 0.0 else run, false, col)
	_draw_ear(EAR_BACK[0], EAR_BACK[1], tilt, glow, ears, false, detail, col)
	# tail: bushy two-tone brush with a pale tip
	var sway := sin(t * 6.0) * 1.5
	_poly([Vector2(-10, 1), Vector2(-16, -3 + sway), Vector2(-22, -9 + sway), Vector2(-24, -3 + sway),
			Vector2(-20, 4), Vector2(-14, 7), Vector2(-10, 6)], col.call(C_SAND_DARK))
	if detail:
		_poly([Vector2(-10, 1), Vector2(-16, -3 + sway), Vector2(-21, -8 + sway), Vector2(-20, -4 + sway),
				Vector2(-15, 1), Vector2(-10, 3)], col.call(C_SAND))
	_poly([Vector2(-20, -5 + sway), Vector2(-22, -10 + sway), Vector2(-25, -6 + sway),
			Vector2(-24, -1 + sway), Vector2(-21, -1 + sway)], col.call(C_PALE))
	# body: sand side, dark belly, navy saddle with a cyan cell strip, purple collar
	_poly([Vector2(-14, 2), Vector2(-11, -4), Vector2(-3, -6), Vector2(8, -5), Vector2(12, 0),
			Vector2(10, 6), Vector2(-11, 7)], col.call(C_SAND))
	if detail:
		_poly([Vector2(-14, 3), Vector2(-8, 3), Vector2(4, 3), Vector2(11, 2), Vector2(10, 6),
				Vector2(-11, 7)], col.call(C_SAND_DARK))
		_poly([Vector2(-10, -5), Vector2(-3, -7), Vector2(5, -6), Vector2(4, 0), Vector2(-9, 0)],
				col.call(C_NAVY))
		draw_rect(Rect2(-7, -4, 9, 2), col.call(C_CYAN))
		draw_rect(Rect2(-7, -4, 2, 1), col.call(C_GLINT))
		_poly([Vector2(5, -6), Vector2(9, -7), Vector2(12, -1), Vector2(10, 3), Vector2(7, 2)],
				col.call(C_PURPLE))
		draw_rect(Rect2(9, 0, 2, 2), col.call(C_GOLD))
	# near legs (over the belly)
	for lx in [-8.0, 5.0]:
		_fennec_leg(lx, run if lx < 0.0 else -run, true, col)
	# front solar-panel ear (behind the head)
	_draw_ear(EAR_FRONT[0], EAR_FRONT[1], tilt, glow, ears, true, detail, col)
	# head: light skull, sand jaw, pale throat ruff, slanted visor eye, nose
	_poly([Vector2(7, -8), Vector2(13, -11), Vector2(17, -8), Vector2(22, -4), Vector2(22, -2),
			Vector2(17, 0), Vector2(11, 1), Vector2(7, -3)], col.call(C_SAND_LIGHT))
	if detail:
		_poly([Vector2(14, -2), Vector2(22, -2), Vector2(17, 0), Vector2(14, 0)], col.call(C_SAND))
		_poly([Vector2(8, -3), Vector2(13, -3), Vector2(15, 0), Vector2(11, 1), Vector2(8, 0)],
				col.call(C_PALE))
		_poly([Vector2(10, -9), Vector2(17, -7), Vector2(17, -4), Vector2(10, -6)], col.call(C_INK))
		_poly([Vector2(11, -8), Vector2(16, -6.5), Vector2(16, -5), Vector2(11, -6.5)],
				col.call(C_GOLD if glow > 0.6 else C_RED))
		draw_rect(Rect2(11, -8, 1, 1), col.call(C_GLINT))
		draw_rect(Rect2(20, -5, 3, 3), col.call(C_INK))
		draw_rect(Rect2(20, -5, 1, 1), col.call(C_PALE))
	if charge > 0.0 and tint.a <= 0.0:
		var tip := _ear_tip(EAR_FRONT[0], EAR_FRONT[1], tilt, ears)
		for i in 6:
			var k := fmod(t * 2.5 + i / 6.0, 1.0)
			var at := tip + Vector2.from_angle(i * TAU / 6.0 + t * 3.0) * 18.0 * (1.0 - k)
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), Color(C_GOLD, charge * k))
		draw_circle(tip, 2.0 + charge * 2.0, Color(1.0, 0.95, 0.75, charge * 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _poly(pts: Array, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), c)


## One leg at body x `lx`, swung by `swing` (running scissor): navy shin and a paw.
func _fennec_leg(lx: float, swing: float, near: bool, col: Callable) -> void:
	draw_line(Vector2(lx, 3), Vector2(lx + swing, FEET - 2.0), col.call(C_LEG if near else C_LEG_FAR), 3.0)
	draw_rect(Rect2(lx + swing - 2.0, FEET - 2.0, 5, 2), col.call(C_PAW if near else C_PAW_FAR))


## Ear tip after the sweep (`tilt` > 0 lays the ear back) and the intro fold (`ears`).
func _ear_tip(base: Vector2, tip: Vector2, tilt: float, ears: float) -> Vector2:
	return base + ((tip - base) * ears).rotated(-tilt)


## A triangular solar-panel ear: navy panel with checkered lighter cells and a
## cyan grid (all fill with gold as the ears charge), glint, gold / heat rim.
func _draw_ear(base: Vector2, tip: Vector2, tilt: float, glow: float, ears: float, front: bool,
		detail: bool, col: Callable) -> void:
	var tip_r := _ear_tip(base, tip, tilt, ears)
	var axis := (tip_r - base).normalized()
	var side := Vector2(-axis.y, axis.x) * EAR_HALF_W
	var at := func(k: float, w: float) -> Vector2: return base.lerp(tip_r, k) + side * (w * (1.0 - k))
	var dim := 0.0 if front else 0.3
	var pts := PackedVector2Array([base - side, tip_r, base + side])
	draw_colored_polygon(pts, col.call(C_NAVY.darkened(dim).lerp(C_GOLD, glow * 0.65)))
	if detail:
		var cell := C_PANEL.darkened(dim).lerp(C_GOLD, glow * 0.75)
		for c in [[0.0, 0.3, 0.0, 1.0], [0.3, 0.55, -1.0, 0.0], [0.55, 0.78, 0.0, 1.0]]:
			_poly([at.call(c[0], c[2]), at.call(c[0], c[3]), at.call(c[1], c[3]), at.call(c[1], c[2])],
					col.call(cell))
		var grid: Color = col.call(C_CYAN.darkened(dim))
		for k: float in [0.3, 0.55, 0.78]:
			draw_line(at.call(k, -1.0), at.call(k, 1.0), grid, 1.0)
		draw_line(base, base.lerp(tip_r, 0.9), grid, 1.0)
		if front:
			draw_line(at.call(0.12, -0.5), at.call(0.24, -0.2), col.call(C_GLINT), 1.0)
			draw_line(at.call(0.4, 0.5), at.call(0.48, 0.25), col.call(C_GLINT), 1.0)
		pts.append(base - side)
		draw_polyline(pts, col.call(C_HEAT if phase2 else C_GOLD), 1.0)


func _draw_mirage(m) -> void:
	var o := Vector2(m.x - position.x, _ground_y() - position.y)
	var a := 0.55
	match m.phase:
		0:
			a = 0.25 + 0.2 * float(int(t * 14.0) % 2)
		2:
			a = 0.55 * (1.0 - m.t / 0.3)
	_draw_fennec(o, m.dir, 0.6 if m.phase == 0 else 0.3, 0.9, 0.0, false, Color(C_HEAT, 1.0), a)
	if m.phase == 0:
		_draw_heat(o + Vector2(0, -14), a)
	elif m.phase == 1:
		for i in 3:
			var tx: float = o.x - m.dir * (12.0 + i * 9.0)
			draw_line(Vector2(tx, o.y - 4.0 + i * 3.0), Vector2(tx - m.dir * 8.0, o.y - 4.0 + i * 3.0),
					Color(C_HEAT, a * 0.6), 1.0)


## Wavy heat-shimmer lines rising from `o`.
func _draw_heat(o: Vector2, alpha: float) -> void:
	for i in 3:
		var pts := PackedVector2Array()
		var x0 := -8.0 + i * 8.0
		for j in 5:
			var y := -j * 5.0 - fmod(t * 20.0, 5.0)
			pts.append(o + Vector2(x0 + sin(t * 9.0 + j + i) * 2.0, y))
		draw_polyline(pts, Color(C_HEAT, alpha * 0.6), 1.0)


func _draw_pillars() -> void:
	if _pillars.is_empty():
		return
	var warn: float = PILLAR_WARN[_p()]
	var top := arena.position.y - position.y
	var bottom := arena.end.y - position.y
	var blink := float(int(t * 16.0) % 2)
	for p in _pillars:
		var x: float = p.x - position.x
		var pt: float = p.t
		if pt < warn:
			var k := pt / warn
			draw_rect(Rect2(x - PILLAR_W * 0.5 * k, top, PILLAR_W * k, bottom - top), Color(C_GOLD, 0.1))
			draw_line(Vector2(x, top), Vector2(x, bottom), Color(C_GOLD, 0.3 + 0.3 * blink), 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 8, bottom - 1), Vector2(x, bottom - 5),
					Vector2(x + 8, bottom - 1), Vector2(x, bottom + 1)]), Color(C_RED, 0.5 + 0.4 * blink))
			draw_circle(Vector2(x, top + 4.0), 2.0 + 3.0 * k, Color(C_GOLD, 0.8))
		elif pt < warn + PILLAR_ON:
			var w := PILLAR_W + sin(t * 50.0) * 2.0
			draw_rect(Rect2(x - w / 2.0, top, w, bottom - top), Color(C_GOLD, 0.85))
			draw_rect(Rect2(x - 4.0, top, 8.0, bottom - top), Color(1.0, 0.97, 0.85))
			draw_circle(Vector2(x, bottom - 2.0), 12.0, Color(C_HEAT, 0.6))
		else:
			var f := 1.0 - (pt - warn - PILLAR_ON) / PILLAR_FADE
			draw_rect(Rect2(x - PILLAR_W * 0.25 * f, top, PILLAR_W * 0.5 * f, bottom - top),
					Color(C_GOLD, 0.5 * f))


func _draw_lance() -> void:
	if state != S.LANCE or _beams.is_empty() or _beam_t < 0.0:
		return
	var r := _beam_rect(_beams[0])
	r.position -= position
	var y := r.get_center().y
	var muzzle := Vector2(facing * 16.0, y)
	if _beam_t < LANCE_WARN:
		var blink := float(int(t * 16.0) % 2)
		var x := r.position.x
		while x < r.end.x:
			draw_line(Vector2(x, y), Vector2(minf(x + 6.0, r.end.x), y), Color(C_RED, 0.55 + 0.45 * blink), 2.0)
			x += 10.0
		draw_circle(muzzle, 2.0 + 4.0 * _beam_t / LANCE_WARN, Color(C_GOLD, 0.9))
	else:
		var wob := sin(t * 60.0)
		draw_rect(Rect2(r.position.x, y - BEAM_H / 2.0 - 1.0 - wob, r.size.x, BEAM_H + 2.0 + wob * 2.0),
				Color(C_GOLD, 0.85))
		draw_rect(Rect2(r.position.x, y - 1.5, r.size.x, 3.0), Color(1.0, 0.97, 0.85))
		draw_circle(muzzle, 7.0, Color(1.0, 0.97, 0.85))


func _draw_dust() -> void:
	var amount := 0.0
	match state:
		S.DASH_WIND, S.MIRAGE_WIND:
			amount = 0.7
		S.DASH:
			amount = 0.5
		S.SKID:
			amount = 1.0
	if amount <= 0.0:
		return
	var back := -facing if state != S.SKID else facing
	for i in 6:
		var k := fmod(t * 3.0 + i / 6.0, 1.0)
		var at := Vector2(back * (6.0 + k * 22.0), FEET - k * 9.0 - float(i % 2) * 3.0)
		draw_circle(at, 3.0 * (1.0 - k) + 0.5, Color(C_SAND, amount * 0.7 * (1.0 - k)))


func _draw_gravity_rings(front: bool) -> void:
	for i in 2:
		var k := fmod(t * 1.6 + i * 0.5, 1.0)
		var rx := 20.0 - k * 6.0
		draw_set_transform(Vector2(0, -6.0 + k * 10.0), 0.0, Vector2(1.0, 0.35))
		var start := PI if front else 0.0
		draw_arc(Vector2.ZERO, rx, start, start + PI, 16, Color(C_GRAVITY, 0.8 * (1.0 - k)), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
