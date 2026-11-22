extends Node2D
## Title screen: IX, SABLE and ECHO standing on an orbital platform edge at the
## lower left, in their idle animations (sprite visuals driven by puppets).

const SpriteVisual = preload("res://scripts/player/sprite_visual.gd")
const PreviewPuppet = preload("res://scripts/player/preview_puppet.gd")
const Level = preload("res://scripts/level/level.gd")

const LEDGE_Y := 196.0
const CAST := [["sable", 30.0, 1], ["ix", 58.0, 1], ["echo", 86.0, 1]]

var _puppets: Array = []


func _ready() -> void:
	for c in CAST:
		var puppet := PreviewPuppet.new()
		puppet.shoot_pose_timer = 0.0
		puppet.facing = c[2]
		var v := SpriteVisual.new()
		v.player = puppet
		v.character = c[0]
		v.position = Vector2(c[1], LEDGE_Y)
		add_child(v)
		_puppets.append(puppet)


func _process(delta: float) -> void:
	for p in _puppets:
		p.anim_time += delta


func _draw() -> void:
	# Platform edge from the training tileset: a top row and one row below.
	var tex := Level.tileset("training")
	for x in range(0, 8):
		var top_mask := 1 | (2 if x == 7 else 0)
		var low_mask := (2 if x == 7 else 0)
		draw_texture_rect_region(tex, Rect2(x * 16 - 8, LEDGE_Y, 16, 16), Rect2(top_mask * 16, (x % 3 == 1) as int * 16, 16, 16))
		draw_texture_rect_region(tex, Rect2(x * 16 - 8, LEDGE_Y + 16, 16, 16), Rect2(low_mask * 16, 0, 16, 16))
