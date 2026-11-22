extends Node2D
## A canvas drawn by a theme method: `paint.call(batch)` fills a Batch, which goes
## out as ONE draw command. It draws once and the renderer keeps it; only small
## animated painters call queue_redraw().

const Batch = preload("res://scripts/level/backdrops/batch.gd")

## Time spent in paint calls and how many ran (read by tests/backdrop_test.gd).
static var draw_usec := 0
static var draw_count := 0

var paint: Callable
## Completed draws of this painter (a paint error leaves it unchanged).
var draws := 0
## Triangles in the last draw.
var triangles := 0


func _draw() -> void:
	if not paint.is_valid():
		return
	var t := Time.get_ticks_usec()
	var b := Batch.new()
	paint.call(b)
	triangles = b.size()
	b.flush(self)
	draw_usec += Time.get_ticks_usec() - t
	draw_count += 1
	draws += 1
