extends Node2D
## One tile of distant data-tower silhouettes; Parallax2D repeats it sideways.
## Used by the training theme (scripts/level/backdrops/training.gd).

const Batch = preload("res://scripts/level/backdrops/batch.gd")
const WIDTH := 384.0

var color := Color("142a47")
var light := Color("00b8be")
var seed_value := 1
var max_height := 200.0
## Screen y of the tower feet (below the bottom edge so they never end in view).
var base_y := 340.0
var _towers: Array[Rect2] = []
## Narrow stepped tops on some towers, so the skyline is not all flat ledges.
var _crowns: Array[Rect2] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := 0.0
	while x < WIDTH:
		var w := rng.randf_range(18.0, 44.0)
		# Tall enough that tower tops never sit right on the stage floor line.
		var h := rng.randf_range(max_height * 0.6, max_height)
		var r := Rect2(roundf(x), roundf(base_y - h), roundf(w), roundf(h))
		_towers.append(r)
		if rng.randf() < 0.5:
			var cw := roundf(w * rng.randf_range(0.3, 0.6))
			var ch := roundf(rng.randf_range(5.0, 12.0))
			_crowns.append(Rect2(r.position.x + roundf((w - cw) * 0.5), r.position.y - ch, cw, ch))
		x += w + rng.randf_range(4.0, 22.0)


func _draw() -> void:
	var b := Batch.new()
	for r in _crowns:
		b.rect(r, color)
	for r in _towers:
		b.rect(r, color)
		b.rect(Rect2(r.position, Vector2(r.size.x, 2)), color.lightened(0.1))
		var wy := r.position.y + 8.0
		while wy < base_y - 10.0:
			if int(wy + r.position.x) % 3 == 0:
				b.rect(Rect2(r.position.x + 4.0, wy, 2, 2), Color(light, 0.35))
			wy += 10.0
	b.flush(self)
