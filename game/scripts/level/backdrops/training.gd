extends "res://scripts/level/backdrops/theme_base.gd"
## Training facility: night city of data towers (the original backdrop) with a
## far row of thin antenna spires whose beacons blink slowly.

const Towers = preload("res://scripts/level/backdrop.gd")
const SPIRE_W := 768.0

var _spires: Array = []  # [x, top y, width]


func build() -> void:
	add_sky([[0.0, Color("0a1326")], [0.55, Color("13223f")], [1.0, Color("1c2f52")]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var x := 20.0
	while x < SPIRE_W - 30.0:
		_spires.append([roundf(x), roundf(rng.randf_range(28.0, 70.0)), roundf(rng.randf_range(6.0, 12.0))])
		x += rng.randf_range(70.0, 130.0)
	var far := add_layer(Vector2(0.08, 0.03), SPIRE_W, _paint_spires)
	pulse(painter(far, _paint_beacons), 0.15, 0.9, 1.7)
	# [scroll x, scroll y, colour, seed, max tower height, feet y]
	for spec in [[0.2, 0.06, Color("101f3a"), 3, 210.0, 300.0],
			[0.42, 0.12, Color("15294a"), 7, 160.0, 310.0]]:
		var layer := add_layer(Vector2(spec[0], spec[1]), Towers.WIDTH)
		var towers := Towers.new()
		towers.color = spec[2]
		towers.seed_value = spec[3]
		towers.max_height = spec[4]
		towers.base_y = spec[5]
		layer.add_child(towers)


func _paint_spires(b: Batch) -> void:
	var col := Color("0e1b34")
	for s in _spires:
		var x: float = s[0]
		var top: float = s[1]
		var w: float = s[2]
		b.rect(Rect2(x, top + 18.0, w, BOTTOM - top), col)
		b.rect(Rect2(x + floorf(w / 2.0) - 1.0, top + 6.0, 2, 12), col)
		b.rect(Rect2(x + floorf(w / 2.0), top, 1, 6), col)
		# Dish / ring halfway up.
		b.rect(Rect2(x - 3.0, top + 44.0, w + 6.0, 3), col)


func _paint_beacons(b: Batch) -> void:
	for s in _spires:
		var x: float = s[0] + floorf(s[2] / 2.0)
		b.rect(Rect2(x - 1.0, s[1] - 1.0, 2, 2), Color("9fd8e8", 0.55))
