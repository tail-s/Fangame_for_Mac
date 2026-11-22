extends "res://scripts/level/backdrops/theme_base.gd"
## Eden Core: the digital core. A dark void with a huge faint core ring turning
## slowly, a perspective grid whose lines drift toward the viewer, rising data
## streams, and dark monoliths with glowing seams in front.

const STREAM_W := 512.0
const MONO_W := 640.0
const CORE := Vector2(220, 70)
const HORIZON := 128.0
const VANISH := Vector2(192, HORIZON)
const GRID_SPEED := 1.2  # depth units per second
const C_VIOLET := Color("7a5ae0")
const C_CYAN := Color("3de0ee")

var _outer: Node2D
var _inner: Node2D
var _grid_lines: Node2D
var _grid_clock := 0.0
var _streams: Array = []  # [node, speed px/s, period, start offset]


func build() -> void:
	add_sky([[0.0, Color("030208")], [0.55, Color("080618")], [1.0, Color("0e0a26")]])
	var core := add_layer(Vector2(0.02, 0.01), 0.0)
	pulse(painter(core, _paint_core_glow), 0.6, 1.0, 0.8)
	_inner = painter(core, _paint_inner_ring)
	_inner.position = CORE
	_outer = painter(core, _paint_outer_ring)
	_outer.position = CORE
	var grid := add_layer(Vector2(0.05, 0.03), 0.0, _paint_grid_rays)
	_grid_lines = painter(grid, _paint_grid_lines)
	var streams := add_layer(Vector2(0.14, 0.05), STREAM_W)
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	var x := 12.0
	while x < STREAM_W - 8.0:
		var period := roundf(rng.randf_range(300.0, 420.0))
		var length := roundf(rng.randf_range(80.0, 160.0))
		var stream_seed := rng.randi()
		var tint := C_CYAN if rng.randf() < 0.6 else Color("b78af3")
		var node := painter(streams, func(b: Batch) -> void:
			_paint_stream(b, stream_seed, tint, period, length))
		node.position = Vector2(roundf(x), -rng.randf_range(0.0, period))
		_streams.append([node, rng.randf_range(14.0, 30.0), period, -node.position.y])
		x += rng.randf_range(34.0, 80.0)
	add_layer(Vector2(0.3, 0.12), MONO_W, _paint_monoliths)


func animate(delta: float) -> void:
	_outer.rotation = _t * 0.035
	_inner.rotation = -_t * 0.05
	for s in _streams:
		s[0].position.y = -fposmod(s[3] + _t * s[1], s[2])
	_grid_clock += delta
	if _grid_clock >= 0.05:  # 15 one-pixel lines, redrawn at 20 Hz
		_grid_clock = 0.0
		_grid_lines.queue_redraw()


func _paint_core_glow(b: Batch) -> void:
	glow(b, CORE, 110.0, Color("3a1a80", 0.16), 6)
	glow(b, CORE, 40.0, Color("6a4ad8", 0.08), 3)


## Segmented outer ring with tick marks (drawn around the node origin; it rotates).
func _paint_outer_ring(b: Batch) -> void:
	var segments := 10
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := a0 + TAU / segments * 0.72
		b.arc(Vector2.ZERO, 132.0, a0, a1, 24, Color(C_VIOLET, 0.24), 2.0)
		var tick := Vector2.from_angle(a1 + TAU / segments * 0.14)
		b.line(tick * 124.0, tick * 140.0, Color(C_VIOLET, 0.16), 1.0)
	b.arc(Vector2.ZERO, 146.0, 0.0, TAU, 96, Color(C_VIOLET, 0.07), 1.0)


func _paint_inner_ring(b: Batch) -> void:
	b.arc(Vector2.ZERO, 112.0, 0.0, TAU, 96, Color(C_CYAN, 0.09), 1.0)
	for i in 48:
		var p := Vector2.from_angle(TAU * i / 48.0) * 98.0
		b.rect(Rect2(p.round(), Vector2(2, 1)), Color("b78af3", 0.16))


## Grid lines running to the vanishing point (static). Each starts where it is
## 3 px from its neighbour (no bright knot at the vanishing point), and the
## flatter outer lines fade out so they do not pile up into a band.
func _paint_grid_rays(b: Batch) -> void:
	var start_y := HORIZON + 11.0
	var f := (start_y - HORIZON) / (BOTTOM - HORIZON)
	for bucket in 6:
		var segs := PackedVector2Array()
		for i in range(-40, 41):
			if mini(absi(i) / 7, 5) != bucket:
				continue
			segs.append(Vector2(roundf(VANISH.x + i * 44.0 * f), start_y))
			segs.append(Vector2(VANISH.x + i * 44.0, BOTTOM))
		b.multiline(segs, Color(C_VIOLET, 0.13 * (1.0 - bucket / 6.0)), 1.0)


## Cross lines of the grid, spaced in depth and drifting toward the viewer.
func _paint_grid_lines(b: Batch) -> void:
	var phase := fposmod(_t * GRID_SPEED, 4.0)
	var z := 64.0 - phase
	while z > 3.0:
		var y := roundf(HORIZON + 560.0 / z)
		if y < BOTTOM:
			var a := 0.13 * clampf((y - HORIZON - 2.0) / 40.0, 0.0, 1.0)
			b.rect(Rect2(-700, y, 1800, 1), Color(C_VIOLET, a))
		z -= 4.0


## One stream: a burst of dashes `length` px long (bright head on top, fading
## tail) repeating every `period`; the node scrolls up and wraps seamlessly.
func _paint_stream(b: Batch, stream_seed: int, tint: Color, period: float, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	var y := 0.0
	while y < length:
		var dash := roundf(rng.randf_range(2.0, 6.0))
		var a := lerpf(0.32, 0.05, y / length)
		for k in [-1, 0, 1]:
			b.rect(Rect2(0, k * period + y, 1, dash), Color(tint, a))
		y += dash + roundf(rng.randf_range(2.0, 9.0))


func _paint_monoliths(b: Batch) -> void:
	var body := Color("07051a")
	var rim := Color("1c1446")
	var seam := Color("3a2a90", 0.35)
	for m in [[40.0, 30.0, 92.0], [250.0, 22.0, 118.0], [430.0, 38.0, 74.0], [560.0, 18.0, 128.0]]:
		var x: float = m[0]
		var w: float = m[1]
		var top: float = m[2]
		var cut := roundf(w * 0.5)
		b.polygon(PackedVector2Array([Vector2(x, top + cut), Vector2(x + cut, top),
				Vector2(x + w, top + cut * 0.5), Vector2(x + w, BOTTOM), Vector2(x, BOTTOM)]), body)
		b.line(Vector2(x, top + cut), Vector2(x + cut, top), rim, 1.0)
		b.rect(Rect2(x, top + cut, 1, BOTTOM - top - cut), rim)
		var sx := x + roundf(w * 0.35)
		b.rect(Rect2(sx, top + cut + 6.0, 1, BOTTOM - top), seam)
		b.rect(Rect2(sx + 1.0, top + cut + 30.0, roundf(w * 0.4), 1), seam)
		b.rect(Rect2(sx + roundf(w * 0.4), top + cut + 30.0, 1, 40), seam)
