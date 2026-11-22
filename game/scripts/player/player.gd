extends CharacterBody2D
## Player body shared by the whole party (GDD v0.2 §6, original characters):
##   IX    — buster, armor parts, special weapons
##   SABLE — saber, three styles, parry          (scripts/player/saber_attack.gd)
##   ECHO  — rapid aimed fire, hover, copy forms   (scripts/player/echo_attack.gd)
## Two characters sortie; Tag swaps them in place. A swap right after landing a
## hit triggers a tag combo strike. A character at 0 HP drops out and the partner
## takes over; the run fails only when both are down (or on pits / spikes).
##
## Movement: run, variable jump, dash, dash jump, wall slide, wall kick.
## Armor parts change IX's `stats` through apply_loadout() (armor_data.gd).
## Units are pixels and seconds at 60 Hz; the origin is at the feet.

const Autoloads = preload("res://scripts/core/autoloads.gd")

signal hp_changed(hp: int, max_hp: int)
signal core_changed(core: float, core_max: float)
signal character_changed(id: String)
signal notice(text: String)
signal died

const Layers = preload("res://scripts/core/layers.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")
const PlayerShot = preload("res://scripts/combat/player_shot.gd")
const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")
const Shockwave = preload("res://scripts/combat/shockwave.gd")
const PlayerVisual = preload("res://scripts/player/player_visual.gd")
const PartnerVisual = preload("res://scripts/player/partner_visual.gd")
const SaberAttack = preload("res://scripts/player/saber_attack.gd")
const EchoAttack = preload("res://scripts/player/echo_attack.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")

enum State { NORMAL, DASH, WALL_SLIDE, HURT, SPECIAL, DEAD, FROZEN }

const CHARACTERS := {
	"ix": {"name": "IX", "walk": 1.0, "dash": 1.0, "hover": 0.0},
	"sable": {"name": "SABLE", "walk": 1.07, "dash": 1.06, "hover": 0.0},
	"echo": {"name": "ECHO", "walk": 1.0, "dash": 1.0, "hover": 0.6},
}
const BODY_SIZE := Vector2(12, 26)
const MINI_SIZE := Vector2(10, 12)
const MUZZLE := Vector2(13, -15)
const CORE_MAX := 100.0
const SPREAD_ANGLE := 0.26
const TAG_WINDOW := 0.6
const SWAP_COOLDOWN := 1.0

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
## The stage (level.gd) for tile zones: water, low gravity, lifts, ice. Optional.
var env = null
var loadout := ArmorData.neutral_loadout()
## IX armor frame: "parts" (mixed parts) or "ultimate" (Ultimate Armor IX).
var frame := "parts"
var stats := ArmorData.compute(ArmorData.neutral_loadout())

# Party ------------------------------------------------------------------------
var party: Array = []  # [{"id": String, "hp": int, "max_hp": int}]
var active := 0
var character := "ix"
## Attack module of SABLE / ECHO (null for IX, whose buster lives here).
var attack = null
var swap_cooldown := 0.0
var last_hit_time := -10.0
var mini := false

# IX special weapons -------------------------------------------------------------
var weapons: Array = ["buster"]
var weapon_index := 0
var weapon_energy := {}

# Input: held states, read from Input or set directly by tests (`scripted`).
# Press edges are derived once per physics frame. Buttons start as "held" so a
# press that opened the stage from a menu does not also jump or shoot.
var scripted := false
## Debug only (screenshot tour): ignore damage and death.
var god_mode := false
var control_lock := 0.0
## Difficulty option: damage taken is multiplied by this (Game.damage_taken_mult()).
var damage_taken_mult := 1.0
var in_dir := 0
var in_up := false
var in_down := false
var in_jump := false
var in_shoot := false
var in_dash := false
var in_special := false
var in_tag := false
var in_wprev := false
var in_wnext := false
var jump_pressed := false
var shoot_pressed := false
var dash_pressed := false
var special_pressed := false
var tag_pressed := false
var wprev_pressed := false
var wnext_pressed := false
var _prev := {"jump": true, "shoot": true, "dash": true, "special": true, "tag": true,
		"wprev": true, "wnext": true}

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
var hovering := false
var hover_left := 0.0
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

var _visuals := {}
var _modules := {}
var _body_shape: CollisionShape2D
var _hurt_shape: CollisionShape2D
var _dual_granted := false
var _hits := {}  # enemies already struck by the current dash / special
var _core_shown := -1
var _regen_clock := 0.0
var _zone := ""
var _on_ice := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD
	floor_snap_length = 4.0
	_body_shape = _rect_shape(BODY_SIZE, Vector2(0, -BODY_SIZE.y / 2.0))
	add_child(_body_shape)

	hurtbox = Area2D.new()
	hurtbox.collision_layer = 0
	hurtbox.collision_mask = Layers.ENEMY | Layers.ENEMY_SHOT | Layers.HAZARD
	hurtbox.monitorable = false
	_hurt_shape = _rect_shape(BODY_SIZE - Vector2(4, 6), Vector2(0, -BODY_SIZE.y / 2.0 - 1.0))
	hurtbox.add_child(_hurt_shape)
	add_child(hurtbox)

	refill_weapons()
	if party.is_empty():
		setup_party(["ix"], max_hp)


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
			_process_attack(delta)
			if tag_pressed and can_swap():
				swap()
	_regen_core(delta)
	_regen_partner(delta)
	var was_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if not was_floor and is_on_floor() and fall_speed > 150.0 and state != State.DEAD:
		Autoloads.sfx("land")
	if state == State.SPECIAL:
		_special_after_move()
	if global_position.y > kill_y:
		die()
		return
	_check_damage()


# --- party ------------------------------------------------------------------------

## Sets the sortie (1-2 character ids) with full HP and activates the first.
func setup_party(ids: Array, hp_max: int) -> void:
	party = []
	for id in ids:
		party.append({"id": id, "hp": hp_max, "max_hp": hp_max})
	max_hp = hp_max
	_activate(0)


func character_name(id := "") -> String:
	return CHARACTERS[id if id != "" else character].name


## The benched partner as {"id", "hp", "max_hp"}, or null when solo.
func partner():
	return party[1 - active] if party.size() > 1 else null


func can_swap() -> bool:
	return party.size() > 1 and swap_cooldown <= 0.0 and party[1 - active].hp > 0 \
			and state in [State.NORMAL, State.DASH, State.WALL_SLIDE] and not mini


func swap() -> void:
	var combo := anim_time - last_hit_time < TAG_WINDOW
	party[active].hp = hp
	_leave_character()
	_activate(1 - active)
	swap_cooldown = SWAP_COOLDOWN
	invuln_timer = maxf(invuln_timer, 0.3)
	_puff(Color("3de0ee"))
	Autoloads.sfx("tag")
	if combo:
		last_hit_time = -10.0
		_start_special("tag_strike")
		notice.emit("TAG COMBO!")


## Called by attacks of the active character when they connect.
func register_hit() -> void:
	last_hit_time = anim_time


## ECHO's copy shot destroyed an enemy that carries copy data.
func on_copy_kill(kind) -> void:
	if character == "echo" and attack != null and typeof(kind) == TYPE_STRING and kind != "":
		attack.on_copy_kill(kind)
		notice.emit("COPY DATA: %s — V로 변신" % attack.COPY_NAMES[kind])


func _activate(i: int) -> void:
	active = i
	var c: Dictionary = party[i]
	character = c.id
	hp = c.hp
	max_hp = c.max_hp
	for id in _visuals:
		_visuals[id].visible = false
	visual = _visual_for(character)
	visual.visible = true
	attack = _module_for(character)
	hover_left = _hover_time()
	_recompute_stats()
	hp_changed.emit(hp, max_hp)
	character_changed.emit(character)


func _leave_character() -> void:
	charging = false
	charge_time = 0.0
	flying = false
	hovering = false
	gliding = false
	if state == State.DASH:
		air_dashing = false
		state = State.NORMAL
	if attack != null:
		attack.deactivate()


func _visual_for(id: String) -> Node2D:
	if not _visuals.has(id):
		var v: Node2D = PlayerVisual.new() if id == "ix" else PartnerVisual.new()
		v.player = self
		if id != "ix":
			v.character = id
		add_child(v)
		_visuals[id] = v
		if id == "ix":
			_sync_ix_visual()
	return _visuals[id]


func _module_for(id: String):
	if id == "ix":
		return null
	if not _modules.has(id):
		_modules[id] = SaberAttack.new(self) if id == "sable" else EchoAttack.new(self)
	return _modules[id]


func _regen_partner(delta: float) -> void:
	swap_cooldown = maxf(swap_cooldown - delta, 0.0)
	var mate = partner()
	if mate == null or mate.hp <= 0 or mate.hp >= mate.max_hp:
		return
	_regen_clock += delta
	if _regen_clock >= 2.0:
		_regen_clock = 0.0
		mate.hp += 1


# --- public API -------------------------------------------------------------------

## Equips an armor loadout (IX only; see ArmorData) and applies its stats.
func apply_loadout(new_loadout: Dictionary) -> void:
	loadout = new_loadout.duplicate()
	_recompute_stats()
	_sync_ix_visual()


## "parts" or "ultimate" (IX only).
func set_frame(new_frame: String) -> void:
	frame = new_frame
	_recompute_stats()
	_sync_ix_visual()


func _sync_ix_visual() -> void:
	if _visuals.has("ix"):
		_visuals["ix"].part_armor = (ArmorData.ULTIMATE_LOADOUT if frame == "ultimate" else loadout).duplicate()


func set_core(value: float) -> void:
	core = clampf(value, 0.0, CORE_MAX)
	if int(core) != _core_shown:
		_core_shown = int(core)
		core_changed.emit(core, CORE_MAX)


func take_damage(amount: int, from_x: float) -> void:
	if god_mode or invuln_timer > 0.0 or state in [State.DEAD, State.FROZEN, State.SPECIAL]:
		return
	if attack != null and attack.try_parry():
		register_hit()
		return
	var scaled := float(amount)
	if state == State.DASH and not air_dashing:
		scaled *= stats.dash_damage_mult
	if not is_on_floor():
		scaled *= stats.air_damage_mult
	scaled *= damage_taken_mult
	hp = maxi(hp - maxi(1, ceili(scaled)), 0)
	hp_changed.emit(hp, max_hp)
	Autoloads.sfx("hurt")
	if hp == 0:
		_character_down()
		return
	invuln_timer = invuln_time
	flying = false
	hovering = false
	if not stats.knockback:
		return  # Vanguard BODY: keep control, no knockback
	state = State.HURT
	air_dashing = false
	hurt_timer = hurt_time
	dash_momentum = false
	if attack != null:
		attack.deactivate()
	var away := signf(global_position.x - from_x)
	if away == 0.0:
		away = -facing
	velocity = Vector2(away * 45.0, maxf(velocity.y, 0.0))


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)


func heal_full() -> void:
	for c in party:
		c.max_hp = max_hp
		if c.hp > 0:
			c.hp = max_hp
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func refill_weapons() -> void:
	for id in WeaponShot.ORDER:
		weapon_energy[id] = WeaponShot.MAX_ENERGY


## Weapon capsule: refills the selected weapon, or the emptiest one on the buster.
func add_weapon_energy(amount: float) -> void:
	var target: String = weapons[weapon_index]
	if target == "buster":
		var lowest := WeaponShot.MAX_ENERGY
		for id in weapons:
			if id != "buster" and weapon_energy[id] < lowest:
				lowest = weapon_energy[id]
				target = id
	if target != "buster":
		weapon_energy[target] = minf(weapon_energy[target] + amount, WeaponShot.MAX_ENERGY)


func current_weapon() -> String:
	return weapons[weapon_index]


func die() -> void:
	if god_mode or state == State.DEAD:
		return
	state = State.DEAD
	Autoloads.sfx("death")
	get_tree().call_group("shaker", "shake", 3.0, 0.35)
	hp = 0
	for c in party:
		c.hp = 0
	hp_changed.emit(hp, max_hp)
	velocity = Vector2.ZERO
	charging = false
	flying = false
	for id in _visuals:
		_visuals[id].visible = false
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
	hovering = false


## ECHO's small form: smaller body for 1-tile gaps. Returns false when there is
## no room to stand back up.
func set_mini(on: bool) -> bool:
	if on == mini:
		return true
	if not on and not _has_headroom():
		return false
	mini = on
	var size := MINI_SIZE if on else BODY_SIZE
	_body_shape.shape.size = size
	_body_shape.position = Vector2(0, -size.y / 2.0)
	_hurt_shape.shape.size = size - Vector2(2, 2) if on else BODY_SIZE - Vector2(4, 6)
	_hurt_shape.position = Vector2(0, -size.y / 2.0)
	_recompute_stats()
	return true


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


## Direction the body (and weapon) points: away from the wall while sliding.
func visual_facing() -> int:
	return -wall_dir if state == State.WALL_SLIDE else facing


func special_ready() -> bool:
	return character == "ix" and stats.special != "" and core >= CORE_MAX


## One-line HUD status for the active character.
func status_text() -> String:
	if attack != null:
		return attack.status_text()
	var w := current_weapon()
	if w == "buster":
		return "BUSTER"
	return "%s  %d" % [WeaponShot.INFO[w].name, int(weapon_energy[w])]


## Weapon energy 0..1 for the HUD bar, or -1 when not applicable.
func status_fraction() -> float:
	if character != "ix" or current_weapon() == "buster":
		return -1.0
	return weapon_energy[current_weapon()] / WeaponShot.MAX_ENERGY


# --- per-frame steps -----------------------------------------------------------------

func _read_input(delta: float) -> void:
	if not scripted:
		var axis := Input.get_axis("move_left", "move_right")
		in_dir = 0 if absf(axis) < 0.5 else int(signf(axis))
		in_up = Input.is_action_pressed("move_up")
		in_down = Input.is_action_pressed("move_down")
		in_jump = Input.is_action_pressed("jump")
		in_shoot = Input.is_action_pressed("shoot")
		in_dash = Input.is_action_pressed("dash")
		in_special = Input.is_action_pressed("special")
		in_tag = Input.is_action_pressed("tag")
		in_wprev = Input.is_action_pressed("weapon_prev")
		in_wnext = Input.is_action_pressed("weapon_next")
	if control_lock > 0.0:
		control_lock -= delta
		in_dir = 0
		in_up = false
		in_down = false
		in_jump = false
		in_shoot = false
		in_dash = false
		in_special = false
		in_tag = false
	jump_pressed = _edge("jump", in_jump)
	shoot_pressed = _edge("shoot", in_shoot)
	dash_pressed = _edge("dash", in_dash)
	special_pressed = _edge("special", in_special)
	tag_pressed = _edge("tag", in_tag)
	wprev_pressed = _edge("wprev", in_wprev)
	wnext_pressed = _edge("wnext", in_wnext)


func _edge(key: String, held: bool) -> bool:
	var pressed: bool = held and not _prev[key]
	_prev[key] = held
	return pressed


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
	var locked: bool = attack != null and attack.locks_movement()
	if on_floor:
		coyote_timer = coyote_time
		dash_momentum = false
		air_dashes_left = stats.air_dashes
		_dual_granted = false
		flying = false
		hover_left = _hover_time()
	wall_dir = _probe_wall()
	_zone = env.zone_at(global_position + Vector2(0, -BODY_SIZE.y / 2.0)) if env != null else ""
	_on_ice = on_floor and env != null and env.is_ice_at(global_position + Vector2(0, 2))
	var grav_mult := 1.0
	var fall_cap := max_fall_speed
	if _zone == "water":
		grav_mult = 0.45
		fall_cap = 120.0
	elif _zone == "lowg":
		grav_mult = 0.3
		fall_cap = 110.0

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
				or (in_dir != 0 and in_dir != dash_dir) or locked:
			state = State.NORMAL
	elif dash_pressed and not locked:
		if on_floor:
			_start_dash(false)
		elif air_dashes_left > 0 and state != State.WALL_SLIDE:
			_start_dash(true)

	if state == State.DASH:
		facing = dash_dir
	elif in_dir != 0 and wall_lock_timer <= 0.0 and not locked:
		facing = in_dir

	# Jump > wall kick > flight (Aero LEG) > hover (ECHO), all from a buffered press.
	if jump_buffer_timer > 0.0 and not locked:
		if on_floor or coyote_timer > 0.0:
			_jump()
		elif wall_dir != 0:
			_wall_kick()
		elif jump_pressed and stats.flight and core >= 10.0 and not flying:
			flying = true
			jump_buffer_timer = 0.0
			if air_dashing:
				_end_air_dash()
		elif jump_pressed and hover_left > 0.0 and not hovering:
			hovering = true
			jump_buffer_timer = 0.0
	if flying and (not in_jump or core <= 0.0 or on_floor):
		flying = false
	if hovering and (not in_jump or hover_left <= 0.0 or on_floor):
		hovering = false

	# Horizontal: no air inertia, like classic action platformers.
	if state == State.DASH:
		velocity.x = dash_dir * dash_speed
	elif locked and on_floor:
		velocity.x = 0.0
	elif wall_lock_timer <= 0.0:
		var target := in_dir * (dash_speed if dash_momentum else walk_speed)
		velocity.x = move_toward(velocity.x, target, 260.0 * delta) if _on_ice else target

	# Vertical.
	if air_dashing:
		velocity.y = 0.0
	elif flying:
		velocity.y = -flight_speed
		set_core(core - flight_cost * delta)
	elif hovering:
		velocity.y = 0.0
		hover_left -= delta
	else:
		if not in_jump and velocity.y < -jump_cut_velocity:
			velocity.y = -jump_cut_velocity
		if not on_floor:
			velocity.y = minf(velocity.y + gravity * grav_mult * delta, fall_cap)
	if _zone == "lift" and not air_dashing:
		velocity.y = move_toward(velocity.y, -160.0, 2200.0 * delta)

	var sliding := not on_floor and velocity.y > 0.0 and wall_dir != 0 \
			and in_dir == wall_dir and wall_lock_timer <= 0.0 and state != State.DASH and not mini
	if sliding:
		velocity.y = minf(velocity.y, wall_slide_speed)
		dash_momentum = false
		air_dashes_left = stats.air_dashes
		hover_left = _hover_time()
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


func _process_attack(delta: float) -> void:
	if attack != null:
		if wprev_pressed:
			attack.cycle(-1)
		elif wnext_pressed:
			attack.cycle(1)
		attack.update(delta)
		return
	if (wprev_pressed or wnext_pressed) and weapons.size() > 1:
		weapon_index = (weapon_index + (1 if wnext_pressed else -1) + weapons.size()) % weapons.size()
		Autoloads.sfx("weapon_switch")
		charging = false
		charge_time = 0.0
	if special_pressed and special_ready():
		_start_special(stats.special)
		return
	var w := current_weapon()
	if w != "buster":
		if shoot_pressed:
			_fire_weapon(w)
		return
	if shoot_pressed:
		_fire(0)
		charging = true
		charge_time = 0.0
	elif charging and in_shoot:
		var before := charge_time
		charge_time += delta
		if before < charge_lv1_time and charge_time >= charge_lv1_time:
			Autoloads.sfx("charge")
		elif before < charge_lv2_time and charge_time >= charge_lv2_time:
			Autoloads.sfx("charge_full")
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
				body.take_damage(stats.dash_attack, "dash")
				register_hit()
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


# --- specials (full armor sets, tag combo) --------------------------------------------------

func _start_special(kind: String) -> void:
	Autoloads.sfx("special")
	get_tree().call_group("shaker", "shake", 2.0, 0.25)
	state = State.SPECIAL
	special_kind = kind
	special_phase = 0
	_hits.clear()
	charging = false
	charge_time = 0.0
	flying = false
	gliding = false
	hovering = false
	air_dashing = false
	match kind:
		"overdrive", "tag_strike", "nova":
			if kind != "tag_strike":
				set_core(0.0)
			special_timer = {"overdrive": overdrive_time, "nova": 0.6, "tag_strike": 0.25}[kind]
			dash_dir = in_dir if in_dir != 0 else facing
			facing = dash_dir
		_:
			set_core(0.0)
			special_timer = 0.22
			velocity = Vector2(0.0, -260.0 if is_on_floor() else -60.0)


func _process_special(delta: float) -> void:
	special_timer -= delta
	if special_kind in ["overdrive", "tag_strike", "nova"]:
		var speed: float = {"overdrive": overdrive_speed, "nova": 460.0, "tag_strike": 380.0}[special_kind]
		velocity = Vector2(dash_dir * speed, 0.0)
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
			body.take_damage(special_damage + (2 if special_kind == "nova" else 0), special_kind)


func _special_after_move() -> void:
	if special_kind in ["overdrive", "tag_strike", "nova"] and is_on_wall():
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

func _character_down() -> void:
	var mate = partner()
	if mate == null or mate.hp <= 0:
		die()
		return
	var down_id := character
	party[active].hp = 0
	_puff(Color("e34f5b"))
	_leave_character()
	state = State.NORMAL
	_activate(1 - active)
	invuln_timer = 1.5
	swap_cooldown = SWAP_COOLDOWN
	notice.emit("%s 다운 — %s 교대" % [character_name(down_id), character_name()])


func _hover_time() -> float:
	return maxf(CHARACTERS[character].hover, stats.get("hover", 0.0))


func _recompute_stats() -> void:
	if character != "ix":
		stats = ArmorData.compute(ArmorData.neutral_loadout())
	elif frame == "ultimate":
		stats = ArmorData.compute_ultimate()
	else:
		stats = ArmorData.compute(loadout)
	var def: Dictionary = CHARACTERS[character]
	walk_speed = stats.walk_speed * def.walk
	dash_speed = stats.dash_speed * def.dash
	dash_time = stats.dash_time
	if mini:
		walk_speed = 110.0
	air_dashes_left = mini(air_dashes_left, stats.air_dashes)


func _start_dash(air: bool) -> void:
	Autoloads.sfx("dash")
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
		hovering = false
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
	Autoloads.sfx("jump")
	velocity.y = -jump_velocity * (0.85 if mini else 1.0) * (1.12 if _zone == "water" else 1.0)
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	dash_momentum = state == State.DASH and not air_dashing
	if dash_momentum:
		_grant_dual_core()
	if state == State.DASH:
		state = State.NORMAL
	air_dashing = false


func _wall_kick() -> void:
	Autoloads.sfx("wall_kick")
	velocity.y = -jump_velocity
	jump_buffer_timer = 0.0
	dash_momentum = in_dash
	velocity.x = -wall_dir * (dash_speed if dash_momentum else wall_kick_speed)
	wall_lock_timer = wall_kick_lock
	facing = -wall_dir
	state = State.NORMAL
	air_dashing = false
	flying = false
	hovering = false


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
		shot.source = self
		shot.breaker = stats.breaker and level > 0
		shot.homing = stats.homing and level == 0
		shot.pierce_all = stats.pierce_all and level == 2
		shot.plasma = stats.plasma and level == 2
		shot.position = origin
		get_parent().add_child(shot)
	Autoloads.sfx(["shoot", "shoot_mid", "shoot_full"][level])
	shoot_pose_timer = 0.3


func _fire_weapon(id: String) -> void:
	var info: Dictionary = WeaponShot.INFO[id]
	if weapon_energy[id] < info.cost:
		return
	if get_tree().get_nodes_in_group("weapon_" + id).size() >= info.max:
		return
	weapon_energy[id] -= info.cost
	Autoloads.sfx("weapon_fire")
	var dir := visual_facing()
	var shot := WeaponShot.new()
	shot.setup(id, dir, self)
	if id == "heat_mirage":
		shot.position = position + Vector2(10 * dir, 0)
	elif id == "pulse_ring":
		shot.position = position + Vector2(0, -14)
	else:
		shot.position = position + Vector2(MUZZLE.x * dir, MUZZLE.y)
	get_parent().add_child(shot)
	shoot_pose_timer = 0.3


func _puff(c: Color) -> void:
	var fx := Explosion.new()
	fx.size = 14.0
	fx.position = position + Vector2(0, -13)
	fx.modulate = c
	get_parent().add_child(fx)


func _has_headroom() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY_SIZE - Vector2(1, 1)
	query.shape = rect
	query.transform = Transform2D(0.0, global_position + Vector2(0, -BODY_SIZE.y / 2.0 - 0.5))
	query.collision_mask = Layers.WORLD
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


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
