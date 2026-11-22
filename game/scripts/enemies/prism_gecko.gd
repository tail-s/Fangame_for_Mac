extends CharacterBody2D
## PRISM GECKO — prototype boss (GDD v0.2 §5).
## Crawls along the floor, walls and ceiling of its arena and drops on the
## player, clings to a wall to fire refracting prism orbs, and in phase 2
## (HP <= 50%) spawns hologram decoys. Moves kinematically inside `arena`.

signal hp_changed(hp: int, max_hp: int)
signal defeated

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const PrismOrb = preload("res://scripts/combat/prism_orb.gd")
const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")

const MAX_HP := 32
## GDD §5-2 weakness loop: Pulse Ring (Pulse Cicada's weapon) beats Prism Gecko.
const WEAKNESS := "pulse_ring"
const WEAK_MULT := 2.5
const STAGGER_COOLDOWN := 2.5
const HALF := 9.0  # distance from body centre to the surface it clings to
const GRAVITY := 900.0

enum S { INTRO, IDLE, RUN, CLIMB, CEILING, DROP, LEAP, WALL_FIRE, DECOY, DEAD }

var arena := Rect2()
var player
var is_decoy := false
var hp := MAX_HP
var state := S.INTRO
var surface := "ceiling"  # floor | ceiling | left | right
var move := Vector2.ZERO
var face := 1.0
var phase2 := false
var contact_damage := 3

var _timer := 0.0
var _flash := 0.0
var _invuln := 0.0
var _t := 0.0
var _vy := 0.0
var _shots_left := 0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_time := 0.0
var _decoys: Array = []
var _rng := RandomNumberGenerator.new()
var _last_pattern := -1
var _stagger_cd := 0.0


func _ready() -> void:
	add_to_group("enemy")
	if not is_decoy:
		add_to_group("boss")
	collision_layer = Layers.ENEMY
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	cs.shape = circle
	add_child(cs)
	_rng.randomize()
	if not is_decoy:
		position = Vector2(position.x, arena.position.y + HALF)
		_timer = 0.8


func get_contact_damage() -> int:
	return 0 if is_decoy else contact_damage


## Returns true if this hit destroyed the boss (or popped a decoy).
## The weakness weapon hits harder and interrupts the current pattern, at most
## once per STAGGER_COOLDOWN (no infinite stun, GDD §5-2).
func take_damage(amount: int, weapon := "") -> bool:
	if is_decoy:
		_pop()
		return true
	if state in [S.INTRO, S.DEAD] or _invuln > 0.0:
		return false
	if weapon == WEAKNESS:
		amount = ceili(amount * WEAK_MULT)
		if _stagger_cd <= 0.0 and state not in [S.DROP, S.IDLE]:
			_stagger_cd = STAGGER_COOLDOWN
			_clear_decoys()
			_begin_drop()
	hp = maxi(hp - amount, 0)
	_flash = 0.08
	_invuln = 0.08
	hp_changed.emit(hp, MAX_HP)
	if hp == 0:
		_start_death()
		return true
	if not phase2 and hp <= MAX_HP / 2:
		phase2 = true
	return false


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_stagger_cd = maxf(_stagger_cd - delta, 0.0)
	if is_decoy:
		queue_redraw()
		return
	_timer -= delta
	var before := position
	match state:
		S.INTRO:
			if _timer <= 0.0:
				_begin_drop()
		S.IDLE:
			if _timer <= 0.0:
				_choose_pattern()
		S.RUN:
			position.x += move.x * delta
			if position.x <= arena.position.x + HALF or position.x >= arena.end.x - HALF:
				position.x = clampf(position.x, arena.position.x + HALF, arena.end.x - HALF)
				surface = "left" if move.x < 0.0 else "right"
				move = Vector2(0, -_speed(150.0))
				state = S.CLIMB
		S.CLIMB:
			position.y += move.y * delta
			if position.y <= arena.position.y + HALF:
				position.y = arena.position.y + HALF
				surface = "ceiling"
				var to_player := signf(_player_x() - position.x)
				move = Vector2((to_player if to_player != 0.0 else 1.0) * _speed(170.0), 0)
				state = S.CEILING
		S.CEILING:
			position.x += move.x * delta
			var reached_wall := position.x <= arena.position.x + HALF + 1.0 or position.x >= arena.end.x - HALF - 1.0
			position.x = clampf(position.x, arena.position.x + HALF, arena.end.x - HALF)
			if absf(position.x - _player_x()) < 6.0 or reached_wall:
				_begin_drop()
		S.DROP:
			_vy = minf(_vy + GRAVITY * delta, 420.0)
			position.y += _vy * delta
			if position.y >= arena.end.y - HALF:
				position.y = arena.end.y - HALF
				surface = "floor"
				if phase2:
					_ground_shards()
				_idle(0.5)
		S.LEAP:
			_leap_time += delta
			var k := clampf(_leap_time / 0.5, 0.0, 1.0)
			position = _leap_from.lerp(_leap_to, k) + Vector2(0, -sin(k * PI) * 40.0)
			if k >= 1.0:
				surface = "left" if _leap_to.x < arena.get_center().x else "right"
				state = S.WALL_FIRE
				_shots_left = 3 if phase2 else 2
				_timer = 0.35
		S.WALL_FIRE:
			if _timer <= 0.0:
				if _shots_left > 0:
					_fire_orb(5 if phase2 else 3)
					_shots_left -= 1
					_timer = 0.55 if phase2 else 0.7
				else:
					_begin_drop()
		S.DECOY:
			if _timer <= 0.0:
				if _shots_left > 0:
					_decoy_volley()
					_shots_left -= 1
					_timer = 0.6
				else:
					_clear_decoys()
					_idle(0.4)
		S.DEAD:
			if _timer <= 0.0:
				_finish_death()
				return
			if int(_t * 10.0) % 2 == 0:
				var fx := Explosion.new()
				fx.position = position + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-10, 10))
				get_parent().add_child(fx)
	var delta_pos := position - before
	if delta_pos.length() > 0.01:
		var along := _surface_axis()
		var d := delta_pos.dot(along)
		if absf(d) > 0.01:
			face = signf(d)
	queue_redraw()


# --- patterns ------------------------------------------------------------------

func _choose_pattern() -> void:
	var pattern := _rng.randi_range(0, 1)
	if phase2 and _rng.randf() < 0.35 and _last_pattern != 2:
		pattern = 2
	elif pattern == _last_pattern and _rng.randf() < 0.6:
		pattern = 1 - pattern
	_last_pattern = pattern
	match pattern:
		0:
			var dir := signf(_player_x() - position.x)
			move = Vector2((dir if dir != 0.0 else 1.0) * _speed(170.0), 0)
			state = S.RUN
		1:
			var left := _player_x() > arena.get_center().x
			_leap_from = position
			var wall_x := arena.position.x + HALF if left else arena.end.x - HALF
			_leap_to = Vector2(wall_x, arena.get_center().y - 8.0)
			_leap_time = 0.0
			state = S.LEAP
		2:
			_start_decoys()


func _begin_drop() -> void:
	surface = "ceiling" if surface == "ceiling" else surface
	_vy = 0.0
	state = S.DROP


func _idle(time: float) -> void:
	state = S.IDLE
	surface = "floor"
	_timer = time * (0.65 if phase2 else 1.0)


func _speed(base: float) -> float:
	return base * (1.3 if phase2 else 1.0)


func _fire_orb(split: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var orb := PrismOrb.new()
	var target: Vector2 = player.global_position + Vector2(0, -13)
	orb.velocity = (target - global_position).normalized() * 120.0
	orb.split_count = split
	orb.position = position
	get_parent().add_child(orb)


func _ground_shards() -> void:
	for d in [-1, 1]:
		var shard := EnemyShot.new()
		shard.velocity = Vector2(d * 130.0, 0)
		shard.position = position + Vector2(0, HALF - 4.0)
		get_parent().add_child(shard)


func _start_decoys() -> void:
	state = S.DECOY
	_shots_left = 3
	_timer = 0.5
	var xs := [arena.position.x + 40.0, arena.get_center().x, arena.end.x - 40.0]
	xs.shuffle()
	surface = "floor"
	position = Vector2(xs[0], arena.end.y - HALF)
	_flash = 0.3
	for i in 2:
		var d = load(get_script().resource_path).new()
		d.is_decoy = true
		d.arena = arena
		d.surface = "floor"
		d.face = face
		d.position = Vector2(xs[i + 1], arena.end.y - HALF)
		get_parent().add_child(d)
		_decoys.append(d)


func _decoy_volley() -> void:
	_fire_orb(0)
	for d in _decoys:
		if is_instance_valid(d) and player != null:
			var orb := PrismOrb.new()
			var target: Vector2 = player.global_position + Vector2(0, -13)
			orb.velocity = (target - d.global_position).normalized() * 120.0
			orb.split_count = 0
			orb.position = d.position
			get_parent().add_child(orb)


func _clear_decoys() -> void:
	for d in _decoys:
		if is_instance_valid(d):
			d._pop()
	_decoys.clear()


func _pop() -> void:
	if is_queued_for_deletion():
		return
	var fx := Explosion.new()
	fx.size = 10.0
	fx.position = position
	get_parent().add_child.call_deferred(fx)
	queue_free()


func _start_death() -> void:
	state = S.DEAD
	_timer = 1.8
	_clear_decoys()
	for s in get_tree().get_nodes_in_group("enemy_shot"):
		s.queue_free()


func _finish_death() -> void:
	var fx := Explosion.new()
	fx.big = true
	fx.position = position
	get_parent().add_child(fx)
	defeated.emit()
	queue_free()


# --- helpers ------------------------------------------------------------------

func _player_x() -> float:
	if player != null and is_instance_valid(player):
		return player.global_position.x
	return arena.get_center().x


func _surface_rotation() -> float:
	match surface:
		"ceiling":
			return PI
		"left":
			return PI / 2.0
		"right":
			return -PI / 2.0
	return 0.0


func _surface_axis() -> Vector2:
	return Vector2.from_angle(_surface_rotation())


func _draw() -> void:
	var rot := _surface_rotation()
	if state == S.LEAP or state == S.DROP:
		rot = 0.0 if state == S.DROP else rot
	draw_set_transform(Vector2.ZERO, rot, Vector2(face, 1.0))
	var white := _flash > 0.0 and int(_t * 30.0) % 2 == 0
	var body := Color.WHITE if white else Color("6543a2")
	var alpha := 1.0
	if is_decoy:
		alpha = 0.55 + 0.25 * sin(_t * 18.0)
	elif state == S.DECOY:
		alpha = 0.75 + 0.2 * sin(_t * 18.0)
	var a := func(c: Color) -> Color: return Color(c, c.a * alpha)
	# tail
	draw_polyline(PackedVector2Array([Vector2(-10, 3), Vector2(-16, 0), Vector2(-21, 3),
			Vector2(-24, -1)]), a.call(body.darkened(0.2)), 3.0)
	# legs
	var step := sin(_t * 16.0) * 2.0 if state in [S.RUN, S.CLIMB, S.CEILING] else 0.0
	for lx in [-7.0, 6.0]:
		draw_line(Vector2(lx, 3), Vector2(lx - 3 + step, 9), a.call(Color("2a3550")), 2.0)
		draw_line(Vector2(lx + 2, 3), Vector2(lx + 5 - step, 9), a.call(Color("2a3550")), 2.0)
	# body + prism back plates
	draw_colored_polygon(PackedVector2Array([Vector2(-12, 4), Vector2(10, 4), Vector2(13, -1),
			Vector2(8, -6), Vector2(-9, -6)]), a.call(body))
	var plates := [Color("3de0ee"), Color("b78af3"), Color("f0b84a")]
	for i in 3:
		var px := -8.0 + i * 6.0
		draw_colored_polygon(PackedVector2Array([Vector2(px, -6), Vector2(px + 3, -12),
				Vector2(px + 6, -6)]), a.call(Color.WHITE if white else plates[i]))
	# head
	draw_colored_polygon(PackedVector2Array([Vector2(9, -5), Vector2(18, -3), Vector2(19, 2),
			Vector2(10, 4)]), a.call(body.lightened(0.15)))
	draw_rect(Rect2(14, -3, 3, 2), a.call(Color("f0b84a")))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
