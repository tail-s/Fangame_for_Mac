extends CharacterBody2D
## Player controller — prototype 0.1.
##
## Movement: run, variable jump, dash, dash jump, wall slide, wall kick.
## Combat: buster with three charge levels.
## Armor parts (GDD v0.2 §4) change `stats` through apply_loadout(); the rules
## live in scripts/armor/armor_data.gd. Units are pixels and seconds at 60 Hz;
## the origin is at the feet. Tunables are exported for live tweaking.

signal hp_changed(hp: int, max_hp: int)
signal core_changed(core: float, core_max: float)
signal died

const Layers = preload("res://scripts/core/layers.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")
const PlayerShot = preload("res://scripts/combat/player_shot.gd")
const Shockwave = preload("res://scripts/combat/shockwave.gd")
const PlayerVisual = preload("res://scripts/player/player_visual.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")

enum State { NORMAL, DASH, WALL_SLIDE, HURT, SPECIAL, DEAD, FROZEN }

const BODY_SIZE := Vector2(12, 26)
const MUZZLE := Vector2(13, -15)
const CORE_MAX := 100.0
const SPREAD_ANGLE := 0.26

@export_group("Run & Jump")
@export var walk_speed := 90.0
@export var gravity := 900.0
@export var jump_velocity := 330.0
## Upward speed kept when jump is released early (variable jump height).
@export var jump_cut_velocity := 90.0
@export var max_fall_speed := 330.0
@export var coyote_time := 0.08
@export var jump_buffer_time := 0.1

@export_group("Dash")
@export var dash_speed := 210.0
@export var dash_time := 0.36
@export var air_dash_time := 0.26

@export_group("Wall")
@export var wall_slide_speed := 60.0
@export var wall_kick_speed := 90.0
## Horizontal input is ignored this long after a wall kick.
@export var wall_kick_lock := 0.12
@export var wall_probe := 2.0

@export_group("Air armor")
@export var flight_speed := 80.0
## Core gauge spent per second of flight.
@export var flight_cost := 110.0
@export var glide_fall_speed := 40.0

@export_group("Combat")
@export var max_hp := 16
@export var hurt_time := 0.35
@export var invuln_time := 1.0
@export var charge_lv1_time := 0.45
@export var charge_lv2_time := 1.3
@export var max_small_shots := 3

@export_group("Specials")
@export var overdrive_speed := 420.0
@export var overdrive_time := 0.5
@export var special_damage := 4
@export var skybreaker_speed := 540.0

var state := State.NORMAL
var facing := 1
var hp := 0
var core := 50.0
## Falling below this y kills the player (set by the stage).
var kill_y := INF
var loadout := ArmorData.neutral_loadout()
var stats := ArmorData.compute(ArmorData.neutral_loadout())

# Input: held states, read from Input or set directly by tests (`scripted`).
# Press edges are derived once per physics frame. Buttons start as "held" so a
# press that opened the stage from a menu does not also jump or shoot.
var scripted := false
## Debug only (screenshot tour): ignore damage and death.
var god_mode := false
var control_lock := 0.0
var in_dir := 0
var in_jump := false
var in_shoot := false
var in_dash := false
var in_special := false
var jump_pressed := false
var shoot_pressed := false
var dash_pressed := false
var special_pressed := false
var _prev_jump := true
var _prev_shoot := true
var _prev_dash := true
var _prev_special := true

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_timer := 0.0
var dash_dir := 1
## True while airborne after a dash jump / dash wall kick: air speed = dash speed.
var dash_momentum := false
var air_dashing := false
var air_dashes_left := 0
var dash_chain_left := 0
var flying := false
var gliding := false
var wall_lock_timer := 0.0
## -1 = wall on the left, 1 = wall on the right, 0 = none.
var wall_dir := 0
var hurt_timer := 0.0
var invuln_timer := 0.0
var charging := false
var charge_time := 0.0
var shoot_pose_timer := 0.0
var anim_time := 0.0
var special_kind := ""
var special_timer := 0.0
var special_phase := 0

var hurtbox: Area2D
var visual: Node2D

var _dual_granted := false
var _hits := {}  # enemies already struck by the current dash / special
var _core_shown := -1


func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD
	floor_snap_length = 4.0
	add_child(_rect_shape(BODY_SIZE, Vector2(0, -BODY_SIZE.y / 2.0)))

	hurtbox = Area2D.new()
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = Layers.ENEMY | Layers.ENEMY_SHOT | Layers.HAZARD
	hurtbox.monitorable = false
	hurtbox.add_child(_rect_shape(BODY_SIZE - Vector2(4, 6), Vector2(0, -BODY_SIZE.y / 2.0 - 1.0)))
	add_child(hurtbox)

	visual = PlayerVisual.new()
	visual.player = self
	add_child(visual)
	apply_loadout(loadout)


func _physics_process(delta: float) -> void:
	anim_time += delta
	_read_input(delta)
	_tick_timers(delta)
	match state:
		State.DEAD, State.FROZEN:
			return
		State.HURT:
			_process_hurt(delta)
		State.SPECIAL:
			_process_special(delta)
		_:
			_process_move(delta)
			_process_shoot(delta)
			_try_special()
	_regen_core(delta)
	move_and_slide()
	if state == State.SPECIAL:
		_special_after_move()
	if global_position.y > kill_y:
		die()
		return
	_check_damage()


# --- public API -------------------------------------------------------------------

## Equips a loadout (see ArmorData) and applies its stats.
func apply_loadout(new_loadout: Dictionary) -> void:
	loadout = new_loadout.duplicate()
	stats = ArmorData.compute(loadout)
	walk_speed = stats.walk_speed
	dash_speed = stats.dash_speed
	dash_time = stats.dash_time
	air_dashes_left = mini(air_dashes_left, stats.air_dashes)
	if visual != null:
		visual.part_armor = loadout.duplicate()


func set_core(value: float) -> void:
	core = clampf(value, 0.0, CORE_MAX)
	if int(core) != _core_shown:
		_core_shown = int(core)
		core_changed.emit(core, CORE_MAX)


func take_damage(amount: int, from_x: float) -> void:
	if god_mode or invuln_timer > 0.0 or state in [State.DEAD, State.FROZEN, State.SPECIAL]:
		return
	var scaled := float(amount)
	if state == State.DASH and not air_dashing:
		scaled *= stats.dash_damage_mult
	if not is_on_floor():
		scaled *= stats.air_damage_mult
	hp = maxi(hp - maxi(1, ceili(scaled)), 0)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		die()
		return
	invuln_timer = invuln_time
	flying = false
	if not stats.knockback:
		return  # Vanguard BODY: keep control, no knockback
	state = State.HURT
	air_dashing = false
	hurt_timer = hurt_time
	dash_momentum = false
	var away := signf(global_position.x - from_x)
	if away == 0.0:
		away = -facing
	velocity = Vector2(away * 45.0, maxf(velocity.y, 0.0))


func heal_full() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func die() -> void:
	if god_mode or state == State.DEAD:
		return
	state = State.DEAD
	hp = 0
	hp_changed.emit(hp, max_hp)
	velocity = Vector2.ZERO
	charging = false
	flying = false
	visual.visible = false
	var fx := Explosion.new()
	fx.big = true
	fx.position = position + Vector2(0, -BODY_SIZE.y / 2.0)
	get_parent().add_child(fx)
	died.emit()


## Stops all control (stage clear).
func freeze() -> void:
	state = State.FROZEN
	velocity = Vector2.ZERO
	charging = false
	flying = false


func is_alive() -> bool:
	return state != State.DEAD


func is_dashing() -> bool:
	return state == State.DASH


func is_wall_sliding() -> bool:
	return state == State.WALL_SLIDE


func is_hurt() -> bool:
	return state == State.HURT


func state_name() -> String:
	return State.keys()[state]


## 0 = not charged, 1 = mid charge, 2 = full charge.
func charge_level() -> int:
	if not charging:
		return 0
	if charge_time >= charge_lv2_time:
		return 2
	if charge_time >= charge_lv1_time:
		return 1
	return 0


## Direction the body (and buster) points: away from the wall while sliding.
func visual_facing() -> int:
	return -wall_dir if state == State.WALL_SLIDE else facing


func special_ready() -> bool:
	return stats.special != "" and core >= CORE_MAX


# --- per-frame steps -----------------------------------------------------------------

func _read_input(delta: float) -> void:
	if not scripted:
		var axis := Input.get_axis("move_left", "move_right")
		in_dir = 0 if absf(axis) < 0.5 else int(signf(axis))
		in_jump = Input.is_action_pressed("jump")
		in_shoot = Input.is_action_pressed("shoot")
		in_dash = Input.is_action_pressed("dash")
		in_special = Input.is_action_pressed("special")
	if control_lock > 0.0:
		control_lock -= delta
		in_dir = 0
		in_jump = false
		in_shoot = false
		in_dash = false
		in_special = false
	jump_pressed = in_jump and not _prev_jump
	shoot_pressed = in_shoot and not _prev_shoot
	dash_pressed = in_dash and not _prev_dash
	special_pressed = in_special and not _prev_special
	_prev_jump = in_jump
	_prev_shoot = in_shoot
	_prev_dash = in_dash
	_prev_special = in_special


func _tick_timers(delta: float) -> void:
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	wall_lock_timer = maxf(wall_lock_timer - delta, 0.0)
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	shoot_pose_timer = maxf(shoot_pose_timer - delta, 0.0)
	if jump_pressed:
		jump_buffer_timer = jump_buffer_time


func _process_move(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		coyote_timer = coyote_time
		dash_momentum = false
		air_dashes_left = stats.air_dashes
		_dual_granted = false
		flying = false
	wall_dir = _probe_wall()

	# Dash. Ground dash ends on timer, release, turning around, or running off a
	# ledge (which keeps the speed as air momentum). Air dash needs Aero LEG or
	# the hybrid bonus and holds altitude.
	if state == State.DASH:
		dash_timer -= delta
		if air_dashing:
			if dash_timer <= 0.0 or on_floor or wall_dir == dash_dir:
				_end_air_dash()
		elif not on_floor:
			state = State.NORMAL
			dash_momentum = true
			_grant_dual_core()
		elif dash_pressed and dash_chain_left > 0:
			dash_chain_left -= 1
			dash_timer = dash_time
			_hits.clear()
		elif dash_timer <= 0.0 or (not in_dash and not stats.dash_commit) \
				or (in_dir != 0 and in_dir != dash_dir):
			state = State.NORMAL
	elif dash_pressed:
		if on_floor:
			_start_dash(false)
		elif air_dashes_left > 0 and state != State.WALL_SLIDE:
			_start_dash(true)

	if state == State.DASH:
		facing = dash_dir
	elif in_dir != 0 and wall_lock_timer <= 0.0:
		facing = in_dir

	# Jump > wall kick > flight (Aero LEG), all from a buffered press.
	if jump_buffer_timer > 0.0:
		if on_floor or coyote_timer > 0.0:
			_jump()
		elif wall_dir != 0:
			_wall_kick()
		elif jump_pressed and stats.flight and core >= 10.0 and not flying:
			flying = true
			jump_buffer_timer = 0.0
			if air_dashing:
				_end_air_dash()
	if flying and (not in_jump or core <= 0.0 or on_floor):
		flying = false

	# Horizontal: no air inertia, like classic action platformers.
	if state == State.DASH:
		velocity.x = dash_dir * dash_speed
	elif wall_lock_timer <= 0.0:
		velocity.x = in_dir * (dash_speed if dash_momentum else walk_speed)

	# Vertical.
	if air_dashing:
		velocity.y = 0.0
	elif flying:
		velocity.y = -flight_speed
		set_core(core - flight_cost * delta)
	else:
		if not in_jump and velocity.y < -jump_cut_velocity:
			velocity.y = -jump_cut_velocity
		if not on_floor:
			velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	var sliding := not on_floor and velocity.y > 0.0 and wall_dir != 0 \
			and in_dir == wall_dir and wall_lock_timer <= 0.0 and state != State.DASH
	if sliding:
		velocity.y = minf(velocity.y, wall_slide_speed)
		dash_momentum = false
		air_dashes_left = stats.air_dashes
		state = State.WALL_SLIDE
		gliding = false
	else:
		if state == State.WALL_SLIDE:
			state = State.NORMAL
		gliding = stats.glide and not on_floor and in_jump and velocity.y > 0.0 \
				and not flying and state == State.NORMAL
		if gliding:
			velocity.y = minf(velocity.y, glide_fall_speed)


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, 240.0 * delta)
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	# Keep the charge while held; releasing during hit-stun drops it.
	if charging:
		if in_shoot:
			charge_time += delta
		else:
			charging = false
			charge_time = 0.0
	if hurt_timer <= 0.0:
		state = State.NORMAL


func _process_shoot(delta: float) -> void:
	if shoot_pressed:
		_fire(0)
		charging = true
		charge_time = 0.0
	elif charging and in_shoot:
		charge_time += delta
	elif charging:
		charging = false
		if charge_time >= charge_lv2_time:
			_fire(2)
		elif charge_time >= charge_lv1_time:
			_fire(1)
		charge_time = 0.0


func _regen_core(delta: float) -> void:
	if flying or state == State.SPECIAL:
		return
	var rate: float = stats.core_regen_ground if is_on_floor() else stats.core_regen_air
	if rate > 0.0:
		set_core(core + rate * delta)


func _check_damage() -> void:
	if state == State.SPECIAL:
		return
	# Vanguard LEG: the dash itself is an attack.
	if state == State.DASH and stats.dash_attack > 0:
		for body in hurtbox.get_overlapping_bodies():
			if body.is_in_group("enemy") and not _hits.has(body):
				_hits[body] = true
				body.take_damage(stats.dash_attack)
	if invuln_timer > 0.0:
		return
	for area in hurtbox.get_overlapping_areas():
		if area.is_in_group("hazard"):
			die()
			return
		if area.is_in_group("damaging"):
			take_damage(area.damage, global_position.x + signf(velocity.x) * 8.0)
			return
		if area.is_in_group("enemy_shot"):
			take_damage(area.damage, area.global_position.x)
			area.hit()
			return
	for body in hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and not body.is_queued_for_deletion() \
				and body.get_contact_damage() > 0:
			take_damage(body.get_contact_damage(), body.global_position.x)
			return


# --- specials (full armor sets) ---------------------------------------------------------

func _try_special() -> void:
	if special_pressed and special_ready():
		_start_special(stats.special)


func _start_special(kind: String) -> void:
	state = State.SPECIAL
	special_kind = kind
	special_phase = 0
	set_core(0.0)
	_hits.clear()
	charging = false
	charge_time = 0.0
	flying = false
	gliding = false
	air_dashing = false
	if kind == "overdrive":
		special_timer = overdrive_time
		dash_dir = in_dir if in_dir != 0 else facing
		facing = dash_dir
	else:
		special_timer = 0.22
		velocity = Vector2(0.0, -260.0 if is_on_floor() else -60.0)


func _process_special(delta: float) -> void:
	special_timer -= delta
	if special_kind == "overdrive":
		velocity = Vector2(dash_dir * overdrive_speed, 0.0)
		if special_timer <= 0.0:
			_end_special()
	elif special_phase == 0:  # Sky Breaker: rise / hang
		velocity.x = 0.0
		velocity.y = minf(velocity.y + gravity * delta, 0.0)
		if special_timer <= 0.0:
			special_phase = 1
	elif special_phase == 1:  # dive
		velocity = Vector2(0.0, skybreaker_speed)
	else:  # landing recovery
		velocity = Vector2.ZERO
		if special_timer <= 0.0:
			_end_special()
	for body in hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and not _hits.has(body):
			_hits[body] = true
			body.take_damage(special_damage)


func _special_after_move() -> void:
	if special_kind == "overdrive" and is_on_wall():
		_end_special()
	elif special_kind == "skybreaker" and special_phase == 1 and is_on_floor():
		special_phase = 2
		special_timer = 0.2
		for d in [-1, 1]:
			var wave := Shockwave.new()
			wave.dir = d
			wave.position = position
			get_parent().add_child(wave)


func _end_special() -> void:
	state = State.NORMAL
	special_kind = ""
	invuln_timer = maxf(invuln_timer, 0.25)


# --- helpers ------------------------------------------------------------------------

func _start_dash(air: bool) -> void:
	state = State.DASH
	air_dashing = air
	dash_dir = in_dir if in_dir != 0 else facing
	_hits.clear()
	if air:
		dash_timer = air_dash_time
		air_dashes_left -= 1
		velocity.y = 0.0
		dash_momentum = false
		flying = false
	else:
		dash_timer = dash_time
		dash_chain_left = stats.dash_chain - 1


func _end_air_dash() -> void:
	state = State.NORMAL
	air_dashing = false


## Hybrid 2+2 bonus: one extra air dash after a dash jump / dash run-off.
func _grant_dual_core() -> void:
	if stats.dual_core and not _dual_granted:
		_dual_granted = true
		air_dashes_left += 1


func _jump() -> void:
	velocity.y = -jump_velocity
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	dash_momentum = state == State.DASH and not air_dashing
	if dash_momentum:
		_grant_dual_core()
	if state == State.DASH:
		state = State.NORMAL
	air_dashing = false


func _wall_kick() -> void:
	velocity.y = -jump_velocity
	jump_buffer_timer = 0.0
	dash_momentum = in_dash
	velocity.x = -wall_dir * (dash_speed if dash_momentum else wall_kick_speed)
	wall_lock_timer = wall_kick_lock
	facing = -wall_dir
	state = State.NORMAL
	air_dashing = false
	flying = false


func _fire(level: int) -> void:
	if level == 0 and get_tree().get_nodes_in_group("player_shot_small").size() >= max_small_shots:
		return
	var dir := visual_facing()
	var origin := position + Vector2(MUZZLE.x * dir, MUZZLE.y)
	var angles := [0.0]
	if level > 0 and stats.spread:
		angles = [0.0, -SPREAD_ANGLE, SPREAD_ANGLE]
	for angle in angles:
		var shot := PlayerShot.new()
		shot.setup(level, dir, angle, angles.size() > 1)
		shot.breaker = stats.breaker and level > 0
		shot.homing = stats.homing and level == 0
		shot.pierce_all = stats.pierce_all and level == 2
		shot.position = origin
		get_parent().add_child(shot)
	shoot_pose_timer = 0.3


func _probe_wall() -> int:
	if test_move(global_transform, Vector2(wall_probe, 0)):
		return 1
	if test_move(global_transform, Vector2(-wall_probe, 0)):
		return -1
	return 0


func _rect_shape(size: Vector2, offset: Vector2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = offset
	return cs
