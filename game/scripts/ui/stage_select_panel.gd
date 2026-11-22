extends Node2D
## Stage select extras (GDD §7-2): the selected boss portrait (art/portraits/,
## captured in game with `-- --portraits=<dir>`), its status, and the EDEN LINK
## region map where every stage is a node wired to the core:
##   ✓ cleared (green)   ▲ environment changed (amber)   ◈ unknown signal (violet)
## Lives inside the menu's CanvasLayer; main.gd fills `entries` and calls show_index().

const PORTRAITS := "res://art/portraits/"
const PORTRAIT_RECT := Rect2(10, 30, 160, 112)
const MAP_RECT := Rect2(190, 124, 186, 44)
## Node positions inside the map (EDEN core station at the top, orbit up right).
const MAP_POS := {
	"final_eden_core": Vector2(93, 7),
	"gravity_albatross": Vector2(152, 9),
	"cryo_narwhal": Vector2(18, 21),
	"prism_gecko": Vector2(44, 31),
	"solar_fennec": Vector2(74, 36),
	"terra_pangolin": Vector2(108, 39),
	"pulse_cicada": Vector2(140, 30),
	"training": Vector2(170, 37),
}
const C_FRAME := Color("497593")
const C_BG := Color("0a1326")
const C_TEXT := Color("d7edf3")
const C_DIM := Color("6f8fae")
const C_LINE := Color("1f4a66")
const C_NODE := Color("3de0ee")
const C_CLEAR := Color("7de38a")
const C_CHANGE := Color("f0b84a")
const C_SIGNAL := Color("b78af3")
const C_LOCK := Color("4b5a72")

## One per menu row: {"kind": "stage"|"lab"|"title", "id", "name", "locked",
## "cleared", "changed", "signal": ""|"weak"|"detected", "portrait": id or ""}
var entries: Array = []
var index := 0
var _t := 0.0
var _tex := {}


func show_index(i: int) -> void:
	index = i
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _portrait(id: String) -> Texture2D:
	if id == "":
		return null
	if not _tex.has(id):
		var path := PORTRAITS + id + ".png"
		_tex[id] = load(path) if ResourceLoader.exists(path) else null
	return _tex[id]


func _draw() -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries[clampi(index, 0, entries.size() - 1)]
	_draw_portrait(e)
	_draw_map(e)


func _text(pos: Vector2, s: String, size: int, c: Color, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, 3, C_BG)
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, c)


func _draw_portrait(e: Dictionary) -> void:
	var r := PORTRAIT_RECT
	draw_rect(r.grow(1), C_BG)
	var tex := _portrait(e.get("portrait", "")) if not e.get("locked", false) else null
	if tex != null:
		draw_texture_rect(tex, r, false)
		# Scanline sheen over the feed.
		for y in range(int(r.position.y) + 1, int(r.end.y), 4):
			draw_rect(Rect2(r.position.x, y, r.size.x, 1), Color(0, 0, 0, 0.12))
	else:
		# No feed: static noise (locked / no boss) with a caption.
		for k in 90:
			var nx := r.position.x + fmod(k * 37.7 + floor(_t * 12.0) * 13.1, r.size.x - 2.0)
			var ny := r.position.y + fmod(k * 23.3 + floor(_t * 12.0) * 7.9, r.size.y - 2.0)
			draw_rect(Rect2(nx, ny, 2, 1), Color(C_DIM, 0.35))
		var cap: String = "LOCKED" if e.get("locked", false) else {"lab": "ARMOR LAB", "title": "TITLE"}.get(e.kind, "SIMULATION")
		_text(r.position + Vector2(8, r.size.y * 0.5 + 4), cap, 12, C_DIM)
	draw_rect(r.grow(1), C_FRAME, false, 1.0)
	# Corner brackets.
	for c in [r.position, Vector2(r.end.x - 5, r.position.y), Vector2(r.position.x, r.end.y - 5), r.end - Vector2(5, 5)]:
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(6, 6)), C_NODE, false, 1.0)
	if e.get("signal", "") != "" and int(_t * 3.0) % 2 == 0:
		_text(r.position + Vector2(r.size.x - 18, 14), "◈", 12, C_SIGNAL)
	# Name and status under the portrait.
	_text(Vector2(10, 156), e.get("name", ""), 11, C_TEXT, 176)
	var status := []
	if e.get("cleared", false):
		status.append("✓ CLEARED")
	if e.get("changed", false):
		status.append("▲ 환경 변화")
	if e.get("signal", "") == "detected":
		status.append("◈ 신호 감지")
	elif e.get("signal", "") == "weak":
		status.append("◈ 신호 약함")
	if e.get("locked", false):
		status = ["LOCKED"]
	_text(Vector2(10, 168), "  ".join(status), 7, C_DIM, 176)


func _draw_map(e: Dictionary) -> void:
	var m := MAP_RECT
	draw_rect(m, Color(C_BG, 0.92))
	# Planet limb and orbit.
	var pts := PackedVector2Array()
	for k in 25:
		var x := m.position.x + m.size.x * k / 24.0
		var u := (x - m.get_center().x) / (m.size.x * 0.5)
		pts.append(Vector2(x, m.end.y - 2 - 12.0 * (1.0 - u * u)))
	draw_polyline(pts, C_LINE, 1.0)
	draw_arc(m.position + Vector2(93, 52), 70.0, PI * 1.12, PI * 1.88, 24, Color(C_LINE, 0.8), 1.0)
	# Links to the core.
	var core: Vector2 = m.position + MAP_POS.final_eden_core
	for entry in entries:
		if entry.kind != "stage" or not MAP_POS.has(entry.id) or entry.id == "final_eden_core":
			continue
		var p: Vector2 = m.position + MAP_POS[entry.id]
		draw_line(p, core, Color(C_LINE, 1.0) if not entry.locked else Color(C_LOCK, 0.5), 1.0)
	# Nodes.
	for entry in entries:
		if entry.kind != "stage" or not MAP_POS.has(entry.id):
			continue
		var p: Vector2 = m.position + MAP_POS[entry.id]
		var c := C_NODE
		if entry.locked:
			c = C_LOCK
		elif entry.cleared:
			c = C_CLEAR
		var sz := 3.0 if entry.id == "final_eden_core" else 2.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz), p + Vector2(sz, 0), p + Vector2(0, sz),
				p + Vector2(-sz, 0)]), c)
		if entry.changed:
			draw_rect(Rect2(p + Vector2(3, -5), Vector2(2, 2)), C_CHANGE)
		if entry.signal != "" and int(_t * 3.0) % 2 == 0:
			draw_arc(p, 5.0, 0.0, TAU, 10, C_SIGNAL, 1.0)
	# Selected node.
	if e.kind == "stage" and MAP_POS.has(e.id):
		var p: Vector2 = m.position + MAP_POS[e.id]
		var rad := 5.0 + 1.5 * sin(_t * 6.0)
		draw_arc(p, rad, 0.0, TAU, 14, Color.WHITE, 1.0)
	draw_rect(m, C_FRAME, false, 1.0)
	_text(m.position + Vector2(4, 9), "EDEN LINK", 7, C_DIM)
