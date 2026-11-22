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


func _ready() -> void:
	stages = load_stage_registry()
	add_to_group("shaker")
	_build_backdrop()
	Game.loadout_changed.connect(_on_loadout_changed)
	Game.settings_changed.connect(_on_settings_changed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoshot=") or arg.begins_with("--gallery="):
			Game.save_enabled = false
			Game.new_game()
			var shot := Autoshot.new()
			shot.gallery = arg.begins_with("--gallery=")
			shot.out_dir = arg.split("=", true, 1)[1]
			shot.main = self
			add_child(shot)
			return
	Game.load_settings()
	show_title()


func _process(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
		var k := _shake_strength * _shake_time / _shake_total
		_cam.offset = Vector2(randf_range(-k, k), randf_range(-k, k)).round()
	elif _cam.offset != Vector2.ZERO:
		_cam.offset = Vector2.ZERO


## Screen shake (off when the "shake" option is off). Called through the "shaker" group.
func shake(strength: float, seconds: float) -> void:
	if not Game.settings.shake or strength * seconds < _shake_strength * _shake_time:
		return
	_shake_strength = strength
	_shake_time = seconds
	_shake_total = seconds


func _physics_process(_delta: float) -> void:
	if level == null or _menu != null or _lab != null:
		return
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
	items.append({"id": "options", "text": "옵션", "note": "음량 · 난이도 · 화면 흔들림 · 깜박임 · 조작"})
	items.append({"id": "quit", "text": "종료"})
	_show_menu("REBIRTH PROTOCOL", "PROTOTYPE 0.6 · ORIGINAL TEST BUILD", items,
			"↑↓ 선택   Z / Enter 결정", _on_title_choice, Callable())
	Audio.music("title")


# --- options (GDD §8-2 phase 6: accessibility) --------------------------------------

const OPTION_IDS := ["music", "sfx", "difficulty", "shake", "flashes", "fullscreen"]


func show_options(back: Callable) -> void:
	var items := []
	for id in OPTION_IDS:
		var row := _option_row(id)
		items.append({"id": id, "text": row[0], "note": row[1], "adjust": true})
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
		"shake", "flashes", "fullscreen":
			Game.set_setting(id, not s[id])
	var row := _option_row(id)
	if _menu != null:
		_menu.update_item(id, row[0], row[1])


func _on_option_choice(id: String, back: Callable) -> void:
	if OPTION_IDS.has(id):
		_on_option_adjust(id, 1)
	elif id == "controls":
		_show_controls(back)
	else:
		back.call()


func _show_controls(back: Callable) -> void:
	var rows := [
		["이동", "← →  /  스틱 · 십자키"], ["점프", "Z · Space  /  A"], ["공격 (길게: 차지)", "X · J  /  X"],
		["대시", "C · K · Shift  /  B"], ["필살기", "V · L  /  Y"], ["특수무기 전환", "Q · E  /  LB · RB"],
		["캐릭터 교대 · 태그", "Tab · F  /  LT"], ["아머 랩 (체크포인트)", "↑"], ["일시정지", "Esc · P  /  Start"],
		["체크포인트부터 다시", "R  /  Back"],
	]
	var items := []
	for r in rows:
		items.append({"id": "back", "text": r[0], "note": r[1]})
	_show_menu("CONTROLS", "↑↓ 로 항목을 고르면 아래에 키가 표시됩니다", items, "Z / Esc 돌아가기",
			func(_id: String) -> void: show_options(back), show_options.bind(back), level != null)


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
	_show_menu("STAGE SELECT", "HP %d · 파츠 %d / 8 · 보스 %d / 6" % [Game.max_hp(),
			Game.unlocked_count(), bosses_cleared()],
			items, "Z 결정   Esc 타이틀", _on_select_choice, show_title)


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
		on_choice: Callable, on_cancel: Callable, dim := false, selected := 0) -> void:
	_close_menu()
	_menu = MenuScreen.new()
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
	if not level.active_changes.is_empty():
		hud.toast("▲ 환경 변화\n" + "\n".join(level.active_changes), 3.5)


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
	level.add_child(boss)
	boss.hp_changed.connect(hud.set_boss_hp)
	boss.defeated.connect(_on_boss_defeated)
	hud.set_boss_hp(boss.hp, boss.get_max_hp())
	var bname = boss.get("boss_name")
	hud.set_boss_name(bname if typeof(bname) == TYPE_STRING else stage.get("name", ""))
	hud.show_message("WARNING" if kind == "main" else "!! UNKNOWN SIGNAL !!")
	Audio.sfx("door")
	Audio.sfx("warning")
	Audio.music("boss_intro")
	var gen := _generation
	await get_tree().create_timer(1.4).timeout
	if gen == _generation and hud != null:
		hud.show_message("")
		if kind == "hidden":
			Audio.music("hidden_boss")
		else:
			Audio.music("final_boss" if stage.get("final", "") == "true" else "boss")


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
	hud.show_message(text)
	Game.mark_cleared(stage.id)
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
	var sky := CanvasLayer.new()
	sky.layer = -10
	var gradient := Gradient.new()
	gradient.set_color(0, Color("0a1326"))
	gradient.set_color(1, Color("1c2f52"))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(384, 216)
	sky.add_child(rect)
	add_child(sky)

	# [scroll scale, colour, seed, max tower height]
	for spec in [[0.2, Color("101f3a"), 3, 230.0], [0.45, Color("15294a"), 7, 170.0]]:
		var layer := Parallax2D.new()
		layer.scroll_scale = Vector2(spec[0], spec[0] * 0.5)
		layer.repeat_size = Vector2(Backdrop.WIDTH, 0)
		layer.repeat_times = 3
		layer.z_index = -5
		var towers := Backdrop.new()
		towers.color = spec[1]
		towers.seed_value = spec[2]
		towers.max_height = spec[3]
		layer.add_child(towers)
		add_child(layer)
