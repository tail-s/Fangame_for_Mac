extends "res://scripts/level/backdrops/theme_base.gd"
## Pulse Cicada: high-voltage substation under a storm. Drifting storm clouds,
## cloud-to-cloud lightning now and then (sky flash + bolt; none while
## flashes_enabled is false), rows of transmission pylons with sagging lines,
## transformer yard silhouettes.

const CLOUD_W := 768.0
const FAR_W := 768.0
const MID_W := 640.0
const HORIZON := 150.0
const C_BOLT := Color("dcdcff")
## Seconds between strikes.
const STRIKE_GAP := Vector2(4.5, 9.5)
const STRIKE_LEN := 0.45

var flash_strength := 0.07
var _rng := RandomNumberGenerator.new()
var _flash: ColorRect
var _bolt: Node2D
var _clouds: Array = []
var _bolt_lines: Array[PackedVector2Array] = []
var _next_strike := 2.5
var _strike_t := -1.0


func build() -> void:
	_rng.seed = 71
	var sky := add_sky([[0.0, Color("06060d")], [0.4, Color("0d0e1a")], [0.72, Color("191a2a")],
			[1.0, Color("222235")]])
	_flash = ColorRect.new()
	_flash.color = Color(C_BOLT, 0.0)
	_flash.size = Vector2(W, H)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	sky.add_child(_flash)
	_bolt = painter(sky, _paint_bolt)
	_bolt.visible = false
	for spec in [[0.03, -6.0, 0], [0.05, -10.0, 1]]:
		var layer := add_layer(Vector2(spec[0], 0.01), CLOUD_W)
		layer.autoscroll = Vector2(spec[1], 0)
		var band_index: int = spec[2]
		_clouds.append(painter(layer, func(b: Batch) -> void: _paint_clouds(b, band_index)))
	add_layer(Vector2(0.08, 0.03), FAR_W, _paint_far)
	var mid := add_layer(Vector2(0.2, 0.08), MID_W, _paint_mid)
	pulse(painter(mid, _paint_glints), 0.2, 0.8, 2.6)


func animate(delta: float) -> void:
	if not flashes_allowed():
		_end_strike()
		return
	_next_strike -= delta
	if _strike_t < 0.0 and _next_strike <= 0.0:
		_start_strike()
	if _strike_t < 0.0:
		return
	_strike_t += delta
	if _strike_t >= STRIKE_LEN:
		_end_strike()
		return
	# Double flicker, then fade.
	var a := 1.0
	if _strike_t < 0.05:
		a = 1.0
	elif _strike_t < 0.1:
		a = 0.25
	elif _strike_t < 0.18:
		a = 0.8
	else:
		a = 0.8 * (1.0 - (_strike_t - 0.18) / (STRIKE_LEN - 0.18))
	_flash.color.a = flash_strength * a
	_bolt.modulate.a = a
	for cl in _clouds:
		cl.modulate = Color(1.0 + 0.3 * a, 1.0 + 0.3 * a, 1.0 + 0.5 * a)


func is_striking() -> bool:
	return _strike_t >= 0.0


func stop_flashes() -> void:
	_end_strike()


func _start_strike() -> void:
	flash_count += 1
	_strike_t = 0.0
	_next_strike = _rng.randf_range(STRIKE_GAP.x, STRIKE_GAP.y)
	# Cloud-to-cloud lightning up in the storm bank (never a ground strike, so it
	# cannot be mistaken for a boss attack), with a couple of short forks.
	_bolt_lines.clear()
	var start := Vector2(roundf(_rng.randf_range(40.0, W - 130.0)), roundf(_rng.randf_range(44.0, 62.0)))
	var main := _bolt_path(start, Vector2(1, 0.15), _rng.randf_range(60.0, 100.0), 9)
	_bolt_lines.append(main)
	for i in _rng.randi_range(1, 2):
		var from: Vector2 = main[_rng.randi_range(2, 6)]
		_bolt_lines.append(_bolt_path(from, Vector2(_rng.randf_range(-0.4, 0.4), 1), _rng.randf_range(10.0, 18.0), 3))
	_flash.visible = true
	_bolt.visible = true
	_bolt.queue_redraw()


func _end_strike() -> void:
	if _strike_t < 0.0 and not _flash.visible:
		return
	_strike_t = -1.0
	_flash.visible = false
	_bolt.visible = false
	for cl in _clouds:
		cl.modulate = Color.WHITE


## Jagged path from `from`, `length` px along `dir`.
func _bolt_path(from: Vector2, dir: Vector2, length: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var step := dir.normalized() * length / segments
	var side := step.orthogonal().normalized()
	var p := from
	for i in segments:
		p += step
		pts.append((p + side * _rng.randf_range(-4.0, 4.0)).round())
	return pts


func _paint_bolt(b: Batch) -> void:
	for i in _bolt_lines.size():
		var pts: PackedVector2Array = _bolt_lines[i]
		b.polyline(pts, Color(C_BOLT, 0.12), 3.0)
		b.polyline(pts, Color(C_BOLT, 0.55 if i == 0 else 0.35), 1.0)


## Lumpy storm clouds: a heavy upper bank (band 0) or a thinner lower one (band 1).
func _paint_clouds(b: Batch, band_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72 + band_index
	var body := Color("10111c") if band_index == 0 else Color("161726", 0.85)
	var lit := Color("161727") if band_index == 0 else Color("1a1b2c", 0.8)
	var base := 26.0 if band_index == 0 else 74.0
	var spread := 26.0 if band_index == 0 else 10.0
	var x := 0.0
	while x < CLOUD_W:
		var r := rng.randf_range(10.0, 24.0) if band_index == 0 else rng.randf_range(5.0, 11.0)
		var y := base + wave(x, CLOUD_W, [[2, spread * 0.5, band_index], [5, spread * 0.3, 1.0]])
		if band_index == 1 and sin(x * 0.02) < -0.2:
			x += r
			continue
		b.circle(Vector2(roundf(x), roundf(y + 3.0)), r, lit)
		b.circle(Vector2(roundf(x), roundf(y)), r, body)
		if band_index == 0:
			b.rect(Rect2(x - r, -60, r * 2.0, y + 60.0), body)
		x += r * 0.9


func _paint_far(b: Batch) -> void:
	var ground := Color("0c0c16")
	ridge(b, FAR_W, HORIZON, [[3, 2.0, 0.0], [7, 1.0, 1.0]], ground)
	var col := Color("0e0f1a")
	var tops: Array = []
	for i in 4:
		var x := 40.0 + i * 192.0
		tops.append(_pylon(b, Vector2(x, HORIZON + 2.0), 66.0, 14.0, col))
	for i in 4:
		var here: Array = tops[i]
		var next: Array = tops[(i + 1) % 4]
		for k in here.size():
			var to: Vector2 = next[k] + (Vector2(FAR_W, 0) if i == 3 else Vector2.ZERO)
			wire(b, here[k], to, 12.0, Color(col, 0.9))


func _paint_mid(b: Batch) -> void:
	var col := Color("090a12")
	var tops: Array = []
	for x in [110.0, 430.0]:
		tops.append(_pylon(b, Vector2(x, BOTTOM), 268.0, 34.0, col))
	for i in 2:
		var here: Array = tops[i]
		var next: Array = tops[(i + 1) % 2]
		for k in here.size():
			var to: Vector2 = next[k] + (Vector2(MID_W, 0) if i == 1 else Vector2.ZERO)
			wire(b, here[k], to, 30.0, col)
	# Transformer yard: boxes with cooling fins and thin bushings on top.
	for x in [210.0, 540.0]:
		b.rect(Rect2(x, 150, 34, BOTTOM - 150.0), col)
		for k in 5:
			b.rect(Rect2(x - 4, 156 + k * 8, 4, 4), col)
			b.rect(Rect2(x + 34, 156 + k * 8, 4, 4), col)
		for k in 3:
			var ix: float = x + 6.0 + k * 11.0
			b.rect(Rect2(ix, 130, 1, 20), col)
			b.rect(Rect2(ix - 2.0, 136, 5, 1), col)
			b.rect(Rect2(ix - 2.0, 142, 5, 1), col)


func _paint_glints(b: Batch) -> void:
	for x in [210.0, 540.0]:
		for k in 3:
			b.rect(Rect2(x + 6.0 + k * 11.0, 125, 1, 1), Color("9fb0ff", 0.5))


## Lattice pylon standing at `foot` (centre), `h` tall, `base_w` wide at the foot.
## Returns the cross-arm tip points (where the lines hang).
func _pylon(b: Batch, foot: Vector2, h: float, base_w: float, col: Color) -> Array:
	var top := foot - Vector2(0, h)
	var top_w := maxf(3.0, roundf(base_w * 0.22))
	var l0 := foot + Vector2(-base_w * 0.5, 0)
	var r0 := foot + Vector2(base_w * 0.5, 0)
	var l1 := top + Vector2(-top_w * 0.5, 0)
	var r1 := top + Vector2(top_w * 0.5, 0)
	var leg_w := 1.0 if h < 100.0 else 2.0
	b.line(l0, l1, col, leg_w)
	b.line(r0, r1, col, leg_w)
	var segs := PackedVector2Array()
	var n := 8 if h < 100.0 else 12
	for i in n:
		var f0 := float(i) / n
		var f1 := float(i + 1) / n
		segs.append_array(PackedVector2Array([l0.lerp(l1, f0), r0.lerp(r1, f1),
				r0.lerp(r1, f0), l0.lerp(l1, f1)]))
	segs.append_array(PackedVector2Array([top, top - Vector2(0, roundf(h * 0.08))]))
	var tips: Array = []
	for arm in [[0.12, 0.9], [0.3, 0.7]]:
		var y := roundf(top.y + h * arm[0])
		var half := roundf(base_w * arm[1])
		var rise := roundf(h * 0.05)
		# Insulator strings hang under each tip.
		var drop := roundf(h * 0.04) + 1.0
		segs.append_array(PackedVector2Array([
			Vector2(top.x - half, y), Vector2(top.x + half, y),
			Vector2(top.x - half, y), Vector2(top.x - top_w, y - rise),
			Vector2(top.x + half, y), Vector2(top.x + top_w, y - rise),
			Vector2(top.x - half, y), Vector2(top.x - half, y + drop),
			Vector2(top.x + half, y), Vector2(top.x + half, y + drop)]))
		tips.append(Vector2(top.x - half, y + drop))
		tips.append(Vector2(top.x + half, y + drop))
	b.multiline(segs, col, 1.0)
	return tips
