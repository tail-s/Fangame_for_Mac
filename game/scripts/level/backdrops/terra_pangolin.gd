extends "res://scripts/level/backdrops/theme_base.gd"
## Terra Pangolin: underground maglev. No sky: a rock wall of layered strata, a
## distant rail tunnel with a row of lights (a far train glides through it),
## concrete support pillars, and a dark rock ceiling with hanging work lamps.

const FAR_W := 768.0
const MID_W := 512.0
const NEAR_W := 640.0
const RAIL_Y := 118.0
const TRAIN_SPEED := 70.0
const TRAIN_LEN := 46.0
const CEILING := [[2, 7.0, 0.3], [5, 4.0, 1.9], [11, 2.0, 0.8]]

var _train: Node2D


func build() -> void:
	add_sky([[0.0, Color("060504")], [0.3, Color("0e0b09")], [0.65, Color("15110d")],
			[1.0, Color("110d0a")]])
	var far := add_layer(Vector2(0.05, 0.03), FAR_W, _paint_strata)
	_train = painter(far, _paint_train)
	_train.position.x = FAR_W * 0.6
	var mid := add_layer(Vector2(0.15, 0.06), MID_W, _paint_pillars)
	pulse(painter(mid, _paint_lamps), 0.2, 0.8, 1.2)
	var near := add_layer(Vector2(0.3, 0.12), NEAR_W, _paint_ceiling)
	pulse(painter(near, _paint_lamp_cones), 0.7, 1.0, 0.9)


func animate(delta: float) -> void:
	# Glides right to left through the tunnel (the layer repeats, so it loops).
	_train.position.x = fposmod(_train.position.x - TRAIN_SPEED * delta, FAR_W)


func _paint_strata(b: Batch) -> void:
	var tones := [Color("120f0c"), Color("17130f"), Color("100d0b"), Color("1a1510"), Color("14100d")]
	var y := -30.0
	var i := 0
	while y < BOTTOM:
		var thick := 28.0 + 12.0 * sin(i * 1.9)
		band(b, FAR_W, y, [[1 + i % 3, 5.0, i * 0.8], [4 + i % 2, 2.0, i * 1.7]], thick + 4.0,
				[[2, 4.0, i * 2.3]], tones[i % tones.size()])
		y += thick
		i += 1
	# Mineral specks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for k in 60:
		b.rect(Rect2(roundf(rng.randf_range(0, FAR_W)), roundf(rng.randf_range(0, 210)), 1, 1),
				Color("3a2e22", rng.randf_range(0.4, 0.8)))
	# Rail tunnel: a dark slot with a dotted line of lights.
	b.rect(Rect2(0, RAIL_Y - 9.0, FAR_W, 14), Color("0c0a08"))
	var x := 4.0
	while x < FAR_W:
		b.rect(Rect2(x, RAIL_Y - 8.0, 1, 1), Color("c09050", 0.28))
		x += 16.0


## The far train: only its lights show in the dark tunnel (cool white, no body).
func _paint_train(b: Batch) -> void:
	b.rect(Rect2(0, RAIL_Y - 3.0, 2, 2), Color("eef2ff", 0.5))
	b.rect(Rect2(2, RAIL_Y - 2.0, TRAIN_LEN - 2.0, 1), Color("c8d4f0", 0.08))
	var x := 6.0
	while x < TRAIN_LEN - 3.0:
		b.rect(Rect2(x, RAIL_Y - 3.0, 2, 1), Color("c8d4f0", 0.22))
		x += 5.0


func _paint_pillars(b: Batch) -> void:
	var concrete := Color("1f1915")
	var lit := Color("2c241c")
	var shadow := Color("120e0b")
	b.rect(Rect2(0, -40, MID_W, 48), shadow)  # ceiling beam
	for px in [60.0, 316.0]:
		b.rect(Rect2(px, 0, 20, BOTTOM), concrete)
		b.rect(Rect2(px, 0, 2, BOTTOM), lit)
		b.rect(Rect2(px + 17, 0, 3, BOTTOM), shadow)
		b.polygon(PackedVector2Array([Vector2(px - 10, 8), Vector2(px + 30, 8),
				Vector2(px + 20, 24), Vector2(px, 24)]), concrete)
		b.line(Vector2(px - 10, 8), Vector2(px, 24), lit, 1.0)
		# Diagonal bracing to the next pillar's head.
		b.line(Vector2(px + 20, 30), Vector2(px + 120, 8), shadow, 2.0)
		b.line(Vector2(px + 236, 30), Vector2(px + 136, 8), shadow, 2.0)
		var y := 40.0
		while y < 220.0:
			b.rect(Rect2(px + 4, y, 12, 1), shadow)  # form-work seams
			y += 36.0


func _paint_lamps(b: Batch) -> void:
	for px in [60.0, 316.0]:
		b.rect(Rect2(px + 9, 92, 2, 2), Color("e0a050", 0.55))


func _paint_ceiling(b: Batch) -> void:
	overhang(b, NEAR_W, 14.0, CEILING, Color("0a0806"))
	for lamp in _hanging_lamps():
		var top := Vector2(lamp.x, 14.0 + wave(lamp.x, NEAR_W, CEILING) - 2.0)
		b.rect(Rect2(lamp.x, top.y, 1, lamp.y - top.y), Color("19140f"))
		b.rect(Rect2(lamp.x - 2, lamp.y, 5, 2), Color("19140f"))
	wire(b, Vector2(0, 20), Vector2(NEAR_W * 0.5, 22), 26.0, Color("0d0a08"))
	wire(b, Vector2(NEAR_W * 0.5, 22), Vector2(NEAR_W, 20), 18.0, Color("0d0a08"))


func _paint_lamp_cones(b: Batch) -> void:
	for lamp in _hanging_lamps():
		var p: Vector2 = lamp + Vector2(0.5, 2)
		b.polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(3, 0),
				p + Vector2(26, 90), p + Vector2(-25, 90)]), Color("e0a050", 0.035))
		b.rect(Rect2(p.x - 1.5, p.y, 4, 1), Color("f0c080", 0.6))


func _hanging_lamps() -> Array:
	return [Vector2(140, 44), Vector2(470, 38)]
