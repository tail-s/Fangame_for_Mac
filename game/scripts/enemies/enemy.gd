extends CharacterBody2D
## Base class for prototype enemies: HP, hit flash, contact damage, freeze,
## copy data for ECHO, item drops and the death burst.
## Enemies only collide with the world; the player passes through them and takes
## contact damage via its hurtbox.

const Autoloads = preload("res://scripts/core/autoloads.gd")

signal killed

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const Drop = preload("res://scripts/level/drop.gd")
const GRAVITY := 900.0

@export var max_hp := 3
@export var contact_damage := 2
## What ECHO gets when a copy round destroys this enemy ("" = nothing).
@export var copy_kind := ""
@export var drop_chance := 0.35

var hp := 0
var flash := 0.0
var frozen := 0.0


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = body_size()
	cs.shape = rect
	cs.position = Vector2(0, -rect.size.y / 2.0)
	add_child(cs)


func body_size() -> Vector2:
	return Vector2(14, 12)


func get_contact_damage() -> int:
	return 0 if frozen > 0.0 else contact_damage


## Returns true if this hit destroyed the enemy. `weapon` is the attack id.
func take_damage(amount: int, _weapon := "") -> bool:
	if hp <= 0:
		return false
	hp -= amount
	flash = 0.08
	queue_redraw()
	if hp <= 0:
		_die()
		return true
	Autoloads.sfx("enemy_hit")
	return false


## Freeze Lance: stop moving and attacking for `seconds`.
func freeze(seconds: float) -> void:
	frozen = maxf(frozen, seconds)


func find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p != null and p.is_alive():
		return p
	return null


func _die() -> void:
	Autoloads.sfx("enemy_die")
	var fx := Explosion.new()
	fx.position = position + Vector2(0, -body_size().y / 2.0)
	get_parent().add_child(fx)
	if randf() < drop_chance:
		var drop := Drop.new()
		drop.kind = "hp" if randf() < 0.5 else "energy"
		drop.position = position + Vector2(0, -4)
		get_parent().add_child.call_deferred(drop)
	killed.emit()
	queue_free()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, 330.0)


func _tick_flash(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(flash - delta, 0.0)


## Shared frozen-state step; returns true while frozen (skip normal behaviour).
func _tick_frozen(delta: float) -> bool:
	if frozen <= 0.0:
		return false
	frozen = maxf(frozen - delta, 0.0)
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	queue_redraw()
	return true


func _draw_frozen() -> void:
	if frozen > 0.0:
		var s := body_size()
		draw_rect(Rect2(-s.x / 2.0 - 1, -s.y - 1, s.x + 2, s.y + 2), Color(0.57, 0.85, 0.98, 0.55))
