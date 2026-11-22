extends Node2D
## Base for one stage backdrop theme (see backdrop_set.gd): a fixed sky on a
## CanvasLayer behind everything, then Parallax2D layers from far to near.
##
## Coordinates are screen pixels (384 x 216) as seen when the camera's top edge is
## at REF_TOP (the usual view of a 20-row stage). Layers scroll only a little
## vertically, so taller stages shift them by a few pixels: draw every layer down
## to BOTTOM so no gap shows.
##
## Rules for readability: stay darker and lower in contrast than the stage tiles
## (fill #1c375b, cyan #00b8be top edges); no bright straight horizontal lines
## (they read as floors), no red, nothing that moves like an enemy or a shot.
## Each Painter fills a Batch once, so it costs ONE draw command per frame however
## many shapes it holds; animation only moves or fades nodes, or redraws a few
## tiny painters.

const Painter = preload("res://scripts/level/backdrops/painter.gd")
const Batch = preload("res://scripts/level/backdrops/batch.gd")
const W := 384.0
const H := 216.0
const REF_TOP := 104.0
const BOTTOM := 300.0

## The BackdropSet that owns this theme (for flashes_enabled).
var root: Node
## Bright flashes started so far (lightning). Stays 0 while flashes are disabled.
var flash_count := 0
var _t := 0.0
## [CanvasItem, alpha lo, alpha hi, speed (rad/s), phase]
var _pulses: Array = []


## Builds the sky and the layers as children. Overridden by each theme.
func build() -> void:
	pass


## Per-frame animation beyond the alpha pulses. Overridden by themes that need it.
func animate(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	_t += delta
	for p in _pulses:
		p[0].modulate.a = lerpf(p[1], p[2], 0.5 + 0.5 * sin(_t * p[3] + p[4]))
	animate(delta)


func flashes_allowed() -> bool:
	return root == null or bool(root.get("flashes_enabled"))


## Hides any flash on screen now (flashes were just turned off). Overridden by
## themes that flash.
func stop_flashes() -> void:
	pass


# --- building blocks ----------------------------------------------------------------

## Fixed sky: vertical gradient [[offset, Color], ...] on CanvasLayer -10. Fixed
## extras (stars, glows, lightning) can be added to the returned layer.
func add_sky(stops: Array) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Sky"
	layer.layer = -10
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_to = Vector2(0, 1)
	tex.width = 1
	tex.height = int(H)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(W, H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	return layer


## A Parallax2D layer. `scroll` is how much it follows the camera (far = small);
## `width` > 0 repeats it sideways every `width` px (content must tile there).
## The painter (if given) is its first child.
func add_layer(scroll: Vector2, width: float, paint := Callable()) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.scroll_scale = scroll
	# Local y == screen y when the camera top is at REF_TOP.
	layer.scroll_offset = Vector2(0, scroll.y * REF_TOP)
	if width > 0.0:
		layer.repeat_size = Vector2(width, 0)
		layer.repeat_times = 3
	layer.z_index = -5
	add_child(layer)
	if paint.is_valid():
		painter(layer, paint)
	return layer


## Adds a Painter under `parent` that draws with `paint(batch)`.
func painter(parent: Node, paint: Callable) -> Node2D:
	var p := Painter.new()
	p.paint = paint
	parent.add_child(p)
	return p


## Fades `item` between two alphas forever (cheap: modulate only, no redraw).
func pulse(item: CanvasItem, lo: float, hi: float, speed: float, phase := 0.0) -> void:
	_pulses.append([item, lo, hi, speed, phase])
	item.modulate.a = lerpf(lo, hi, 0.5 + 0.5 * sin(phase))


# --- drawing helpers (static; they add shapes to a painter's Batch) ------------------

## Sum of sines that repeats every `period`: terms = [[cycles, amplitude, phase], ...].
static func wave(x: float, period: float, terms: Array) -> float:
	var y := 0.0
	for t in terms:
		y += float(t[1]) * sin(TAU * float(t[0]) * x / period + float(t[2]))
	return y


## Ground / rock mass under the periodic curve `base + wave(x)`, down to `bottom`,
## as `step` px columns (pixel steps; tiles seamlessly over `period`).
static func ridge(b: Batch, period: float, base: float, terms: Array, color: Color,
		bottom := BOTTOM, step := 2.0) -> void:
	var x := 0.0
	while x < period:
		var y := roundf(base + wave(x + step * 0.5, period, terms))
		b.rect(Rect2(x, y, step, bottom - y), color)
		x += step


## Rock hanging from `top` down to the periodic curve `base + wave(x)`.
static func overhang(b: Batch, period: float, base: float, terms: Array, color: Color,
		top := -80.0, step := 2.0) -> void:
	var x := 0.0
	while x < period:
		var y := roundf(base + wave(x + step * 0.5, period, terms))
		b.rect(Rect2(x, top, step, y - top), color)
		x += step


## Band of wavy thickness along a wavy line (rock strata).
static func band(b: Batch, period: float, top: float, top_terms: Array, thick: float,
		thick_terms: Array, color: Color, step := 4.0) -> void:
	var x := 0.0
	while x < period:
		var cx := x + step * 0.5
		var y := roundf(top + wave(cx, period, top_terms))
		var h := roundf(thick + wave(cx, period, thick_terms))
		if h > 0.0:
			b.rect(Rect2(x, y, step, h), color)
		x += step


## Hanging cable / power line from p to q with `sag` px of droop.
static func wire(b: Batch, p: Vector2, q: Vector2, sag: float, color: Color, width := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var f := i / 16.0
		pts.append((p.lerp(q, f) + Vector2(0, sag * 4.0 * f * (1.0 - f))).round())
	b.polyline(pts, color, width)


## Lattice truss between two rails (x0, x1) from y_top down to y_bottom.
static func truss(b: Batch, x0: float, x1: float, y_top: float, y_bottom: float,
		color: Color, step := 8.0) -> void:
	b.rect(Rect2(x0, y_top, 1, y_bottom - y_top), color)
	b.rect(Rect2(x1, y_top, 1, y_bottom - y_top), color)
	var y := y_top
	var flip := false
	while y + step <= y_bottom:
		b.line(Vector2(x0 if flip else x1, y), Vector2(x1 if flip else x0, y + step), color)
		flip = not flip
		y += step


## Horizontal lattice boom from x0 to x1 (rails at y and y + depth).
static func boom(b: Batch, x0: float, x1: float, y: float, depth: float, color: Color,
		step := 8.0) -> void:
	b.rect(Rect2(x0, y, x1 - x0, 1), color)
	b.rect(Rect2(x0, y + depth, x1 - x0, 1), color)
	var x := x0
	var flip := false
	while x + step <= x1:
		b.line(Vector2(x, y if flip else y + depth), Vector2(x + step, y + depth if flip else y), color)
		flip = not flip
		x += step


## `count` 1 px stars inside `area`, alpha between lo and hi.
static func stars(b: Batch, rng: RandomNumberGenerator, count: int, area: Rect2,
		tint: Color, lo: float, hi: float) -> void:
	for i in count:
		var p := Vector2(roundf(rng.randf_range(area.position.x, area.end.x)),
				roundf(rng.randf_range(area.position.y, area.end.y)))
		b.rect(Rect2(p, Vector2.ONE), Color(tint, rng.randf_range(lo, hi)))


## Soft round glow: stacked translucent discs.
static func glow(b: Batch, center: Vector2, radius: float, color: Color, rings := 4) -> void:
	for i in rings:
		var f := 1.0 - float(i) / rings
		b.circle(center, radius * f, Color(color, color.a / rings), 24)
