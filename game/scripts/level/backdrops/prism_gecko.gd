extends "res://scripts/level/backdrops/theme_base.gd"
## Prism Gecko: optical data archive. Violet dark, giant faint crystal spires far
## away, prism columns (data slots inside) split slow cyan light beams into
## violet, and crystal clusters rise from below.

const SPIRE_W := 1024.0
const COLUMN_W := 768.0
const CLUSTER_W := 640.0
const C_BEAM := Color("3de0ee")
const C_SPLIT := Color("b78af3")

var _columns: Array = []  # [x, top, width]
var _beams: Array = []  # [source x at the top, column index]


func build() -> void:
	add_sky([[0.0, Color("06051a")], [0.5, Color("0d0a27")], [1.0, Color("191338")]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var x := 10.0
	while x < COLUMN_W - 40.0:
		_columns.append([roundf(x), roundf(rng.randf_range(40.0, 105.0)), 2.0 * roundf(rng.randf_range(7.0, 15.0))])
		x += rng.randf_range(80.0, 150.0)
	for i in _columns.size():
		_beams.append([_columns[i][0] - rng.randf_range(50.0, 110.0), i])
	add_layer(Vector2(0.04, 0.02), SPIRE_W, _paint_spires)
	var mid := add_layer(Vector2(0.12, 0.05), COLUMN_W)
	pulse(painter(mid, _paint_beams), 0.55, 1.0, 0.7)
	painter(mid, _paint_columns)
	pulse(painter(mid, _paint_glints), 0.2, 1.0, 1.3, 1.0)
	add_layer(Vector2(0.26, 0.1), CLUSTER_W, _paint_clusters)


## Faint crystal spires on the horizon, barely lighter than the sky.
func _paint_spires(b: Batch) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var x := 0.0
	while x < SPIRE_W - 20.0:
		var w := 2.0 * roundf(rng.randf_range(5.0, 11.0))
		var top := roundf(rng.randf_range(20.0, 80.0))
		_prism(b, x, top, w, Color("120e2e"), Color("17123a"), Color.TRANSPARENT)
		x += w + rng.randf_range(16.0, 70.0)


func _paint_beams(b: Batch) -> void:
	for beam in _beams:
		var col: Array = _columns[beam[1]]
		var hit := Vector2(col[0] + col[2] * 0.5, col[1] + 46.0)
		var src := Vector2(beam[0], -40.0)
		_beam(b, src, hit, 16.0, Color(C_BEAM, 0.07))
		# Split into two fainter fans on the far side of the prism.
		var d := (hit - src).normalized()
		_beam(b, hit, hit + d.rotated(-0.34) * 300.0, 14.0, Color(C_SPLIT, 0.06))
		_beam(b, hit, hit + d.rotated(0.1) * 300.0, 8.0, Color(C_BEAM, 0.05))


func _paint_columns(b: Batch) -> void:
	for col in _columns:
		_prism(b, col[0], col[1], col[2], Color("140f31"), Color("1c1644"), Color("2a2260"))
		# Archive slots: a dim stack of data cells inside the column.
		var y: float = col[1] + 22.0
		var i := 0
		while y < 200.0:
			if (i + int(col[0])) % 3 != 0:
				b.rect(Rect2(col[0] + col[2] * 0.5 - 2.0, y, 4, 1), Color("4a3f9a", 0.5))
			y += 6.0
			i += 1


func _paint_glints(b: Batch) -> void:
	for beam in _beams:
		var col: Array = _columns[beam[1]]
		var p := Vector2(col[0] + col[2] * 0.5, col[1] + 46.0)
		b.rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("bfeff5", 0.45))
	for col in _columns:
		b.rect(Rect2(col[0] + col[2] * 0.5, col[1], 1, 1), Color("b78af3", 0.6))


## Crystal clusters rising from below, darker than the sky (silhouettes).
func _paint_clusters(b: Batch) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var x := 30.0
	while x < CLUSTER_W - 60.0:
		var n := rng.randi_range(2, 4)
		for i in n:
			var tip_y := rng.randf_range(96.0, 126.0) + absf(i - (n - 1) / 2.0) * 22.0
			_shard(b, x + i * rng.randf_range(11.0, 16.0), tip_y, rng.randf_range(14.0, 22.0),
					rng.randf_range(-0.1, 0.1))
		x += rng.randf_range(130.0, 220.0)


## Hexagonal prism: body, a lit left facet, a pointed cap, optional edge glint line.
func _prism(b: Batch, x: float, top: float, w: float, body: Color, facet: Color, edge: Color) -> void:
	var cap := roundf(w * 0.6)
	b.polygon(PackedVector2Array([Vector2(x, top + cap), Vector2(x + w * 0.5, top),
			Vector2(x + w, top + cap), Vector2(x + w, BOTTOM), Vector2(x, BOTTOM)]), body)
	b.polygon(PackedVector2Array([Vector2(x, top + cap), Vector2(x + w * 0.5, top),
			Vector2(x + w * 0.5 - 1.0, BOTTOM), Vector2(x, BOTTOM)]), facet)
	if edge.a > 0.0:
		b.line(Vector2(x, top + cap), Vector2(x + w * 0.5, top), edge)
		b.rect(Rect2(x, top + cap, 1, BOTTOM - top - cap), Color(edge, 0.6))


## One leaning crystal shard standing on the layer bottom, tip at `tip_y`.
func _shard(b: Batch, x: float, tip_y: float, w: float, lean: float) -> void:
	var tip := Vector2(roundf(x + lean * (BOTTOM - tip_y)), roundf(tip_y))
	var l := Vector2(x - w * 0.5, BOTTOM)
	var r := Vector2(x + w * 0.5, BOTTOM)
	var shoulder_l := (l.lerp(tip, 0.8) + Vector2(-2, 0)).round()
	var shoulder_r := (r.lerp(tip, 0.8) + Vector2(2, 0)).round()
	var mid := Vector2(roundf((l.x + r.x) * 0.5 + (tip.x - x) * 0.3), BOTTOM)
	b.polygon(PackedVector2Array([l, shoulder_l, tip, shoulder_r, r]), Color("0c0920"))
	b.polygon(PackedVector2Array([l, shoulder_l, tip, mid]), Color("120d2a"))
	b.line(shoulder_l, tip, Color("2c2358"))
	b.line(tip, mid, Color("0a071a"))


## Light shaft from `from` (narrow) to `to` (wide).
static func _beam(b: Batch, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	var n := (to - from).normalized().orthogonal() * width * 0.5
	b.quad(from - n * 0.4, from + n * 0.4, to + n, to - n, color)
