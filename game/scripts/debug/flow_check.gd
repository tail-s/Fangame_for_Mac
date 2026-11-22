extends Node
## Game-flow and performance checks that need main.gd (autoload names such as
## `Game` / `Audio` only compile in a normal run, not in `-s` test scripts).
##   godot --headless --fixed-fps 60 --path game -- --flowcheck
##   godot --headless --fixed-fps 60 --path game -- --perfcheck
## Prints PASS / FAIL lines and quits with code 1 on any failure.

const Level = preload("res://scripts/level/level.gd")

var main: Node
var perf := false

var _pass := 0
var _fail := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if perf:
		await _perf_all()
	else:
		await _check_alt_tiles()
		await _check_requirements()
		await _check_options()
		await _check_select()
		await _check_stage_start()
		await _check_shake()
		await _check_pause_options()
	print("%d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  " + label)
	else:
		_fail += 1
		print("  FAIL  " + label)


# --- cross-stage changes (GDD §5-4) -----------------------------------------------

const ALT_MAP := """; @id alt_test
; @alt T cleared:alpha g .
; @alt M cleared:alpha . m
; @change cleared:alpha 전력 복구
; @change cleared:beta 다른 변화
#..........
#P..T..M...
###########
"""


func _check_alt_tiles() -> void:
	var before := Level.new()
	add_child(before)
	before.load_from_text(ALT_MAP)
	_check(before.cell(4, 1) == "g" and before.cell(7, 1) == "." and before.is_solid(4, 1),
			"@alt before: gate is solid, no mover")
	_check(before.active_changes.is_empty(), "@change before: no active change")
	var after := Level.new()
	after.condition = func(req: String) -> bool: return req == "cleared:alpha"
	add_child(after)
	after.load_from_text(ALT_MAP)
	_check(after.cell(4, 1) == "." and after.cell(7, 1) == "m" and not after.is_solid(4, 1),
			"@alt after: gate open, mover placed")
	_check(after.active_changes == ["전력 복구"], "@change after: only the met change is active")
	_check(before.meta.alts.size() == 2 and before.meta.changes.size() == 2,
			"repeatable @alt / @change lines are all kept")
	before.queue_free()
	after.queue_free()
	await _frames(1)


func _check_requirements() -> void:
	Game.new_game()
	_check(not main.requirement_met("cleared:prism_gecko"), "cleared:<id> unmet on a new game")
	Game.mark_cleared("prism_gecko")
	_check(main.requirement_met("cleared:prism_gecko"), "cleared:<id> met after the clear")
	_check(main.requirement_met("cleared:prism_gecko+bosses:1"), "cleared + bosses combine")
	_check(not main.requirement_met("cleared:prism_gecko+bosses:2"), "combined requirement needs both")
	_check(main._requirement_text("cleared:pulse_cicada").contains("PULSE CICADA"),
			"requirement text names the stage")
	Game.new_game()


# --- options -------------------------------------------------------------------------

func _check_options() -> void:
	Game.settings = Game.default_settings()
	main.show_title()
	await _frames(3)
	var ids: Array = main._menu.items.map(func(it): return it.id)
	_check(ids.has("options"), "title menu has OPTIONS")
	_check(Audio.current_track == "title", "title music starts")
	main.show_options(main.show_title)
	await _frames(3)
	_check(main._menu.items.size() == 8 and main._menu._compact(), "options menu: 8 rows, compact layout")
	main._on_option_adjust("music", -1)
	main._on_option_adjust("difficulty", 1)
	main._on_option_adjust("shake", 1)
	_check(Game.settings.music == 6 and Game.settings.difficulty == "hard" and not Game.settings.shake,
			"← → change music / difficulty / shake")
	_check(main._menu.items[0].text.contains("■■■■■■□□□□"), "music row shows the new value")
	_check(is_equal_approx(Game.damage_taken_mult(), 1.5), "hard = damage taken x1.5")
	for i in 5:
		main._on_option_adjust("music", -1)
	main._on_option_adjust("music", -1)
	_check(Game.settings.music == 0, "volume clamps at 0")
	main._on_option_adjust("difficulty", 1)
	_check(Game.settings.difficulty == "hard", "difficulty clamps at hard")
	# Real key input on the menu: ↓ moves the cursor, → adjusts the selected row.
	main._menu.selected = 0
	Input.action_press("move_down")
	await _frames(2)
	Input.action_release("move_down")
	await _frames(2)
	_check(main._menu.selected == 1, "↓ moves the options cursor")
	var sfx_before: int = Game.settings.sfx
	Input.action_press("move_right")
	await _frames(2)
	Input.action_release("move_right")
	await _frames(2)
	_check(Game.settings.sfx == mini(sfx_before + 1, 10), "→ raises the selected volume")
	main._on_option_choice("controls", main.show_title)
	await _frames(2)
	_check(main._menu.title == "CONTROLS" and main._menu.items.size() >= 8, "controls page lists the keys")
	Game.settings = Game.default_settings()


func _check_select() -> void:
	Game.new_game()
	main.show_select()
	await _frames(3)
	var m = main._menu
	_check(m.items.size() == main.stages.size() + 2 and m._compact(), "stage select uses the compact list")
	m.selected = m.items.size() - 1
	m._refresh()
	var last_row: Label = m._rows[m.items.size() - 1][0]
	_check(last_row.visible and last_row.position.y + 12.0 < 196.0, "last row scrolls into view above the footer")
	_check(not m._rows[0][0].visible, "first row scrolls out of view")
	var final_row = m.items.filter(func(it): return it.text.begins_with("EDEN CORE"))
	_check(final_row.size() == 1 and final_row[0].id == "locked" and final_row[0].text.contains("LOCKED"),
			"final stage is locked on a new game")
	var terra = m.items.filter(func(it): return it.id == "terra_pangolin")
	_check(terra.size() == 1 and terra[0].text.contains("◈") and terra[0].note.contains("약함"),
			"hidden-route stage shows a weak unknown signal")
	for id in ["prism_gecko", "gravity_albatross", "solar_fennec"]:
		Game.mark_cleared(id)
	Game.set_flag("mid_event")
	main.show_select()
	await _frames(3)
	terra = main._menu.items.filter(func(it): return it.id == "terra_pangolin")
	_check(terra[0].note.contains("감지"), "3 bosses: the unknown signal is detected")
	# Every stage with @change lines shows ▲ exactly when one of them is met.
	var ok := true
	for s in main.stages:
		var row = main._menu.items.filter(func(it): return it.id == s.id)
		if row.is_empty():
			continue
		var marked: bool = row[0].text.contains("▲")
		if marked != not Level.changes_met(s, main.requirement_met).is_empty():
			ok = false
	_check(ok, "▲ environment-change mark matches the met @change lines")
	Game.new_game()


func _check_stage_start() -> void:
	Game.new_game()
	Game.settings.difficulty = "easy"
	main.start_stage("training")
	await _frames(5)
	_check(main.level != null and main.player != null, "training stage loads")
	_check(main.hud._msg.text == "READY", "READY banner on stage start")
	_check(is_equal_approx(main.player.damage_taken_mult, 0.5), "easy difficulty reaches the player")
	_check(Audio.current_track == "training", "stage music starts")
	var hp: int = main.player.hp
	main.player.take_damage(4, main.player.global_position.x + 10)
	_check(main.player.hp == hp - 2, "easy: a 4-damage hit takes 2 HP")
	await get_tree().create_timer(1.3).timeout
	_check(main.hud._msg.text == "", "READY banner clears")
	Game.settings = Game.default_settings()
	Game._refresh()


func _check_shake() -> void:
	main.start_stage("training")
	await _frames(3)
	Game.settings.shake = true
	main.shake(4.0, 0.4)
	var moved := false
	for i in 10:
		await get_tree().process_frame
		if main._cam.offset != Vector2.ZERO:
			moved = true
	_check(moved, "screen shake moves the camera")
	await get_tree().create_timer(0.5).timeout
	_check(main._cam.offset == Vector2.ZERO, "shake settles back to zero")
	Game.settings.shake = false
	main.shake(4.0, 0.4)
	moved = false
	for i in 10:
		await get_tree().process_frame
		if main._cam.offset != Vector2.ZERO:
			moved = true
	_check(not moved, "shake off: camera stays still")
	Game.settings = Game.default_settings()


func _check_pause_options() -> void:
	main.start_stage("training")
	await _frames(3)
	main._open_pause()
	await _frames(2)
	_check(get_tree().paused and main._menu.items.any(func(it): return it.id == "options"),
			"pause menu has OPTIONS")
	main._on_pause_choice("options")
	await _frames(2)
	_check(main._menu.title == "OPTIONS" and get_tree().paused, "options open over the paused stage")
	main._menu.cancelled.emit()
	await _frames(2)
	_check(main._menu != null and main._menu.title == "PAUSE", "Esc in options returns to pause")
	main._resume()
	await _frames(2)
	_check(not get_tree().paused, "resume unpauses")
	main.show_title()
	await _frames(2)


# --- performance ------------------------------------------------------------------------

## Runs every stage for 10 s with the player running right, jumping and
## shooting, and reports the average / worst wall time per frame.
func _perf_all() -> void:
	Game.unlock_all()
	var worst_all := 0.0
	for s in main.stages:
		main.start_stage(s.id)
		await _frames(30)
		var p = main.player
		p.god_mode = true
		var worst := 0.0
		var total := 0.0
		var nodes := 0
		var calls := 0
		for i in 600:
			Input.action_press("move_right")
			if i % 40 == 0:
				Input.action_press("jump")
			elif i % 40 == 20:
				Input.action_release("jump")
			if i % 12 == 0:
				Input.action_press("shoot")
			elif i % 12 == 6:
				Input.action_release("shoot")
			# With --fixed-fps the engine never sleeps, so wall time per frame is
			# the real cost of a frame (physics + process + drawing).
			var t0 := Time.get_ticks_usec()
			await get_tree().physics_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			nodes = maxi(nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			calls = maxi(calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		for a in ["move_right", "jump", "shoot"]:
			Input.action_release(a)
		# Draw calls are 0 under --headless (nothing is rendered).
		print("  %-20s avg %5.2f ms  worst %5.2f ms  nodes %d  draw calls %d" % [s.id, total / 600.0,
				worst, nodes, calls])
		worst_all = maxf(worst_all, worst)
		_check(total / 600.0 < 8.0, "%s: average frame cost under 8 ms" % s.id)
	main.show_title()
	await _frames(2)
	print("  worst frame over all stages: %.2f ms" % worst_all)
