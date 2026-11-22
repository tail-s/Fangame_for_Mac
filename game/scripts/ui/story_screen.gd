extends CanvasLayer
## Full-screen story pages (prologue, mid event, endings). Z / Enter: next page
## (finishes the typing first), Esc: skip. Emits `finished` after the last page.

const Autoloads = preload("res://scripts/core/autoloads.gd")

signal finished

const C_TEXT := Color("d7edf3")
const C_ACCENT := Color("3de0ee")
const CHARS_PER_SEC := 40.0

var pages: Array = []  # [[title, body], ...]
var page := 0

var _title: Label
var _body: Label
var _hint: Label
var _shown := 0.0
var _guard := 2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.11, 0.97)
	bg.size = Vector2(384, 216)
	add_child(bg)
	var line := ColorRect.new()
	line.color = Color(0.0, 0.72, 0.75, 0.6)
	line.position = Vector2(40, 52)
	line.size = Vector2(304, 1)
	add_child(line)
	_title = _label(13, Vector2(40, 30), Vector2(304, 20), C_ACCENT)
	_body = _label(10, Vector2(40, 64), Vector2(304, 120), C_TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(8, Vector2(40, 196), Vector2(304, 12), Color("6f8fae"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_show_page()


func _process(delta: float) -> void:
	var total := _body.text.length()
	if _shown < total:
		var before := int(_shown)
		_shown = minf(_shown + CHARS_PER_SEC * delta, total)
		_body.visible_characters = int(_shown)
		if int(_shown) / 3 != before / 3:
			Autoloads.sfx("text")
	if _guard > 0:
		_guard -= 1
		return
	if Input.is_action_just_pressed("cancel"):
		finished.emit()
	elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("shoot"):
		Autoloads.sfx("menu_ok")
		if _shown < total:
			_shown = total
			_body.visible_characters = -1
		elif page + 1 < pages.size():
			page += 1
			_show_page()
		else:
			finished.emit()


func _show_page() -> void:
	var p: Array = pages[page]
	_title.text = p[0]
	_body.text = p[1]
	_shown = 0.0
	_body.visible_characters = 0
	_hint.text = "%d / %d   Z 다음   Esc 건너뛰기" % [page + 1, pages.size()]


func _label(size: int, pos: Vector2, box: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = box
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("0a1326"))
	l.add_theme_constant_override("outline_size", 2)
	add_child(l)
	return l
