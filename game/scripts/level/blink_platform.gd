extends StaticBody2D
## Hologram platform ('o' = phase A, 'O' = phase B). Phases alternate: while A
## is solid B is off, and vice versa. Flickers before switching off.

const Layers = preload("res://scripts/core/layers.gd")
const PERIOD := 2.4
const WARN := 0.4
const OUTLINE := Color("0a1326")
## Device steel (same family as tools/bake_devices.gd), deep -> light.
const STEEL := [Color("161d33"), Color("3c5576"), Color("5f88a8"), Color("b4d4e6")]

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
	var lite := c.lerp(Color.WHITE, 0.6)
	var warn := solid and _time_left_on() < WARN
	var flick := int(_clock * 20.0) % 2 == 0
	for r in rects:
		if solid:
			# Flicker before switching off: dimmed, scan lines torn sideways.
			_panel(r, c, lite, 0.4 if warn and flick else 1.0, 1.0 if warn and flick else 0.0)
		else:
			_ghost(r, c)
		_projectors(r, c, lite, solid and not (warn and flick))


## Hard-light panel: translucent body with scan lines, bright lit top edge,
## light cells along the top, a fainter frame down the sides and bottom.
func _panel(r: Rect2, c: Color, lite: Color, a: float, tear: float) -> void:
	draw_rect(r, Color(c, 0.3 * a))
	var y := r.position.y + 3.0
	var row := 0
	while y < r.end.y - 1.0:
		var dx := tear * (1.0 if row % 2 == 0 else -1.0)
		draw_rect(Rect2(r.position.x + 1.0 + dx, y, r.size.x - 2.0, 1.0), Color(c, 0.22 * a))
		y += 2.0
		row += 1
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(lite, 0.95 * a))
	draw_rect(Rect2(r.position + Vector2(0, 1), Vector2(r.size.x, 1)), Color(c, 0.85 * a))
	draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(c, 0.55 * a))
	draw_rect(Rect2(r.position.x, r.position.y + 2.0, 1.0, r.size.y - 3.0), Color(c, 0.6 * a))
	draw_rect(Rect2(r.end.x - 1.0, r.position.y + 2.0, 1.0, r.size.y - 3.0), Color(c, 0.6 * a))
	var x := r.position.x + 6.0
	while x < r.end.x - 6.0:
		draw_rect(Rect2(x, r.position.y + 4.0, 4.0, 1.0), Color(lite, 0.6 * a))
		draw_rect(Rect2(x, r.position.y + 5.0, 4.0, 1.0), Color(c, 0.35 * a))
		x += 8.0


## Off phase: a dashed outline where the platform will reappear.
func _ghost(r: Rect2, c: Color) -> void:
	var col := Color(c, 0.3)
	var x := r.position.x
	while x < r.end.x:
		draw_rect(Rect2(x, r.position.y, 2.0, 1.0), col)
		draw_rect(Rect2(x, r.end.y - 1.0, 2.0, 1.0), col)
		x += 4.0
	var y := r.position.y + 4.0
	while y < r.end.y - 2.0:
		draw_rect(Rect2(r.position.x, y, 1.0, 2.0), col)
		draw_rect(Rect2(r.end.x - 1.0, y, 1.0, 2.0), col)
		y += 4.0


## Projector clamps at both ends (always there, so the spot reads in the off
## phase too); their lamps light while the panel is solid.
func _projectors(r: Rect2, c: Color, lite: Color, lit: bool) -> void:
	for side in 2:
		var x := r.position.x + 1.0 if side == 0 else r.end.x - 4.0
		var y := r.position.y + 4.0
		draw_rect(Rect2(x, y, 3.0, 8.0), OUTLINE)
		draw_rect(Rect2(x + 1.0, y + 1.0, 1.0, 6.0), STEEL[2])
		draw_rect(Rect2(x + 1.0, y + 1.0, 1.0, 1.0), STEEL[3])
		draw_rect(Rect2(x + 1.0, y + 6.0, 1.0, 1.0), STEEL[0])
		draw_rect(Rect2(x + 1.0, y + 3.0, 1.0, 2.0), lite if lit else c.darkened(0.5))
