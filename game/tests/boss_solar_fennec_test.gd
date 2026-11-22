extends SceneTree
## Headless test for the Solar Fennec stage and boss.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_solar_fennec_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const Fennec = preload("res://scripts/enemies/solar_fennec.gd")
const Crumble = preload("res://scripts/level/crumble_block.gd")
const Mover = preload("res://scripts/level/mover.gd")
const Walker = preload("res://scripts/enemies/walker.gd")
const Turret = preload("res://scripts/enemies/turret.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const STAGE := "res://levels/solar_fennec.txt"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run.call_deferred()


func _run() -> void:
	await test_stage()
	await test_fight()
	await test_dash_hits_standing_player()
	await test_dash_is_jumpable()
	await test_mirage_is_jumpable(false)
	await test_mirage_is_jumpable(true)
	await test_pillars_and_lance()
	await test_buster_hits()
	await test_weakness()
	await test_defeat()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage ----------------------------------------------------------------------------

func test_stage() -> void:
	var lv = _level()
	var m: Dictionary = lv.meta
	_check(m.get("id") == "solar_fennec" and m.get("name") == "SOLAR FENNEC" and m.get("order") == "3",
			"stage metadata: id / name / order")
	_check(m.get("desc") == "사막 태양열 발전소 · 약점 GRAVITY WING", "stage description names the weakness")
	_check(m.get("boss") == "res://scripts/enemies/solar_fennec.gd" and m.get("weapon") == "heat_mirage",
			"stage metadata: boss script and Heat Mirage reward")
	_check(lv.height == 20 and lv.width >= 150 and lv.width <= 190,
			"stage size %dx%d (150-190 columns, 20 rows)" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO, "stage has a player spawn")
	_check(lv.has_boss(), "stage has a boss room")
	var arena: Rect2 = lv.boss_arena
	_check(arena.size == Vector2(352, 176), "boss arena is 22 x 11 tiles (%s)" % str(arena.size))
	_check(arena.has_point(lv.boss_spawn), "boss spawn marker is inside the arena")
	var door: Rect2 = lv.arenas.main.door_rect
	_check(door.size == Vector2(16, 64) and is_equal_approx(door.end.y, arena.end.y),
			"boss door is one column, 4 tiles tall, on the arena floor")
	_check(lv.checkpoints.size() == 2, "two checkpoints (%d)" % lv.checkpoints.size())
	var last_cp: float = lv.checkpoints[lv.checkpoints.size() - 1].position.x
	var mid_cp: float = lv.checkpoints[0].position.x
	_check(last_cp < door.position.x and door.position.x - last_cp <= 10 * 16,
			"second checkpoint sits right before the boss door")
	_check(mid_cp > lv.width * 16 * 0.35 and mid_cp < lv.width * 16 * 0.65, "first checkpoint is mid-stage")
	var vents := 0
	var bent := 0
	for laser in lv.lasers:
		if laser.style == "flame":
			vents += 1
			if laser.segments.size() >= 2:
				bent += 1
	_check(vents == lv.lasers.size() and vents >= 6, "heat vents only, %d of them" % vents)
	_check(bent >= 3, "mirrors bend vent flames (%d bent)" % bent)
	var crumbles := 0
	var sliders := 0
	var lifts := 0
	var walkers := 0
	var turrets := 0
	var hp_ups := 0
	for c in lv.get_children():
		if c.get_script() == Crumble:
			crumbles += 1
		elif c.get_script() == Mover:
			if c.axis == Vector2.UP:
				lifts += 1
			else:
				sliders += 1
		elif c.get_script() == Walker:
			walkers += 1
		elif c.get_script() == Turret:
			turrets += 1
		elif c.get("kind") == "hp":
			hp_ups += 1
	_check(crumbles >= 3, "crumbling sand floors (%d)" % crumbles)
	_check(sliders >= 2 and lifts >= 1, "moving platforms: %d sliders, %d lifts" % [sliders, lifts])
	_check(walkers + turrets >= 3, "a few enemies (%d walkers, %d turrets)" % [walkers, turrets])
	_check(hp_ups == 1, "one optional HP-up")
	var reg: Array = Level.load_registry("res://levels")
	var ids := reg.map(func(s): return s.id)
	_check(ids.has("solar_fennec") and ids[0] == "training", "stage registry lists solar_fennec (%s)" % str(ids))
	await _free(lv)


# --- boss --------------------------------------------------------------------------------

func test_fight() -> void:
	var s: Array = await _arena_setup(60.0)
	var lv = s[0]
	var p = s[1]
	var b = s[2]
	var arena: Rect2 = lv.boss_arena
	var patterns := {}
	var p2_patterns := {}
	var states := {}
	var inside := true
	var phase2_ok := false
	for i in 900:
		await physics_frame
		if not is_instance_valid(p):
			break
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 90) % 2 == 0 else -1
		states[b.state] = true
		if b.pattern != "":
			patterns[b.pattern] = true
			if b.phase2:
				p2_patterns[b.pattern] = true
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if i == 420:
			b._invuln = 0.0
			b.take_damage(17)  # 32 -> 15: phase 2
			phase2_ok = b.phase2 and b.state == Fennec.S.FLARE
	var attack_states := 0
	for st in [Fennec.S.DASH, Fennec.S.MIRAGE_WIND, Fennec.S.PILLARS, Fennec.S.LANCE]:
		if states.has(st):
			attack_states += 1
	_check(patterns.size() >= 3, "boss cycles through its patterns (%s)" % str(patterns.keys()))
	_check(attack_states >= 3, "at least 3 attack states visited (%d, %d states total)" % [attack_states, states.size()])
	_check(phase2_ok, "phase 2 at <= 50% HP, entered through the solar flare")
	_check(p2_patterns.has("lance"), "phase 2 adds Solar Lance (%s)" % str(p2_patterns.keys()))
	_check(inside, "boss stays inside its arena")
	await _free(lv)


func test_dash_hits_standing_player() -> void:
	var s: Array = await _arena_setup(150.0)
	var p = s[1]
	var b = s[2]
	b.position.x = b.arena.end.x - 16.0
	b._start_pattern("dash")
	var hp0: int = p.hp
	for i in 150:
		await physics_frame
		if b.state == Fennec.S.IDLE:
			break
	_check(p.hp < hp0, "sand dash hurts a player who stays on the ground (hp %d -> %d)" % [hp0, p.hp])
	await _free(s[0])


func test_dash_is_jumpable() -> void:
	var s: Array = await _arena_setup(150.0)
	var p = s[1]
	var b = s[2]
	b.position.x = b.arena.end.x - 16.0
	b._start_pattern("dash")
	var hp0: int = p.hp
	var dashed := false
	for i in 180:
		await physics_frame
		dashed = dashed or b.state == Fennec.S.DASH
		_dodge(p, i, [_threat(b.position.x, b.facing if b.state == Fennec.S.DASH else 0.0)], b._dash_speed())
		if dashed and b.state == Fennec.S.IDLE:
			break
	_check(dashed and p.hp == hp0, "a timed jump clears the sand dash (hp %d -> %d)" % [hp0, p.hp])
	await _free(s[0])


func test_mirage_is_jumpable(phase2: bool) -> void:
	var s: Array = await _arena_setup(150.0)
	var p = s[1]
	var b = s[2]
	b.phase2 = phase2  # skip the flare: only the tuning changes
	b.position.x = b.arena.end.x - 16.0
	b._start_pattern("mirage")
	var hp0: int = p.hp
	var most := 0
	var ran := {}
	for i in 480:
		await physics_frame
		var threats := [_threat(b.position.x, b.facing if b.state == Fennec.S.DASH else 0.0)]
		most = maxi(most, b._mirages.size())
		for m in b._mirages:
			threats.append(_threat(m.x, m.dir if m.phase == 1 else 0.0))
			if m.phase == 1:
				ran[m] = true
		_dodge(p, i, threats, b._dash_speed())
		if b.state == Fennec.S.IDLE:
			break
	var want: int = Fennec.MIRAGE_COUNT[1 if phase2 else 0]
	_check(most == want and ran.size() == want and b.state == Fennec.S.IDLE,
			"heat mirage: %d afterimages replay the dash (phase %d)" % [most, 2 if phase2 else 1])
	_check(p.hp == hp0, "jumping each pass clears the mirage dash train (phase %d, hp %d -> %d)"
			% [2 if phase2 else 1, hp0, p.hp])
	await _free(s[0])


func test_pillars_and_lance() -> void:
	# Pillars land where the player stands.
	var s: Array = await _arena_setup(120.0)
	var p = s[1]
	var b = s[2]
	b._start_pattern("pillars")
	var hp0: int = p.hp
	var most := 0
	for i in 150:
		await physics_frame
		most = maxi(most, b._pillars.size())
		if b.state == Fennec.S.IDLE:
			break
	_check(most == 3, "phase 1 drops 3 sun pillars (%d)" % most)
	_check(p.hp < hp0, "a sun pillar hurts a player standing on its marker")
	# Phase 2 barrage: three waves, a step aside each time keeps the player safe.
	b._idle(99.0)
	b.position.x = b.arena.end.x - 16.0  # out of the dodger's way (contact is not under test)
	p.hp = p.max_hp
	await _frames(70)
	p.invuln_timer = 0.0
	b.phase2 = true
	b._start_pattern("pillars")
	hp0 = p.hp
	var waves := 0
	var last_left := 0
	for i in 240:
		await physics_frame
		if b._waves_left < last_left:
			waves += 1
		last_left = b._waves_left
		_step_aside(p, b)
		if b.state == Fennec.S.IDLE:
			break
	_check(waves == 3, "phase 2 pillar barrage comes in 3 waves (%d)" % waves)
	_check(p.hp == hp0, "stepping out of each wave's markers avoids the barrage (hp %d -> %d)" % [hp0, p.hp])
	# Solar Lance: the high beam passes over a standing player, the low one does not.
	b._idle(99.0)
	b.position = Vector2(b.arena.position.x + 16.0, b._ground_y())
	p.position.x = b.arena.get_center().x + 40.0
	p.in_dir = 0
	await _frames(70)
	p.invuln_timer = 0.0
	b._start_pattern("lance")
	b._beams = [Fennec.HIGH_BEAM, Fennec.LOW_BEAM]
	hp0 = p.hp
	var after_high := -1
	for i in 240:
		await physics_frame
		if after_high < 0 and b._beams.size() == 1:
			after_high = p.hp
		if b.state == Fennec.S.IDLE:
			break
	_check(b.pattern == "" and after_high == hp0, "high lance beam passes over a standing player")
	_check(p.hp < hp0, "low lance beam hits a standing player")
	# ... and a jump started at the end of the aim line clears it.
	b._idle(99.0)
	b.position = Vector2(b.arena.position.x + 16.0, b._ground_y())
	p.position.x = b.arena.get_center().x + 40.0
	p.in_dir = 0
	await _frames(70)
	p.invuln_timer = 0.0
	b._start_pattern("lance")
	b._beams = [Fennec.LOW_BEAM]
	hp0 = p.hp
	var jumped := -1
	for i in 150:
		await physics_frame
		if jumped < 0 and b.state == Fennec.S.LANCE and b._beam_t >= Fennec.LANCE_WARN - 0.1:
			p.in_jump = true
			jumped = i
		elif jumped >= 0 and i - jumped > 20:
			p.in_jump = false
		if b.state == Fennec.S.IDLE:
			break
	_check(jumped >= 0 and p.hp == hp0, "jumping as the aim line ends clears the low lance beam (hp %d -> %d)"
			% [hp0, p.hp])
	await _free(s[0])


func test_buster_hits() -> void:
	var s: Array = await _arena_setup(60.0)
	var p = s[1]
	var b = s[2]
	b._idle(99.0)
	b.position.x = b.arena.get_center().x + 40.0
	p.facing = 1
	var hp0: int = b.hp
	for i in 60:
		p.in_shoot = i % 12 < 6  # tap shots
		await physics_frame
	p.in_shoot = false
	_check(b.hp < hp0, "plain buster shots hit the fennec (hp %d -> %d)" % [hp0, b.hp])
	await _free(s[0])


func test_weakness() -> void:
	var s: Array = await _arena_setup(60.0)
	var b = s[2]
	await _frames(10)
	var hp0: int = b.hp
	b._invuln = 0.0
	b.take_damage(2, "buster")
	_check(hp0 - b.hp == 2 and b.stagger_count == 0, "buster deals normal damage, no stagger")
	b._start_pattern("pillars")
	for i in 120:
		await physics_frame
		if not b._zones.is_empty():
			break
	_check(not b._zones.is_empty(), "sun pillars are firing before the weakness hit")
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(2, "gravity_wing")
	var since := 0
	_check(hp0 - b.hp == ceili(2 * 2.5), "Gravity Wing deals x2.5 (%d)" % (hp0 - b.hp))
	_check(b.state == Fennec.S.STAGGER and b.stagger_count == 1 and b.pattern == "",
			"Gravity Wing interrupts the pattern into a stagger")
	_check(b._pillars.is_empty() and b._zones.is_empty(), "stagger clears the boss's hazards")
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(1, "gravity_wing")
	_check(hp0 - b.hp == 3 and b.stagger_count == 1, "second weakness hit: damage but no new stagger (cooldown)")
	var lifted := false
	var recovered := false
	for i in 120:
		await physics_frame
		since += 1
		if b.position.y < b._ground_y() - 12.0:
			lifted = true
		if b.state != Fennec.S.STAGGER:
			recovered = true
			break
	_check(lifted and recovered and b._on_ground(), "stagger lifts the fennec, drops it and recovers")
	await _frames(int((b.stagger_cooldown + 0.1) * 60.0) - since)
	b._invuln = 0.0
	b.take_damage(1, "gravity_wing")
	_check(b.stagger_count == 2 and b.state == Fennec.S.STAGGER, "after the cooldown the weakness staggers again")
	await _free(s[0])


func test_defeat() -> void:
	var s: Array = await _arena_setup(60.0)
	var b = s[2]
	b._start_pattern("pillars")
	for i in 120:
		await physics_frame
		if not b._zones.is_empty():
			break
	var zones: Array = b._zones.duplicate()
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	b._invuln = 0.0
	b.take_damage(99)
	await _frames(150)
	var cleaned := not zones.is_empty()
	for z in zones:
		if is_instance_valid(z):
			cleaned = false
	_check(done[0] and not is_instance_valid(b), "lethal damage plays the death sequence and emits defeated")
	_check(cleaned, "hazards are removed when the fennec is destroyed")
	await _free(s[0])


# --- helpers -------------------------------------------------------------------------------

func _level():
	var lv = Level.new()
	lv.stage_id = "solar_fennec"
	root.add_child(lv)
	lv.load_from_file(STAGE)
	return lv


## Stage + scripted player `px` pixels into the arena + the boss, ready to fight.
func _arena_setup(px: float) -> Array:
	var lv = _level()
	var arena: Rect2 = lv.boss_arena
	var p = Player.new()
	p.scripted = true
	p.position = Vector2(arena.position.x + px, arena.end.y - 1.0)
	lv.add_child(p)
	var b = Fennec.new()
	b.arena = arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	for i in 150:
		await physics_frame
		if b.active:
			break
	return [lv, p, b]


func _threat(x: float, dir: float) -> Dictionary:
	return {"x": x, "dir": dir}


## Scripted dodge: jump when a running threat is about to reach the player.
func _dodge(p, frame: int, threats: Array, speed: float) -> void:
	if p.in_jump and frame - p.get_meta("jumped", -100) > 20:
		p.in_jump = false
	if p.in_jump or not p.is_on_floor():
		return
	var reach := speed * 0.33 + 4.0
	for th in threats:
		var dx: float = p.global_position.x - th.x
		if th.dir != 0.0 and dx * th.dir > 0.0 and absf(dx) <= reach:
			p.in_jump = true
			p.set_meta("jumped", frame)
			return


## Scripted dodge for pillars: walk out of any telegraphed column covering the player.
func _step_aside(p, b) -> void:
	p.in_dir = 0
	for pl in b._pillars:
		var dx: float = p.global_position.x - pl.x
		if absf(dx) < 18.0:
			var dir := 1 if dx >= 0.0 else -1
			if p.global_position.x + dir * 30.0 > b.arena.end.x - 8.0:
				dir = -1
			elif p.global_position.x + dir * 30.0 < b.arena.position.x + 8.0:
				dir = 1
			p.in_dir = dir
			return


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _free(lv: Node) -> void:
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
