extends StaticBody2D
## Crumbling floor ('c', one object per horizontal run): shakes for SHAKE seconds
## after the player stands on it, falls away, and returns after RESPAWN seconds.

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")
const SHAKE := 0.5
const RESPAWN := 4.0
## Slab pieces (tools/bake_devices.gd): column = single / left / middle / right,
## row = crack stage.
const TEX = preload("res://art/devices/crumble.png")
const TILE := 16.0

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
		Autoloads.sfx("crumble")
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
		# Dashed ghost where the slab will return.
		var col := Color("9fc274", 0.18)
		var x := rect.position.x
		while x < rect.end.x:
			draw_rect(Rect2(x, rect.position.y, 3.0, 1.0), col)
			draw_rect(Rect2(x, rect.end.y - 1.0, 3.0, 1.0), col)
			x += 5.0
		draw_rect(Rect2(rect.position.x, rect.position.y, 1.0, rect.size.y), col)
		draw_rect(Rect2(rect.end.x - 1.0, rect.position.y, 1.0, rect.size.y), col)
		return
	var shaking := _timer >= 0.0
	# Whole-pixel shake; cracks spread over the shake (stage 1, then 2).
	var shake := Vector2(roundf(sin(_t * 70.0)), 0.0) if shaking else Vector2.ZERO
	var stage := 0
	if shaking:
		stage = 1 if _timer > SHAKE * 0.5 else 2
	var n := int(rect.size.x / TILE)
	for i in n:
		var piece := 0 if n == 1 else (1 if i == 0 else (3 if i == n - 1 else 2))
		draw_texture_rect_region(TEX, Rect2(rect.position + shake + Vector2(i * TILE, 0), Vector2(TILE, TILE)),
				Rect2(piece * TILE, stage * TILE, TILE, TILE))
	if shaking:
		# Grit trickling out of the underside.
		var fall := (SHAKE - _timer) * 40.0
		for k in n * 2:
			var gx := rect.position.x + float((k * 7 + 3) % int(rect.size.x))
			var gy := rect.end.y + floorf(fmod(fall + k * 3.0, 9.0))
			draw_rect(Rect2(gx, gy, 1.0 + float(k % 2), 1.0), Color("6b7d52") if k % 3 else Color("9fc274"))
