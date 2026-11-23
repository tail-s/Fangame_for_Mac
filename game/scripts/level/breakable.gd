extends StaticBody2D
## Cracked wall ('x'). Solid until hit by a breaker shot (Vanguard ARM charge).

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const TILE := 16
const TEX = preload("res://art/devices/cracked_wall.png")

signal broken

var rect := Rect2()  # world rect covered by this wall
var reveal := false:
	set(value):
		reveal = value
		queue_redraw()


func _ready() -> void:
	add_to_group("breakable")
	collision_layer = Layers.WORLD
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	add_child(cs)


func break_wall() -> void:
	if is_queued_for_deletion():
		return
	Autoloads.sfx("break")
	var x := rect.position.x + TILE / 2.0
	while x < rect.end.x:
		var y := rect.position.y + TILE / 2.0
		while y < rect.end.y:
			var fx := Explosion.new()
			fx.size = 9.0
			fx.position = Vector2(x, y)
			get_parent().add_child.call_deferred(fx)
			y += TILE
		x += TILE
	broken.emit()
	queue_free()


func _draw() -> void:
	# Cracked plates (tools/bake_devices.gd); the column is the mask of the sides
	# on the edge of the wall (1 up, 2 right, 4 down, 8 left), outlined and bevelled.
	var cols := int(rect.size.x / TILE)
	var rows := int(rect.size.y / TILE)
	for j in rows:
		for i in cols:
			var m := (1 if j == 0 else 0) | (2 if i == cols - 1 else 0) \
					| (4 if j == rows - 1 else 0) | (8 if i == 0 else 0)
			var o := rect.position + Vector2(i, j) * TILE
			draw_texture_rect_region(TEX, Rect2(o, Vector2(TILE, TILE)),
					Rect2(m * TILE, ((i + j * 3) % 2) * TILE, TILE, TILE))
	if reveal:
		# Vanguard HEAD scan: gold frame with bright corner brackets.
		var g := Color("f0b84a")
		var gl := Color("ffe3a0")
		var r := rect.grow(-1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), g)
		draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1), g)
		draw_rect(Rect2(r.position, Vector2(1, r.size.y)), g)
		draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1, r.size.y), g)
		for corner in [r.position, Vector2(r.end.x - 4.0, r.position.y),
				Vector2(r.position.x, r.end.y - 4.0), r.end - Vector2(4, 4)]:
			var right: bool = corner.x > r.position.x
			var bottom: bool = corner.y > r.position.y
			draw_rect(Rect2(corner + Vector2(0, 3.0 if bottom else 0.0), Vector2(4, 1)), gl)
			draw_rect(Rect2(corner + Vector2(3.0 if right else 0.0, 0), Vector2(1, 4)), gl)
