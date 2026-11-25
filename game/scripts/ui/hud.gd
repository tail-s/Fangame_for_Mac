extends CanvasLayer
## In-stage HUD: HP and core gauges, equipped-part chips, boss gauge, centre
## message, short toasts, control hints and the F1 debug readout.

const ArmorData = preload("res://scripts/armor/armor_data.gd")
const PixelArt = preload("res://scripts/fx/pixel_art.gd")
const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const C_BG := Color("0a1326")
const C_FRAME := Color("497593")
const C_FULL := Color("00b8be")
const C_LOW := Color("e34f5b")
const C_EMPTY := Color("1c375b")
const C_CORE := Color("f0b84a")
const C_BOSS := Color("b78af3")
const C_TEXT := Color("d7edf3")
# Pixel housings: ink outline with cut corners, bevel lit from the upper left.
const C_INK := Color("050a17")
const C_BEZEL_HI := Color("9ec4d8")
const C_BEZEL_LO := Color("213e5e")
const C_WELL := Color("0a1326")
## Gauge cell ramps: [shadow, mid, light].
const R_FULL := [Color("00808a"), Color("00b8be"), Color("7cf3ec")]
const R_LOW := [Color("9a2637"), Color("e34f5b"), Color("ff9f9b")]
const R_EMPTY := [Color("12274a"), Color("1c375b"), Color("244670")]
const R_CORE := [Color("ad6c1c"), Color("f0b84a"), Color("ffe5a3")]
const R_READY := [Color("8ccfe4"), Color("e6f8ff"), Color("ffffff")]
const R_BOSS := [Color("6c48b4"), Color("b78af3"), Color("e8d9ff")]
## Badge window (character head / boss emblem), in pixels.
const ICON := Vector2i(17, 15)
## Character badge: top-left of the ICON window on head.png, idle frame 0.
## IX's row follows the equipped helmet (sheet.json variants order).
const HEAD_CROP := {"ix": Vector2i(24, 12), "echo": Vector2i(24, 14), "sable": Vector2i(24, 12)}
const HEAD_ROWS := ["neutral", "vanguard", "aero", "ultimate"]
const SHEET_CELL_H := 56
## Boss emblem: [top-left of the ICON window on art/portraits/<id>.png, mirror].
## Mirrored crops face left, toward the player.
const BOSS_CROP := {
	"cryo_narwhal": [Vector2i(43, 19), true], "eclipse": [Vector2i(31, 7), true],
	"final_eden_core": [Vector2i(33, 25), false], "fragment": [Vector2i(32, 21), false],
	"gravity_albatross": [Vector2i(42, 23), true], "prism_gecko": [Vector2i(16, 19), false],
	"pulse_cicada": [Vector2i(24, 10), false], "solar_fennec": [Vector2i(46, 18), true],
	"terra_pangolin": [Vector2i(48, 23), true],
}
## Boss names that do not slug to their portrait id.
const BOSS_ALIAS := {"ARCA": "final_eden_core"}

var hp := 16
var max_hp := 16
var core := 0.0
var special_ready := false
var boss_hp := -1
var boss_max := 1
var boss_name := ""
var loadout := ArmorData.neutral_loadout()
var player

var _gauges: Control
var _status: Label
var _status_text := ""
var _status_frac := -1.0
var _msg: Label
var _toast: Label
var _hint: Label
var _help: Label
var _timer: Label
var _debug: Label
var _toast_tween: Tween
var _textures := {}


func _ready() -> void:
	layer = 10
	_gauges = Control.new()
	_gauges.size = Vector2(384, 216)
	_gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauges.draw.connect(_draw_gauges)
	add_child(_gauges)

	_status = _label(8, Vector2(34, 4), Vector2(220, 12), HORIZONTAL_ALIGNMENT_LEFT)
	_msg = _label(16, Vector2(0, 84), Vector2(384, 24), HORIZONTAL_ALIGNMENT_CENTER)
	_toast = _label(9, Vector2(0, 26), Vector2(384, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _label(8, Vector2(0, 186), Vector2(384, 12), HORIZONTAL_ALIGNMENT_CENTER)
	_help = _label(8, Vector2(6, 202), Vector2(372, 12), HORIZONTAL_ALIGNMENT_LEFT)
	_timer = _label(8, Vector2(296, 190), Vector2(82, 12), HORIZONTAL_ALIGNMENT_RIGHT)
	_help.text = help_text()
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
	boss_name = ""
	_gauges.queue_redraw()


func set_boss_name(text: String) -> void:
	boss_name = text
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
	if player != null and is_instance_valid(player):
		var text: String = "%s · %s" % [player.character_name(), player.status_text()]
		var frac: float = player.status_fraction()
		if text != _status_text or absf(frac - _status_frac) > 0.001:
			_status_text = text
			_status_frac = frac
			_status.text = text
			_gauges.queue_redraw()
	if _debug.visible and player != null and is_instance_valid(player):
		_debug.text = "%s  v=(%.0f, %.0f)\nmomentum=%s  airdash=%d\ncore=%.0f  wall=%d  FPS %d" % [
			player.state_name(), player.velocity.x, player.velocity.y,
			player.dash_momentum, player.air_dashes_left, player.core,
			player.wall_dir, Engine.get_frames_per_second()]


func _draw_gauges() -> void:
	var seg := 3.0 if max_hp <= 32 else 2.0
	var origin := Vector2(8, 19)
	var h := max_hp * seg + 3.0
	_housing(Rect2(origin, Vector2(10, h + 2)))
	var ramp: Array = R_LOW if hp <= 4 else R_FULL
	for i in max_hp:
		var y := origin.y + 2.0 + (max_hp - 1 - i) * seg
		_cell(Rect2(origin.x + 2, y, 6, seg - 1.0), ramp if i < hp else R_EMPTY)

	# Core gauge (flight / specials), with quarter ticks in the empty well.
	var core_box := Rect2(origin.x + 12, origin.y, 7, h + 2)
	_housing(core_box)
	var well := h - 2.0
	var fill := roundf(well * clampf(core / 100.0, 0.0, 1.0))
	var cr: Array = R_CORE
	if special_ready and int(Time.get_ticks_msec() / 120.0) % 2 == 0:
		cr = R_READY
	var fx := core_box.position.x + 2.0
	var bottom := core_box.end.y - 2.0
	for q in [0.25, 0.5, 0.75]:
		var ty := bottom - roundf(well * q)
		_gauges.draw_rect(Rect2(fx, ty, 3, 1), R_EMPTY[2])
	if fill > 0.0:
		_cell(Rect2(fx, bottom - fill, 3, fill), cr)

	# Character badge capping both gauges.
	_badge(Rect2(origin.x - 1, 1, 21, origin.y), false)
	_draw_head(Vector2(origin.x + 1, 3))

	# Weapon energy bar under the status line, in the weapon's colour.
	if _status_frac >= 0.0:
		var wb := Rect2(34, 15, 64, 7)
		_housing(wb)
		var wc := _weapon_color()
		var ww := roundf(60.0 * clampf(_status_frac, 0.0, 1.0))
		if ww > 0.0:
			_cell(Rect2(wb.position.x + 2, wb.position.y + 2, ww, 3), [wc.darkened(0.42), wc, wc.lightened(0.5)])
		for nx in range(5, 60, 4):
			_gauges.draw_rect(Rect2(wb.position.x + 2 + nx, wb.position.y + 2, 1, 3), C_WELL)

	# Benched partner: small HP bar.
	var y0 := origin.y + h + 6.0
	var mate = player.partner() if player != null and is_instance_valid(player) else null
	if mate != null:
		PixelArt.text(_gauges, Vector2(origin.x, y0), player.character_name(mate.id).substr(0, 2), C_TEXT)
		var frac := float(mate.hp) / float(maxi(mate.max_hp, 1))
		var bar := Rect2(origin.x + 9, y0 - 1, 20, 7)
		_housing(bar)
		var bw := roundf(16.0 * clampf(frac, 0.0, 1.0))
		if bw > 0.0:
			_cell(Rect2(bar.position.x + 2, bar.position.y + 2, bw, 3), R_FULL if mate.hp > 0 else R_LOW)
		for nx in [3, 7, 11]:
			_gauges.draw_rect(Rect2(bar.position.x + 2 + nx, bar.position.y + 2, 1, 3), C_WELL)
		y0 += 10.0
	if player == null or not is_instance_valid(player) or player.character == "ix":
		_draw_chips(origin, y0)

	# Boss gauge, capped by the boss emblem; name plate to its left.
	if boss_hp >= 0:
		var bh := boss_max * 2.0 + 3.0
		var bo := Vector2(366, 19)
		_housing(Rect2(bo, Vector2(10, bh + 2)))
		for i in boss_max:
			var y := bo.y + 2.0 + (boss_max - 1 - i) * 2.0
			_cell(Rect2(bo.x + 2, y, 6, 1), R_BOSS if i < boss_hp else R_EMPTY)
		_badge(Rect2(bo.x - 11, 1, 21, bo.y), true)
		_draw_boss_emblem(Vector2(bo.x - 9, 3))
		if boss_name != "":
			var font := ThemeDB.fallback_font
			var tw := ceilf(font.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
			var right := bo.x - 15.0
			var at := Vector2(right - tw, 12)
			_gauges.draw_string_outline(font, at, boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, C_BG)
			_gauges.draw_string(font, at, boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_TEXT)
			_gauges.draw_rect(Rect2(right - tw - 2, 15, tw + 6, 1), R_BOSS[0])
			_gauges.draw_rect(Rect2(right - tw + 2, 15, tw + 2, 1), R_BOSS[1])
			_gauges.draw_rect(Rect2(right - tw - 1, 16, tw + 6, 1), C_INK)


## Equipped armor part chips: H B A L (IX only).
func _draw_chips(origin: Vector2, y0: float) -> void:
	for i in ArmorData.SLOTS.size():
		var slot: String = ArmorData.SLOTS[i]
		var c: Color = ArmorData.ARMOR_COLOR[loadout.get(slot, "neutral")]
		_chip(Rect2(origin.x + (i % 2) * 10, y0 + (i / 2) * 10, 9, 9), c,
				ArmorData.SLOT_LABEL[slot].substr(0, 1))


## Bevelled armor-colour tile with a 3x5 pixel letter.
func _chip(r: Rect2, c: Color, letter: String) -> void:
	var x := r.position.x
	var y := r.position.y
	_outline(r)
	_gauges.draw_rect(r.grow(-1), c)
	_gauges.draw_rect(Rect2(x + 1, y + 1, 6, 1), c.lightened(0.5))
	_gauges.draw_rect(Rect2(x + 1, y + 2, 1, 5), c.lightened(0.25))
	_gauges.draw_rect(Rect2(x + 2, y + 7, 6, 1), c.darkened(0.38))
	_gauges.draw_rect(Rect2(x + 7, y + 1, 1, 6), c.darkened(0.22))
	var ink := C_BG if c.get_luminance() > 0.6 else Color("f4fbff")
	PixelArt.text(_gauges, Vector2(x + 3, y + 2), letter, ink)


## 1 px ink outline with the corner pixels cut.
func _outline(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	_gauges.draw_rect(Rect2(x + 1, y, r.size.x - 2, 1), C_INK)
	_gauges.draw_rect(Rect2(x + 1, r.end.y - 1, r.size.x - 2, 1), C_INK)
	_gauges.draw_rect(Rect2(x, y + 1, 1, r.size.y - 2), C_INK)
	_gauges.draw_rect(Rect2(r.end.x - 1, y + 1, 1, r.size.y - 2), C_INK)


## Gauge housing: ink outline, steel bevel lit from the upper left, dark well.
func _housing(r: Rect2) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	_outline(r)
	_gauges.draw_rect(Rect2(x + 1, y + 1, w - 2, 1), C_BEZEL_HI)
	_gauges.draw_rect(Rect2(x + 1, y + 2, 1, h - 3), C_FRAME)
	_gauges.draw_rect(Rect2(x + 2, y + h - 2, w - 3, 1), C_BEZEL_LO)
	_gauges.draw_rect(Rect2(x + w - 2, y + 2, 1, h - 4), C_BEZEL_LO)
	_gauges.draw_rect(Rect2(x + 2, y + 2, w - 4, h - 4), C_WELL)


## One gauge segment: lit top row and left column, shaded right column.
func _cell(r: Rect2, ramp: Array) -> void:
	_gauges.draw_rect(r, ramp[1])
	if r.size.y >= 2.0:
		_gauges.draw_rect(Rect2(r.position, Vector2(r.size.x - 1, 1)), ramp[2])
	_gauges.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), ramp[2])
	if r.size.x >= 3.0:
		_gauges.draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), ramp[0])


## Badge housing with a two-tone window for the character head / boss emblem.
func _badge(r: Rect2, boss: bool) -> void:
	_housing(r)
	var top := Color("2a1d4d") if boss else Color("1c375b")
	var low := Color("170f2e") if boss else Color("122746")
	var win := Rect2(r.position + Vector2(2, 2), Vector2(ICON))
	_gauges.draw_rect(win, top)
	_gauges.draw_rect(Rect2(win.position.x, win.position.y + 8, win.size.x, win.size.y - 8), low)
	_gauges.draw_rect(Rect2(win.position.x, win.end.y - 1, win.size.x, 1), R_BOSS[0] if boss else Color("00808a"))


func _draw_head(at: Vector2) -> void:
	var id := "ix"
	if player != null and is_instance_valid(player):
		id = player.character
	var tex := _texture("res://art/characters/%s/head.png" % id)
	if tex == null:
		return
	var row := 0
	if id == "ix":
		row = maxi(HEAD_ROWS.find(loadout.get("head", "neutral")), 0)
	var src := Rect2(Vector2(HEAD_CROP.get(id, Vector2i(24, 14))) + Vector2(0, row * SHEET_CELL_H), Vector2(ICON))
	_gauges.draw_texture_rect_region(tex, Rect2(at, Vector2(ICON)), src)


func _draw_boss_emblem(at: Vector2) -> void:
	var id := _boss_portrait_id()
	var tex: Texture2D = _texture("res://art/portraits/%s.png" % id) if id != "" else null
	if tex == null:
		_draw_crest(at + Vector2(8, 7))
		return
	var crop: Array = BOSS_CROP[id]
	var src := Rect2(Vector2(crop[0]), Vector2(ICON))
	if crop[1]:
		# Mirror in place: x -> 2 * at.x + ICON.x - x.
		_gauges.draw_set_transform(Vector2(at.x * 2.0 + ICON.x, 0), 0.0, Vector2(-1, 1))
	_gauges.draw_texture_rect_region(tex, Rect2(at, Vector2(ICON)), src)
	_gauges.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Fallback boss emblem: a faceted crest.
func _draw_crest(c: Vector2) -> void:
	for dy in range(-6, 7):
		var half := 5 - absi(dy) if absi(dy) <= 5 else -1
		if half < 0:
			continue
		var y := c.y + dy
		_gauges.draw_rect(Rect2(c.x - half - 1, y, half * 2 + 3, 1), C_INK)
		_gauges.draw_rect(Rect2(c.x - half, y, half + 1, 1), R_BOSS[2] if dy < 0 else R_BOSS[1])
		_gauges.draw_rect(Rect2(c.x + 1, y, half, 1), R_BOSS[1] if dy < 0 else R_BOSS[0])
	_gauges.draw_rect(Rect2(c.x - 1, c.y - 1, 3, 3), C_INK)
	_gauges.draw_rect(Rect2(c.x, c.y, 1, 1), C_LOW)


func _boss_portrait_id() -> String:
	if BOSS_ALIAS.has(boss_name):
		return BOSS_ALIAS[boss_name]
	var slug := boss_name.to_lower().replace(" ", "_")
	if BOSS_CROP.has(slug):
		return slug
	var first := boss_name.to_lower().get_slice(" ", 0)
	return first if BOSS_CROP.has(first) else ""


func _weapon_color() -> Color:
	if player != null and is_instance_valid(player):
		var w: String = player.current_weapon()
		if WeaponShot.INFO.has(w):
			return WeaponShot.INFO[w].color
	return C_CORE


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


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


## One-line control hint built from the current key bindings (OPTIONS → 키 설정).
static func help_text() -> String:
	var short := {"Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Escape": "Esc"}
	var k := func(action: String) -> String:
		var code := InputSetup.key_of(action)
		var name := OS.get_keycode_string(code) if code != 0 else "—"
		return short.get(name, name)
	return "이동 %s%s  점프 %s  공격 %s  대시 %s  특수 %s  무기 %s·%s  교대 %s  아머 %s  일시정지 %s" % [
			k.call("move_left"), k.call("move_right"), k.call("jump"), k.call("shoot"), k.call("dash"),
			k.call("special"), k.call("weapon_prev"), k.call("weapon_next"), k.call("tag"), k.call("armor_swap"),
			k.call("pause")]


## Challenge clock (OPTIONS → 기록 타이머); "" hides it.
func set_timer(text: String) -> void:
	if _timer != null:
		_timer.text = text
