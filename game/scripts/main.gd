extends Node2D
## Game flow: title -> stage select -> stage (with checkpoints, armor lab at
## checkpoints, pause, boss fight, clear) -> stage select.
## Debug: `godot --path game -- --autoshot=<dir>` runs a screenshot tour.

const ArmorData = preload("res://scripts/armor/armor_data.gd")
const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const ArmorLab = preload("res://scripts/ui/armor_lab.gd")
const Backdrop = preload("res://scripts/level/backdrop.gd")
const Autoshot = preload("res://scripts/debug/autoshot.gd")
const StoryScreen = preload("res://scripts/ui/story_screen.gd")
const Story = preload("res://scripts/story/story_text.gd")
const StageSelectPanel = preload("res://scripts/ui/stage_select_panel.gd")
const BossCutin = preload("res://scripts/ui/boss_cutin.gd")
const TitleHeroes = preload("res://scripts/ui/title_heroes.gd")
const DepthProps = preload("res://scripts/level/backdrops/depth_props.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const GalleryPanel = preload("res://scripts/ui/gallery_panel.gd")
const FlowCheck = preload("res://scripts/debug/flow_check.gd")

const LEVEL_DIR := "res://levels"
## Sortie choices (GDD §6 tag battle). Characters are original designs.
const PARTIES := [["ix", "sable"], ["ix", "echo"], ["sable", "echo"], ["ix"]]
const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")
const RESPAWN_DELAY := 1.6
const CLEAR_DELAY := 3.5

var level: Node2D
var player: CharacterBody2D
var boss: Node2D
var hud: CanvasLayer
var stage: Dictionary = {}
## Stage registry built from the `; @key` headers of levels/*.txt (see levels/README.md).
var stages: Array = []

var _cam: Camera2D
var _menu: CanvasLayer
var _lab: CanvasLayer
var _story: CanvasLayer
var _in_boss := false
var _boss_kind := ""
var _generation := 0  # bumps on every (re)load so stale timers do nothing
var _shake_time := 0.0
var _shake_total := 0.0
var _shake_strength := 0.0
var _last_hp := -1
## Boss track that follows the boss_intro sting.
var _after_intro := ""
## Armor preset swap in battle (GDD §4-1 "전투 중 제한된 교체"): cooldown left.
var _swap_cd := 0.0
var _swap_index := -1
var _hitstop_until := 0
var _look_x := 0.0
## Tests only: run hit-stop even in headless / silent runs.
var force_hitstop := false
## Challenge records (optional): stage clock and whether any damage was taken.
var _stage_time := 0.0
var _timing := false
var _took_damage := false


func _ready() -> void:
	stages = load_stage_registry()
	add_to_group("shaker")
	_build_backdrop()
	Game.loadout_changed.connect(_on_loadout_changed)
	Game.settings_changed.connect(_on_settings_changed)
	Audio.music_finished.connect(_on_music_finished)
	for arg in OS.get_cmdline_user_args():
		if (arg.begins_with("--autoshot=") or arg.begins_with("--gallery=") or arg.begins_with("--portraits=")
				or arg.begins_with("--moves=")):
			Game.save_enabled = false
			Game.new_game()
			Game.silent = true  # automated runs open a window: keep them silent
			Game.apply_settings()
			var shot := Autoshot.new()
			shot.gallery = arg.begins_with("--gallery=")
			shot.portraits = arg.begins_with("--portraits=")
			shot.moves = arg.begins_with("--moves=")
			shot.out_dir = arg.split("=", true, 1)[1]
			shot.main = self
			add_child(shot)
			return
		if arg == "--flowcheck" or arg == "--perfcheck":
			Game.save_enabled = false
			Game.new_game()
			Game.load_settings()
			var check := FlowCheck.new()
			check.main = self
			check.perf = arg == "--perfcheck"
			add_child(check)
			return
	Game.load_settings()
	show_title()


func _process(delta: float) -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _hitstop_until:
		Engine.time_scale = 1.0
	if _cam == null or not is_instance_valid(_cam):
		return
	_look_ahead(delta)
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var k := _shake_strength * _shake_time / _shake_total
		_cam.offset = Vector2(randf_range(-k, k), randf_range(-k, k)).round()
	elif _cam.offset != Vector2.ZERO:
		_cam.offset = Vector2.ZERO


## Hit-stop: game time nearly freezes for `seconds` of real time (heavy hits, boss
## down, taking damage). Called through the "shaker" group; off in automated runs so
## their timing stays deterministic.
func hitstop(seconds: float) -> void:
	if not force_hitstop and (Game.silent or DisplayServer.get_name() == "headless"):
		return
	if get_tree().paused:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _hitstop_until and Engine.time_scale < 1.0:
		return
	_hitstop_until = until
	Engine.time_scale = 0.05


## Camera leads a little in the facing direction (more while dashing), eased.
func _look_ahead(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var want := 0.0
	if not _in_boss:
		want = player.facing * (28.0 if player.is_dashing() else (18.0 if absf(player.velocity.x) > 1.0 else 10.0))
	_look_x = lerpf(_look_x, want, 1.0 - exp(-3.5 * delta))
	_cam.position.x = roundf(_look_x)


## Screen shake (off when the "shake" option is off). Called through the "shaker" group.
func shake(strength: float, seconds: float) -> void:
	if not Game.settings.shake or strength * seconds < _shake_strength * _shake_time:
		return
	_shake_strength = strength
	_shake_time = seconds
	_shake_total = seconds


func _physics_process(delta: float) -> void:
	if level == null or _menu != null or _lab != null:
		return
	_swap_cd = maxf(_swap_cd - delta, 0.0)
	if _timing:
		_stage_time += delta
		if Game.settings.get("timer", false):
			hud.set_timer(Game.clock(_stage_time))
	if Input.is_action_just_pressed("armor_swap"):
		_try_armor_swap()
	if Input.is_action_just_pressed("pause"):
		_open_pause()
		return
	if Input.is_action_just_pressed("debug"):
		hud.toggle_debug()
	if Input.is_action_just_pressed("debug_unlock"):
		Game.unlock_all()
		player.weapons = Game.weapons_available()
		hud.toast("디버그: 모든 아머 파츠·특수무기 해금")
	if Input.is_action_just_pressed("restart"):
		Game.clear_checkpoint()
		load_level()
		return
	if at_checkpoint():
		hud.set_hint("↑  ARMOR LAB")
		if Input.is_action_just_pressed("move_up") and not Input.is_action_pressed("shoot"):
			open_lab()
	else:
		hud.set_hint("")


# --- screens ----------------------------------------------------------------------

func show_title() -> void:
	_leave_stage()
	var items := []
	if Game.has_save():
		items.append({"id": "continue", "text": "이어하기"})
	items.append({"id": "new", "text": "새 게임", "note": "저장 데이터를 새로 시작합니다" if Game.has_save() else ""})
	if Game.has_save():
		items.append({"id": "gallery", "text": "갤러리", "note": "아머 · 보스 · 기록"})
	items.append({"id": "options", "text": "옵션", "note": "음량 · 난이도 · 키 · 조작"})
	items.append({"id": "quit", "text": "종료"})
	get_tree().call_group("backdrop", "set_theme", "title")
	_show_menu("REBIRTH PROTOCOL", "ORIGINAL FAN-INSPIRED BUILD  —  PROTOTYPE 0.13", items,
			"↑↓ 선택   Z / Enter 결정", _on_title_choice, Callable())
	_menu.add_child(TitleHeroes.new())
	Audio.music("title")


# --- options (GDD §8-2 phase 6: accessibility) --------------------------------------

const OPTION_IDS := ["music", "sfx", "difficulty", "shake", "flashes", "fullscreen", "timer"]


func show_options(back: Callable) -> void:
	var items := []
	for id in OPTION_IDS:
		var row := _option_row(id)
		items.append({"id": id, "text": row[0], "note": row[1], "adjust": true})
	items.append({"id": "keys", "text": "키 설정", "note": "키보드 키 바꾸기 (게임패드는 그대로)"})
	items.append({"id": "controls", "text": "조작 안내", "note": "키보드 · 게임패드 버튼 목록"})
	items.append({"id": "back", "text": "돌아가기"})
	_show_menu("OPTIONS", "← → 값 변경 · 자동 저장", items, "Z 결정   Esc 돌아가기",
			_on_option_choice.bind(back), back, level != null)
	_menu.adjusted.connect(_on_option_adjust)


func _option_row(id: String) -> Array:
	var s: Dictionary = Game.settings
	match id:
		"music":
			return ["음악 음량   ◀ %s ▶" % _bar(s.music), "0 이면 음악을 끕니다"]
		"sfx":
			return ["효과음 음량   ◀ %s ▶" % _bar(s.sfx), "0 이면 효과음을 끕니다"]
		"difficulty":
			return ["난이도   ◀ %s ▶" % Game.DIFFICULTY_NAME[s.difficulty],
					"받는 피해 ×%s — 언제든 바꿀 수 있습니다" % str(Game.DIFFICULTY_DAMAGE[s.difficulty])]
		"shake":
			return ["화면 흔들림   ◀ %s ▶" % ("켜기" if s.shake else "끄기"), "폭발·피격 때 화면이 흔들립니다"]
		"flashes":
			return ["밝은 깜박임   ◀ %s ▶" % ("켜기" if s.flashes else "줄이기"),
					"피격 섬광·번개 등 밝은 깜박임을 줄입니다"]
		"fullscreen":
			return ["전체 화면   ◀ %s ▶" % ("켜기" if s.fullscreen else "끄기"), "창 모드 / 전체 화면"]
		"timer":
			return ["기록 타이머   ◀ %s ▶" % ("켜기" if s.get("timer", false) else "끄기"),
					"스테이지 클리어 시간을 화면에 표시합니다 (도전용, 기록은 언제나 저장)"]
	return [id, ""]


func _bar(v: int) -> String:
	return "■".repeat(v) + "□".repeat(10 - v)


func _on_option_adjust(id: String, dir: int) -> void:
	var s: Dictionary = Game.settings
	match id:
		"music", "sfx":
			Game.set_setting(id, clampi(s[id] + dir, 0, 10))
			if id == "sfx":
				Audio.sfx("pickup")
		"difficulty":
			var i := Game.DIFFICULTIES.find(s.difficulty)
			Game.set_setting(id, Game.DIFFICULTIES[clampi(i + dir, 0, Game.DIFFICULTIES.size() - 1)])
		"shake", "flashes", "fullscreen", "timer":
			Game.set_setting(id, not s.get(id, false))
			if id == "timer" and hud != null:
				hud.set_timer("")
	var row := _option_row(id)
	if _menu != null:
		_menu.update_item(id, row[0], row[1])


func _on_option_choice(id: String, back: Callable) -> void:
	if OPTION_IDS.has(id):
		_on_option_adjust(id, 1)
	elif id == "controls":
		_show_controls(back)
	elif id == "keys":
		show_keys(back)
	else:
		back.call()


func _show_controls(back: Callable) -> void:
	var k := func(action: String) -> String: return InputSetup.key_label(action)
	var rows := [
		["이동", "%s · %s  /  스틱 · 십자키" % [k.call("move_left"), k.call("move_right")]],
		["점프", "%s  /  A" % k.call("jump")], ["공격 (길게: 차지)", "%s  /  X" % k.call("shoot")],
		["대시", "%s  /  B" % k.call("dash")], ["필살기", "%s  /  Y" % k.call("special")],
		["특수무기 전환", "%s · %s  /  LB · RB" % [k.call("weapon_prev"), k.call("weapon_next")]],
		["캐릭터 교대 · 태그", "%s  /  LT" % k.call("tag")],
		["아머 프리셋 교체 (IX, 전투 중)", "%s  /  RT — 코어 %d, 대기 %d초" % [k.call("armor_swap"), int(SWAP_COST), int(SWAP_COOLDOWN)]],
		["아머 랩 (체크포인트)", "↑"], ["일시정지", "%s  /  Start" % k.call("pause")],
		["체크포인트부터 다시", "R  /  Back"],
	]
	var items := []
	for r in rows:
		items.append({"id": "back", "text": r[0], "note": r[1]})
	_show_menu("CONTROLS", "↑↓ 로 항목을 고르면 아래에 키가 표시됩니다", items, "Z / Esc 돌아가기",
			func(_id: String) -> void: show_options(back), show_options.bind(back), level != null)


# --- gallery (GDD §7-2) -----------------------------------------------------------------

const GALLERY_TABS := ["armor", "bosses", "records"]
const GALLERY_TAB_NAME := {"armor": "ARMOR", "bosses": "BOSSES", "records": "RECORDS"}


func show_gallery(tab := "armor", selected := 0) -> void:
	var rows := _gallery_rows(tab)
	var items := []
	var entries := []
	for r in rows:
		items.append({"id": r.id, "text": r.text, "note": r.note, "adjust": true})
		entries.append(r.entry)
	var tabs := []
	for t in GALLERY_TABS:
		tabs.append(("◀ %s ▶" % GALLERY_TAB_NAME[t]) if t == tab else GALLERY_TAB_NAME[t])
	_show_menu("GALLERY", "  ".join(tabs), items, "↑↓ 선택   ← → 탭   Esc 타이틀",
			func(_id: String) -> void: pass, show_title, false, clampi(selected, 0, items.size() - 1), "split")
	_menu.adjusted.connect(func(_id: String, dir: int) -> void:
		var i := posmod(GALLERY_TABS.find(tab) + dir, GALLERY_TABS.size())
		show_gallery(GALLERY_TABS[i]))
	var panel := GalleryPanel.new()
	panel.entries = entries
	panel.index = _menu.selected
	_menu.add_child(panel)
	_menu.highlighted.connect(panel.show_index)


## "최고 1:23.45 ★" for a stage with a recorded clear ("" otherwise).
func _record_text(stage_id: String) -> String:
	var r := Game.record(stage_id)
	if not r.has("best"):
		return ""
	return "최고 %s%s" % [Game.clock(r.best), "  ★" if r.get("nodmg", false) else ""]


## [{id, text, note, entry}] for one gallery tab.
func _gallery_rows(tab: String) -> Array:
	var rows := []
	match tab:
		"armor":
			for armor in ["vanguard", "aero"]:
				for slot in ArmorData.SLOTS:
					var id := ArmorData.part_id(armor, slot)
					var have := Game.is_unlocked(id)
					var where := _capsule_stage(id)
					rows.append({"id": id, "text": ArmorData.part_name(id) if have else "???  (%s)" % ArmorData.SLOT_LABEL[slot],
							"note": ArmorData.PART_DESC[id] if have else "미획득 — %s 어딘가의 캡슐" % where,
							"entry": {"kind": "armor", "name": ArmorData.part_name(id) if have else "???", "part": id,
									"unlocked": have, "status": ("획득 · " + where) if have else "미획득"}})
			var ult: bool = Game.data.get("ultimate", false)
			rows.append({"id": "ultimate", "text": "ULTIMATE ARMOR IX" if ult else "???  (완성형 프레임)",
					"note": ArmorData.ULTIMATE_DESC if ult else "어느 히든 보스가 갖고 있다는 기록이 있다",
					"entry": {"kind": "armor", "name": "ULTIMATE ARMOR IX" if ult else "???", "part": "ultimate",
							"unlocked": ult, "status": "획득" if ult else "미획득"}})
		"bosses":
			for s in stages:
				if s.has("boss"):
					var won := Game.is_cleared(s.id)
					rows.append({"id": s.id, "text": s.get("name", s.id) if won else "???",
							"note": s.get("desc", "") if won else "아직 쓰러뜨리지 않은 상대",
							"entry": {"kind": "boss", "name": s.get("name", s.id) if won else "???", "portrait": s.id,
									"unlocked": won, "status": "격파" if won else "기록 없음"}})
				if s.has("hidden_boss"):
					var hid: String = s.get("hidden_id", "")
					var won := Game.is_cleared("hidden_" + hid)
					var hname: String = {"eclipse": "ECLIPSE", "fragment": "FRAGMENT Λ"}.get(hid, hid.to_upper())
					rows.append({"id": "hidden_" + hid, "text": hname if won else "◈ ???",
							"note": ("히든 보스 · %s 구역" % s.get("name", "")) if won else "미확인 신호",
							"entry": {"kind": "boss", "name": hname if won else "◈ ???", "portrait": hid,
									"unlocked": won, "status": "격파 (히든)" if won else "미확인 신호"}})
		"records":
			var cleared := stages.filter(func(st): return Game.is_cleared(st.id)).size()
			var hidden := ["eclipse", "fragment"].filter(func(h): return Game.is_cleared("hidden_" + h)).size()
			var weapons: int = Game.data.get("weapons", []).size()
			var endings := []
			for k in [["normal", "일반"], ["extended", "확장"], ["true", "진"]]:
				endings.append(("%s ✓" % k[1]) if Game.has_flag("ending_" + k[0]) else ("%s —" % k[1]))
			var seen := ["normal", "extended", "true"].filter(func(k): return Game.has_flag("ending_" + k)).size()
			var recs := [
				["stages", "스테이지 클리어  %d / %d" % [cleared, stages.size()], float(cleared) / maxf(stages.size(), 1)],
				["bosses", "보스 격파  %d / 6" % bosses_cleared(), bosses_cleared() / 6.0],
				["hidden", "히든 보스  %d / 2" % hidden, hidden / 2.0],
				["parts", "아머 파츠  %d / 8" % Game.unlocked_count(), Game.unlocked_count() / 8.0],
				["weapons", "특수무기  %d / 6" % weapons, weapons / 6.0],
				["hp", "HP 상한  %d" % Game.max_hp(), clampf((Game.max_hp() - 16) / 16.0, 0.0, 1.0)],
				["endings", "엔딩  %s" % "  ".join(endings), seen / 3.0],
				["nodmg", "무피격 클리어 ★  %d / %d" % [_nodmg_count(), stages.size()],
						float(_nodmg_count()) / maxf(stages.size(), 1)],
			]
			for st in stages:
				var rt := _record_text(st.id)
				if rt != "":
					recs.append(["time_" + st.id, "%s  %s" % [st.get("name", st.id), rt], 1.0])
			for r in recs:
				rows.append({"id": r[0], "text": r[1], "note": "",
						"entry": {"kind": "record", "name": "RECORDS", "status": r[1], "value": r[2], "unlocked": true}})
	return rows


func _nodmg_count() -> int:
	return stages.filter(func(st): return Game.record(st.id).get("nodmg", false)).size()


## Name of the stage whose map holds the capsule for `part` (a real stage before
## the training room, which keeps practice capsules).
func _capsule_stage(part: String) -> String:
	var ordered := stages.filter(func(st): return st.id != "training")
	ordered.append_array(stages.filter(func(st): return st.id == "training"))
	for code in ArmorData.CAPSULE_CODES:
		if ArmorData.CAPSULE_CODES[code] != part:
			continue
		for s in ordered:
			var text := FileAccess.get_file_as_string(s.path)
			for line in text.split("\n"):
				if not line.begins_with(";") and line.contains(code):
					return s.get("name", s.id)
	return "어느 스테이지"


# --- key settings (OPTIONS → 키 설정) ------------------------------------------------

const KEY_ROWS := [["move_left", "왼쪽"], ["move_right", "오른쪽"], ["move_up", "위 · 조준"],
		["move_down", "아래"], ["jump", "점프"], ["shoot", "공격"], ["dash", "대시"], ["special", "필살기 · 특수"],
		["weapon_prev", "무기 ←"], ["weapon_next", "무기 →"], ["tag", "캐릭터 교대"],
		["armor_swap", "아머 프리셋 교체"], ["pause", "일시정지"]]


func show_keys(back: Callable, selected := 0) -> void:
	var items := []
	for row in KEY_ROWS:
		items.append({"id": row[0], "text": "%s   %s" % [row[1], InputSetup.key_label(row[0])],
				"note": "Z 를 누른 뒤 새 키를 누르세요 (Esc 취소). 다른 동작이 쓰던 키면 서로 바뀝니다"})
	items.append({"id": "reset", "text": "기본값으로", "note": "모든 키를 처음 설정으로 되돌립니다"})
	items.append({"id": "back", "text": "돌아가기"})
	_show_menu("KEYS", "키보드 키 바꾸기 · 게임패드는 그대로", items, "Z 바꾸기   Esc 돌아가기",
			_on_key_choice.bind(back), show_options.bind(back), level != null, selected)


func _on_key_choice(id: String, back: Callable) -> void:
	match id:
		"back":
			show_options(back)
		"reset":
			Game.set_setting("keys", {})
			show_keys(back, _menu.selected)
		_:
			_capture_key(id, back)


## Waits for the next key press and binds it to `action`.
func _capture_key(action: String, back: Callable) -> void:
	var idx: int = _menu.selected
	_menu.set_process(false)
	var label: String = KEY_ROWS.filter(func(r): return r[0] == action)[0][1]
	_menu.update_item(action, "%s   ▶ ?" % label, "새 키를 누르세요 — Esc 취소")
	var cap := KeyCapture.new()
	add_child(cap)
	var code: int = await cap.captured
	cap.queue_free()
	if code != KEY_ESCAPE and code != 0:
		assign_key(action, code)
	show_keys(back, idx)


## Binds `code` (physical keycode) to `action`; an action already using it gets
## this action's old key (a swap).
func assign_key(action: String, code: int) -> void:
	var keys: Dictionary = Game.settings.get("keys", {}).duplicate()
	var old := InputSetup.key_of(action)
	for other in InputSetup.REMAPPABLE:
		if other == action:
			continue
		for ev in InputMap.action_get_events(other):
			if ev is InputEventKey and ev.physical_keycode == code:
				keys[other] = old
	keys[action] = code
	Game.set_setting("keys", keys)


class KeyCapture extends Node:
	signal captured(code: int)

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			captured.emit(event.physical_keycode if event.physical_keycode != 0 else event.keycode)


# --- armor preset swap in battle (GDD §4-1) ------------------------------------------

const SWAP_COST := 25.0
const SWAP_COOLDOWN := 8.0


## Switches IX to the next saved preset that differs from the current parts.
## Limited: costs core gauge and has a cooldown; not in the Ultimate frame.
func _try_armor_swap() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.character != "ix":
		hud.toast("아머 교체는 IX만 할 수 있어요", 1.6)
		return false
	if Game.is_ultimate():
		hud.toast("얼티밋 프레임 중에는 파츠를 바꿀 수 없어요 (아머 랩에서 전환)", 2.0)
		return false
	if _swap_cd > 0.0:
		hud.toast("아머 교체 대기 %d초" % ceili(_swap_cd), 1.2)
		return false
	if player.core < SWAP_COST:
		hud.toast("코어 부족 — 아머 교체에 %d 필요" % int(SWAP_COST), 1.6)
		return false
	var cur: Dictionary = Game.loadout()
	for k in range(1, Game.PRESET_COUNT + 1):
		var i := posmod(_swap_index + k, Game.PRESET_COUNT)
		var p = Game.preset(i)
		if p == null or p == cur:
			continue
		if Game.load_preset(i):
			_swap_index = i
			player.core -= SWAP_COST
			_swap_cd = SWAP_COOLDOWN
			Audio.sfx("weapon_switch")
			var names := []
			for slot in ArmorData.SLOTS:
				names.append("%s %s" % [ArmorData.SLOT_LABEL[slot].substr(0, 1), ArmorData.ARMOR_NAME[p[slot]]])
			hud.toast("프리셋 %d 장착 — %s" % [i + 1, " · ".join(names)], 2.2)
			return true
	hud.toast("바꿀 프리셋이 없어요 — 체크포인트 아머 랩에서 저장하세요", 2.2)
	return false


static func load_stage_registry() -> Array:
	return Level.load_registry(LEVEL_DIR)


## Stage bosses beaten (stages with a `boss` that are not the final stage).
func bosses_cleared() -> int:
	var n := 0
	for s in stages:
		if s.has("boss") and s.get("final", "") != "true" and Game.is_cleared(s.id):
			n += 1
	return n


## `bosses:N`, `cleared:<stage id>` and/or `+eclipse` / `+fragment`, joined by `+`.
func requirement_met(req: String) -> bool:
	for part in req.split("+", false):
		part = part.strip_edges()
		if part.begins_with("bosses:"):
			if bosses_cleared() < int(part.substr(7)):
				return false
		elif part.begins_with("cleared:"):
			if not Game.is_cleared(part.substr(8)):
				return false
		elif part != "" and not Game.is_cleared("hidden_" + part):
			return false
	return true


## Shows story pages, then calls `then`.
func play_story(pages: Array, then: Callable, track := "story") -> void:
	_leave_stage()
	Audio.music(track)
	_story = StoryScreen.new()
	_story.pages = pages
	_story.finished.connect(func() -> void:
		_story.queue_free()
		_story = null
		then.call())
	add_child(_story)


func show_select() -> void:
	_leave_stage()
	if bosses_cleared() >= 3 and not Game.has_flag("mid_event"):
		Game.set_flag("mid_event")
		play_story(Story.MID_EVENT, show_select)
		return
	Audio.music("select")
	var items := []
	for s in stages:
		var locked: bool = s.has("require") and not requirement_met(s.require)
		items.append({"id": "locked" if locked else s.id, "text": _select_title(s, locked),
				"note": _select_note(s, locked)})
	items.append({"id": "lab", "text": "ARMOR LAB", "note": "파츠 %d / 8 · 장착 · 프리셋" % Game.unlocked_count()})
	items.append({"id": "title", "text": "타이틀로"})
	_show_menu("STAGE SELECT", "HP %d · 파츠 %d / 8 · 보스 %d / 6 · 난이도 %s" % [Game.max_hp(),
			Game.unlocked_count(), bosses_cleared(), Game.DIFFICULTY_NAME[Game.settings.difficulty]],
			items, "Z 결정   Esc 타이틀", _on_select_choice, show_title, false, 0, "split")
	# Portrait + EDEN LINK map on the left / under the list (GDD §7-2).
	var panel := StageSelectPanel.new()
	for s in stages:
		var locked: bool = s.has("require") and not requirement_met(s.require)
		var sig := _hidden_signal(s)
		panel.entries.append({"kind": "stage", "id": s.id, "name": s.get("name", s.id), "locked": locked,
				"cleared": Game.is_cleared(s.id), "changed": not locked and not Level.changes_met(s, requirement_met).is_empty(),
				"signal": "" if sig == "" else ("detected" if sig.contains("감지") else "weak"),
				"portrait": s.id if s.has("boss") else "", "record": _record_text(s.id)})
	panel.entries.append({"kind": "lab", "id": "lab", "name": "ARMOR LAB", "locked": false, "cleared": false,
			"changed": false, "signal": "", "portrait": ""})
	panel.entries.append({"kind": "title", "id": "title", "name": "타이틀로", "locked": false, "cleared": false,
			"changed": false, "signal": "", "portrait": ""})
	_menu.add_child(panel)
	_menu.highlighted.connect(panel.show_index)
	panel.show_index(_menu.selected)


## Stage-select row: name plus status marks (✓ cleared, ◈ unknown signal, ▲ changed).
func _select_title(s: Dictionary, locked: bool) -> String:
	var text: String = s.get("name", s.id)
	if locked:
		return text + "  (LOCKED)"
	if Game.is_cleared(s.id):
		text += "  ✓"
	if _hidden_signal(s) != "":
		text += "  ◈"
	if not Level.changes_met(s, requirement_met).is_empty():
		text += "  ▲"
	return text


func _select_note(s: Dictionary, locked: bool) -> String:
	if locked:
		return "LOCKED — " + _requirement_text(s.require)
	var bits: Array = [s.get("desc", "")]
	for change in Level.changes_met(s, requirement_met):
		bits.append("▲ 환경 변화: " + change)
	var signal_text := _hidden_signal(s)
	if signal_text != "":
		bits.append(signal_text)
	return "   ".join(bits)


## GDD §5-4: stages with a hidden route show an "unknown signal" until it is cleared.
func _hidden_signal(s: Dictionary) -> String:
	if not s.has("hidden_boss") or Game.is_cleared("hidden_" + s.get("hidden_id", "")):
		return ""
	if requirement_met(s.get("hidden_require", "")):
		return "◈ 미확인 신호 감지"
	return "◈ 미확인 신호 (약함)"


func _requirement_text(req: String) -> String:
	var bits := []
	for part in req.split("+", false):
		part = part.strip_edges()
		if part.begins_with("bosses:"):
			bits.append("보스 %d명 격파 필요" % int(part.substr(7)))
		elif part.begins_with("cleared:"):
			bits.append("%s 격파 필요" % _stage_name(part.substr(8)))
		elif part != "":
			bits.append("히든 보스 필요")
	return " · ".join(bits)


func _stage_name(id: String) -> String:
	for s in stages:
		if s.id == id:
			return s.get("name", id)
	return id


func open_lab() -> void:
	if _lab != null:
		return
	_lab = ArmorLab.new()
	_lab.closed.connect(_close_lab)
	add_child(_lab)
	if level != null:
		get_tree().paused = true


func _close_lab() -> void:
	if _lab != null:
		_lab.queue_free()
		_lab = null
	if level != null:
		get_tree().paused = false
	else:
		show_select()


func _open_pause() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = true
	_show_menu("PAUSE", stage.get("name", ""), [
		{"id": "resume", "text": "계속하기"},
		{"id": "retry", "text": "체크포인트부터 다시"},
		{"id": "options", "text": "옵션"},
		{"id": "exit", "text": "스테이지 나가기"},
	], "Esc 계속", _on_pause_choice, _resume, true)


func _resume() -> void:
	_close_menu()
	get_tree().paused = false


func _on_title_choice(id: String) -> void:
	match id:
		"continue":
			Game.load_game()
			show_select()
		"new":
			Game.new_game()
			Game.save_game()
			play_story(Story.PROLOGUE, show_select)
		"gallery":
			Game.load_game()
			show_gallery()
		"options":
			show_options(show_title)
		"quit":
			get_tree().quit()


func _on_select_choice(id: String) -> void:
	match id:
		"lab":
			_close_menu()
			open_lab()
		"title":
			show_title()
		"locked":
			pass
		_:
			_show_party_select(id)


func _show_party_select(stage_id: String) -> void:
	var items := []
	var current := 0
	for i in PARTIES.size():
		var ids: Array = PARTIES[i]
		var names := " + ".join(ids.map(func(c): return Player.CHARACTERS[c].name))
		items.append({"id": str(i), "text": names, "note": _party_note(ids)})
		if ids == Game.party():
			current = i
	_show_menu("SORTIE", "출격 멤버 선택 — 스테이지 중 Tab 으로 교대", items,
			"Z 출격   Esc 뒤로", _on_party_choice.bind(stage_id), show_select, false, current)


func _on_party_choice(choice: String, stage_id: String) -> void:
	Game.set_party(PARTIES[int(choice)])
	start_stage(stage_id)


func _party_note(ids: Array) -> String:
	var roles := {"ix": "버스터·아머·특수무기", "sable": "세이버·패링", "echo": "연사·호버·복제"}
	return "  /  ".join(ids.map(func(c): return roles[c]))


func _on_pause_choice(id: String) -> void:
	match id:
		"resume":
			_resume()
		"retry":
			_resume()
			load_level()
		"options":
			show_options(_open_pause)
		"exit":
			show_select()


func _show_menu(title: String, subtitle: String, items: Array, footer: String,
		on_choice: Callable, on_cancel: Callable, dim := false, selected := 0, layout := "") -> void:
	_close_menu()
	_menu = MenuScreen.new()
	_menu.layout = layout
	_menu.selected = selected
	_menu.title = title
	_menu.subtitle = subtitle
	_menu.items = items
	_menu.footer = footer
	_menu.dim = dim
	_menu.chosen.connect(on_choice)
	if on_cancel.is_valid():
		_menu.cancelled.connect(on_cancel)
	add_child(_menu)


func _close_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null


# --- stage ----------------------------------------------------------------------------

func start_stage(id: String) -> void:
	for s in stages:
		if s.id == id:
			stage = s
	Game.clear_checkpoint()
	_close_menu()
	_stage_time = 0.0
	_took_damage = false
	_timing = true
	load_level()


func load_level() -> void:
	_generation += 1
	_last_hp = -1
	_in_boss = false
	boss = null
	get_tree().paused = false
	if level != null:
		remove_child(level)
		level.queue_free()
	if hud == null:
		hud = Hud.new()
		add_child(hud)
	hud.hide_boss()
	hud.show_message("")

	level = Level.new()
	level.stage_id = stage.id
	level.condition = requirement_met
	level.collected = Game.data["collected"] + Game.data["unlocked"]
	add_child(level)
	level.load_from_file(stage.path)
	get_tree().call_group("backdrop", "set_theme", stage.get("id", ""))
	level.set_reveal(Game.stats.reveal)
	level.pickup_collected.connect(_on_pickup)
	_boss_kind = ""
	level.boss_triggered.connect(_on_boss_trigger)
	for cp in level.checkpoints:
		cp.reached.connect(_on_checkpoint)
		if Game.has_checkpoint and cp.global_position == Game.checkpoint:
			cp.activate(false)
	if level.goal != null:
		level.goal.reached.connect(_on_goal)

	player = Player.new()
	player.max_hp = Game.max_hp()
	player.position = Game.checkpoint if Game.has_checkpoint else level.spawn
	level.add_child(player)
	player.env = level
	player.setup_party(Game.party(), Game.max_hp())
	player.weapons = Game.weapons_available()
	player.apply_loadout(Game.loadout())
	player.set_frame(Game.data.get("frame", "parts") if Game.is_ultimate() else "parts")
	player.notice.connect(func(text: String) -> void: hud.toast(text, 1.6))
	player.damage_taken_mult = Game.damage_taken_mult()
	player.hp_changed.connect(_on_player_hp)
	player.kill_y = level.pixel_size().y + 48.0
	player.reset_physics_interpolation()
	player.hp_changed.connect(hud.set_hp)
	player.core_changed.connect(hud.set_core)
	player.died.connect(_on_player_died)
	hud.player = player
	hud.set_hp(player.hp, player.max_hp)
	hud.set_core(player.core, Player.CORE_MAX)
	hud.set_loadout(ArmorData.ULTIMATE_LOADOUT if Game.is_ultimate() else Game.loadout())

	_cam = Camera2D.new()
	_cam.position = Vector2(0, -16)
	_set_camera_limits(Rect2(Vector2.ZERO, level.pixel_size()))
	_cam.drag_vertical_enabled = true
	_cam.drag_top_margin = 0.35
	_cam.drag_bottom_margin = 0.1
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	player.add_child(_cam)
	_cam.make_current()
	_cam.reset_smoothing()
	_shake_time = 0.0

	Audio.music(stage.id if Audio.TRACKS.has(stage.id) else "training")
	_flash_ready()
	_pose("warp_in")
	if not level.active_changes.is_empty():
		hud.toast("▲ 환경 변화\n" + "\n".join(level.active_changes), 3.5)


## Plays a one-off pose on the active character's sprite ("warp_in", "victory").
func _pose(name: String) -> void:
	var v = player.get("visual") if player != null else null
	if v != null and "force_anim" in v:
		v.force_anim = name


## Stage start / respawn banner.
func _flash_ready() -> void:
	var gen := _generation
	hud.show_message("READY")
	await get_tree().create_timer(1.1).timeout
	if gen == _generation and hud != null and not _in_boss:
		hud.show_message("")


func _on_player_hp(hp: int, _max_hp: int) -> void:
	if _last_hp >= 0 and hp < _last_hp:
		shake(2.0, 0.18)
		_took_damage = true
	_last_hp = hp


## True while the player stands still at an activated checkpoint (safe zone).
func at_checkpoint() -> bool:
	if player == null or not player.is_alive() or not player.is_on_floor():
		return false
	for cp in level.checkpoints:
		if cp.active and absf(player.global_position.x - cp.global_position.x) < 14.0 \
				and absf(player.global_position.y - cp.global_position.y) < 4.0:
			return true
	return false


func _leave_stage() -> void:
	_generation += 1
	Engine.time_scale = 1.0
	_look_x = 0.0
	get_tree().call_group("backdrop", "set_theme", "")
	get_tree().paused = false
	_close_menu()
	if _story != null:
		_story.queue_free()
		_story = null
	if _lab != null:
		_lab.queue_free()
		_lab = null
	if level != null:
		remove_child(level)
		level.queue_free()
		level = null
	if hud != null:
		hud.queue_free()
		hud = null
	player = null
	boss = null
	_in_boss = false


func _set_camera_limits(r: Rect2) -> void:
	_cam.limit_left = int(r.position.x)
	_cam.limit_top = int(r.position.y)
	_cam.limit_right = int(r.end.x)
	_cam.limit_bottom = int(r.end.y)


func _on_settings_changed() -> void:
	if player != null and is_instance_valid(player):
		player.damage_taken_mult = Game.damage_taken_mult()
	for b in get_tree().get_nodes_in_group("backdrop"):
		b.set("flashes_enabled", Game.settings.flashes)


func _on_loadout_changed() -> void:
	if player != null and is_instance_valid(player):
		player.apply_loadout(Game.loadout())
		player.set_frame("ultimate" if Game.is_ultimate() else "parts")
		hud.set_loadout(ArmorData.ULTIMATE_LOADOUT if Game.is_ultimate() else Game.loadout())
	if level != null:
		level.set_reveal(Game.stats.reveal)


func _on_checkpoint(pos: Vector2) -> void:
	Game.set_checkpoint(pos)
	hud.toast("체크포인트 — ↑ 로 아머 랩", 2.0)


func _on_pickup(pk) -> void:
	Audio.sfx("capsule" if pk.kind == "part" else "heal")
	if pk.kind == "part":
		Game.unlock(pk.part_id)
		hud.toast("%s 획득!\n%s\n체크포인트에서 ↑ 로 장착" % [ArmorData.part_name(pk.part_id),
				ArmorData.PART_DESC[pk.part_id]], 4.5)
	else:
		Game.collect(pk.pickup_id)
		Game.add_hp_bonus(2)
		player.max_hp = Game.max_hp()
		player.heal_full()
		hud.toast("HP 상한 +2", 3.0)


func _on_boss_trigger(kind: String) -> void:
	if _in_boss or not level.has_arena(kind):
		return
	var script_path: String = stage.get("boss" if kind == "main" else "hidden_boss", "")
	if kind == "hidden":
		var hid: String = stage.get("hidden_id", "")
		if script_path == "" or Game.is_cleared("hidden_" + hid):
			return
		if not requirement_met(stage.get("hidden_require", "")):
			hud.toast("미확인 신호… 아직 반응이 약하다 (%s)" % _requirement_text(stage.get("hidden_require", "")), 2.5)
			return
	if script_path == "":
		return
	_in_boss = true
	_boss_kind = kind
	var arena: Dictionary = level.arenas[kind]
	level.close_door(kind)
	_set_camera_limits(arena.camera)
	_cam.reset_smoothing()
	player.control_lock = 1.6
	boss = load(script_path).new()
	boss.arena = arena.rect
	boss.position = arena.spawn
	boss.player = player
	level.add_actor(boss)
	boss.hp_changed.connect(hud.set_boss_hp)
	boss.defeated.connect(_on_boss_defeated)
	hud.set_boss_hp(boss.hp, boss.get_max_hp())
	var bname = boss.get("boss_name")
	hud.set_boss_name(bname if typeof(bname) == TYPE_STRING else stage.get("name", ""))
	_boss_cutin(kind, bname if typeof(bname) == TYPE_STRING else stage.get("name", ""))
	Audio.sfx("door")
	Audio.sfx("warning")
	Audio.music("boss_intro")
	if kind == "hidden":
		_after_intro = "hidden_boss"
	else:
		_after_intro = "final_boss" if stage.get("final", "") == "true" else "boss"
	var gen := _generation
	await get_tree().create_timer(1.4).timeout
	if gen == _generation and hud != null:
		hud.show_message("")
	# Fallback when no audio device consumes the sting (it then never "finishes").
	await get_tree().create_timer(1.4).timeout
	if gen == _generation and _in_boss and Audio.current_track in ["boss_intro", ""]:
		Audio.music(_after_intro)


## Cut-in band with the boss portrait and name (scripts/ui/boss_cutin.gd).
func _boss_cutin(kind: String, boss_label: String) -> void:
	var cut := BossCutin.new()
	cut.boss_name = boss_label
	cut.hidden = kind == "hidden"
	var portrait_id: String = stage.id if kind == "main" else stage.get("hidden_id", "")
	var path := "res://art/portraits/%s.png" % portrait_id
	cut.portrait = load(path) if ResourceLoader.exists(path) else null
	cut.caption = "히든 보스 — 아르카의 기록에 없는 반응" if kind == "hidden" else str(stage.get("desc", ""))
	var preset: Dictionary = DepthProps.PRESETS.get(stage.id, {})
	cut.accent = Color(preset.get("light", "3de0ee"))
	add_child(cut)


func _on_music_finished(track: String) -> void:
	if track == "boss_intro" and _in_boss and _after_intro != "":
		Audio.music(_after_intro)


func _on_boss_defeated() -> void:
	hud.hide_boss()
	if _boss_kind == "hidden":
		_on_hidden_defeated()
		return
	var weapon: String = stage.get("weapon", "")
	if weapon != "" and not Game.data["weapons"].has(weapon):
		Game.unlock_weapon(weapon)
		hud.toast("특수무기 %s 획득 — IX 로 Q / E 전환" % WeaponShot.INFO[weapon].name, 3.4)
	_finish_stage("MISSION COMPLETE")


## Hidden boss down: reward, reopen the room, and let the run continue.
func _on_hidden_defeated() -> void:
	var hid: String = stage.get("hidden_id", "")
	Game.mark_cleared("hidden_" + hid)
	_in_boss = false
	boss = null
	_set_camera_limits(Rect2(Vector2.ZERO, level.pixel_size()))
	level.open_door("hidden")
	_reward_hidden(hid)
	Audio.sfx("capsule")
	Audio.music(stage.id if Audio.TRACKS.has(stage.id) else "training")


## Hidden boss rewards (GDD v0.2 §5-3): Eclipse -> Ultimate Armor IX,
## Fragment Λ -> true-ending route.
func _reward_hidden(hid: String) -> void:
	match hid:
		"eclipse":
			Game.unlock_ultimate()
			hud.toast("ULTIMATE ARMOR IX 획득!\n아머 랩의 FRAME 에서 전환 · 확장 엔딩 조건 달성", 4.0)
		"fragment":
			hud.toast("프래그먼트 Λ 데이터 회수 — 진엔딩 조건 달성", 4.0)
		_:
			hud.toast("히든 보스 격파", 3.0)


## Ending by hidden bosses beaten (GDD v0.2 §3-4): normal / extended / true.
func ending_kind() -> String:
	if Game.is_cleared("hidden_fragment"):
		return "true"
	if Game.is_cleared("hidden_eclipse"):
		return "extended"
	return "normal"


func _on_goal() -> void:
	_finish_stage("STAGE CLEAR")


func _finish_stage(text: String) -> void:
	var gen := _generation
	player.freeze()
	_pose("victory")
	hud.show_message(text)
	Game.mark_cleared(stage.id)
	if _timing:
		_timing = false
		var best := Game.record_clear(stage.id, _stage_time, not _took_damage)
		hud.toast("CLEAR %s%s%s" % [Game.clock(_stage_time), "  —  최고 기록!" if best else "",
				"   ★ 무피격" if not _took_damage else ""], 3.0)
	Audio.music("stage_clear")
	await get_tree().create_timer(CLEAR_DELAY).timeout
	if gen != _generation:
		return
	if stage.get("final", "") == "true":
		var kind := ending_kind()
		Game.set_flag("ending_" + kind)
		var pages: Array = {"normal": Story.ENDING_NORMAL, "extended": Story.ENDING_EXTENDED,
				"true": Story.ENDING_TRUE}[kind]
		play_story(pages + Story.CREDITS, show_select, "ending")
	else:
		show_select()


func _on_player_died() -> void:
	var gen := _generation
	Game.deaths += 1
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if gen == _generation:
		load_level()


func _build_backdrop() -> void:
	add_child(preload("res://scripts/level/backdrop_set.gd").new())
