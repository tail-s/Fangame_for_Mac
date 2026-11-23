extends Node2D
## Short-lived burst used for hits, enemy deaths and the player's death.
## Small bursts (size <= 7) are a pixel hit spark; larger ones are a clustered
## fireball of lit puffs with an ink outline that cool from white to ember red,
## with flying debris, a shock ring and drifting smoke.
## z_index 20 lifts it out of the enemy CanvasGroup's buffer, so pixel_shade never
## touches it (even when an enemy spawns it there): it carries its own outline.

const Autoloads = preload("res://scripts/core/autoloads.gd")
const PixelArt = preload("res://scripts/fx/pixel_art.gd")

## Fire ramp, hot to cold.
const FIRE := [Color("fffbea"), Color("ffe08a"), Color("f0b84a"), Color("e0782e"), Color("b0402e"),
		Color("5c2a40")]
const SMOKE := Color("46506e")
const DEBRIS_BIG := Color("00b8be")

var big := false
var size := 12.0
var duration := 0.35
## Optional colour for hit sparks and debris (the shot's colour); alpha 0 = amber.
var tint := Color(0, 0, 0, 0)
var _t := 0.0
var _seed := 0


func _ready() -> void:
	z_index = 20
	if big:
		size = 30.0
		duration = 0.9
		Autoloads.sfx("big_explosion")
	_seed = hash(Vector2i(position.round()))


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var k := clampf(_t / duration, 0.0, 0.999)
	if size <= 7.0 and not big:
		_draw_spark(k)
	else:
		_draw_blast(k)


## Deterministic 0..1 noise per explosion (never touches the global RNG).
func _rand(n: int) -> float:
	return float(posmod(hash(_seed + n * 7919), 1000)) / 1000.0


func _accent() -> Array:
	if tint.a > 0.0:
		return [Color.WHITE, tint.lightened(0.45), tint, tint.darkened(0.4)]
	return [FIRE[0], FIRE[1], FIRE[2], FIRE[3]]


## Hit spark: a 4-frame star (core + rays -> diagonal flare -> ring of motes -> embers).
func _draw_spark(k: float) -> void:
	var tones := _accent()
	var a := 1.0
	var f := int(k * 4.0)
	var s := size
	match f:
		0:
			_px_rect(Rect2(-1, -1, 3, 3), tones[0], a)
			var n := int(roundf(s * 0.5))
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				for i in range(2, 2 + n):
					_px_rect(Rect2((d * i).round(), Vector2.ONE), tones[1] if i < 3 else tones[2], a)
		1:
			for y in range(-1, 2):
				for x in range(-1, 2):
					_px_rect(Rect2(x, y, 1, 1), tones[0] if x == 0 and y == 0 else tones[1], a)
			var n := int(roundf(s * 0.8))
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				for i in range(3, 2 + n):
					_px_rect(Rect2((d * i).round(), Vector2.ONE), tones[2], a)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				_px_rect(Rect2(d * 2, Vector2.ONE), tones[1], a)
		2:
			for i in 8:
				var p := (Vector2.from_angle(i * TAU / 8.0) * s * 0.9).round()
				_px_rect(Rect2(p, Vector2.ONE), tones[2] if i % 2 == 0 else tones[1], a)
		_:
			for i in 4:
				var p := (Vector2.from_angle(i * TAU / 4.0 + PI / 4.0) * s * 1.1).round()
				_px_rect(Rect2(p, Vector2.ONE), tones[3], a * 0.75)


func _px_rect(r: Rect2, c: Color, a: float) -> void:
	draw_rect(r, Color(c, a))


## Fireball: clustered puffs (rims first, then mid tones, then hot cores, so the
## cluster reads as one cloud), plus flash, shock ring, debris and smoke.
func _draw_blast(k: float) -> void:
	var s := size
	var n := 8 if big else (3 if s < 11.0 else (4 if s < 16.0 else 6))
	var puffs := []
	for i in n:
		var delay := i * (0.05 if big else 0.08)
		if k < delay:
			continue
		var kk := (k - delay) / (1.0 - delay)
		var reach := (0.0 if i == 0 else s * (0.25 + 0.35 * _rand(i))) * (1.25 if big else 1.0)
		var off := Vector2.from_angle(_rand(i + 40) * TAU) * reach + Vector2(0, -s * 0.18 * kk)
		var grow := 1.0 - pow(1.0 - minf(kk * 2.5, 1.0), 2.0)
		var shrink := 1.0 - smoothstep(0.5, 1.0, kk) * 0.8
		var r := s * (0.36 + 0.16 * _rand(i + 80)) * (0.45 + 0.55 * grow) * shrink
		var heat := mini(int(kk * 4.0), 3)
		puffs.append({"p": off.round(), "r": maxf(r, 1.0), "heat": heat})

	# Smoke behind the fire.
	if k > 0.4:
		var sk := (k - 0.4) / 0.6
		for i in (3 if big else 2):
			var p := Vector2((_rand(i + 120) - 0.5) * s, -s * (0.3 + 0.6 * sk) - i * 3.0).round()
			PixelArt.disc(self, p, s * (0.22 + 0.2 * sk), Color(SMOKE, 0.5 * (1.0 - sk)))

	for q in puffs:
		PixelArt.disc(self, q.p, q.r + 1.0, PixelArt.INK)
	for q in puffs:
		PixelArt.disc(self, q.p, q.r, FIRE[q.heat + 2])
	for q in puffs:
		PixelArt.disc(self, q.p + (Vector2(-0.18, -0.18) * q.r).round(), q.r * 0.7, FIRE[q.heat + 1])
	for q in puffs:
		if q.heat < 3:
			PixelArt.disc(self, q.p + (Vector2(-0.3, -0.3) * q.r).round(), q.r * 0.38, FIRE[q.heat])

	# Opening flash.
	if k < 0.12:
		PixelArt.disc(self, Vector2.ZERO, s * 0.5, FIRE[1])
		PixelArt.disc(self, Vector2(-1, -1), s * 0.32, FIRE[0])

	# Shock ring: dashed, thinning out as it expands.
	if s >= 10.0 and k < 0.45:
		var kr := k / 0.45
		var rr := roundf(s * (0.6 + 1.1 * kr))
		var dots := int(rr * TAU)
		var gap := 2 if kr < 0.5 else 3
		for i in dots:
			if i % gap == 0:
				var p := (Vector2.from_angle(i * TAU / dots) * rr).round()
				draw_rect(Rect2(p, Vector2.ONE), FIRE[1] if kr < 0.5 else FIRE[2])

	# Debris: chunky early, single-pixel embers later, arcing under gravity.
	if k < 0.85:
		var tones := _accent()
		var col: Color = DEBRIS_BIG if big and tint.a == 0.0 else tones[2]
		var a := 1.0
		var m := 10 if big else (4 if s < 12.0 else 6)
		var ease := 1.0 - pow(1.0 - k, 2.0)
		for j in m:
			var dir := Vector2.from_angle(_rand(j + 200) * TAU)
			var p := (dir * s * (0.5 + (1.1 + 0.6 * _rand(j + 240)) * ease) + Vector2(0, s * 0.5 * k * k)).round()
			if k < 0.45:
				draw_rect(Rect2(p, Vector2(2, 2)), Color(col, a))
				draw_rect(Rect2(p, Vector2.ONE), Color(tones[0], a))
			elif (j + int(k * 20.0)) % 3 != 0:
				draw_rect(Rect2(p, Vector2.ONE), Color(col, a))
