extends Node2D
## Electrified floor ('e' tiles are solid). On a fixed beat the surface charges:
## off -> warning sparks -> on (touching the top surface deals damage).

const Layers = preload("res://scripts/core/layers.gd")
const DamageZone = preload("res://scripts/level/damage_zone.gd")
const OFF_TIME := 1.2
const WARN_TIME := 0.5
const ON_TIME := 0.9
## Rail / arc colours, dark brass -> white-hot (the gold of the old drawing: efcf5f).
const RAIL := [Color("4a3412"), Color("8a6d2a"), Color("c9a845"), Color("efcf5f"), Color("fff3a8")]

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
	var on := is_on()
	var warn := _clock >= OFF_TIME and not on
	var f := int(_t * 24.0)
	var blink := int(_t * 16.0) % 2 == 0
	# Segmented conductor rail over the top of the 'e' tiles: gold plates split by
	# dark insulators. Off: plain gold. Warning: plates flash in alternation.
	# On: white-hot plates, arcs leaping off them, charged air over the surface.
	var cold: Array = [RAIL[3], RAIL[2], RAIL[1]]
	var hot: Array = [Color.WHITE, RAIL[4], RAIL[3]]
	for r in rects:
		var y := r.position.y
		if on:
			draw_rect(Rect2(r.position.x, y - 6.0, r.size.x, 6.0), Color(RAIL[3], 0.1))
			draw_rect(Rect2(r.position.x, y - 6.0, r.size.x, 1.0), Color(RAIL[3], 0.12))
		draw_rect(Rect2(r.position.x, y + 1.0, r.size.x, 3.0), RAIL[0])
		var x := r.position.x
		var i := 0
		while x < r.end.x:
			var plate: Array = cold
			if on or (warn and (i % 2 == 0) == blink):
				plate = hot
			var w := minf(6.0, r.end.x - x - 1.0)
			for row in 3:
				draw_rect(Rect2(x + 1.0, y + 1.0 + row, w, 1.0), plate[row])
			draw_rect(Rect2(x + 1.0, y + 1.0, 1.0, 1.0), plate[0].lightened(0.4))
			if on:
				_bolt(x + 3.0, y, i, f)
			elif warn and _hash(i, f) < 0.3:
				draw_rect(Rect2(x + 2.0 + floorf(_hash(i + 5, f) * 3.0), y - 1.0 - floorf(_hash(i + 9, f) * 2.0),
						1.0, 1.0), RAIL[4])
			x += 8.0
			i += 1
		if on:
			# Crackle along the surface, broken into flickering dashes.
			var cx := r.position.x
			var k := 0
			while cx < r.end.x:
				if _hash(k + 31, f) < 0.6:
					draw_rect(Rect2(cx, y - 1.0, minf(4.0, r.end.x - cx), 1.0), Color(RAIL[3], 0.85))
				cx += 4.0
				k += 1


## Zigzag arc rising from a stud: white core, yellow fringe, new shape every frame.
func _bolt(x: float, y: float, i: int, f: int) -> void:
	var h := 4 + int(_hash(i, f) * 6.0)
	var px := x + (0.0 if _hash(i + 17, f) < 0.5 else 1.0)
	for k in h:
		if k % 2 == 1:
			px += -1.0 if _hash(i * 7 + k, f) < 0.5 else 1.0
		var side := -1.0 if (k + i) % 2 == 0 else 1.0
		draw_rect(Rect2(px + side, y - 1.0 - k, 1.0, 1.0), Color(RAIL[3], 0.4))
		draw_rect(Rect2(px, y - 1.0 - k, 1.0, 1.0), RAIL[4] if k < h - 1 else Color.WHITE)


static func _hash(i: int, f: int) -> float:
	var n := (i * 374761393 + f * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 1009) / 1009.0
