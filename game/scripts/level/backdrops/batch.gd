extends RefCounted
## Collects a painter's shapes into ONE triangle-array draw command. Separate
## draw_rect / draw_line / draw_colored_polygon calls each cost the canvas
## renderer every frame (polygons are a draw call each), times every Parallax2D
## repeat; one triangle array is one draw call. Shapes keep their order: later
## ones are drawn on top of earlier ones.

var points := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func rect(r: Rect2, color: Color) -> void:
	quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), color)


## Rect fading from `top` colour to `bottom` colour.
func vgradient(r: Rect2, top: Color, bottom: Color) -> void:
	var i := _add([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)],
			top)
	colors[i + 2] = bottom
	colors[i + 3] = bottom
	indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))


## Convex quad a-b-c-d (either winding).
func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	var i := _add([a, b, c, d], color)
	indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))


## Pixel line between pixel coordinates (like draw_line without antialiasing).
func line(a: Vector2, b: Vector2, color: Color, width := 1.0) -> void:
	var d := b - a
	if d.is_zero_approx():
		return
	var n := d.normalized().orthogonal() * (width * 0.5)
	var o := Vector2(0.5, 0.5)
	quad(a + o - n, a + o + n, b + o + n, b + o - n, color)


func polyline(pts: PackedVector2Array, color: Color, width := 1.0) -> void:
	for k in pts.size() - 1:
		line(pts[k], pts[k + 1], color, width)


## Pairs of points: a0 b0 a1 b1 ... (like draw_multiline).
func multiline(pts: PackedVector2Array, color: Color, width := 1.0) -> void:
	for k in range(0, pts.size() - 1, 2):
		line(pts[k], pts[k + 1], color, width)


## Filled circle as a triangle fan.
func circle(center: Vector2, radius: float, color: Color, segments := 16) -> void:
	var ring: Array = [center]
	for k in segments:
		ring.append(center + Vector2.from_angle(TAU * k / segments) * radius)
	var i := _add(ring, color)
	for k in segments:
		indices.append_array(PackedInt32Array([i, i + 1 + k, i + 1 + (k + 1) % segments]))


## Circle outline (or part of it) from angle a0 to a1.
func arc(center: Vector2, radius: float, a0: float, a1: float, segments: int, color: Color,
		width := 1.0) -> void:
	var pts := PackedVector2Array()
	for k in segments + 1:
		pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / segments)) * radius)
	for k in segments:
		var n := (pts[k + 1] - pts[k]).normalized().orthogonal() * (width * 0.5)
		quad(pts[k] - n, pts[k] + n, pts[k + 1] + n, pts[k + 1] - n, color)


## Any simple polygon (triangulated once here).
func polygon(pts: PackedVector2Array, color: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var i := _add(Array(pts), color)
	for t in tris:
		indices.append(i + t)


## Triangles collected so far.
func size() -> int:
	return indices.size() / 3


## Adds everything collected to `canvas` as one command (call from its _draw).
func flush(canvas: CanvasItem) -> void:
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
	points = PackedVector2Array()
	colors = PackedColorArray()
	indices = PackedInt32Array()


func _add(pts: Array, color: Color) -> int:
	var i := points.size()
	for p in pts:
		points.append(p)
		colors.append(color)
	return i
