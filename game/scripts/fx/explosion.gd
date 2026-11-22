extends Node2D
## Short-lived burst used for hits, enemy deaths and the player's death.

const Autoloads = preload("res://scripts/core/autoloads.gd")

var big := false
var size := 12.0
var duration := 0.35
var _t := 0.0


func _ready() -> void:
	z_index = 20
	if big:
		size = 30.0
		duration = 0.9
		Autoloads.sfx("big_explosion")


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var k := _t / duration
	var radius := size * k
	var a := 1.0 - k
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, a), 2.0)
	draw_circle(Vector2.ZERO, maxf(size * 0.4 * (1.0 - k), 0.5), Color(1, 1, 1, a))
	var n := 10 if big else 6
	var c := Color("00b8be") if big else Color("f0b84a")
	for i in n:
		var ang := TAU * i / n + k
		var at := Vector2(cos(ang), sin(ang)) * radius * 1.2
		draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), Color(c, a))
