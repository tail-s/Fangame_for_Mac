extends CanvasLayer
## In-stage HUD: HP and core gauges, equipped-part chips, boss gauge, centre
## message, short toasts, control hints and the F1 debug readout.

const ArmorData = preload("res://scripts/armor/armor_data.gd")

const C_BG := Color("0a1326")
const C_FRAME := Color("497593")
const C_FULL := Color("00b8be")
const C_LOW := Color("e34f5b")
const C_EMPTY := Color("1c375b")
const C_CORE := Color("f0b84a")
const C_BOSS := Color("b78af3")

var hp := 16
var max_hp := 16
var core := 0.0
var special_ready := false
var boss_hp := -1
var boss_max := 1
var loadout := ArmorData.neutral_loadout()
var player

var _gauges: Control
var _msg: Label
var _toast: Label
var _hint: Label
var _help: Label
var _debug: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 10
	_gauges = Control.new()
	_gauges.size = Vector2(384, 216)
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauges.draw.connect(_draw_gauges)
	add_child(_gauges)

	_msg = _label(16, Vector2(0, 84), Vector2(384, 24), HORIZONTAL_ALIGNMENT_CENTER)
	_toast = _label(9, Vector2(0, 26), Vector2(384, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _label(8, Vector2(0, 186), Vector2(384, 12), HORIZONTAL_ALIGNMENT_CENTER)
	_help = _label(8, Vector2(6, 202), Vector2(372, 12), HORIZONTAL_ALIGNMENT_LEFT)
	_help.text = "이동 ←→  점프 Z  사격 X(길게=차지)  대시 C  필살기 V  일시정지 Esc"
	_debug = _label(8, Vector2(236, 4), Vector2(144, 40), HORIZONTAL_ALIGNMENT_LEFT)
	_debug.visible = false
	var tween := create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(_help, "modulate:a", 0.0, 1.0)


func set_hp(value: int, maximum: int) -> void:
	hp = value
	max_hp = maximum
	_gauges.queue_redraw()


func set_core(value: float, _maximum: float) -> void:
	core = value
	special_ready = player != null and is_instance_valid(player) and player.special_ready()
	_gauges.queue_redraw()


func set_loadout(lo: Dictionary) -> void:
	loadout = lo.duplicate()
	_gauges.queue_redraw()


func set_boss_hp(value: int, maximum: int) -> void:
	boss_hp = value
	boss_max = maximum
	_gauges.queue_redraw()


func hide_boss() -> void:
	boss_hp = -1
	_gauges.queue_redraw()


func show_message(text: String) -> void:
	_msg.text = text


func toast(text: String, seconds := 3.0) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func set_hint(text: String) -> void:
	_hint.text = text


func toggle_debug() -> void:
	_debug.visible = not _debug.visible


func _process(_delta: float) -> void:
	if _debug.visible and player != null and is_instance_valid(player):
		_debug.text = "%s  v=(%.0f, %.0f)\nmomentum=%s  airdash=%d\ncore=%.0f  wall=%d  FPS %d" % [
			player.state_name(), player.velocity.x, player.velocity.y,
			player.dash_momentum, player.air_dashes_left, player.core,
			player.wall_dir, Engine.get_frames_per_second()]


func _draw_gauges() -> void:
	var seg := 3.0
	var origin := Vector2(8, 18)
	var h := max_hp * seg + 3.0
	_frame(Rect2(origin, Vector2(10, h + 2)))
	for i in max_hp:
		var y := origin.y + 2.0 + (max_hp - 1 - i) * seg
		var c := C_EMPTY
		if i < hp:
			c = C_LOW if hp <= 4 else C_FULL
		_gauges.draw_rect(Rect2(origin.x + 2, y, 6, seg - 1.0), c)

	# Core gauge (flight / specials).
	var core_box := Rect2(origin.x + 12, origin.y, 5, h + 2)
	_frame(core_box)
	var fill := (h - 2.0) * clampf(core / 100.0, 0.0, 1.0)
	var cc := C_CORE
	if special_ready and int(Time.get_ticks_msec() / 120.0) % 2 == 0:
		cc = Color.WHITE
	_gauges.draw_rect(Rect2(core_box.position.x + 1, core_box.end.y - 2 - fill, 3, fill), cc)

	# Equipped part chips: H B A L.
	var y0 := origin.y + h + 6.0
	for i in ArmorData.SLOTS.size():
		var slot: String = ArmorData.SLOTS[i]
		var c: Color = ArmorData.ARMOR_COLOR[loadout.get(slot, "neutral")]
		_gauges.draw_rect(Rect2(origin.x + (i % 2) * 9, y0 + (i / 2) * 9, 8, 8), c)
		_gauges.draw_string(ThemeDB.fallback_font, Vector2(origin.x + (i % 2) * 9 + 2, y0 + (i / 2) * 9 + 7),
				ArmorData.SLOT_LABEL[slot].substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, C_BG)

	# Boss gauge.
	if boss_hp >= 0:
		var bh := boss_max * 2.0 + 3.0
		var bo := Vector2(366, 18)
		_frame(Rect2(bo, Vector2(10, bh + 2)))
		for i in boss_max:
			var y := bo.y + 2.0 + (boss_max - 1 - i) * 2.0
			_gauges.draw_rect(Rect2(bo.x + 2, y, 6, 1), C_BOSS if i < boss_hp else C_EMPTY)


func _frame(r: Rect2) -> void:
	_gauges.draw_rect(r, C_BG)
	_gauges.draw_rect(r, C_FRAME, false, 1.0)


func _label(font_size: int, pos: Vector2, box: Vector2, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color("d7edf3"))
	l.add_theme_color_override("font_outline_color", C_BG)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
