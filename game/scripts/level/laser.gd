extends Node2D
## Laser emitter ('>' '<' 'v') whose beam follows mirrors ('/' '\') until it
## hits a wall. Cycles: off -> warning -> on. Touching the beam deals damage.

const Layers = preload("res://scripts/core/layers.gd")
const DamageZone = preload("res://scripts/level/damage_zone.gd")
const WIDTH := 4.0
const OFF_TIME := 1.4
const WARN_TIME := 0.5
const ON_TIME := 1.6

var segments: Array = []  # [Vector2 from, Vector2 to] pairs in world space
var emitter_rect := Rect2()
var phase_offset := 0.0
var damage := 3
## "laser" (red beam) or "flame" (heat vent, drawn as a flame column).
var style := "laser"
var _clock := 0.0
var _area
var _t := 0.0


func _ready() -> void:
	_clock = phase_offset
	_area = DamageZone.new()
	_area.damage = damage
	_area.collision_layer = 0
	_area.collision_mask = 0
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(absf(b.x - a.x), absf(b.y - a.y)) + Vector2(WIDTH, WIDTH)
		cs.shape = shape
		cs.position = (a + b) / 2.0
		_area.add_child(cs)
	add_child(_area)


func is_on() -> bool:
	return _clock >= OFF_TIME + WARN_TIME


func _physics_process(delta: float) -> void:
	_t += delta
	_clock = fmod(_clock + delta, OFF_TIME + WARN_TIME + ON_TIME)
	_area.collision_layer = Layers.HAZARD if is_on() else 0
	queue_redraw()


func _draw() -> void:
	draw_rect(emitter_rect, Color("2a3550"))
	var hot := Color("ef9352") if style == "flame" else Color("e34f5b")
	draw_rect(emitter_rect.grow(-3.0), hot if is_on() else Color("6543a2"))
	var warn := _clock >= OFF_TIME and not is_on()
	if not (warn or is_on()):
		return
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if is_on() and style == "flame":
			var w := WIDTH + 4.0 + sin(_t * 40.0) * 2.0
			draw_line(a, b, Color("ef9352", 0.85), w + 2.0)
			draw_line(a, b, Color("f0b84a"), w * 0.5)
		elif is_on():
			var w := WIDTH + sin(_t * 60.0)
			draw_line(a, b, Color("e34f5b"), w + 2.0)
			draw_line(a, b, Color("ffd6d6"), 1.0)
		elif int(_t * 16.0) % 2 == 0:
			draw_line(a, b, Color("ef9352" if style == "flame" else "e34f5b", 0.6), 1.0)
