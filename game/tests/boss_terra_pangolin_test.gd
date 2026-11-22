extends SceneTree
## Headless tests for the TERRA PANGOLIN stage (levels/terra_pangolin.txt) and boss.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_terra_pangolin_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const Pangolin = preload("res://scripts/enemies/terra_pangolin.gd")
const STAGE := "res://levels/terra_pangolin.txt"
const ARENA_SIZE := Vector2(352, 176)
const EXPECTED_CHECKS := 34

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_stage()
	await test_hidden_branch()
	await test_fight()
	await test_weakness()
	# A script error aborts a test function silently; make sure every check ran.
	_check(_pass + _fail == EXPECTED_CHECKS, "all %d checks ran (%d)" % [EXPECTED_CHECKS, _pass + _fail])
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage ---------------------------------------------------------------------------

func test_stage() -> void:
	var lv = _level()
	var m: Dictionary = lv.meta
	_check(m.get("id") == "terra_pangolin" and m.get("name") == "TERRA PANGOLIN" and m.get("order") == "5",
			"metadata: id / name / order")
	_check(m.get("desc", "").contains("FREEZE LANCE"), "metadata: desc names the weakness")
	_check(m.get("boss") == "res://scripts/enemies/terra_pangolin.gd" and m.get("weapon") == "core_drill",
			"metadata: boss script and Core Drill reward")
	_check(m.get("hidden_boss") == "res://scripts/enemies/eclipse.gd" and m.get("hidden_id") == "eclipse"
			and m.get("hidden_require") == "bosses:3", "metadata: hidden boss ECLIPSE (bosses:3)")
	_check(lv.width >= 150 and lv.width <= 190 and lv.height >= 20, "stage size %dx%d" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO and lv.checkpoints.size() == 2, "spawn and 2 checkpoints (%d)" % lv.checkpoints.size())
	_check(lv.has_boss() and lv.boss_arena.size == ARENA_SIZE, "boss arena %s" % str(lv.boss_arena.size))
	_check(lv.arenas.main.door != null and lv.arenas.main.door_rect.size == Vector2(16, 64), "boss door is 4 tiles tall")
	_check(lv.has_arena("hidden") and lv.arenas.hidden.rect.size == ARENA_SIZE,
			"hidden arena %s" % (str(lv.arenas.hidden.rect.size) if lv.has_arena("hidden") else "missing"))
	_check(lv.arenas.hidden.door != null and lv.arenas.hidden.door_rect.size == Vector2(16, 64), "hidden door is 4 tiles tall")
	_check(lv.breakables.size() > 0, "cracked walls (%d)" % lv.breakables.size())
	var kinds := {}
	for c in lv.get_children():
		var s = c.get_script()
		if s != null:
			var key: String = s.resource_path.get_file()
			kinds[key] = kinds.get(key, 0) + 1
	_check(kinds.get("crumble_block.gd", 0) >= 5 and kinds.get("mover.gd", 0) >= 4,
			"gimmicks: crumbling floors (%d) and maglev cars (%d)" % [kinds.get("crumble_block.gd", 0), kinds.get("mover.gd", 0)])
	_check(kinds.get("walker.gd", 0) >= 3 and kinds.get("turret.gd", 0) >= 2,
			"enemies: walkers (%d) and turrets (%d)" % [kinds.get("walker.gd", 0), kinds.get("turret.gd", 0)])
	_check(kinds.get("pickup.gd", 0) == 1, "one HP-up")
	var reg: Array = Level.load_registry("res://levels")
	var ids := reg.map(func(s): return s.id)
	_check(ids.has("terra_pangolin"), "stage registry lists terra_pangolin")
	await _free(lv)


## The cracked wall seals the only way into the hidden room; once broken, neutral IX
## can walk down to the hidden door and climb back out to the split chamber.
func test_hidden_branch() -> void:
	var lv = _level()
	var hidden: Rect2 = lv.arenas.hidden.rect
	var wall = lv.breakables[0]
	var wall_rect: Rect2 = wall.rect
	_check(wall_rect.end.x <= hidden.position.x and wall_rect.position.y >= 17 * 16,
			"the cracked wall sits below the main path, before the hidden room")
	var p = Player.new()
	p.scripted = true
	p.env = lv
	# On the sunken track bed in front of the cracked wall.
	p.position = Vector2(wall_rect.position.x - 20.0, wall_rect.end.y)
	lv.add_child(p)
	await _frames(10)
	p.in_dir = 1
	await _frames(90)
	_check(p.position.x < wall_rect.position.x, "cracked wall blocks the branch (x=%.0f)" % p.position.x)
	wall.break_wall()
	await _frames(2)
	var reached := false
	for i in 300:
		await physics_frame
		p.invuln_timer = 1.0
		if hidden.grow(-2.0).has_point(p.position + Vector2(0, -4)):
			reached = true
			break
	_check(reached, "broken wall leads down into the hidden room (at %s)" % str(p.position))
	# Back out: walk left and hop up the steps.
	p.in_dir = -1
	var out := false
	var hold := 0
	for i in 600:
		await physics_frame
		p.invuln_timer = 1.0
		if hold > 0:
			hold -= 1
			if hold == 0:
				p.in_jump = false
		elif p.is_on_floor() and p.is_on_wall():
			p.in_jump = true
			hold = 18
		if p.position.y <= 17 * 16 + 1 and p.position.x < wall_rect.position.x - 48.0 and p.is_on_floor():
			out = true
			break
	_check(out, "neutral IX climbs back out of the branch (at %s)" % str(p.position))
	await _free(lv)


# --- boss fight ------------------------------------------------------------------------

func test_fight() -> void:
	var lv = _level()
	var arena: Rect2 = lv.boss_arena
	var p = _player(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _boss(lv, p)
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	var patterns := {}
	var states := {}
	var inside := true
	var hurt := false
	for i in 900:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; only the boss is under test
		p.in_dir = 1 if (i / 100) % 2 == 0 else -1
		p.in_jump = i % 70 < 12
		if b.pattern != "":
			patterns[b.pattern] = true
		states[b.state] = true
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if not hurt and i >= 420 and b.is_vulnerable():
			b._invuln = 0.0
			b.take_damage(17)
			hurt = true
	_check(patterns.size() >= 3, "boss uses %d patterns in 15 s %s" % [patterns.size(), str(patterns.keys())])
	_check(states.size() >= 8, "boss visits %d states" % states.size())
	_check(inside, "boss stays inside its arena")
	_check(hurt and b.phase2, "phase 2 after 17 damage (hp %d)" % b.hp)
	var killed := false
	for i in 400:
		await physics_frame
		p.invuln_timer = 1.0
		if b.is_vulnerable():
			b._invuln = 0.0
			killed = b.take_damage(99)
			break
	_check(killed, "lethal damage kills the boss")
	for i in 150:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "death sequence emits defeated and frees the boss")
	await _free(lv)


func test_weakness() -> void:
	var lv = _level()
	var arena: Rect2 = lv.boss_arena
	var p = _player(lv, Vector2(arena.position.x + 40.0, arena.end.y - 1.0))
	var b = _boss(lv, p)
	for i in 120:
		await physics_frame
		if b.active:
			break
	_check(b.active, "intro ends and the fight starts")
	# Buster vs. open body and vs. curled armour.
	b.start_pattern("fling")
	b._invuln = 0.0
	var hp0: int = b.hp
	b.take_damage(1, "buster")
	_check(hp0 - b.hp == 1, "buster hurts the uncurled body")
	b.start_pattern("roll")
	for i in 60:
		await physics_frame
		p.invuln_timer = 1.0
		if b.state == Pangolin.S.ROLL:
			break
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(4, "buster")
	_check(b.is_armored() and b.hp == hp0, "curled armour deflects the buster")
	# Freeze Lance: x2.5 and a stagger that drops it off the ceiling.
	b.state = Pangolin.S.ROLL
	b._leg = 2
	b.position = Vector2(arena.get_center().x, arena.position.y + Pangolin.HALF)
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(2, "freeze_lance")
	_check(hp0 - b.hp == ceili(2 * 2.5), "Freeze Lance deals x2.5 (%d)" % (hp0 - b.hp))
	_check(b.state == Pangolin.S.STAGGER_FALL and b.stagger_count == 1 and not b.is_armored(),
			"Freeze Lance staggers: falls off the ceiling uncurled")
	var landed := false
	for i in 60:
		await physics_frame
		p.invuln_timer = 1.0
		if b.state == Pangolin.S.STAGGER:
			landed = absf(b.position.y - (arena.end.y - Pangolin.HALF)) < 0.5
			break
	_check(landed, "staggered boss lands on the floor and thaws")
	# Second weakness hit inside the cooldown: damage, but no new stagger.
	b.start_pattern("fling")
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(2, "freeze_lance")
	_check(hp0 - b.hp == 5 and b.state == Pangolin.S.REAR and b.stagger_count == 1,
			"stagger cooldown: no stun lock")
	var recovered := false
	for i in 240:
		await physics_frame
		p.invuln_timer = 1.0
		if b.state not in [Pangolin.S.STAGGER, Pangolin.S.STAGGER_FALL, Pangolin.S.REAR,
				Pangolin.S.RECOVER, Pangolin.S.IDLE]:
			recovered = true
			break
	_check(recovered and b.collision_layer != 0, "boss resumes its patterns after the stagger")
	# Cooldown over: it can be staggered again.
	b._stagger_cd = 0.0
	b.start_pattern("rockfall")
	b._invuln = 0.0
	b.take_damage(2, "freeze_lance")
	_check(b.stagger_count == 2 and b.state == Pangolin.S.STAGGER, "staggers again after the cooldown")
	await _free(lv)


# --- helpers -----------------------------------------------------------------------------

func _level():
	var lv = Level.new()
	lv.stage_id = "terra_pangolin"
	root.add_child(lv)
	lv.load_from_file(STAGE)
	return lv


func _player(lv, pos: Vector2):
	var p = Player.new()
	p.scripted = true
	p.env = lv
	p.position = pos
	lv.add_child(p)
	return p


func _boss(lv, p):
	var b = Pangolin.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	return b


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _free(n: Node) -> void:
	for s in get_nodes_in_group("enemy_shot"):
		s.queue_free()
	n.queue_free()
	await process_frame
	await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
