extends Node2D
## One tile of distant data-tower silhouettes; Parallax2D repeats it sideways.

const WIDTH := 384.0
const BASE_Y := 340.0

var color := Color("142a47")
var light := Color("00b8be")
var seed_value := 1
var max_height := 200.0
var _towers: Array[Rect2] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := 0.0
	while x < WIDTH:
		var w := rng.randf_range(18.0, 44.0)
		# Tall enough that tower tops never sit right on the stage floor line.
		var h := rng.randf_range(max_height * 0.6, max_height)
		_towers.append(Rect2(x, BASE_Y - h, w, h))
		x += w + rng.randf_range(4.0, 22.0)


func _draw() -> void:
	for r in _towers:
		draw_rect(r, color)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), color.lightened(0.15))
		var wy := r.position.y + 8.0
		while wy < BASE_Y - 10.0:
			if int(wy + r.position.x) % 3 == 0:
				draw_rect(Rect2(r.position.x + 4.0, wy, 2, 2), Color(light, 0.35))
			wy += 10.0
