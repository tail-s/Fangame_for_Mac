extends Node2D
## Gallery preview (GDD §7-2 "해금된 아머·보스 설정화·자료 기록"), left of the list:
##   armor    IX wearing that part (or the Ultimate frame); locked parts in silhouette
##   bosses   the boss portrait once defeated, static noise while unknown
##   records  progress bars
## main.gd fills `entries` (one per list row) and calls show_index().

const SpriteVisual = preload("res://scripts/player/sprite_visual.gd")
const PreviewPuppet = preload("res://scripts/player/preview_puppet.gd")
const PORTRAITS := "res://art/portraits/"
const FRAME := Rect2(10, 30, 160, 112)
const C_FRAME := Color("497593")
const C_BG := Color("0a1326")
const C_TEXT := Color("d7edf3")
const C_DIM := Color("6f8fae")
const C_ACCENT := Color("3de0ee")
const C_GOLD := Color("f0b84a")

## {"kind": "armor"|"boss"|"record", "name", "status", "unlocked": bool,
##  "part": slot armor id (armor), "portrait": id (boss), "value": 0..1 (record)}
var entries: Array = []
var index := 0
var _t := 0.0
var _ix: Node2D
var _puppet
var _tex := {}


func _ready() -> void:
	_puppet = PreviewPuppet.new()
	_puppet.shoot_pose_timer = 0.0
	_ix = SpriteVisual.new()
	_ix.player = _puppet
	_ix.character = "ix"
	_ix.position = FRAME.position + Vector2(80, 104)
	_ix.scale = Vector2(2, 2)
	add_child(_ix)
	show_index(index)


func show_index(i: int) -> void:
	index = i
	if _ix == null or entries.is_empty():
		return
	var e: Dictionary = entries[clampi(i, 0, entries.size() - 1)]
	_ix.visible = e.kind == "armor"
	if e.kind == "armor":
		var lo := {"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "neutral"}
		var part: String = e.get("part", "")
		if part == "ultimate":
			lo = {"head": "ultimate", "body": "ultimate", "arm": "ultimate", "leg": "ultimate"}
		elif part != "":
			var bits := part.split("_")
			lo[bits[1]] = bits[0]
		_ix.part_armor = lo
		_ix.modulate = Color.WHITE if e.unlocked else Color(0.05, 0.08, 0.16, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _puppet != null:
		_puppet.anim_time += delta
	queue_redraw()


func _portrait(id: String) -> Texture2D:
	if not _tex.has(id):
		var path := PORTRAITS + id + ".png"
		_tex[id] = load(path) if ResourceLoader.exists(path) else null
	return _tex[id]


func _text(pos: Vector2, s: String, size: int, c: Color, width := 176.0) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, 3, C_BG)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, c)


func _draw() -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries[clampi(index, 0, entries.size() - 1)]
	var r := FRAME
	draw_rect(r.grow(1), C_BG)
	match e.kind:
		"armor":
			# Lab floor and grid behind the preview.
			for y in range(int(r.position.y) + 8, int(r.end.y), 12):
				draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(C_FRAME, 0.18))
			draw_rect(Rect2(r.position.x + 40, r.position.y + 104, 80, 2), Color(C_ACCENT, 0.5))
			if not e.unlocked:
				_text(r.position + Vector2(66, 60), "???", 16, C_DIM)
		"boss":
			var tex := _portrait(e.get("portrait", "")) if e.unlocked else null
			if tex != null:
				draw_texture_rect(tex, r, false)
				for y in range(int(r.position.y) + 1, int(r.end.y), 4):
					draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(0, 0, 0, 0.12))
			else:
				for k in 90:
					var nx := r.position.x + fmod(k * 37.7 + floor(_t * 12.0) * 13.1, r.size.x - 2.0)
					var ny := r.position.y + fmod(k * 23.3 + floor(_t * 12.0) * 7.9, r.size.y - 2.0)
					draw_rect(Rect2(nx, ny, 2, 1), Color(C_DIM, 0.35))
				_text(r.position + Vector2(8, r.size.y * 0.5 + 4), "NO DATA", 12, C_DIM)
		"record":
			# Every record row as a bar, the selected one highlighted.
			var y := r.position.y + 14.0
			for i in entries.size():
				var rec: Dictionary = entries[i]
				var on := i == index
				_text(Vector2(r.position.x + 6, y), rec.get("status", ""), 7, C_TEXT if on else C_DIM, 150)
				var bar := Rect2(r.position.x + 6, y + 3, r.size.x - 12, 3)
				draw_rect(bar, Color(C_FRAME, 0.4))
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(rec.get("value", 0.0), 0.0, 1.0), 3)),
						C_GOLD if on else C_ACCENT)
				y += 13.0
	draw_rect(r.grow(1), C_FRAME, false, 1.0)
	for c in [r.position, Vector2(r.end.x - 5, r.position.y), Vector2(r.position.x, r.end.y - 5), r.end - Vector2(5, 5)]:
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(6, 6)), C_ACCENT, false, 1.0)
	_text(Vector2(10, 156), e.get("name", ""), 11, C_TEXT)
	_text(Vector2(10, 168), e.get("status", ""), 7, C_DIM)
