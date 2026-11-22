extends AnimatableBody2D
## Moving platform: 'm' runs slide left-right, 'n' runs bob up-down, by AMPLITUDE
## pixels over PERIOD seconds. The player rides it through move_and_slide().

const Layers = preload("res://scripts/core/layers.gd")
const AMPLITUDE := 48.0
const PERIOD := 3.2

var rect := Rect2()
var axis := Vector2.RIGHT
var _base := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = true
	_base = rect.position
	position = _base
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.size / 2.0
	add_child(cs)


func _physics_process(delta: float) -> void:
	_t += delta
	position = _base + axis * sin(_t * TAU / PERIOD) * AMPLITUDE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, rect.size)
	draw_rect(r, Color("2a3550"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color("f0b84a"))
	var x := 4.0
	while x < r.size.x:
		draw_rect(Rect2(x, 6, 4, 2), Color("f0b84a", 0.5))
		x += 12.0
