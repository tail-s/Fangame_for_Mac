extends Area2D
## Stage exit gate.

signal reached

const Layers = preload("res://scripts/core/layers.gd")

var _done := false
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 40)
	cs.shape = rect
	cs.position = Vector2(0, -20)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not _done:
		_done = true
		reached.emit()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pillar := Color("497593")
	draw_rect(Rect2(-13, -40, 4, 40), pillar)
	draw_rect(Rect2(9, -40, 4, 40), pillar)
	draw_rect(Rect2(-13, -42, 26, 3), pillar)
	var glow := 0.35 + 0.25 * sin(_t * 5.0)
	draw_rect(Rect2(-9, -39, 18, 39), Color(0.0, 0.72, 0.75, glow))
	for i in 4:
		var y := -fmod(_t * 30.0 + i * 10.0, 39.0)
		draw_rect(Rect2(-6, y, 12, 1), Color(0.84, 0.93, 0.95, 0.6))
