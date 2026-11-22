extends Node2D
## One block of map tiles drawn by level.gd. Splitting the map into blocks lets
## the renderer skip every block that is off screen (the whole map as a single
## canvas item sent thousands of draw calls per frame).

var level: Node2D
## Tile rectangle this block draws.
var cells := Rect2i()


func _draw() -> void:
	level.draw_cells(self, cells)
