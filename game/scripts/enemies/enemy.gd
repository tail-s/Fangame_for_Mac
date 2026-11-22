extends CharacterBody2D
## Base class for prototype enemies: HP, hit flash, contact damage, death burst.
## Enemies only collide with the world; the player passes through them and takes
## contact damage via its hurtbox.

signal killed

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const GRAVITY := 900.0

@export var max_hp := 3
@export var contact_damage := 2

var hp := 0
var flash := 0.0


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
	return contact_damage


## Returns true if this hit destroyed the enemy.
func take_damage(amount: int) -> bool:
	if hp <= 0:
		return false
	hp -= amount
	flash = 0.08
	queue_redraw()
	if hp <= 0:
		_die()
		return true
	return false


func find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p != null and p.is_alive():
		return p
	return null


func _die() -> void:
	var fx := Explosion.new()
	fx.position = position + Vector2(0, -body_size().y / 2.0)
	get_parent().add_child(fx)
	killed.emit()
	queue_free()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, 330.0)


func _tick_flash(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(flash - delta, 0.0)
