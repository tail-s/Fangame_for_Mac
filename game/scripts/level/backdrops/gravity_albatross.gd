extends "res://scripts/level/backdrops/theme_base.gd"
## Gravity Albatross: orbital shipyard. Twinkling starfield, the curve of a planet
## below, crane girders and half-built ship hulls, near scaffold trusses.

const YARD_W := 768.0
const TRUSS_W := 640.0
const PLANET_C := Vector2(300, 660)
const PLANET_R := 560.0

var _cranes: Array = []  # [x, top y, jib left, jib right]


func build() -> void:
	var sky := add_sky([[0.0, Color("020309")], [0.6, Color("050a1a")], [1.0, Color("0a1430")]])
	for i in 3:
		var star_seed := 31 + i
		var p := painter(sky, func(b: Batch) -> void: _paint_stars(b, star_seed))
		pulse(p, 0.35, 1.0, 1.1 + i * 0.6, i * 2.1)
	add_layer(Vector2(0.02, 0.02), 0.0, _paint_planet)
	_cranes = [[60.0, 46.0, 30.0, 120.0], [430.0, 34.0, 60.0, 150.0], [640.0, 58.0, 70.0, 60.0]]
	var yard := add_layer(Vector2(0.12, 0.06), YARD_W, _paint_yard)
	pulse(painter(yard, _paint_beacons), 0.1, 0.8, 2.2)
	add_layer(Vector2(0.28, 0.12), TRUSS_W, _paint_trusses)


func _paint_stars(b: Batch, star_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = star_seed
	stars(b, rng, 30, Rect2(0, 0, W, 150), Color("c8d8ff"), 0.25, 0.7)
	for i in 2:
		var p := Vector2(roundf(rng.randf_range(20, W - 20)), roundf(rng.randf_range(8, 90)))
		var col := Color("dfe8ff", 0.5)
		b.rect(Rect2(p, Vector2.ONE), Color(col, 0.8))
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			b.rect(Rect2(p + d, Vector2.ONE), Color(col, 0.3))


## A huge planet whose limb arcs up from the lower left; cloud streaks follow it.
func _paint_planet(b: Batch) -> void:
	var x := -200.0
	while x < 800.0:
		var y := _limb(x + 1.0)
		if y < BOTTOM:
			b.rect(Rect2(x, y - 3.0, 2, 3), Color("1d3f6a", 0.28))  # haze
			b.rect(Rect2(x, y, 2, BOTTOM - y), Color("0b1a29"))
			b.rect(Rect2(x, y, 2, 7), Color("123049"))
			b.rect(Rect2(x, y, 2, 1), Color("2d5f8a", 0.6))
			for band in [[13.0, 0.0, Color("10263a")], [24.0, 1.7, Color("0f2335")], [40.0, 3.1, Color("0e2132")]]:
				var k := sin(x * 0.021 + band[1]) + sin(x * 0.053 + band[1] * 2.0)
				if k > 0.2:
					b.rect(Rect2(x, y + band[0] + roundf(k * 2.0), 2, 2.0 + roundf(k)), band[2])
		x += 2.0


func _limb(x: float) -> float:
	var dx := x - PLANET_C.x
	if absf(dx) >= PLANET_R:
		return INF
	return roundf(PLANET_C.y - sqrt(PLANET_R * PLANET_R - dx * dx))


func _paint_yard(b: Batch) -> void:
	var steel := Color("1a2232")
	var dark := Color("111827")
	# Half-built hull in a dock frame between the first two cranes.
	_hull(b, Vector2(150, 96), 190.0, 30.0, dark, steel)
	_hull(b, Vector2(560, 122), 120.0, 20.0, dark, steel)
	for cr in _cranes:
		var x: float = cr[0]
		var top: float = cr[1]
		truss(b, x, x + 8.0, top, BOTTOM, steel)
		boom(b, x - cr[2], x + 8.0 + cr[3], top, 5.0, steel)
		b.rect(Rect2(x - cr[2] + 2.0, top + 1.0, 8, 8), dark)  # counterweight
		b.line(Vector2(x + 4.0, top - 14.0), Vector2(x - cr[2] + 2.0, top), steel, 1.0)
		b.line(Vector2(x + 4.0, top - 14.0), Vector2(x + 8.0 + cr[3], top), steel, 1.0)
		var hook_x: float = x + 8.0 + cr[3] * 0.7
		b.rect(Rect2(hook_x, top + 6.0, 1, 46), Color(steel, 0.8))
		b.rect(Rect2(hook_x - 2.0, top + 52.0, 5, 4), steel)


func _paint_beacons(b: Batch) -> void:
	for cr in _cranes:
		b.rect(Rect2(cr[0] + 3.0, cr[1] - 16.0, 2, 2), Color("e8c890", 0.6))
		b.rect(Rect2(cr[0] + 8.0 + cr[3] - 1.0, cr[1] - 2.0, 2, 2), Color("e8c890", 0.45))


## Ship hull: a long lens-shaped silhouette; the rear half is still bare ribs.
func _hull(b: Batch, pos: Vector2, length: float, depth: float, body: Color, rib: Color) -> void:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 21:
		var f := i / 20.0
		var x := pos.x + f * length
		var bulge := sin(PI * pow(f, 0.7))
		top.append(Vector2(roundf(x), roundf(pos.y - depth * 0.45 * bulge)))
		bottom.append(Vector2(roundf(x), roundf(pos.y + depth * 0.55 * bulge)))
	var solid_to := 12
	var poly := PackedVector2Array()
	for i in solid_to + 1:
		poly.append(top[i])
	for i in range(solid_to, -1, -1):
		poly.append(bottom[i])
	b.polygon(poly, body)
	# Plating seams and a row of dim ports on the finished part.
	for i in range(2, solid_to, 2):
		b.line(top[i] + Vector2(0, 2), bottom[i] - Vector2(0, 2), Color(rib, 0.6), 1.0)
	for i in range(3, solid_to):
		b.rect(Rect2(top[i].x, pos.y - 2.0, 1, 1), Color("8fb0d0", 0.35))
	# Bare frame: ribs and a keel line.
	for i in range(solid_to, 21):
		b.line(top[i], bottom[i], rib, 1.0)
	b.polyline(top.slice(solid_to), rib, 1.0)
	b.polyline(bottom.slice(solid_to), rib, 1.0)
	b.line(Vector2(top[solid_to].x, pos.y + 2.0), Vector2(pos.x + length, pos.y + 2.0), Color(rib, 0.7), 1.0)
	# Dock gantry arms holding it.
	for f in [0.25, 0.75]:
		var gx := roundf(pos.x + length * f)
		b.rect(Rect2(gx, pos.y - depth - 18.0, 2, depth * 0.6 + 18.0), Color(rib, 0.5))


func _paint_trusses(b: Batch) -> void:
	var col := Color("0c1220")
	for x in [90.0, 330.0, 520.0]:
		truss(b, x, x + 14.0, -40.0, BOTTOM, col, 14.0)
		b.rect(Rect2(x - 1.0, -40.0, 3, BOTTOM + 40.0), col)
		b.rect(Rect2(x + 13.0, -40.0, 3, BOTTOM + 40.0), col)
	wire(b, Vector2(104, 10), Vector2(330, 14), 34.0, col)
	wire(b, Vector2(344, 22), Vector2(520, 6), 26.0, col)
	wire(b, Vector2(534, 12), Vector2(90 + TRUSS_W, 10), 40.0, col)
