extends "res://scripts/enemies/boss_base.gd"
## ARCA — final boss of EDEN CORE (GDD v0.2 §3-2): the autonomous management AI
## of the Eden Link network. "As long as free will exists, irregulars will occur."
## A hovering network core with one iris and four orbiting shield panels.
##
## Phase 1 — the panels orbit and stop buster shots. They are physical bodies on
##   the ENEMY layer that are NOT in group "enemy", so a shot that touches one just
##   bursts (like hitting a wall); shots that slip through the gaps between panels
##   still reach the core. The panels flicker, then open, whenever the eye attacks:
##     LASER   aim line tracks the player -> lock flash -> beam sweeps outward
##     RING    two offset rings of packet shots (shield open)
##     DRONES  2 drones park beside the core, blink, then dive at the player
## Phase 2 (HP <= 50%) — BREAK: the panels burst off as shrapnel and the bare core
##   roams a figure-eight. Adds:
##     SPIRAL  charge, then a 4-arm bullet spiral that reverses spin halfway
##     FIELD   floor stripes telegraphed, then electrified (boss-owned damage
##             zones), in two complementary waves; the arena ledges are safe
##   and the laser re-aims for a second, faster sweep; 3 drones.
## Every beam / field ARCA creates is in group "arca_hazard" and is freed in
## _on_death(); drones and shrapnel are enemy shots (cleared by the base class).

enum S { INTRO, IDLE, LASER_AIM, LASER_LOCK, LASER_FIRE, RING, DRONES, BREAK, SPIRAL, FIELD }

## Hover height of the core above the arena floor in phase 1 (hit from the
## ledges, or by a jump shot from the floor at the bottom of its bob).
const HOVER_HEIGHT := 94.0
const PANEL_COUNT := 4
const PANEL_R := 27.0
const PANEL_OPEN_R := 29.0
const PANEL_LEN := 26.0
const PANEL_THICK := 7.0
const PANEL_SPIN := 1.1
const VENT_WARN := 0.45
const PHASE1_ORDER := [S.LASER_AIM, S.DRONES, S.RING]
const PHASE2_POOL := [S.LASER_AIM, S.SPIRAL, S.FIELD, S.DRONES]
## Control-field stripes in arena tiles [from, to) — each wave leaves 3-tile gaps,
## and the second wave of a pair covers the first wave's gaps.
const FIELD_WAVES := [
	[[[0, 5], [8, 13], [16, 22]], [[3, 8], [13, 19]]],
	[[[0, 6], [9, 14], [17, 22]], [[4, 9], [14, 19]]],
]

const C_DEEP := Color("101b36")
const C_PANEL := Color("1c375b")
const C_CYAN := Color("00b8be")
const C_VIOLET := Color("6543a2")
const C_RED := Color("e34f5b")
const C_GOLD := Color("f0b84a")
const C_PALE := Color("d7edf3")
# Drawing-only shades (flat regions; the Actors shader adds outline and edges).
const C_SHADOW := Color("060b19")
const C_PALE_SHADE := Color("98b4c4")

var state := S.INTRO
var _timer := 0.0
var _step := 0
var _cycle := 0
var _last := -1
var _home := Vector2.ZERO
var _move_t := 0.0
var _anchor := Vector2.ZERO
var _look := Vector2.DOWN

# shield panels
var _panels: Array = []
var _panel_rot := 0.0
var _shield_open := false
var _shield_warn := 0.0
var _open_k := 1.0

# eye laser
var _beam = null
var _beam_angle := PI / 2.0
var _sweeps_left := 0

# patterns
var _spiral_angle := 0.0
var _spiral_spin := 1.0
var _emit := 0.0
var _field_set := 0
var _hazards: Array = []


func _init() -> void:
	boss_name = "ARCA"
	max_hp = 48
	weakness = ""
	contact_damage = 3
	hit_radius = 15.0
	intro_time = 1.8
	death_time = 2.4


func _boss_ready() -> void:
	_home = Vector2(arena.get_center().x, floor_y() - HOVER_HEIGHT)
	_anchor = _home
	for i in PANEL_COUNT:
		var body := StaticBody2D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		body.add_to_group("arca_panel")
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(PANEL_THICK, PANEL_LEN)
		cs.shape = rect
		body.add_child(cs)
		add_child(body)
		_panels.append(body)
	_update_panels(0.0)


## Shots that touch a panel never reach take_damage, so no damage filter is needed.
func shield_solid() -> bool:
	return active and not phase2 and not _shield_open and not _panels.is_empty()


# --- intro / main loop ----------------------------------------------------------------

## Materializes: fades in while gliding to its hover point, panels assembling.
func _boss_intro(delta: float) -> void:
	modulate.a = clampf(t / intro_time * 1.6, 0.0, 1.0)
	position = position.lerp(_home, 1.0 - exp(-2.5 * delta))
	_open_k = move_toward(_open_k, 0.0, delta * 0.7)
	_look = Vector2.DOWN
	_update_panels(delta)


func _on_active() -> void:
	modulate.a = 1.0
	_idle(0.9)


func _boss_process(delta: float) -> void:
	_timer -= delta
	if _shield_warn > 0.0:
		_shield_warn -= delta
		if _shield_warn <= 0.0:
			_shield_open = true
	_look = _look.lerp((player_pos() - position).normalized(), 1.0 - exp(-6.0 * delta))
	match state:
		S.IDLE:
			_drift(delta)
			if _timer <= 0.0:
				_next_pattern()
		S.LASER_AIM:
			_hold(delta)
			_beam_angle = clampf(lerp_angle(_beam_angle, _angle_to_player(), 1.0 - exp(-7.0 * delta)), 0.0, PI)
			_look = Vector2.from_angle(_beam_angle)
			_update_beam()
			if _timer <= 0.0:
				state = S.LASER_LOCK
				_timer = 0.3
				_beam.mode = 1
		S.LASER_LOCK:
			_hold(delta)
			_look = Vector2.from_angle(_beam_angle)
			_update_beam()
			if _timer <= 0.0:
				state = S.LASER_FIRE
				_timer = 0.9 if phase2 else 1.3
				_beam.set_live(true)
		S.LASER_FIRE:
			_hold(delta)
			# Sweep outward, away from the core's vertical: step under ARCA to dodge.
			var out := signf(_beam_angle - PI / 2.0)
			if out == 0.0:
				out = 1.0 if rng().randf() < 0.5 else -1.0
			_beam_angle = clampf(_beam_angle + out * (0.95 if phase2 else 0.55) * delta, 0.0, PI)
			_look = Vector2.from_angle(_beam_angle)
			_update_beam()
			if _timer <= 0.0:
				if _sweeps_left > 0:
					_sweeps_left -= 1
					_beam.set_live(false)
					_beam.mode = 0
					state = S.LASER_AIM
					_timer = 0.45
				else:
					_end_beam()
					_close_shield()
					_idle(0.8)
		S.RING:
			_drift(delta)
			if _step == 0 and _timer <= 1.6:
				_step = 1
				_ring(12, 0.0)
			elif _step == 1 and _timer <= 1.0:
				_step = 2
				_ring(12, PI / 12.0)
			elif _timer <= 0.0:
				_close_shield()
				_idle(0.8)
		S.DRONES:
			_drift(delta)
			if _step == 0 and _timer <= 1.2:
				_step = 1
				_launch_drones(3 if phase2 else 2)
			elif _timer <= 0.0:
				_idle(0.6)
		S.BREAK:
			position = _anchor + Vector2(rng().randf_range(-2, 2), rng().randf_range(-2, 2))
			if _step == 0 and _timer <= 0.4:
				_step = 1
				_burst_panels()
			elif _timer <= 0.0:
				_start(S.SPIRAL)
		S.SPIRAL:
			_hold(delta)
			if _timer <= 2.6 and _timer > 0.4:
				_emit -= delta
				if _emit <= 0.0:
					_emit += 0.1
					for k in 4:
						var a := _spiral_angle + k * TAU / 4.0
						shoot(position + Vector2.from_angle(a) * 14.0, Vector2.from_angle(a) * 92.0, 2)
				_spiral_angle += 2.3 * _spiral_spin * delta
				if _timer <= 1.5:
					_spiral_spin = -1.0
			elif _timer <= 0.0:
				_idle(0.7)
		S.FIELD:
			_roam(delta, 0.5, 18.0)
			if _step == 0 and _timer <= 4.2:
				_step = 1
				_field_wave(0)
			elif _step == 1 and _timer <= 2.1:
				_step = 2
				_field_wave(1)
			elif _timer <= 0.0:
				_idle(0.6)
	clamp_to_arena(22.0)
	_update_panels(delta)


func _next_pattern() -> void:
	if not phase2:
		var pick: int = PHASE1_ORDER[_cycle % PHASE1_ORDER.size()]
		_cycle += 1
		_start(pick)
		return
	var pool: Array = PHASE2_POOL.duplicate()
	pool.erase(_last)
	_start(pool[rng().randi_range(0, pool.size() - 1)])


func _start(pattern: int) -> void:
	_end_beam()
	_last = pattern
	_step = 0
	match pattern:
		S.LASER_AIM:
			_anchor = position
			state = S.LASER_AIM
			_timer = 0.6 if phase2 else 0.9
			_sweeps_left = 1 if phase2 else 0
			_beam_angle = _angle_to_player()
			_spawn_beam()
			_vent_shield()
		S.RING:
			state = S.RING
			_timer = 2.2
			_vent_shield()
		S.DRONES:
			state = S.DRONES
			_timer = 1.6
		S.SPIRAL:
			state = S.SPIRAL
			_anchor = Vector2(arena.get_center().x, floor_y() - 104.0)
			_timer = 3.2
			_spiral_angle = rng().randf() * TAU
			_spiral_spin = 1.0
			_emit = 0.0
		S.FIELD:
			state = S.FIELD
			_timer = 4.6
			_field_set = rng().randi_range(0, FIELD_WAVES.size() - 1)


func _idle(time: float) -> void:
	state = S.IDLE
	_timer = time * (0.75 if phase2 else 1.0)


# --- movement ------------------------------------------------------------------------

## Phase 1 floats around its hover point; phase 2 roams a figure-eight.
func _drift(delta: float) -> void:
	if phase2:
		_roam(delta, 1.0, 24.0)
		return
	var target := _home + Vector2(sin(t * 0.7) * 40.0, sin(t * 1.3) * 6.0)
	position = position.lerp(target, 1.0 - exp(-3.0 * delta))


## The low points (98 - depth px above the floor) sit between the two ledges, so
## a player standing on a ledge is never brushed by the roaming core.
func _roam(delta: float, speed: float, depth: float) -> void:
	_move_t += delta * speed
	var c := arena.get_center()
	var target := Vector2(c.x + sin(_move_t * 0.8) * 104.0,
			floor_y() - 98.0 + sin(_move_t * 1.6) * depth)
	position = position.lerp(target, 1.0 - exp(-2.5 * delta))


func _hold(delta: float) -> void:
	position = position.lerp(_anchor, 1.0 - exp(-4.0 * delta))


func _angle_to_player() -> float:
	var a := (player_pos() - position).angle()
	if a < -PI / 2.0:
		a += TAU  # aim above the left horizon -> treat as left
	return clampf(a, 0.0, PI)


# --- shield panels -----------------------------------------------------------------

func _vent_shield() -> void:
	if phase2 or _shield_open or _shield_warn > 0.0:
		return
	_shield_warn = VENT_WARN


func _close_shield() -> void:
	_shield_open = false
	_shield_warn = 0.0


func _update_panels(delta: float) -> void:
	if _panels.is_empty():
		return
	var spin := PANEL_SPIN * (2.2 if state == S.DRONES else 1.0)
	_panel_rot = fmod(_panel_rot + spin * delta, TAU)
	if active:
		_open_k = move_toward(_open_k, 1.0 if _shield_open else 0.0, delta * 5.0)
	var r := lerpf(PANEL_R, PANEL_OPEN_R, _open_k)
	var solid := shield_solid()
	for i in _panels.size():
		var a := _panel_angle(i)
		var body: StaticBody2D = _panels[i]
		body.position = Vector2.from_angle(a) * r
		body.rotation = a
		body.collision_layer = Layers.ENEMY if solid else 0


func _panel_angle(i: int) -> float:
	return _panel_rot + i * TAU / PANEL_COUNT


func _burst_panels() -> void:
	for i in _panels.size():
		var a := _panel_angle(i)
		var s := PanelShard.new()
		s.velocity = Vector2.from_angle(a) * 120.0
		s.spin = a
		s.position = position + Vector2.from_angle(a) * PANEL_R
		get_parent().add_child(s)
		_panels[i].queue_free()
	_panels.clear()
	fx(position, 26.0)


# --- attacks -----------------------------------------------------------------------

func _spawn_beam() -> void:
	_end_beam()
	_beam = Beam.new()
	_beam.position = position
	get_parent().add_child(_beam)
	_hazards.append(_beam)
	_update_beam()


func _update_beam() -> void:
	if _beam == null or not is_instance_valid(_beam):
		return
	var dir := Vector2.from_angle(_beam_angle)
	var from := position + dir * 10.0
	var length := _ray_to_arena_edge(from, dir)
	var query := PhysicsRayQueryParameters2D.create(from, from + dir * length, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		length = from.distance_to(hit.position)
	_beam.position = from
	_beam.rotation = _beam_angle
	_beam.set_length(maxf(length, 4.0))


## Distance from `from` along `dir` to the edge of the arena.
func _ray_to_arena_edge(from: Vector2, dir: Vector2) -> float:
	var best := 600.0
	if dir.x > 0.001:
		best = minf(best, (arena.end.x - from.x) / dir.x)
	elif dir.x < -0.001:
		best = minf(best, (arena.position.x - from.x) / dir.x)
	if dir.y > 0.001:
		best = minf(best, (arena.end.y - from.y) / dir.y)
	elif dir.y < -0.001:
		best = minf(best, (arena.position.y - from.y) / dir.y)
	return maxf(best, 0.0)


func _end_beam() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
	_hazards.erase(_beam)
	_beam = null


func _ring(count: int, offset: float) -> void:
	for i in count:
		var a := offset + i * TAU / count
		shoot(position + Vector2.from_angle(a) * 16.0, Vector2.from_angle(a) * 82.0, 2)


func _launch_drones(count: int) -> void:
	var slots := [Vector2(-46, 14), Vector2(46, 14), Vector2(0, 40)]
	for i in count:
		var d := Drone.new()
		d.position = position
		d.slot = (position + slots[i]).clamp(arena.position + Vector2(8, 8), arena.end - Vector2(8, 8))
		d.player = player
		d.hold = 0.75 + i * 0.18
		d.speed = 170.0 if phase2 else 140.0
		get_parent().add_child(d)


func _field_wave(wave: int) -> void:
	_hazards = _hazards.filter(func(h) -> bool: return is_instance_valid(h))
	for span in FIELD_WAVES[_field_set][wave]:
		var f := Field.new()
		var x0: float = arena.position.x + span[0] * 16.0
		var x1: float = arena.position.x + span[1] * 16.0
		f.rect = Rect2(x0, floor_y() - 12.0, x1 - x0, 12.0)
		get_parent().add_child(f)
		_hazards.append(f)
	# One aimed packet per wave keeps the player moving.
	shoot(position, (player_pos() - position).normalized() * 105.0, 2)


func _clear_hazards() -> void:
	for h in _hazards:
		if h != null and is_instance_valid(h):
			h.queue_free()
	_hazards.clear()
	_beam = null


# --- hooks ---------------------------------------------------------------------------

func _on_phase2() -> void:
	_clear_hazards()
	_close_shield()
	_anchor = position
	state = S.BREAK
	_step = 0
	_timer = 0.9


func _on_death() -> void:
	_clear_hazards()
	for body in _panels:
		if is_instance_valid(body):
			body.set_deferred("collision_layer", 0)


# --- drawing -------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	var w := func(c: Color) -> Color: return Color(1, 1, 1, c.a) if white else c
	var dying := _dying >= 0.0
	var appear := clampf(t / maxf(intro_time, 0.01), 0.0, 1.0) if state == S.INTRO and not active else 1.0
	# Data halo with rotating ticks.
	draw_arc(Vector2.ZERO, 31.0, 0.0, TAU, 32, w.call(Color(C_CYAN, 0.25 * appear)), 1.0)
	for i in 8:
		var a := -t * 0.6 + i * TAU / 8.0
		draw_line(Vector2.from_angle(a) * 29.0, Vector2.from_angle(a) * 32.0,
				w.call(Color(C_CYAN, 0.5 * appear)), 1.0)
	# Phase 2: exposed core spikes (two-tone blades).
	if phase2:
		for i in 6:
			var a := t * 1.8 + i * TAU / 6.0
			var tip := Vector2.from_angle(a) * (25.0 + sin(t * 9.0 + i) * 2.0)
			_spike(Vector2.from_angle(a - 0.22) * 15.0, tip, Vector2.from_angle(a + 0.22) * 15.0,
					C_RED if i % 2 == 0 else C_VIOLET, w)
	# Shield panels.
	var r := lerpf(PANEL_R, PANEL_OPEN_R, _open_k)
	var half := asin(PANEL_LEN * 0.5 / PANEL_R)
	var warn := _shield_warn > 0.0 and int(t * 20.0) % 2 == 0
	for i in _panels.size():
		var a := _panel_angle(i)
		if state == S.BREAK and int(t * 16.0) % 2 == 0:
			_panel(a, r, half, C_RED, C_GOLD, w)
		elif _open_k > 0.5 or not active:
			var alpha := 0.35 * appear
			draw_arc(Vector2.ZERO, r - PANEL_THICK * 0.5, a - half, a + half, 8, w.call(Color(C_CYAN, alpha)), 1.0)
			draw_arc(Vector2.ZERO, r + PANEL_THICK * 0.5, a - half, a + half, 8, w.call(Color(C_CYAN, alpha)), 1.0)
		else:
			_panel(a, r, half, C_PALE if warn else C_PANEL, C_GOLD, w)
	# Core shell and eye.
	if dying and int(t * 20.0) % 2 == 0:
		return
	_draw_core(w)
	# Intro: scan lines sweep over the forming core.
	if not active and not dying:
		for i in 3:
			var y := fmod(t * 40.0 + i * 12.0, 36.0) - 18.0
			var hw := sqrt(maxf(18.0 * 18.0 - y * y, 0.0))
			draw_line(Vector2(-hw, y), Vector2(hw, y), Color(C_CYAN, 0.7), 1.0)
	# Spiral charge: inward-spinning lines.
	if state == S.SPIRAL and _timer > 2.6:
		for i in 4:
			var a := t * 6.0 + i * TAU / 4.0
			draw_line(Vector2.from_angle(a) * 34.0, Vector2.from_angle(a + 0.5) * 20.0, w.call(C_GOLD), 1.5)


## The network core: a bezel ring (lit on top, shaded below) with four studs, a
## lit hood and a shadowed jaw inside the housing, then the eye: shaded sclera,
## rimmed iris with turning aperture blades, pupil and two catchlights.
func _draw_core(w: Callable) -> void:
	var ring_c := C_GOLD if phase2 else C_VIOLET
	draw_circle(Vector2.ZERO, 16.0, w.call(C_DEEP))
	_poly(_ring_seg(13.0, 16.0, PI, TAU), w.call(ring_c.lightened(0.25)))
	_poly(_ring_seg(13.0, 16.0, 0.0, PI), w.call(ring_c.darkened(0.3)))
	for k in 4:
		var p := (Vector2.from_angle(PI / 4.0 + k * PI / 2.0) * 14.5).floor()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), w.call(C_RED if phase2 else C_PALE))
	_poly(_ring_seg(10.5, 13.0, PI + 0.35, TAU - 0.35), w.call(C_PANEL))
	_poly(_ring_seg(10.5, 13.0, 0.35, PI - 0.35), w.call(C_SHADOW))
	var attacking := state in [S.LASER_AIM, S.LASER_LOCK, S.LASER_FIRE, S.SPIRAL]
	var iris_c := C_RED if attacking else (C_GOLD if phase2 else C_CYAN)
	if state == S.LASER_LOCK and int(t * 30.0) % 2 == 0:
		iris_c = C_PALE
	var look := _look * 3.5
	var sc := look * 0.3
	# Sclera with a shaded lower segment.
	draw_circle(sc, 10.0, w.call(C_PALE))
	var shade := PackedVector2Array()
	for k in 9:
		shade.append(sc + Vector2.from_angle(lerpf(0.45, PI - 0.45, k / 8.0)) * 10.0)
	draw_colored_polygon(shade, w.call(C_PALE_SHADE))
	# Iris with turning aperture blades, pupil.
	draw_circle(look, 6.0, w.call(iris_c))
	for i in 6:
		var a := t * (4.0 if attacking else 1.0) + i * TAU / 6.0
		draw_line(look + Vector2.from_angle(a) * 2.5, look + Vector2.from_angle(a + 0.7) * 5.5,
				w.call(Color(C_DEEP, 0.55)), 1.0)
	draw_circle(look, 2.5, w.call(C_DEEP))
	draw_rect(Rect2((look + Vector2(-3, -3)).floor(), Vector2(2, 2)), w.call(Color.WHITE))
	draw_rect(Rect2((look + Vector2(2, 1)).floor(), Vector2(1, 1)), w.call(Color.WHITE))


## One shield panel: a navy plate split into three tiles by dark seams, a cyan
## rim on the outside edge and a gold emitter node with a glint in the middle.
func _panel(a: float, r: float, half: float, fill: Color, node: Color, w: Callable) -> void:
	var h := PANEL_THICK * 0.5
	_poly(_ring_seg(r - h, r + h - 1.5, a - half, a + half), w.call(fill))
	_poly(_ring_seg(r + h - 1.5, r + h, a - half, a + half), w.call(C_CYAN))
	for k in [-1.0, 1.0]:
		var s: float = a + k * half * 0.38
		draw_line(Vector2.from_angle(s) * (r - h), Vector2.from_angle(s) * (r + h - 1.5), w.call(C_DEEP), 1.0)
	_poly(_ring_seg(r - h + 1.0, r + h - 1.5, a - 0.07, a + 0.07, 2), w.call(node))
	var g := (Vector2.from_angle(a) * (r + 1.0)).floor()
	draw_rect(Rect2(g, Vector2(1, 1)), w.call(C_PALE))


## Two-tone blade from base_l to base_r with its tip; the half facing up is lit.
func _spike(base_l: Vector2, tip: Vector2, base_r: Vector2, c: Color, w: Callable) -> void:
	var mid := (base_l + base_r) * 0.5
	var left_up := (base_l + tip + mid).y < (base_r + tip + mid).y
	var lit := c.lightened(0.3)
	var dark := c.darkened(0.3)
	_poly([base_l, tip, mid], w.call(lit if left_up else dark))
	_poly([mid, tip, base_r], w.call(dark if left_up else lit))


## Annulus segment between radii r0 and r1, angles a0..a1, as a polygon.
func _ring_seg(r0: float, r1: float, a0: float, a1: float, n := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		pts.append(Vector2.from_angle(lerpf(a0, a1, k / float(n))) * r1)
	for k in n + 1:
		pts.append(Vector2.from_angle(lerpf(a1, a0, k / float(n))) * r0)
	return pts


func _poly(pts, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), c)


# --- boss-owned objects -----------------------------------------------------------------

## Eye laser: a straight damage zone from the eye. mode 0 = tracking aim line,
## 1 = locked (flashing), live = damaging beam.
class Beam extends "res://scripts/level/damage_zone.gd":
	var length := 8.0
	var mode := 0
	var live := false
	var _shape := RectangleShape2D.new()
	var _cs := CollisionShape2D.new()
	var _t := 0.0

	func _ready() -> void:
		super._ready()
		add_to_group("arca_hazard")
		collision_layer = 0
		collision_mask = 0
		z_index = 5
		_cs.shape = _shape
		add_child(_cs)
		set_length(length)

	func set_length(l: float) -> void:
		length = l
		_shape.size = Vector2(l, 6.0)
		_cs.position = Vector2(l / 2.0, 0.0)

	func set_live(on: bool) -> void:
		live = on
		collision_layer = 32 if on else 0  # Layers.HAZARD

	func _physics_process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var end := Vector2(length, 0)
		if live:
			var wdt := 6.0 + sin(_t * 50.0) * 1.0
			draw_line(Vector2.ZERO, end, Color("e34f5b"), wdt + 2.0)
			draw_line(Vector2.ZERO, end, Color("ffd6d6"), 2.0)
			draw_circle(end, 4.0 + sin(_t * 40.0), Color("f0b84a"))
		elif mode == 1:
			if int(_t * 30.0) % 2 == 0:
				draw_line(Vector2.ZERO, end, Color("d7edf3", 0.9), 2.0)
		elif int(_t * 16.0) % 2 == 0:
			draw_line(Vector2.ZERO, end, Color("e34f5b", 0.55), 1.0)


## Control field: one floor stripe, telegraphed then electrified, then gone.
class Field extends "res://scripts/level/damage_zone.gd":
	const WARN_TIME := 0.9
	const ON_TIME := 1.2
	var rect := Rect2()
	var _t := 0.0

	func _ready() -> void:
		super._ready()
		add_to_group("arca_hazard")
		collision_layer = 0
		collision_mask = 0
		position = rect.position
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		cs.shape = shape
		cs.position = rect.size / 2.0
		add_child(cs)

	func is_on() -> bool:
		return _t >= WARN_TIME

	func _physics_process(delta: float) -> void:
		_t += delta
		collision_layer = 32 if is_on() else 0  # Layers.HAZARD
		if _t >= WARN_TIME + ON_TIME:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		var base := Rect2(0, r.size.y - 2.0, r.size.x, 2.0)
		if not is_on():
			if int(_t * 14.0) % 2 == 0:
				draw_rect(base, Color("e34f5b", 0.8))
				var x := 2.0
				while x < r.size.x:
					draw_rect(Rect2(x, r.size.y - 5.0, 4, 1), Color("e34f5b", 0.5))
					x += 8.0
			return
		draw_rect(r, Color("6543a2", 0.25))
		draw_rect(base, Color("f0b84a"))
		var i := 0
		var x2 := 1.0
		while x2 < r.size.x - 1.0:
			var h := 6.0 + 5.0 * sin(_t * 45.0 + i * 1.7)
			draw_line(Vector2(x2, r.size.y), Vector2(x2 + 2.0, r.size.y - h), Color("e34f5b"), 1.0)
			draw_line(Vector2(x2 + 2.0, r.size.y - h), Vector2(x2 + 4.0, r.size.y - 2.0), Color("d7edf3", 0.8), 1.0)
			x2 += 5.0
			i += 1


## Drone: glides to a slot beside ARCA, blinks, then dives at the player's
## position once (no homing after launch).
class Drone extends "res://scripts/combat/enemy_shot.gd":
	var slot := Vector2.ZERO
	var player = null
	var hold := 0.75
	var speed := 140.0
	var _age := 0.0
	var _launched := false

	func _ready() -> void:
		super._ready()
		damage = 2
		life = 5.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _launched:
			position = position.lerp(slot, 1.0 - exp(-7.0 * delta))
			if _age >= hold:
				_launched = true
				var target := position + Vector2(0, 60)
				if player != null and is_instance_valid(player):
					target = player.global_position + Vector2(0, -13)
				velocity = (target - position).normalized() * speed
		super._physics_process(delta)

	func _draw() -> void:
		var blink := not _launched and _age > hold - 0.35 and int(_age * 20.0) % 2 == 0
		# Lit upper half, shaded lower half, cyan rim, red sensor eye with a glint.
		var top := Color("d7edf3") if blink else Color("2f5a86")
		var bottom := Color("98b4c4") if blink else Color("13284a")
		draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(-6, 0)]), top)
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(0, 6)]), bottom)
		draw_polyline(PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0),
				Vector2(0, -6)]), Color("00b8be"), 1.0)
		draw_circle(Vector2.ZERO, 2.0, Color("e34f5b"))
		draw_rect(Rect2(-1, -1, 1, 1), Color("ffd6d6"))


## Shield panel torn off at the phase change: flies outward, spinning.
class PanelShard extends "res://scripts/combat/enemy_shot.gd":
	var spin := 0.0

	func _ready() -> void:
		super._ready()
		damage = 2

	func _physics_process(delta: float) -> void:
		spin += 9.0 * delta
		super._physics_process(delta)

	func _draw() -> void:
		# A torn-off panel tile: navy plate, cyan rim, dark seams, gold node.
		draw_set_transform(Vector2.ZERO, spin, Vector2.ONE)
		draw_rect(Rect2(-6, -3, 12, 6), Color("1c375b"))
		draw_rect(Rect2(-6, -3, 12, 2), Color("00b8be"))
		draw_rect(Rect2(-3, -1, 1, 4), Color("101b36"))
		draw_rect(Rect2(2, -1, 1, 4), Color("101b36"))
		draw_rect(Rect2(-1, -1, 2, 3), Color("f0b84a"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
