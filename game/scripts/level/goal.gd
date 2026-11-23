extends Area2D
## Stage exit gate.

signal reached

const Layers = preload("res://scripts/core/layers.gd")
## Pylons and lintel (tools/bake_devices.gd); the field is drawn below.
const TEX = preload("res://art/devices/goal.png")
const GOAL_SIZE := Vector2(32, 50)

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
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	# Exit field between the pylons: glow, bright edges by the emitter strips,
	# scan lines and sparks rising through it.
	draw_rect(Rect2(-9, -41, 18, 41), Color(0.0, 0.72, 0.75, 0.2 + 0.2 * pulse))
	draw_rect(Rect2(-9, -41, 1, 41), Color(0.54, 0.96, 0.97, 0.35 + 0.25 * pulse))
	draw_rect(Rect2(8, -41, 1, 41), Color(0.54, 0.96, 0.97, 0.35 + 0.25 * pulse))
	for i in 4:
		var y := -1.0 - floorf(fmod(_t * 30.0 + i * 10.0, 39.0))
		draw_rect(Rect2(-8, y, 16, 1), Color(0.84, 0.93, 0.95, 0.5))
		draw_rect(Rect2(-4 + (i % 2) * 4, y, 4, 1), Color(0.95, 1.0, 1.0, 0.8))
	for i in 5:
		var x := -7.0 + float((i * 7) % 15)
		var y := -2.0 - floorf(fmod(_t * (16.0 + i * 5.0) + i * 9.0, 37.0))
		draw_rect(Rect2(x, y, 1, 1 + (i % 2)), Color(0.9, 1.0, 1.0, 0.85))
	draw_texture(TEX, Vector2(-GOAL_SIZE.x / 2.0, -GOAL_SIZE.y))
	# Emitter strips flare with the pulse.
	for ey in [-38, -29, -20, -11]:
		draw_rect(Rect2(-10, ey, 1, 4), Color(1, 1, 1, 0.55 * pulse))
		draw_rect(Rect2(9, ey, 1, 4), Color(1, 1, 1, 0.55 * pulse))
