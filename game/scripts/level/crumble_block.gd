extends StaticBody2D
## Crumbling floor ('c', one object per horizontal run): shakes for SHAKE seconds
## after the player stands on it, falls away, and returns after RESPAWN seconds.

const Layers = preload("res://scripts/core/layers.gd")
const SHAKE := 0.5
const RESPAWN := 4.0

var rect := Rect2()
var _timer := -1.0  # < 0 idle, counting down while shaking
var _gone := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	add_child(cs)


func _physics_process(delta: float) -> void:
	_t += delta
	if _gone > 0.0:
		_gone -= delta
		if _gone <= 0.0 and not _player_inside():
			collision_layer = Layers.WORLD
		elif _gone <= 0.0:
			_gone = 0.2
		queue_redraw()
		return
	if _timer < 0.0 and _player_on_top():
		_timer = SHAKE
	if _timer >= 0.0:
		_timer -= delta
		if _timer < 0.0:
			collision_layer = 0
			_gone = RESPAWN
		queue_redraw()


func _player_on_top() -> bool:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not p.is_on_floor():
		return false
	var feet: Vector2 = p.global_position
	return absf(feet.y - rect.position.y) < 3.0 and feet.x > rect.position.x - 6.0 and feet.x < rect.end.x + 6.0


func _player_inside() -> bool:
	var p = get_tree().get_first_node_in_group("player")
	return p != null and rect.grow(6.0).has_point(p.global_position + Vector2(0, -8))


func _draw() -> void:
	if _gone > 0.0:
		draw_rect(rect, Color("9fc274", 0.15), false, 1.0)
		return
	var shake := Vector2(sin(_t * 70.0) * 1.0, 0) if _timer >= 0.0 else Vector2.ZERO
	var r := Rect2(rect.position + shake, rect.size)
	draw_rect(r, Color("4a5a3a"))
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x + 3, r.position.y + 3), Vector2(x + 9, r.position.y + 12), Color("2a3550"), 1.0)
		x += 16.0
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color("9fc274"))
