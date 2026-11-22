extends "res://scripts/level/backdrops/theme_base.gd"
## Cryo Narwhal: polar deep-sea base. Night sky with drifting aurora curtains,
## tabular icebergs on a dark sea, and nearer ice cliffs carrying the base's
## domes and mast. (No floating floes in front: flat floes read as platforms.)

const AURORA_W := 768.0
const FAR_W := 896.0
const MID_W := 640.0
const SEA_Y := 150.0
const C_SEA := Color("060d19")

## Crest polygons of the mid-layer ice cliffs (built once).
var _cliffs: Array[PackedVector2Array] = []


func build() -> void:
	var sky := add_sky([[0.0, Color("03060e")], [0.45, Color("061024")], [0.7, Color("0b1a30")],
			[1.0, Color("0b1a30")]])
	painter(sky, func(b: Batch) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 51
		stars(b, rng, 40, Rect2(0, 0, W, 110), Color("cfe4ff"), 0.15, 0.5))
	# Aurora: two curtains on slow layers that also drift by themselves.
	for spec in [[0.02, -3.0, 52, Color("2fd3a0"), 0.0], [0.03, -5.0, 53, Color("7a6ad8"), 2.0]]:
		var layer := add_layer(Vector2(spec[0], 0.01), AURORA_W)
		layer.autoscroll = Vector2(spec[1], 0)
		var aurora_seed: int = spec[2]
		var tint: Color = spec[3]
		var p := painter(layer, func(b: Batch) -> void: _paint_aurora(b, aurora_seed, tint))
		pulse(p, 0.55, 1.0, 0.45, spec[4])
	add_layer(Vector2(0.06, 0.03), FAR_W, _paint_far)
	for cliff in [[20.0, 170.0, 78.0], [330.0, 220.0, 60.0]]:
		_cliffs.append(_cliff_points(cliff[0], cliff[1], cliff[2]))
	var mid := add_layer(Vector2(0.15, 0.06), MID_W, _paint_mid)
	pulse(painter(mid, _paint_lights), 0.25, 0.9, 1.5)


## A curtain: 2 px columns hanging from a wavy top edge, brightest at the bottom.
func _paint_aurora(b: Batch, aurora_seed: int, tint: Color) -> void:
	var phase := float(aurora_seed) * 1.3
	var top_terms := [[1, 14.0, phase], [3, 7.0, phase * 2.0], [7, 3.0, phase * 0.5]]
	var len_terms := [[2, 12.0, phase + 1.0], [5, 6.0, phase * 3.0]]
	var x := 0.0
	while x < AURORA_W:
		var top := roundf(30.0 + wave(x, AURORA_W, top_terms))
		var length := roundf(34.0 + wave(x, AURORA_W, len_terms))
		var strength := 0.5 + 0.5 * sin(x * 0.05 + phase) * sin(x * 0.013 + phase * 2.0)
		if strength > 0.12:
			b.vgradient(Rect2(x, top, 2, length), Color(tint, 0.03), Color(tint, 0.04 + 0.12 * strength))
			b.rect(Rect2(x, top + length, 2, 2), Color(tint, 0.2 * strength))
		x += 2.0


## Dark sea from the horizon down, tabular icebergs, sparse ripples.
func _paint_far(b: Batch) -> void:
	b.rect(Rect2(0, SEA_Y, FAR_W, BOTTOM - SEA_Y), C_SEA)
	var rng := RandomNumberGenerator.new()
	rng.seed = 54
	var x := 20.0
	while x < FAR_W - 80.0:
		var w := roundf(rng.randf_range(30.0, 80.0))
		var h := roundf(rng.randf_range(6.0, 16.0))
		_berg(b, Vector2(x, SEA_Y), w, h, rng)
		x += w + rng.randf_range(40.0, 140.0)
	for i in 50:
		var p := Vector2(roundf(rng.randf_range(0, FAR_W - 12)), roundf(rng.randf_range(SEA_Y + 4, 200)))
		b.rect(Rect2(p, Vector2(roundf(rng.randf_range(3, 9)), 1)), Color("1a3a52", 0.45))


func _berg(b: Batch, foot: Vector2, w: float, h: float, rng: RandomNumberGenerator) -> void:
	var slope := roundf(rng.randf_range(2.0, 6.0))
	b.polygon(PackedVector2Array([foot, foot + Vector2(slope, -h),
			foot + Vector2(w - slope, -h - roundf(rng.randf_range(-2, 2))), foot + Vector2(w, 0)]), Color("142536"))
	b.rect(Rect2(foot.x + slope, foot.y - h, roundf(w * 0.4), h), Color("1a2e42"))
	# Faint reflection below the waterline.
	b.rect(Rect2(foot.x + 2, foot.y + 1, w - 4, 2), Color("142536", 0.5))


## Ice cliffs with the base built into them.
func _paint_mid(b: Batch) -> void:
	var ice := Color("101d2c")
	var snow := Color("182a3c")
	var face := Color("14243a")
	var edge := Color("25405a")
	for pts in _cliffs:
		b.polygon(pts, ice)
		# Lit faces under the rising slopes, a snow band along the crest, the crest line.
		for i in range(1, pts.size() - 2):
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[i + 1]
			if q.y < p.y:
				b.quad(p, q, Vector2(q.x, BOTTOM), Vector2(p.x, BOTTOM), face)
			b.quad(p, q, q + Vector2(0, 5), p + Vector2(0, 5), snow)
			b.line(p, q, edge)
	# The base: domes and a mast standing on cliff peaks.
	var mast := Color("1d3044")
	_dome(b, _peak(0, 0.45), 13.0)
	_dome(b, _peak(0, 0.6) + Vector2(0, 2), 8.0)
	_dome(b, _peak(1, 0.4), 11.0)
	var m := _peak(1, 0.55)
	b.rect(Rect2(m.x, m.y - 24.0, 1, 24), mast)
	b.rect(Rect2(m.x - 4.0, m.y - 16.0, 9, 1), mast)


## Point on cliff `i`'s crest at fraction f of its width.
func _peak(i: int, f: float) -> Vector2:
	var pts: PackedVector2Array = _cliffs[i]
	var k := clampi(1 + roundi(f * (pts.size() - 3)), 1, pts.size() - 2)
	return pts[k]


## Jagged cliff outline from x0, w wide, peaking h px above the sea.
func _cliff_points(x0: float, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(x0, BOTTOM)])
	var steps := int(w / 10.0)
	for i in steps + 1:
		var f := float(i) / steps
		var y := SEA_Y + 6.0 - h * sin(PI * f) * (0.75 + 0.25 * sin(i * 2.7 + x0))
		pts.append(Vector2(roundf(x0 + f * w), roundf(y)))
	pts.append(Vector2(x0 + w, BOTTOM))
	return pts


func _dome(b: Batch, foot: Vector2, r: float) -> void:
	b.circle(foot, r, Color("15283a"))
	b.rect(Rect2(foot.x - r, foot.y, r * 2.0, 4), Color("101d2c"))
	b.arc(foot, r, PI, TAU, 16, Color("27425a"), 1.0)


func _paint_lights(b: Batch) -> void:
	var lamp := Color("8fe3e8", 0.55)
	var m := _peak(1, 0.55)
	b.rect(Rect2(m.x, m.y - 25.0, 1, 1), lamp)
	for d in [[0, 0.45, 13.0], [1, 0.4, 11.0]]:
		var foot := _peak(d[0], d[1])
		for k in 3:
			b.rect(Rect2(foot.x - 6.0 + k * 6.0, foot.y - roundf(d[2] * 0.4), 1, 1), lamp)
