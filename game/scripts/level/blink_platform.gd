extends StaticBody2D
## Hologram platform ('o' = phase A, 'O' = phase B). Phases alternate: while A
## is solid B is off, and vice versa. Flickers before switching off.

const Layers = preload("res://scripts/core/layers.gd")
const PERIOD := 2.4
const WARN := 0.4

var rects: Array[Rect2] = []
var phase_b := false
var solid := true
var _clock := 0.0


func _ready() -> void:
	collision_mask = 0
	for r in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center()
		add_child(cs)
	_apply(_is_on())


func _physics_process(delta: float) -> void:
	_clock = fmod(_clock + delta, PERIOD)
	var on := _is_on()
	if on != solid:
		_apply(on)
	queue_redraw()


func _is_on() -> bool:
	var first_half := _clock < PERIOD / 2.0
	return first_half != phase_b


func _time_left_on() -> float:
	var half := PERIOD / 2.0
	return (half - _clock) if _clock < half else (PERIOD - _clock)


func _apply(on: bool) -> void:
	solid = on
	collision_layer = Layers.WORLD if on else 0


func _draw() -> void:
	var c := Color("b78af3") if phase_b else Color("3de0ee")
	for r in rects:
		if solid:
			var warn := _time_left_on() < WARN and int(_clock * 20.0) % 2 == 0
			var a := 0.35 if warn else 0.8
			draw_rect(r, Color(c, a * 0.45))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(c, a))
			var x := r.position.x + 3.0
			while x < r.end.x:
				draw_rect(Rect2(x, r.position.y + 5, 6, 1), Color(c, a * 0.6))
				x += 8.0
		else:
			draw_rect(r, Color(c, 0.25), false, 1.0)
