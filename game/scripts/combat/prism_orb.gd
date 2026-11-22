extends "res://scripts/combat/enemy_shot.gd"
## Boss projectile: flies toward the player, then refracts into `split_count`
## shards fanned around its travel direction.

const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")

var split_after := 0.5
var split_count := 3
var spread := 0.45
var shard_speed := 150.0
var _age := 0.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_age += delta
	if split_count > 0 and _age >= split_after and not is_queued_for_deletion():
		_split()


func _split() -> void:
	var base := velocity.angle()
	for i in split_count:
		var k := 0.0 if split_count == 1 else (float(i) / (split_count - 1) - 0.5) * 2.0
		var shard := EnemyShot.new()
		shard.velocity = Vector2.from_angle(base + k * spread) * shard_speed
		shard.position = position
		get_parent().add_child(shard)
	queue_free()


func _draw() -> void:
	var c := Color("b78af3") if int(_age * 20.0) % 2 == 0 else Color("3de0ee")
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)]), c)
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
