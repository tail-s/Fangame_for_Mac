extends SceneTree
## Hidden boss tests: ECLIPSE and FRAGMENT Λ (GDD v0.2 §3-5, §5-3).
## Each boss is spawned in the hidden room (b / d / Y) of an inline test map.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_hidden_test.gd

const Player = preload("res://scripts/player/player.gd")
const Level = preload("res://scripts/level/level.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const Eclipse = preload("res://scripts/enemies/eclipse.gd")
const Lambda = preload("res://scripts/enemies/fragment_lambda.gd")

## Corridor on the left (trigger `b`), door column `d`, 22 x 11 hidden room, `Y` spawn.
const HIDDEN_MAP := """; @id hidden_boss_test
#############################
#....#......................#
#....#......................#
#....#......................#
#....#......................#
#....#......................#
#....#......................#
#....#......................#
#....#...........Y..........#
#....d......................#
#....d......................#
#..b.d......................#
#############################
"""

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_room()
	await test_eclipse_fight()
	await test_eclipse_learning()
	await test_lambda_fight()
	await test_lambda_core()
	await test_lambda_inversion_and_cleanup()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func test_room() -> void:
	var s := _setup(null)
	var lv = s[0]
	var r: Rect2 = lv.arenas.hidden.rect
	_check(lv.has_arena("hidden") and r.size == Vector2(352, 176),
			"hidden room (b / d / Y) is 22 x 11 tiles inside (%s)" % str(r.size))
	await _teardown(lv)


# --- ECLIPSE ---------------------------------------------------------------------------

func test_eclipse_fight() -> void:
	var s := _setup(Eclipse)
	var lv = s[0]
	var p = s[1]
	var b = s[2]
	var arena: Rect2 = b.arena
	var seen := {}
	var inside := true
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var shots := 0
	for i in 900:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		_drive(p, i)
		if b.active:
			seen[b.state] = true
			min_x = minf(min_x, b.position.x)
			max_x = maxf(max_x, b.position.x)
			min_y = minf(min_y, b.position.y)
		shots = maxi(shots, get_nodes_in_group("enemy_shot").size())
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if i == 450:
			b._invuln = 0.0
			b.take_damage(29, "test")  # 48 -> 19: phase 2
	var patterns := _names(seen, Eclipse.S, [Eclipse.S.INTRO, Eclipse.S.IDLE])
	_check(patterns.size() >= 3, "ECLIPSE cycles its patterns (%s)" % ", ".join(patterns))
	_check(b.phase2, "ECLIPSE enters phase 2 at half HP")
	_check(seen.has(Eclipse.S.MIRROR_RUSH), "ECLIPSE phase 2 adds MIRROR RUSH")
	_check(inside, "ECLIPSE stays inside its arena")
	_check(max_x - min_x > 150.0 and b.floor_y() - min_y > 60.0,
			"ECLIPSE runs, dashes and climbs (x span %.0f, rose %.0f px)" % [max_x - min_x, b.floor_y() - Eclipse.H - min_y])
	_check(shots > 0, "ECLIPSE fires buster shots")
	b._invuln = 0.0
	b.take_damage(99, "kill")
	for i in 150:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "ECLIPSE death sequence emits defeated")
	await _teardown(lv)


func test_eclipse_learning() -> void:
	var s := _setup(Eclipse)
	var lv = s[0]
	var b = s[2]
	await _wait_active(b)
	var d1 := _hit(b, 4, "buster")
	var d2 := _hit(b, 4, "buster")
	var d3 := _hit(b, 4, "buster")
	_check(d1 == 4 and d2 == 4 and d3 == 4, "ECLIPSE: first 3 buster hits do full damage (%d %d %d)" % [d1, d2, d3])
	var d4 := _hit(b, 4, "buster")
	_check(d4 == 1 and b.resist_weapon == "buster", "ECLIPSE learns: 4th buster hit does x0.25 (%d)" % d4)
	var d5 := _hit(b, 2, "refraction_beam")
	_check(d5 == 2 and b.resist_weapon == "", "ECLIPSE: a different weapon hits fully and breaks the adaptation (%d)" % d5)
	var d6 := _hit(b, 4, "buster")
	_check(d6 == 4, "ECLIPSE: buster does full damage again after the reset (%d)" % d6)
	for i in 3:
		_hit(b, 1, "saber")
	var d7 := _hit(b, 1, "saber")
	_check(d7 == 1 and b.resist_weapon == "saber", "ECLIPSE: adapted damage never drops below 1")
	await _teardown(lv)


# --- FRAGMENT Λ ------------------------------------------------------------------------

func test_lambda_fight() -> void:
	var s := _setup(Lambda)
	var lv = s[0]
	var p = s[1]
	var b = s[2]
	var arena: Rect2 = b.arena
	var seen := {}
	var inside := true
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	var hit_done := false
	var closed := 0
	var max_closed := 0
	for i in 900:
		await physics_frame
		p.invuln_timer = 1.0
		_drive(p, i)
		if b.active:
			seen[b.state] = true
			closed = 0 if b.core_open else closed + 1
			max_closed = maxi(max_closed, closed)
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if i >= 400 and not hit_done and b.core_open:
			hit_done = true
			b._invuln = 0.0
			b.take_damage(25, "test")  # 48 -> 23: phase 2
	var patterns := _names(seen, Lambda.S, [Lambda.S.INTRO, Lambda.S.IDLE, Lambda.S.TELEPORT, Lambda.S.OPEN])
	_check(patterns.size() >= 3, "FRAGMENT cycles its patterns (%s)" % ", ".join(patterns))
	_check(seen.has(Lambda.S.TELEPORT) and seen.has(Lambda.S.OPEN), "FRAGMENT teleports and opens its core")
	_check(b.phase2, "FRAGMENT enters phase 2 at half HP")
	_check(inside, "FRAGMENT stays inside its arena")
	_check(max_closed <= 4.1 * 60, "FRAGMENT core opens at least every ~4 s (longest closed %.2f s, %d windows)"
			% [max_closed / 60.0, b.open_windows])
	await _wait_open(b, 400)
	b._invuln = 0.0
	b.take_damage(99, "kill")
	for i in 180:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "FRAGMENT death sequence emits defeated")
	await _teardown(lv)


func test_lambda_core() -> void:
	var s := _setup(Lambda)
	var lv = s[0]
	var b = s[2]
	await _wait_active(b)
	_check(not b.core_open, "FRAGMENT starts with the shell closed")
	var blocked := _hit(b, 5, "buster")
	_check(blocked == 0, "FRAGMENT: damage while the shell is closed is ignored")
	var frames := await _wait_open(b, 300)
	_check(b.core_open, "FRAGMENT: core opens within 5 s (%.2f s)" % (frames / 60.0))
	var dealt := _hit(b, 5, "buster")
	_check(dealt == 5, "FRAGMENT: the exposed core takes buster damage (%d)" % dealt)
	await _teardown(lv)


func test_lambda_inversion_and_cleanup() -> void:
	var s := _setup(Lambda)
	var lv = s[0]
	var p = s[1]
	var b = s[2]
	await _wait_active(b)
	# Phase-2 gravity inversion: pull toward the crystal and shards falling upward.
	b.phase2 = true
	b.position = Vector2(b.arena.get_center().x, b.arena.position.y + 40.0)
	b._start_pattern(Lambda.S.INVERSION)
	p.position = Vector2(b.arena.position.x + 40.0, b.arena.end.y - 1.0)
	p.velocity = Vector2.ZERO
	p.in_dir = 0
	await physics_frame
	var x0: float = p.position.x
	var up := 0
	for i in 90:
		await physics_frame
		p.invuln_timer = 1.0
		for shot in get_nodes_in_group("enemy_shot"):
			if shot.velocity.y < -150.0:
				up = maxi(up, 1)
	_check(p.position.x - x0 > 15.0, "FRAGMENT inversion pulls the player toward it (%.0f px)" % (p.position.x - x0))
	_check(up > 0, "FRAGMENT inversion makes shards fall upward from the floor")
	# Killing it mid-lattice frees the boss-owned laser hazard.
	await _wait_open(b, 400)
	for i in 30:
		await physics_frame
	b._end_attack()
	b._start_pattern(Lambda.S.LATTICE)
	for i in 60:
		await physics_frame
	var had_beam: bool = b._beam != null and is_instance_valid(b._beam) and b._beam.collision_layer != 0
	b.core_open = true  # test hook: let the kill land mid-pattern
	b._invuln = 0.0
	b.take_damage(99, "kill")
	await physics_frame
	var leftovers := get_nodes_in_group("damaging").filter(func(n) -> bool: return not n.is_queued_for_deletion())
	_check(had_beam and leftovers.is_empty(), "FRAGMENT lattice beam is live, then freed on death")
	for i in 180:
		await physics_frame
	await _teardown(lv)


# --- helpers ---------------------------------------------------------------------------

## [level, player, boss] with the boss (if any) at the hidden spawn.
func _setup(script) -> Array:
	var lv = Level.new()
	root.add_child(lv)
	lv.load_from_text(HIDDEN_MAP)
	lv.close_door("hidden")
	var arena: Rect2 = lv.arenas.hidden.rect
	var p = Player.new()
	p.scripted = true
	p.env = lv
	p.position = Vector2(arena.position.x + 60.0, arena.end.y - 1.0)
	lv.add_child(p)
	var b = null
	if script != null:
		b = script.new()
		b.arena = arena
		b.position = lv.arenas.hidden.spawn
		b.player = p
		lv.add_child(b)
	return [lv, p, b]


## Scripted player: walks back and forth, jumps and dashes now and then.
func _drive(p, i: int) -> void:
	p.in_dir = 1 if (i / 90) % 2 == 0 else -1
	p.in_jump = i % 75 < 14
	p.in_dash = i % 160 > 120 and i % 160 < 135


func _hit(b, amount: int, weapon: String) -> int:
	b._invuln = 0.0
	var hp0: int = b.hp
	b.take_damage(amount, weapon)
	return hp0 - b.hp


func _wait_active(b) -> void:
	for i in 240:
		if b.active:
			return
		await physics_frame


## Waits until the core is open; returns the frames waited.
func _wait_open(b, limit: int) -> int:
	for i in limit:
		if b.core_open:
			return i
		await physics_frame
	return limit


func _names(seen: Dictionary, states: Dictionary, skip: Array) -> Array:
	var out := []
	for k in states:
		if seen.has(states[k]) and not skip.has(states[k]):
			out.append(k)
	return out


func _teardown(lv: Node) -> void:
	for s in get_nodes_in_group("enemy_shot"):
		s.queue_free()
	lv.queue_free()
	await process_frame
	await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
