extends StaticBody2D
## Cracked wall ('x'). Solid until hit by a breaker shot (Vanguard ARM charge).

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const TILE := 16

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
	var base := Color("1c375b")
	draw_rect(rect, base)
	var x := rect.position.x
	while x < rect.end.x:
		var y := rect.position.y
		while y < rect.end.y:
			var o := Vector2(x, y)
			draw_rect(Rect2(o + Vector2(1.5, 1.5), Vector2(TILE - 3, TILE - 3)), Color("142a47"), false, 1.0)
			draw_polyline(PackedVector2Array([o + Vector2(3, 2), o + Vector2(7, 7),
					o + Vector2(5, 10), o + Vector2(10, 14)]), Color("0a1326"), 1.0)
			draw_line(o + Vector2(7, 7), o + Vector2(13, 5), Color("0a1326"), 1.0)
			y += TILE
		x += TILE
	if reveal:
		draw_rect(rect.grow(-1.0), Color("f0b84a"), false, 1.0)
