extends "res://scripts/level/backdrops/theme_base.gd"
## Solar Fennec: desert solar plant at dusk. Warm sky with the afterglow of the
## sun, a glowing central solar tower fed by a far heliostat field, rows of
## heliostat mirrors on the dunes, and a faint heat shimmer above the sand.

const FAR_W := 1152.0
const MID_W := 768.0
const NEAR_W := 640.0
const TOWER_X := 300.0
const RECEIVER := Vector2(TOWER_X, 44)
const FAR_DUNES := [[1, 6.0, 0.0], [3, 4.0, 1.3], [7, 2.0, 2.2]]
const MID_DUNES := [[2, 7.0, 0.4], [5, 3.0, 2.0], [9, 1.5, 0.7]]
const NEAR_DUNES := [[2, 9.0, 1.1], [3, 4.0, 0.2], [8, 2.0, 2.9]]
const FAR_BASE := 150.0
const MID_BASE := 160.0
const NEAR_BASE := 178.0

var _shimmer: Node2D
var _shimmer_clock := 0.0


func build() -> void:
	var sky := add_sky([[0.0, Color("110a20")], [0.35, Color("21122d")], [0.62, Color("3a1b33")],
			[0.78, Color("522639")], [1.0, Color("482234")]])
	painter(sky, func(b: Batch) -> void:
		glow(b, Vector2(96, 178), 150.0, Color("b0583a", 0.2), 6)
		glow(b, Vector2(96, 178), 60.0, Color("d07a48", 0.12), 3))
	var far := add_layer(Vector2(0.04, 0.02), FAR_W)
	pulse(painter(far, _paint_receiver_glow), 0.6, 1.0, 1.4)
	painter(far, _paint_far)
	var mid := add_layer(Vector2(0.12, 0.05), MID_W, _paint_mid)
	_shimmer = painter(mid, _paint_shimmer)
	add_layer(Vector2(0.24, 0.1), NEAR_W, _paint_near)


func animate(delta: float) -> void:
	_shimmer_clock += delta
	if _shimmer_clock >= 1.0 / 12.0:  # tiny painter, redrawn at 12 Hz
		_shimmer_clock = 0.0
		_shimmer.queue_redraw()


func _paint_receiver_glow(b: Batch) -> void:
	glow(b, RECEIVER, 30.0, Color("f0a050", 0.22), 6)


func _paint_far(b: Batch) -> void:
	ridge(b, FAR_W, FAR_BASE, FAR_DUNES, Color("2b1729"))
	# Far heliostat field: glints around the tower foot, beams converging on it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var beams := PackedVector2Array()
	for i in 70:
		var x := roundf(TOWER_X + rng.randf_range(-130.0, 130.0))
		if absf(x - TOWER_X) < 8.0:
			continue
		var y := roundf(FAR_BASE + wave(x, FAR_W, FAR_DUNES) + rng.randf_range(1.0, 7.0))
		if i % 5 == 0:
			beams.append(Vector2(x, y))
			beams.append(RECEIVER + Vector2(0, 4))
		b.rect(Rect2(x, y, 1, 1), Color("e8a070", rng.randf_range(0.25, 0.55)))
	b.multiline(beams, Color("f0c080", 0.045), 1.0)
	# The tower: tapered shaft, receiver block with a hot core.
	var foot := FAR_BASE + wave(TOWER_X, FAR_W, FAR_DUNES) + 4.0
	b.polygon(PackedVector2Array([Vector2(TOWER_X - 6, foot), Vector2(TOWER_X - 3, 52),
			Vector2(TOWER_X + 3, 52), Vector2(TOWER_X + 6, foot)]), Color("1d0f1e"))
	b.rect(Rect2(TOWER_X - 6, 36, 12, 16), Color("2a1626"))
	b.rect(Rect2(TOWER_X - 4, 39, 8, 10), Color("d09058"))
	b.rect(Rect2(TOWER_X - 2, 41, 4, 6), Color("e8c48c"))
	b.rect(Rect2(TOWER_X - 1, 30, 2, 6), Color("1d0f1e"))


func _paint_mid(b: Batch) -> void:
	ridge(b, MID_W, MID_BASE, MID_DUNES, Color("22121f"))
	# Heliostat rows on the dune: small tilted mirrors on posts.
	for row in [[30.0, 250.0], [400.0, 610.0]]:
		var x: float = row[0]
		while x < row[1]:
			var y := roundf(MID_BASE + wave(x, MID_W, MID_DUNES))
			_mirror(b, Vector2(x, y), 9.0, 4.0, 5.0, Color("33203a"), Color("8a5060", 0.55))
			x += 12.0


func _paint_shimmer(b: Batch) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for i in 16:
		var x := rng.randf_range(0.0, MID_W - 30.0)
		var y := roundf(MID_BASE + wave(x, MID_W, MID_DUNES) - rng.randf_range(4.0, 16.0))
		var w := rng.randf_range(10.0, 26.0)
		var dx := roundf(sin(_t * 2.3 + i * 1.7) * 2.0)
		var a := 0.05 + 0.04 * sin(_t * 1.6 + i)
		b.rect(Rect2(roundf(x) + dx, y, roundf(w), 1), Color("f0b080", a))


func _paint_near(b: Batch) -> void:
	ridge(b, NEAR_W, NEAR_BASE, NEAR_DUNES, Color("170c18"))
	var x := 40.0
	while x < NEAR_W - 20.0:
		if fmod(x, 200.0) < 110.0:
			var y := roundf(NEAR_BASE + wave(x, NEAR_W, NEAR_DUNES))
			_mirror(b, Vector2(x, y), 16.0, 7.0, 9.0, Color("26152a"), Color("9a5a5a", 0.45))
		x += 22.0


## A heliostat: post on the sand at `foot`, tilted panel w x h, top edge catching the sky.
func _mirror(b: Batch, foot: Vector2, w: float, h: float, post: float, body: Color, shine: Color) -> void:
	var top := foot - Vector2(0, post)
	b.rect(Rect2(foot.x, top.y, 1, post), body)
	var tilt := roundf(w * 0.3)
	var l := (top + Vector2(-w * 0.5, -h + tilt * 0.5)).round()
	var r := (top + Vector2(w * 0.5, -h - tilt * 0.5)).round()
	b.quad(l, r, r + Vector2(0, h), l + Vector2(0, h), body)
	b.line(l, r, shine)
