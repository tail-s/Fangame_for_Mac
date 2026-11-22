extends Area2D
## Enemy projectile. The player's hurtbox detects it and calls hit().

const Layers = preload("res://scripts/core/layers.gd")

var velocity := Vector2.ZERO
var damage := 2
var life := 3.0


func _ready() -> void:
	add_to_group("enemy_shot")
	collision_layer = Layers.ENEMY_SHOT
	collision_mask = Layers.WORLD
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 3.0
	cs.shape = circle
	add_child(cs)
	body_entered.connect(func(_body: Node) -> void: hit())


func hit() -> void:
	if not is_queued_for_deletion():
		queue_free()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.5, Color("e34f5b"))
	draw_circle(Vector2.ZERO, 1.5, Color("ffd6d6"))
