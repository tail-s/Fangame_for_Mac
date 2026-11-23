extends Node2D
## Laser emitter ('>' '<' 'v') whose beam follows mirrors ('/' '\') until it
## hits a wall. Cycles: off -> warning -> on. Touching the beam deals damage.

const Layers = preload("res://scripts/core/layers.gd")
const DamageZone = preload("res://scripts/level/damage_zone.gd")
## Emitter housings (tools/bake_devices.gd): column = style * 3 + state, row = facing.
const TEX = preload("res://art/devices/emitter.png")
const TILE := 16.0
## Beam / flame palettes, deep -> white-hot.
const BEAM := [Color("4a1020"), Color("a3243a"), Color("e34f5b"), Color("ff9aa2"), Color("ffe3e3")]
const FLAME_C := [Color("4a1e12"), Color("d0602e"), Color("ef9352"), Color("f0b84a"), Color("fff0b0")]
const WIDTH := 4.0
const OFF_TIME := 1.4
const WARN_TIME := 0.5
const ON_TIME := 1.6

var segments: Array = []  # [Vector2 from, Vector2 to] pairs in world space
var emitter_rect := Rect2()
var phase_offset := 0.0
var damage := 3
## "laser" (red beam) or "flame" (heat vent, drawn as a flame column).
var style := "laser"
var _clock := 0.0
var _area
var _t := 0.0


func _ready() -> void:
	_clock = phase_offset
	_area = DamageZone.new()
	_area.damage = damage
	_area.collision_layer = 0
	_area.collision_mask = 0
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(absf(b.x - a.x), absf(b.y - a.y)) + Vector2(WIDTH, WIDTH)
		cs.shape = shape
		cs.position = (a + b) / 2.0
		_area.add_child(cs)
	add_child(_area)


func is_on() -> bool:
	return _clock >= OFF_TIME + WARN_TIME


func _physics_process(delta: float) -> void:
	_t += delta
	_clock = fmod(_clock + delta, OFF_TIME + WARN_TIME + ON_TIME)
	_area.collision_layer = Layers.HAZARD if is_on() else 0
	queue_redraw()


func _draw() -> void:
	var on := is_on()
	var warn := _clock >= OFF_TIME and not on
	var blink := int(_t * 16.0) % 2 == 0
	if on:
		for seg in segments:
			if style == "flame":
				_flame(seg[0], seg[1])
			else:
				_beam(seg[0], seg[1])
		for i in range(1, segments.size()):
			_flare(segments[i][0])
		if not segments.is_empty() and style != "flame":
			_impact(segments[-1][0], segments[-1][1])
	elif warn:
		for seg in segments:
			_sight(seg[0], seg[1], blink)
	# Emitter housing on top of the beam root. Off: dim lens. Warning: the lens
	# glows hot and pulses (warn / on cells). On: white-hot.
	var state := 0
	if on:
		state = 2
	elif warn:
		state = 2 if blink else 1
	var col := (3 if style == "flame" else 0) + state
	draw_texture_rect_region(TEX, emitter_rect, Rect2(col * TILE, _facing_row() * TILE, TILE, TILE))
	if warn and not segments.is_empty():
		if style == "flame":
			_pilot(segments[0][0], segments[0][1])
		else:
			_charge(segments[0][0])


## Emitter sheet row from the first segment: 0 right, 1 left, 2 down, 3 up.
func _facing_row() -> int:
	if segments.is_empty():
		return 3 if style == "flame" else 0
	var d: Vector2 = segments[0][0] - emitter_rect.get_center()
	if absf(d.x) > absf(d.y):
		return 0 if d.x > 0.0 else 1
	return 2 if d.y > 0.0 else 3


## Rect along segment a-b covering offsets [lo, hi) across it and [s0, s1) along it
## (s measured from a toward b; s1 < 0 means "to b").
func _band(a: Vector2, b: Vector2, lo: float, hi: float, c: Color, s0 := 0.0, s1 := -1.0) -> void:
	var length := a.distance_to(b)
	if s1 < 0.0 or s1 > length:
		s1 = length
	if s1 <= s0:
		return
	var d := (b - a) / maxf(length, 0.001)
	var p0 := a + d * s0
	var p1 := a + d * s1
	if absf(d.x) > absf(d.y):
		draw_rect(Rect2(minf(p0.x, p1.x), a.y + lo, absf(p1.x - p0.x), hi - lo), c)
	else:
		draw_rect(Rect2(a.x + lo, minf(p0.y, p1.y), hi - lo, absf(p1.y - p0.y)), c)


## Laser: soft red glow, red body, pink inner band, white core; energy pulses run
## along it and the outer glow flickers every other frame.
func _beam(a: Vector2, b: Vector2) -> void:
	var flick := int(_t * 30.0) % 2 == 0
	var g := 5.0 if flick else 4.0
	_band(a, b, -g, g, Color(BEAM[2], 0.16))
	_band(a, b, -3.0, 3.0, Color(BEAM[2], 0.55 if flick else 0.35))
	_band(a, b, -2.0, 2.0, BEAM[2])
	_band(a, b, -1.0, 1.0, BEAM[3])
	_band(a, b, -1.0, 0.0, BEAM[4])
	var length := a.distance_to(b)
	var s := fmod(_t * 160.0, 24.0)
	while s < length:
		_band(a, b, -1.0, 1.0, Color.WHITE, s, s + 8.0)
		s += 24.0


## Mirror bounce: a bright square flare where two segments meet.
func _flare(p: Vector2) -> void:
	var flick := int(_t * 30.0) % 2 == 0
	var hot: Array = FLAME_C if style == "flame" else BEAM
	var r := 4.0 if flick else 3.0
	draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), Color(hot[2], 0.8))
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), hot[3])
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)


## Where the beam hits the wall: a flickering white-hot splash with sparks.
func _impact(a: Vector2, b: Vector2) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var f := int(_t * 24.0)
	draw_rect(Rect2(b - d * 2.0 - Vector2(2, 2), Vector2(4, 4)), BEAM[3])
	draw_rect(Rect2(b - d * 2.0 - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)
	for i in 4:
		var h := _hash(i, f)
		var along := 2.0 + floorf(h * 5.0)
		var side := (floorf(_hash(i + 7, f) * 9.0) - 4.0)
		var p := (b - d * along + n * side).floor()
		draw_rect(Rect2(p, Vector2(1, 1)), BEAM[4] if i % 2 == 0 else BEAM[3])


## Warning: faint sight line with bright dashes marching from the emitter.
func _sight(a: Vector2, b: Vector2, blink: bool) -> void:
	var hot: Array = FLAME_C if style == "flame" else BEAM
	_band(a, b, -1.0, 0.0, Color(hot[2], 0.4))
	if not blink:
		return
	var length := a.distance_to(b)
	var s := fmod(_t * 48.0, 8.0)
	while s < length:
		_band(a, b, -1.0, 0.0, Color(hot[3], 0.85), s, s + 4.0)
		s += 8.0


## Heat vent: a flame column with ragged flickering sides, yellow middle and a
## pale core near the nozzle, embers flying off it.
func _flame(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var f := int(_t * 20.0)
	_band(a, b, -6.0, 6.0, Color(FLAME_C[1], 0.3))
	var s := 0.0
	var k := 0
	while s < length:
		var hw := 3.0 if s < 6.0 else 3.0 + floorf(_hash(k, f) * 3.0)
		var step := minf(4.0, length - s)
		_band(a, b, -hw, hw, FLAME_C[2], s, s + step)
		_band(a, b, -hw + 2.0, hw - 2.0 - float(k % 2), FLAME_C[3], s, s + step)
		s += 4.0
		k += 1
	_band(a, b, -1.0, 1.0, FLAME_C[4], 0.0, floorf(length * 0.4))
	var d := (b - a) / maxf(length, 0.001)
	var n := Vector2(-d.y, d.x)
	for i in 5:
		var along := floorf(_hash(i, f >> 1) * length)
		var side := (6.0 + floorf(_hash(i + 3, f) * 3.0)) * (1.0 if i % 2 == 0 else -1.0)
		draw_rect(Rect2((a + d * along + n * side).floor(), Vector2(1, 1)), FLAME_C[3])


## Warning on a laser: a spark at the lens growing as the shot charges.
func _charge(p: Vector2) -> void:
	var k := clampf((_clock - OFF_TIME) / WARN_TIME, 0.0, 1.0)
	var r := 1.0 + floorf(k * 3.0)
	draw_rect(Rect2(p - Vector2(r + 1.0, r + 1.0), Vector2(r + 1.0, r + 1.0) * 2.0), Color(BEAM[2], 0.35))
	draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), BEAM[3])
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)


## Warning on a heat vent: a small pilot flame licking out of the throat.
func _pilot(a: Vector2, b: Vector2) -> void:
	var h := 3.0 + floorf(_hash(0, int(_t * 20.0)) * 3.0)
	_band(a, b, -2.0, 2.0, FLAME_C[2], 0.0, h)
	_band(a, b, -1.0, 1.0, FLAME_C[4], 0.0, h - 2.0)


static func _hash(i: int, f: int) -> float:
	var n := (i * 374761393 + f * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 1009) / 1009.0
