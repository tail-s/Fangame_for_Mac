extends CanvasLayer
## Boss entrance (GDD §7-2): letterbox bars close in, a striped band slides across
## with the boss portrait (art/portraits/<id>.png), "WARNING" and the boss name,
## then everything slides away. Purely visual; frees itself (about 1.6 s).

const C_BG := Color("0a1326")
const C_TEXT := Color("d7edf3")
const C_WARN := Color("e34f5b")
const BAND_Y := 70.0
const BAND_H := 60.0
const BARS := 18.0
const HOLD := 1.05

var boss_name := ""
var caption := ""
var portrait: Texture2D
var accent := Color("3de0ee")
var hidden := false

var _bars := 0.0
var _slide := 1.0
var _t := 0.0
var _canvas: Node2D


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_cutin)
	add_child(_canvas)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_bars", 1.0, 0.18)
	tw.tween_property(self, "_slide", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(HOLD)
	tw.chain().tween_property(self, "_slide", -1.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_bars", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()


func _draw_cutin() -> void:
	var c := _canvas
	# Letterbox.
	var bh := BARS * _bars
	c.draw_rect(Rect2(0, 0, 384, bh), Color.BLACK)
	c.draw_rect(Rect2(0, 216 - bh, 384, bh), Color.BLACK)
	var ox := _slide * 384.0
	# Band with moving diagonal stripes.
	var band := Rect2(ox, BAND_Y, 384, BAND_H)
	c.draw_rect(band, Color(C_BG, 0.92))
	var stripe := Color(accent, 0.12)
	var shift := fmod(_t * 60.0, 16.0)
	for k in range(-2, 28):
		var x := ox + k * 16.0 - shift
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, BAND_Y), Vector2(x + 6, BAND_Y),
				Vector2(x + 6 - BAND_H * 0.5, BAND_Y + BAND_H), Vector2(x - BAND_H * 0.5, BAND_Y + BAND_H)]), stripe)
	c.draw_rect(Rect2(ox, BAND_Y, 384, 2), accent)
	c.draw_rect(Rect2(ox, BAND_Y + BAND_H - 2, 384, 2), accent)
	# Portrait.
	var pr := Rect2(ox + 14, BAND_Y + 2, 80, 56)
	if portrait != null:
		c.draw_texture_rect(portrait, pr, false)
	c.draw_rect(pr, accent, false, 1.0)
	# Text.
	var font := ThemeDB.fallback_font
	var warn := "!! UNKNOWN SIGNAL !!" if hidden else "WARNING"
	if int(_t * 8.0) % 2 == 0 or _slide != 0.0:
		_text(font, Vector2(ox + 106, BAND_Y + 16), warn, 9, C_WARN)
	_text(font, Vector2(ox + 106, BAND_Y + 38), boss_name, 18, C_TEXT)
	_text(font, Vector2(ox + 106, BAND_Y + 53), caption, 8, Color(accent, 0.95))


func _text(font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	_canvas.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, 270, size, 4, C_BG)
	_canvas.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, 270, size, col)
