extends Area2D
## Sky Breaker landing wave: runs along the ground and hits each enemy once.

const Layers = preload("res://scripts/core/layers.gd")

var dir := 1
var speed := 240.0
var damage := 3
var life := 0.6
var _t := 0.0
var _hit := {}


func _ready() -> void:
	collision_layer = Layers.PLAYER_SHOT
	collision_mask = Layers.ENEMY
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 18)
	cs.shape = rect
	cs.position = Vector2(0, -9)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position.x += dir * speed * delta
	_t += delta
	if _t >= life:
		queue_free()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not _hit.has(body):
		_hit[body] = true
		body.take_damage(damage)


func _draw() -> void:
	var a := 1.0 - _t / life
	var h := 18.0 * (0.6 + 0.4 * sin(_t * 40.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7 * dir, 0), Vector2(5 * dir, -h), Vector2(8 * dir, 0)]), Color(0.44, 0.87, 0.87, a))
	draw_line(Vector2(-10 * dir, -1), Vector2(8 * dir, -1), Color(1, 1, 1, a), 2.0)
