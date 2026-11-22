extends CanvasLayer
## Keyboard / gamepad list menu used for the title, stage select, options and pause.
## items: [{"id": String, "text": String, "note": String (optional),
##          "adjust": bool (optional: ← / → emit `adjusted`)}]
## Up to 5 items: roomy layout with every note shown. More items: compact
## scrolling list, and only the selected item's note is shown at the bottom.

signal chosen(id: String)
signal cancelled
## ← / → on an item with "adjust": true. dir is -1 or 1.
signal adjusted(id: String, dir: int)

const C_TEXT := Color("d7edf3")
const C_DIM := Color("6f8fae")
const C_ACCENT := Color("3de0ee")
const ROOMY_MAX := 5
const COMPACT_ROWS := 8
const COMPACT_STEP := 13

var title := ""
var subtitle := ""
var footer := ""
var items: Array = []
var dim := false
var selected := 0

var _rows: Array = []
var _cursor: ColorRect
var _detail: Label
var _more_up: Label
var _more_down: Label
var _top := 0
var _guard := 2  # ignore the press that opened this menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0.04, 0.07, 0.15, 0.75)
		shade.size = Vector2(384, 216)
		add_child(shade)
	_label(title, 20, Vector2(0, 28 if not _compact() else 18), C_TEXT)
	_label(subtitle, 9, Vector2(0, 56 if not _compact() else 46), C_ACCENT)
	_cursor = ColorRect.new()
	_cursor.color = Color(0.0, 0.72, 0.75, 0.18)
	_cursor.size = Vector2(300, 15 if not _compact() else 12)
	add_child(_cursor)
	for i in items.size():
		var it: Dictionary = items[i]
		if _compact():
			_rows.append([_label(it.text, 10, Vector2.ZERO, C_TEXT), null])
		else:
			var row := _label(it.text, 11, Vector2(0, 80 + i * 22), C_TEXT)
			var note := _label(it.get("note", ""), 7, Vector2(0, 93 + i * 22), C_DIM)
			_rows.append([row, note])
	if _compact():
		_detail = _label("", 8, Vector2(0, 180), C_DIM)
		_more_up = _label("▲", 7, Vector2(0, 63), C_DIM)
		_more_down = _label("▼", 7, Vector2(0, 63 + (COMPACT_ROWS + 1) * COMPACT_STEP - 2), C_DIM)
	_label(footer, 8, Vector2(0, 200), C_DIM)
	_refresh()


func _process(_delta: float) -> void:
	if _guard > 0:
		_guard -= 1
		return
	if items.is_empty():
		return
	if Input.is_action_just_pressed("move_down"):
		selected = (selected + 1) % items.size()
		_sfx("menu_move")
		_refresh()
	elif Input.is_action_just_pressed("move_up"):
		selected = (selected - 1 + items.size()) % items.size()
		_sfx("menu_move")
		_refresh()
	elif items[selected].get("adjust", false) and (Input.is_action_just_pressed("move_left")
			or Input.is_action_just_pressed("move_right")):
		_sfx("menu_move")
		adjusted.emit(items[selected].id, -1 if Input.is_action_just_pressed("move_left") else 1)
	elif Input.is_action_just_pressed("confirm"):
		_sfx("menu_ok")
		chosen.emit(items[selected].id)
	elif Input.is_action_just_pressed("cancel"):
		_sfx("menu_back")
		cancelled.emit()


## Changes one item's text / note in place (e.g. an option value).
func update_item(id: String, text: String, note := "") -> void:
	for i in items.size():
		if items[i].id == id:
			items[i].text = text
			items[i].note = note
			if _rows[i][1] != null:
				_rows[i][1].text = note
	_refresh()


func _compact() -> bool:
	return items.size() > ROOMY_MAX


func _refresh() -> void:
	if _compact():
		_top = clampi(_top, selected - COMPACT_ROWS + 1, selected)
		_top = clampi(_top, 0, maxi(items.size() - COMPACT_ROWS, 0))
	for i in _rows.size():
		var on := i == selected
		var row: Label = _rows[i][0]
		row.add_theme_color_override("font_color", C_ACCENT if on else C_TEXT)
		row.text = ("▶ " if on else "") + items[i].text
		if _compact():
			var vis := i - _top
			row.visible = vis >= 0 and vis < COMPACT_ROWS
			row.position = Vector2(0, 72 + vis * COMPACT_STEP)
	if _compact():
		_cursor.position = Vector2(42, 73 + (selected - _top) * COMPACT_STEP)
		_detail.text = items[selected].get("note", "")
		_more_up.visible = _top > 0
		_more_down.visible = _top + COMPACT_ROWS < items.size()
	else:
		_cursor.position = Vector2(42, 79 + selected * 22)


func _sfx(name: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.sfx(name)


func _label(text: String, size: int, pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(384, size + 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("0a1326"))
	l.add_theme_constant_override("outline_size", 3)
	add_child(l)
	return l
