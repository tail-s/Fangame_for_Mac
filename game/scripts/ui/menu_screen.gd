extends CanvasLayer
## Keyboard / gamepad list menu used for the title, stage select and pause.
## items: [{"id": String, "text": String, "note": String (optional)}]

signal chosen(id: String)
signal cancelled

const C_TEXT := Color("d7edf3")
const C_DIM := Color("6f8fae")
const C_ACCENT := Color("3de0ee")

var title := ""
var subtitle := ""
var footer := ""
var items: Array = []
var dim := false
var selected := 0

var _rows: Array = []
var _cursor: ColorRect
var _guard := 2  # ignore the press that opened this menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0.04, 0.07, 0.15, 0.75)
		shade.size = Vector2(384, 216)
		add_child(shade)
	_label(title, 20, Vector2(0, 28), C_TEXT)
	_label(subtitle, 9, Vector2(0, 56), C_ACCENT)
	_cursor = ColorRect.new()
	_cursor.color = Color(0.0, 0.72, 0.75, 0.18)
	_cursor.size = Vector2(300, 15)
	add_child(_cursor)
	for i in items.size():
		var it: Dictionary = items[i]
		var row := _label(it.text, 11, Vector2(0, 80 + i * 22), C_TEXT)
		var note := _label(it.get("note", ""), 7, Vector2(0, 93 + i * 22), C_DIM)
		_rows.append([row, note])
	_label(footer, 8, Vector2(0, 200), C_DIM)
	_refresh()


func _process(_delta: float) -> void:
	if _guard > 0:
		_guard -= 1
		return
	if Input.is_action_just_pressed("move_down"):
		selected = (selected + 1) % items.size()
		_refresh()
	elif Input.is_action_just_pressed("move_up"):
		selected = (selected - 1 + items.size()) % items.size()
		_refresh()
	elif Input.is_action_just_pressed("confirm"):
		chosen.emit(items[selected].id)
	elif Input.is_action_just_pressed("cancel"):
		cancelled.emit()


func _refresh() -> void:
	for i in _rows.size():
		var on := i == selected
		_rows[i][0].add_theme_color_override("font_color", C_ACCENT if on else C_TEXT)
		_rows[i][0].text = ("▶ " if on else "") + items[i].text
	_cursor.position = Vector2(42, 79 + selected * 22)


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
