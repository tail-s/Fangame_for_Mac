extends CharacterBody2D
## Base class for stage bosses (GDD v0.2 §5). A subclass implements the fight in
## _boss_process() and the look in _boss_draw(); this class handles HP, the
## weakness bonus with a capped stagger, hit flash / i-frames, the intro, the
## death sequence and the signals main.gd listens to.
##
## Contract with main.gd
##   set before add_child: `arena` (Rect2, inner empty room), `player`, `position`
##   (the spawn marker cell centre)
##   signals: hp_changed(hp, max_hp), defeated
##   get_max_hp(), take_damage(amount, weapon) -> bool, get_contact_damage()
##
## Subclasses set the tunables below in _init() and override the hooks.
## Bosses move kinematically (set `position` directly) and stay inside `arena`.

signal hp_changed(hp: int, max_hp: int)
signal defeated

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")
const PrismOrb = preload("res://scripts/combat/prism_orb.gd")

# --- tunables (set in the subclass _init) ---
var boss_name := "BOSS"
var max_hp := 32
## Weapon id that hits this boss hard (GDD §5-2 weakness loop), "" for none.
var weakness := ""
var weak_mult := 2.5
## A weakness hit interrupts the pattern at most this often (no stun lock).
var stagger_cooldown := 2.5
var contact_damage := 3
var hit_radius := 11.0
var intro_time := 1.2
var death_time := 1.8

# --- state ---
var arena := Rect2()
var player
var hp := 0
var phase2 := false
## -1 = facing left, 1 = facing right (for drawing / aiming).
var facing := -1.0
## Seconds since spawn.
var t := 0.0
## False during the intro and the death sequence (no damage taken or dealt).
var active := false

var _flash := 0.0
var _invuln := 0.0
var _stagger_cd := 0.0
var _dying := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = Layers.ENEMY
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	cs.shape = circle
	add_child(cs)
	hp = max_hp
	_rng.randomize()
	_boss_ready()


func get_max_hp() -> int:
	return max_hp


func get_contact_damage() -> int:
	return contact_damage if active else 0


## Returns true if this hit destroyed the boss.
func take_damage(amount: int, weapon := "") -> bool:
	if not active or _invuln > 0.0 or _dying >= 0.0:
		return false
	if weakness != "" and weapon == weakness:
		amount = ceili(amount * weak_mult)
		if _stagger_cd <= 0.0:
			_stagger_cd = stagger_cooldown
			_on_stagger()
	amount = _modify_damage(amount, weapon)
	if amount <= 0:
		return false
	hp = maxi(hp - amount, 0)
	_flash = 0.08
	_invuln = 0.08
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		_start_death()
		return true
	if not phase2 and hp <= max_hp / 2:
		phase2 = true
		_on_phase2()
	return false


func _physics_process(delta: float) -> void:
	t += delta
	_flash = maxf(_flash - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_stagger_cd = maxf(_stagger_cd - delta, 0.0)
	if _dying >= 0.0:
		_process_death(delta)
		return
	if not active:
		_boss_intro(delta)
		intro_time -= delta
		if intro_time <= 0.0:
			active = true
			_on_active()
	else:
		_boss_process(delta)
	queue_redraw()


func _draw() -> void:
	_boss_draw(_flash > 0.0 and int(t * 30.0) % 2 == 0)


# --- hooks to override ---------------------------------------------------------

func _boss_ready() -> void:
	pass


## Runs every frame until `intro_time` runs out (e.g. drop into the arena).
func _boss_intro(_delta: float) -> void:
	pass


func _on_active() -> void:
	pass


## The fight: run your pattern state machine here.
func _boss_process(_delta: float) -> void:
	pass


## Draw the boss around (0, 0). `white` is true on hit-flash frames.
func _boss_draw(white: bool) -> void:
	draw_circle(Vector2.ZERO, hit_radius, Color.WHITE if white else Color("6543a2"))


## A weakness hit: interrupt the current pattern (move to a recovery state).
func _on_stagger() -> void:
	pass


func _on_phase2() -> void:
	pass


## Last chance to change incoming damage (e.g. learned resistances). Return 0 to ignore.
func _modify_damage(amount: int, _weapon: String) -> int:
	return amount


func _on_death() -> void:
	pass


# --- helpers ------------------------------------------------------------------------

func player_pos() -> Vector2:
	if player != null and is_instance_valid(player):
		return player.global_position + Vector2(0, -13)
	return arena.get_center()


func floor_y() -> float:
	return arena.end.y


func rng() -> RandomNumberGenerator:
	return _rng


## Fires a plain enemy shot (world space position / velocity).
func shoot(pos: Vector2, vel: Vector2, damage := 2):
	var s := EnemyShot.new()
	s.velocity = vel
	s.damage = damage
	s.position = pos
	get_parent().add_child(s)
	return s


## Fires a prism orb that splits into `split` shards after `split_after` seconds.
func shoot_orb(pos: Vector2, vel: Vector2, split := 3, split_after := 0.5):
	var o := PrismOrb.new()
	o.velocity = vel
	o.split_count = split
	o.split_after = split_after
	o.position = pos
	get_parent().add_child(o)
	return o


func fx(pos: Vector2, size := 10.0) -> void:
	var e := Explosion.new()
	e.size = size
	e.position = pos
	get_parent().add_child(e)


func clamp_to_arena(margin: float) -> void:
	position = position.clamp(arena.position + Vector2(margin, margin), arena.end - Vector2(margin, margin))


func _start_death() -> void:
	active = false
	_dying = death_time
	for s in get_tree().get_nodes_in_group("enemy_shot"):
		s.queue_free()
	_on_death()


func _process_death(delta: float) -> void:
	_dying -= delta
	if int(t * 10.0) % 2 == 0:
		fx(position + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-12, 12)))
	queue_redraw()
	if _dying <= 0.0:
		var e := Explosion.new()
		e.big = true
		e.position = position
		get_parent().add_child(e)
		defeated.emit()
		queue_free()
