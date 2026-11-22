extends Node2D
## Electrified floor ('e' tiles are solid). On a fixed beat the surface charges:
## off -> warning sparks -> on (touching the top surface deals damage).

const Layers = preload("res://scripts/core/layers.gd")
const DamageZone = preload("res://scripts/level/damage_zone.gd")
const OFF_TIME := 1.2
const WARN_TIME := 0.5
const ON_TIME := 0.9

var rects: Array[Rect2] = []
var damage := 3
var _clock := 0.0
var _zone
var _t := 0.0


func _ready() -> void:
	_zone = DamageZone.new()
	_zone.damage = damage
	_zone.collision_layer = 0
	_zone.collision_mask = 0
	for r in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size.x - 2.0, 6.0)
		cs.shape = shape
		cs.position = Vector2(r.get_center().x, r.position.y - 3.0)
		_zone.add_child(cs)
	add_child(_zone)


func is_on() -> bool:
	return _clock >= OFF_TIME + WARN_TIME


func _physics_process(delta: float) -> void:
	_t += delta
	_clock = fmod(_clock + delta, OFF_TIME + WARN_TIME + ON_TIME)
	_zone.collision_layer = Layers.HAZARD if is_on() else 0
	queue_redraw()


func _draw() -> void:
	var warn := _clock >= OFF_TIME and not is_on()
	if not (warn or is_on()):
		return
	var c := Color("efcf5f")
	for r in rects:
		var x := r.position.x + 2.0
		var i := 0
		while x < r.end.x - 2.0:
			var h := (4.0 + 3.0 * sin(_t * 50.0 + i)) if is_on() else 2.0
			if is_on() or int(_t * 16.0 + i) % 2 == 0:
				draw_line(Vector2(x, r.position.y), Vector2(x + 2.0, r.position.y - h), c, 1.0)
			x += 5.0
			i += 1
		if is_on():
			draw_rect(Rect2(r.position.x, r.position.y - 1, r.size.x, 1), Color(c, 0.8))
