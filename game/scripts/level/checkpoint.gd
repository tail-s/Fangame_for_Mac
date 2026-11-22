extends Area2D
## Respawn point. Lights up when the player touches it.

signal reached(pos: Vector2)

const Layers = preload("res://scripts/core/layers.gd")

var active := false
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 40)
	cs.shape = rect
	cs.position = Vector2(0, -20)
	add_child(cs)
	body_entered.connect(_on_body_entered)


## announce = false when restoring an already-reached checkpoint after a respawn.
func activate(announce := true) -> void:
	if active:
		return
	active = true
	if announce:
		reached.emit(global_position)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		activate()


func _process(delta: float) -> void:
	_t += delta
	if active:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-1, -30, 2, 30), Color("497593"))
	draw_rect(Rect2(-4, -2, 8, 2), Color("497593"))
	var c := Color("00b8be") if active else Color("2a3550")
	if active:
		draw_circle(Vector2(0, -31.5), 5.0 + sin(_t * 6.0) * 1.5, Color(c, 0.25))
	draw_rect(Rect2(-3, -34, 6, 5), c)
