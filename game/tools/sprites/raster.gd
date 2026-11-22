extends RefCounted
## Small CPU rasteriser for baking pixel-art sprites (tools only, not shipped).
## Shapes are filled at 1 pixel = 1 game pixel, shaded with a 5-tone ramp
## [line, shadow, base, light, highlight]:
##   - edge pixels facing the light get the light tone, edges facing away the shadow tone
##   - the part's far side (away from the light) falls into shadow
##   - parts drawn over other parts get a dark inner line where they overlap
## Then `finish()` adds a 1 px outer outline around the whole layer.

var w := 0
var h := 0
var img: Image
## Part id per pixel (-1 = empty). Later parts have higher ids (drawn in front).
var ids := PackedInt32Array()
var _lines := {}  # id -> line colour
var _next_id := 0
## Direction *towards* the light (screen space, y down): from the upper front.
var light := Vector2(0.55, -0.85).normalized()
## Outer outline takes a deep shade of the colour it wraps (32-bit sprite style).
var selout := false


func _init(width: int, height: int) -> void:
	w = width
	h = height
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	ids.resize(w * h)
	ids.fill(-1)


## Fills a polygon. opts:
##   shade (float, default 0.42): how far past the centre (towards the shadow side)
##     the interior turns to shadow; > 1 disables interior shadow
##   flat (bool): single base tone, no bevel (for glows / visors)
##   line (bool, default true): dark inner line where this part covers another
##   spec (bool, default true): a highlight pixel run on the most lit edge
func poly(points: PackedVector2Array, ramp: Array, opts := {}) -> void:
	if points.size() < 3:
		return
	var id := _next_id
	_next_id += 1
	_lines[id] = ramp[0] if opts.get("line", true) else null
	var flat: bool = opts.get("flat", false)
	var shade_cut: float = opts.get("shade", 0.42)
	var spec: bool = opts.get("spec", true)
	# Orientation, centre, extent along the light axis.
	var area := 0.0
	var c := Vector2.ZERO
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
		c += a
	c /= points.size()
	var ccw := area > 0.0  # in y-down space a positive area means clockwise on screen
	var ext := 0.01
	for q in points:
		ext = maxf(ext, absf((q - c).dot(light)))
	var r := Rect2(points[0], Vector2.ZERO)
	for q in points:
		r = r.expand(q)
	var x0 := maxi(int(floor(r.position.x)), 0)
	var y0 := maxi(int(floor(r.position.y)), 0)
	var x1 := mini(int(ceil(r.end.x)), w - 1)
	var y1 := mini(int(ceil(r.end.y)), h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if not Geometry2D.is_point_in_polygon(p, points):
				continue
			var col: Color = ramp[2]
			if not flat:
				# Nearest edge and its outward normal.
				var best := 1e9
				var nrm := Vector2.ZERO
				for i in points.size():
					var a: Vector2 = points[i]
					var b: Vector2 = points[(i + 1) % points.size()]
					var q := Geometry2D.get_closest_point_to_segment(p, a, b)
					var d := p.distance_to(q)
					if d < best:
						best = d
						var e := (b - a).normalized()
						nrm = Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
				var lit := nrm.dot(light)
				var side := (p - c).dot(light) / ext  # +1 lit side, -1 shadow side
				if best < 1.0 and lit > 0.35:
					col = ramp[4] if (spec and lit > 0.8 and side > 0.55) else ramp[3]
				elif best < 1.0 and lit < -0.3:
					col = ramp[1]
				elif side < -shade_cut:
					col = ramp[1]
			_put(x, y, col, id)


func _put(x: int, y: int, col: Color, id: int) -> void:
	img.set_pixel(x, y, col)
	ids[y * w + x] = id


## Ellipse helper (centre, radii, rotation in radians).
func ellipse(center: Vector2, rx: float, ry: float, angle: float, ramp: Array, opts := {}) -> void:
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var a := TAU * i / n
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	poly(pts, ramp, opts)


## Tapered segment from a (width wa) to b (width wb) with rounded-ish ends.
func limb(a: Vector2, b: Vector2, wa: float, wb: float, ramp: Array, opts := {}) -> void:
	var d := (b - a)
	if d.length() < 0.01:
		ellipse(a, wa * 0.5, wa * 0.5, 0.0, ramp, opts)
		return
	var dir := d.normalized()
	var n := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	pts.append(a + n * wa * 0.5)
	pts.append(b + n * wb * 0.5)
	pts.append(b + dir * wb * 0.35 + n * wb * 0.2)
	pts.append(b + dir * wb * 0.35 - n * wb * 0.2)
	pts.append(b - n * wb * 0.5)
	pts.append(a - n * wa * 0.5)
	pts.append(a - dir * wa * 0.35 - n * wa * 0.2)
	pts.append(a - dir * wa * 0.35 + n * wa * 0.2)
	poly(pts, ramp, opts)


## Hand-drawn pixel grid ("stamp"): rows of palette keys, "." = empty. The grid
## cell `anchor` lands on `at`. opts:
##   shear (float): push each row forward by shear * (rows above the anchor) px (lean)
##   flip (bool): mirror horizontally (around the anchor column)
##   line (Color or null): inner line colour where the stamp covers earlier parts
func stamp(grid: Array, pal: Dictionary, at: Vector2, anchor: Vector2i, opts := {}) -> void:
	var id := _next_id
	_next_id += 1
	_lines[id] = opts.get("line", null)
	var shear: float = opts.get("shear", 0.0)
	var flip: bool = opts.get("flip", false)
	var ax := int(round(at.x))
	var ay := int(round(at.y))
	for r in grid.size():
		var row: String = grid[r]
		var dx := int(round(shear * (anchor.y - r)))
		for c in row.length():
			var ch := row[c]
			if ch == "." or not pal.has(ch):
				continue
			var cx := (anchor.x - c) if flip else (c - anchor.x)
			var x := ax + cx + dx
			var y := ay + r - anchor.y
			if x >= 0 and y >= 0 and x < w and y < h:
				_put(x, y, pal[ch], id)


## Single pixel (eyes, glints).
func dot(p: Vector2, col: Color) -> void:
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if x >= 0 and y >= 0 and x < w and y < h:
		_put(x, y, col, _next_id)
		_next_id += 1
		_lines[_next_id - 1] = null


## Inner lines between overlapping parts, then the outer outline.
func finish(outline: Color) -> void:
	var out := img.duplicate()
	for y in h:
		for x in w:
			var id := ids[y * w + x]
			if id < 0:
				continue
			var line = _lines.get(id)
			if line == null:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nid := ids[ny * w + nx]
				if nid >= 0 and nid < id and _lines.get(nid) != null:
					out.set_pixel(x, y, line)
					break
	img = out
	out = img.duplicate()
	for y in h:
		for x in w:
			if ids[y * w + x] >= 0:
				continue
			for o in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and ids[ny * w + nx] >= 0:
					var c := outline
					if selout:
						# Selective outline: a deep shade of the colour it wraps.
						c = img.get_pixel(nx, ny).darkened(0.68).lerp(outline, 0.45)
						c.a = 1.0
					out.set_pixel(x, y, c)
					break
	img = out


## 5-tone ramp from a base colour (hue-shifted: shadows cooler, lights warmer).
static func ramp_from(base: Color, line := Color("101b36")) -> Array:
	var shadow := base.darkened(0.32)
	shadow.h = wrapf(shadow.h + 0.03, 0.0, 1.0)
	var lit := base.lightened(0.28)
	var hi := base.lightened(0.62)
	var ln := base.darkened(0.5).lerp(line, 0.25)
	return [ln, shadow, base, lit, hi]
