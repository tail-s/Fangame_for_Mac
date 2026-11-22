extends CanvasLayer
## ARMOR LAB (GDD v0.2 §4-1, §7-2): change HEAD / BODY / ARM / LEG among
## unlocked parts, save / load three presets, see active set bonuses.
## Opened from stage select or at a checkpoint (safe zone).

signal closed

const ArmorData = preload("res://scripts/armor/armor_data.gd")
const PlayerVisual = preload("res://scripts/player/sprite_visual.gd")
const PreviewPuppet = preload("res://scripts/player/preview_puppet.gd")

const C_TEXT := Color("d7edf3")
const C_DIM := Color("6f8fae")
const C_ACCENT := Color("3de0ee")
const ROWS := ["frame", "head", "body", "arm", "leg", "preset0", "preset1", "preset2", "close"]

var selected := 0
var _labels: Array = []
var _info: Label
var _sets: Label
var _status: Label
var _cursor: ColorRect
var _preview: Node2D
var _puppet
var _guard := 2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.15, 0.94)
	bg.size = Vector2(384, 216)
	add_child(bg)
	var panel := ColorRect.new()
	panel.color = Color("1a3552")
	panel.position = Vector2(10, 28)
	panel.size = Vector2(108, 150)
	add_child(panel)
	_make_label("ARMOR LAB / NEUTRAL FRAME IX", 11, Vector2(10, 6), Vector2(364, 16), C_ACCENT)

	_puppet = PreviewPuppet.new()
	_preview = PlayerVisual.new()
	_preview.player = _puppet
	_preview.position = Vector2(64, 160)
	_preview.scale = Vector2(3, 3)
	add_child(_preview)

	_cursor = ColorRect.new()
	_cursor.color = Color(0.0, 0.72, 0.75, 0.2)
	_cursor.size = Vector2(250, 12)
	add_child(_cursor)
	for i in ROWS.size():
		_labels.append(_make_label("", 9, Vector2(128, 26 + i * 13), Vector2(250, 12), C_TEXT))
	_info = _make_label("", 8, Vector2(128, 140), Vector2(250, 24), C_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sets = _make_label("", 8, Vector2(10, 168), Vector2(364, 28), Color("f0b84a"))
	_sets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _make_label("", 8, Vector2(10, 202), Vector2(364, 12), C_DIM)
	_status.text = "↑↓ 선택   ←→ 파츠 변경   Z 프리셋 불러오기   X 프리셋 저장   Esc 닫기"
	_refresh()


func _process(delta: float) -> void:
	_puppet.anim_time += delta
	if _guard > 0:
		_guard -= 1
		return
	var row: String = ROWS[selected]
	if Input.is_action_just_pressed("move_down"):
		selected = (selected + 1) % ROWS.size()
	elif Input.is_action_just_pressed("move_up"):
		selected = (selected - 1 + ROWS.size()) % ROWS.size()
	elif Input.is_action_just_pressed("move_left"):
		_cycle(row, -1)
	elif Input.is_action_just_pressed("move_right"):
		_cycle(row, 1)
	elif Input.is_action_just_pressed("confirm"):
		if row == "close":
			closed.emit()
			return
		if row.begins_with("preset"):
			var i := int(row.substr(6))
			_flash("프리셋 %d 불러옴" % (i + 1) if Game.load_preset(i) else "프리셋 %d 이(가) 비어 있음" % (i + 1))
	elif Input.is_action_just_pressed("shoot") and row.begins_with("preset"):
		var i := int(row.substr(6))
		Game.save_preset(i)
		_flash("프리셋 %d 에 저장" % (i + 1))
	elif Input.is_action_just_pressed("cancel"):
		closed.emit()
		return
	_refresh()


func _cycle(slot: String, step: int) -> void:
	if slot == "frame":
		if not Game.data.get("ultimate", false):
			_flash("얼티밋 아머 IX 미획득 — 히든 보스를 찾아보세요")
		else:
			Game.set_frame("parts" if Game.is_ultimate() else "ultimate")
		return
	if not ArmorData.SLOTS.has(slot):
		return
	if Game.is_ultimate():
		_flash("얼티밋 아머 IX는 파츠를 바꿀 수 없음 — FRAME 을 PARTS 로")
		return
	var options: Array = Game.options_for(slot)
	if options.size() <= 1:
		_flash("이 슬롯에 해금된 파츠가 없음 — 스테이지에서 캡슐을 찾으세요")
		return
	var i := options.find(Game.loadout()[slot])
	Game.set_slot(slot, options[(i + step + options.size()) % options.size()])


func _refresh() -> void:
	var lo: Dictionary = Game.loadout()
	var ult: bool = Game.is_ultimate()
	_preview.part_armor = (ArmorData.ULTIMATE_LOADOUT if ult else lo).duplicate()
	for i in ROWS.size():
		var row: String = ROWS[i]
		var l: Label = _labels[i]
		var on := i == selected
		var text := ""
		var color := C_ACCENT if on else C_TEXT
		if row == "frame":
			var owned: bool = Game.data.get("ultimate", false)
			text = "FRAME  %s %s %s" % ["◀" if owned else " ", "ULTIMATE IX" if ult else "PARTS", "▶" if owned else ""]
			if not on and ult:
				color = ArmorData.ARMOR_COLOR["ultimate"]
		elif ArmorData.SLOTS.has(row) and ult:
			text = "%-5s  —" % ArmorData.SLOT_LABEL[row]
			color = C_ACCENT if on else C_DIM
		elif ArmorData.SLOTS.has(row):
			var armor: String = lo[row]
			var count: int = Game.options_for(row).size()
			text = "%-5s  %s %s %s" % [ArmorData.SLOT_LABEL[row], "◀" if count > 1 else " ",
					ArmorData.ARMOR_NAME[armor], "▶" if count > 1 else ""]
			if not on:
				color = ArmorData.ARMOR_COLOR[armor]
		elif row.begins_with("preset"):
			var p = Game.preset(int(row.substr(6)))
			text = "PRESET %d   %s" % [int(row.substr(6)) + 1, _preset_text(p)]
		else:
			text = "닫기"
		l.text = text
		l.add_theme_color_override("font_color", color)
	_cursor.position = Vector2(124, 25 + selected * 13)

	var sel: String = ROWS[selected]
	if sel == "frame":
		_info.text = ArmorData.ULTIMATE_DESC if Game.data.get("ultimate", false) else "FRAME: 파츠 조합 / 완성형 프레임 전환 (얼티밋 아머 IX 획득 후)"
	elif ArmorData.SLOTS.has(sel) and ult:
		_info.text = "얼티밋 아머 IX 장착 중"
	elif ArmorData.SLOTS.has(sel):
		var id := ArmorData.part_id(lo[sel], sel)
		_info.text = "%s — %s" % [ArmorData.part_name(id), ArmorData.PART_DESC[id]]
	elif sel.begins_with("preset"):
		_info.text = "Z: 이 프리셋을 장착   X: 현재 장착 상태를 이 프리셋에 저장"
	else:
		_info.text = "파츠 해금 %d / 8" % Game.unlocked_count()
	var sets: Array = [] if ult else ArmorData.sets_for(lo)
	if ult:
		_sets.text = ArmorData.ULTIMATE_DESC
	elif sets.is_empty():
		_sets.text = "세트 효과 없음 — 같은 계열 2파츠 / 4파츠, 또는 뱅가드 2 + 에어로 2"
	else:
		_sets.text = "  ".join(sets.map(func(s): return ArmorData.SET_DESC[s]))


func _preset_text(p) -> String:
	if not ArmorData.is_valid_loadout(p):
		return "(비어 있음)"
	var parts := []
	for slot in ArmorData.SLOTS:
		parts.append(ArmorData.ARMOR_NAME[p[slot]].substr(0, 1))
	return " ".join(parts)


func _flash(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", C_ACCENT)


func _make_label(text: String, size: int, pos: Vector2, box: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color("0a1326"))
	l.add_theme_constant_override("outline_size", 2)
	add_child(l)
	return l
