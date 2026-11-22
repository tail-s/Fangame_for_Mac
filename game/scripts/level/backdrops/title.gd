extends "res://scripts/level/backdrops/theme_base.gd"
## Title screen (GDD §7-2): the EDEN LINK orbital structure. Deep space, a planet
## low on the right with city lights on its night side, and the orbital ring
## around it: the far half passes behind the planet, the near half in front, with
## station modules, uplink beams from the surface and the glowing core hub.
## Static (no camera on the title); stars, beacons and the hub pulse.

const PLANET_C := Vector2(268, 452)
const PLANET_R := 290.0
const RING_C := Vector2(250, 150)
const RING_R := Vector2(220, 52)
const RING_TILT := -0.1


func build() -> void:
	var sky := add_sky([[0.0, Color("02040c")], [0.55, Color("070d22")], [1.0, Color("0f1c3c")]])
	for i in 3:
		var star_seed := 71 + i
		var p := painter(sky, func(b: Batch) -> void: _paint_stars(b, star_seed))
		pulse(p, 0.3, 1.0, 0.9 + i * 0.5, i * 1.9)
	add_layer(Vector2.ZERO, 0.0, _paint_ring_back)
	add_layer(Vector2.ZERO, 0.0, _paint_planet)
	var front := add_layer(Vector2.ZERO, 0.0, _paint_ring_front)
	pulse(painter(front, _paint_beacons), 0.15, 1.0, 2.4)
	pulse(painter(front, _paint_hub_glow), 0.45, 1.0, 1.3)


func _paint_stars(b: Batch, star_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = star_seed
	stars(b, rng, 45, Rect2(0, 0, W, 170), Color("c8d8ff"), 0.25, 0.8)


## Point on the ring ellipse at angle a (0 = right, PI/2 = nearest / lowest).
func _ring(a: float, grow := 0.0) -> Vector2:
	return RING_C + Vector2(cos(a) * (RING_R.x + grow), sin(a) * (RING_R.y + grow * 0.2)).rotated(RING_TILT)


func _ring_band(b: Batch, a0: float, a1: float, col: Color, edge: Color, modules: bool) -> void:
	var steps := 60
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		outer.append(_ring(a, 3.0).round())
		inner.append(_ring(a, -2.0).round())
	for k in steps:
		b.polygon(PackedVector2Array([outer[k], outer[k + 1], inner[k + 1], inner[k]]), col)
	b.polyline(outer, edge, 1.0)
	# Truss ticks and station modules.
	for k in range(0, steps, 3):
		b.line(outer[k], inner[k], Color(edge, 0.6))
	if modules:
		for a in [a0 + 0.35, a0 + 1.0, a0 + 1.7, a0 + 2.45]:
			if a < a1:
				var p := _ring(a).round()
				b.rect(Rect2(p - Vector2(5, 4), Vector2(10, 7)), col.lightened(0.15))
				b.rect(Rect2(p - Vector2(5, 4), Vector2(10, 1)), edge)
				b.rect(Rect2(p + Vector2(-9, -1), Vector2(4, 2)), col.lightened(0.3))
				b.rect(Rect2(p + Vector2(5, -1), Vector2(4, 2)), col.lightened(0.3))


## Far half of the ring (upper arc), dim, behind the planet.
func _paint_ring_back(b: Batch) -> void:
	_ring_band(b, PI, TAU, Color("1b2c4f"), Color("3a6a9a"), false)


func _paint_planet(b: Batch) -> void:
	var x := 0.0
	while x < W:
		var dx := x + 1.0 - PLANET_C.x
		if absf(dx) < PLANET_R:
			var y := roundf(PLANET_C.y - sqrt(PLANET_R * PLANET_R - dx * dx))
			if y < BOTTOM:
				b.rect(Rect2(x, y - 4.0, 2, 4), Color("2fc4cc", 0.12))   # atmosphere haze
				b.rect(Rect2(x, y, 2, BOTTOM - y), Color("08142a"))
				b.rect(Rect2(x, y, 2, 6), Color("123a5c"))
				b.rect(Rect2(x, y, 2, 1), Color("4fd6e0", 0.7))
				for band in [[11.0, 0.0, Color("0d2240")], [23.0, 1.3, Color("0b1d38")], [38.0, 2.6, Color("0a1a33")]]:
					var k := sin(x * 0.025 + band[1]) + sin(x * 0.061 + band[1] * 1.7)
					if k > 0.3:
						b.rect(Rect2(x, y + band[0] + roundf(k * 2.0), 2, 2.0 + roundf(k)), band[2])
				# City lights on the night side (left part of the disc).
				if x < 230.0 and int(x) % 6 == 0:
					var ly := y + 14.0 + fmod(x * 7.3, 30.0)
					if ly < BOTTOM:
						b.rect(Rect2(x, ly, 1, 1), Color("f0b84a", 0.55))
		x += 2.0
	# Uplink beams from the surface to the ring.
	for a in [0.55, 1.25, 2.1, 2.7]:
		var top := _ring(a)
		var base := Vector2(top.x - 10.0, PLANET_C.y - sqrt(maxf(PLANET_R * PLANET_R - pow(top.x - 10.0 - PLANET_C.x, 2), 0.0)))
		if base.y < H:
			b.line(base.round(), top.round(), Color("3de0ee", 0.16))


## Near half of the ring (lower arc) with modules, in front of the planet.
func _paint_ring_front(b: Batch) -> void:
	_ring_band(b, 0.0, PI, Color("24406a"), Color("5fe3ec"), true)
	# Core hub on the near arc.
	var hub := _ring(1.0).round()
	b.polygon(PackedVector2Array([hub + Vector2(0, -12), hub + Vector2(10, -4), hub + Vector2(10, 6),
			hub + Vector2(0, 12), hub + Vector2(-10, 6), hub + Vector2(-10, -4)]), Color("24385f"))
	b.polygon(PackedVector2Array([hub + Vector2(0, -12), hub + Vector2(10, -4), hub + Vector2(0, 0),
			hub + Vector2(-10, -4)]), Color("35507d"))
	b.rect(Rect2(hub - Vector2(2, 2), Vector2(4, 4)), Color("3de0ee"))


func _paint_beacons(b: Batch) -> void:
	for k in 9:
		var p := _ring(0.15 + k * 0.33).round()
		b.rect(Rect2(p + Vector2(0, -4), Vector2(1, 1)), Color("f0b84a"))


func _paint_hub_glow(b: Batch) -> void:
	glow(b, _ring(1.0), 16.0, Color("3de0ee", 0.5), 4)
