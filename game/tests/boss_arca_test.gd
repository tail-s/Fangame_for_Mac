extends SceneTree
## Headless tests for the final stage EDEN CORE and its boss ARCA.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_arca_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const PlayerShot = preload("res://scripts/combat/player_shot.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const STAGE := "res://levels/final_eden_core.txt"
const ARCA_PATH := "res://scripts/enemies/arca.gd"

var Arca = load(ARCA_PATH)
var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_stage()
	await test_route()
	await test_shield_panels()
	await test_fight()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage ------------------------------------------------------------------------

func test_stage() -> void:
	var lv = _load_stage()
	_check(lv.meta.get("id") == "final_eden_core" and lv.meta.get("name") == "EDEN CORE",
			"stage id / name")
	_check(lv.meta.get("require") == "bosses:6" and lv.meta.get("final") == "true",
			"metadata: require bosses:6, final true")
	_check(lv.meta.get("boss") == ARCA_PATH,
			"metadata: ARCA is the stage boss")
	_check(lv.width >= 150 and lv.width <= 200 and lv.height >= 20,
			"stage size (%dx%d tiles)" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO and lv.checkpoints.size() == 2,
			"spawn and 2 checkpoints (%d)" % lv.checkpoints.size())
	_check(lv.has_boss(), "stage has a boss room")
	_check(lv.boss_arena.size == Vector2(352, 176), "boss arena is 22 x 11 tiles (%s)" % str(lv.boss_arena.size))
	var reflected := false
	for laser in lv.lasers:
		if laser.segments.size() >= 2:
			reflected = true
	_check(lv.lasers.size() >= 3 and reflected, "laser grid with a mirror-bent beam (%d emitters)" % lv.lasers.size())
	var kinds := {}
	for c in lv.entities():
		var path: String = c.get_script().resource_path if c.get_script() != null else ""
		kinds[path.get_file()] = true
	for gimmick in ["blink_platform.gd", "mover.gd", "crumble_block.gd", "electric_floor.gd",
			"walker.gd", "turret.gd"]:
		_check(kinds.has(gimmick), "stage contains %s" % gimmick)
	var zones := {}
	for y in lv.height:
		for x in lv.width:
			var z: String = lv.zone_at(Vector2(x * 16 + 8, y * 16 + 8))
			if z != "":
				zones[z] = true
	_check(zones.has("lowg") and zones.has("lift"), "low-gravity zone and updraft lift (%s)" % str(zones.keys()))
	# The registry lists the stage after the six bosses.
	var reg: Array = Level.load_registry("res://levels")
	var entry := {}
	for s in reg:
		if s.id == "final_eden_core":
			entry = s
	_check(entry.get("order", 0) == 9 and entry.get("final", "") == "true", "stage registry entry (order 9, final)")
	lv.queue_free()
	await process_frame


# --- route: a scripted neutral IX clears the gimmick sections --------------------------
## Damage is switched off (invuln each frame); falling into a pit or onto spikes
## would leave the player below the landing heights checked here.

func test_route() -> void:
	var lv = _load_stage()
	var p = Player.new()
	p.scripted = true
	p.env = lv
	lv.add_child(p)
	# Hologram bridge: run to the platform edge, jump while it flickers (the next
	# phase switches on mid-air).
	await _place(p, 46, 288)
	var blink := {}
	for c in lv.entities():
		if c.has_method("_time_left_on"):
			blink[c.phase_b] = c
	var cur = null
	var ok := true
	for hop in [[51, false], [56, true], [61, false], [66, true]]:
		var plat = blink[hop[1]]
		for i in 300:
			if cur == null and plat.solid and plat._time_left_on() > 0.8:
				break
			if cur == null:
				await _tick(p)
				continue
			var dx: float = (hop[0] - 3) * 16 - 7 - p.position.x
			p.in_dir = 0 if absf(dx) < 2.0 else int(signf(dx))
			if cur._time_left_on() < (0.4 if absf(dx) < 2.0 else 0.12):
				break
			await _tick(p)
		p.in_dir = 0
		await _hop(p, hop[0] * 16 + 8, 30)
		ok = ok and p.is_on_floor() and _near(p.position.y, 256.0)
		cur = plat
	await _hop(p, 72 * 16 + 8, 30)
	_check(ok and _near(p.position.y, 288.0) and p.position.x > 70 * 16, "hologram bridge: 4 timed hops reach the far side")
	# Updraft lift onto the wall.
	await _place(p, 75, 288)
	for i in 400:
		p.in_dir = 1
		await _tick(p)
		if p.is_on_floor() and p.position.y < 120.0:
			break
	p.in_dir = 0
	_check(p.is_on_floor() and _near(p.position.y, 112.0), "updraft lift carries IX onto the wall (y=%.0f)" % p.position.y)
	# Low-gravity data stream: wall -> platform -> high ledge -> bobbing platform -> pillar.
	await _place(p, 84, 112)
	var land := []
	for hop in [[92, 30], [96, 30], [99, 6], [109, 30]]:
		await _hop(p, hop[0] * 16 + 8, hop[1])
		land.append(Vector2i(floori(p.position.x / 16), roundi(p.position.y)))
	_check(land[0].y == 160 and land[1].y == 80 and land[3].y == 192 and land[3].x >= 106,
			"low-gravity stream crossed to the landing pillar (%s)" % str(land))
	# Mover, then two crumbling blocks, then the boss approach.
	await _place(p, 141, 288)
	var mover = null
	for c in lv.entities():
		if c is AnimatableBody2D and c.axis == Vector2.RIGHT:
			mover = c
	var base_x: float = mover._base.x
	for i in 400:
		if mover.position.x < base_x - 44.0:
			break
		await _tick(p)
	for i in 30:
		p.in_dir = 1
		await _tick(p)
		if p.position.x > mover.position.x + 16.0:
			break
	p.in_dir = 0
	for i in 400:
		if mover.position.x > base_x + 40.0:
			break
		await _tick(p)
	await _run_jump(p, mover.position.x + 48.0, 155 * 16 + 8)
	var c1: float = p.position.y
	await _run_jump(p, 157 * 16, 160 * 16 + 8)
	var c2: float = p.position.y
	await _run_jump(p, 162 * 16, 167 * 16 + 8)
	_check(_near(c1, 272.0) and _near(c2, 256.0) and _near(p.position.y, 288.0) and p.position.x > 165 * 16,
			"mover and crumbling blocks lead to the boss approach")
	lv.queue_free()
	await process_frame


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1.5


func _place(p, tx: int, feet_y: float) -> void:
	p.position = Vector2(tx * 16 + 8, feet_y)
	p.velocity = Vector2.ZERO
	p.in_dir = 0
	p.in_jump = false
	for i in 20:
		await _tick(p)


func _tick(p) -> void:
	await physics_frame
	p.invuln_timer = 1.0


## Jumps (holding the button `hold` frames), steers to target_x, returns on landing.
func _hop(p, target_x: float, hold: int) -> void:
	p.in_jump = true
	var airborne := false
	for i in 400:
		if i == hold:
			p.in_jump = false
		var dx: float = target_x - p.position.x
		p.in_dir = 0 if absf(dx) < 3.0 else int(signf(dx))
		await _tick(p)
		if i > 3 and not p.is_on_floor():
			airborne = true
		if (airborne and p.is_on_floor()) or p.position.y > 400.0:
			break
	p.in_dir = 0
	p.in_jump = false
	await _tick(p)


## Runs right to a platform edge, then hops toward target_x.
func _run_jump(p, edge_x: float, target_x: float) -> void:
	for i in 60:
		if p.position.x >= edge_x - 5.0:
			break
		p.in_dir = 1
		await _tick(p)
	await _hop(p, target_x, 30)


# --- shield panels: a shot on a closed panel bursts, gaps and open panels let it through ---

func test_shield_panels() -> void:
	var lv = _load_stage()
	var arena: Rect2 = lv.boss_arena
	var b = _spawn_arca(lv, null)
	for i in 150:
		await physics_frame
		if b.active:
			break
	_check(b.active and arena.has_point(b.position), "ARCA finishes its intro inside the arena")
	b.set_physics_process(false)  # freeze the fight; panels stay where they are
	b._close_shield()
	b._update_panels(0.0)
	await physics_frame
	var hp0: int = b.hp
	var shot = await _fire_at(lv, b, b._panel_angle(0))
	_check(b.hp == hp0 and not is_instance_valid(shot), "a buster shot that meets a closed panel bursts harmlessly")
	b._invuln = 0.0
	shot = await _fire_at(lv, b, b._panel_angle(0) + PI / 4.0)
	_check(b.hp < hp0, "a shot through the gap between panels reaches the core")
	b._invuln = 0.0
	hp0 = b.hp
	b._shield_open = true
	b._update_panels(0.0)
	await physics_frame
	shot = await _fire_at(lv, b, b._panel_angle(0))
	_check(b.hp < hp0, "open panels let the shot hit the core")
	lv.queue_free()
	await process_frame


## Fires a tap shot from 48 px out along `angle` straight at the core, waits 12 frames.
func _fire_at(lv, b, angle: float):
	var dir := Vector2.from_angle(angle)
	var s = PlayerShot.new()
	s.setup(0, 1)
	s.velocity = -dir * 300.0
	s.position = b.position + dir * 48.0
	lv.add_child(s)
	for i in 12:
		await physics_frame
	return s


# --- full fight ---------------------------------------------------------------------

func test_fight() -> void:
	var lv = _load_stage()
	var arena: Rect2 = lv.boss_arena
	var p = Player.new()
	p.scripted = true
	p.env = lv
	p.position = Vector2(arena.position.x + 60.0, arena.end.y - 1.0)
	lv.add_child(p)
	var damaging_before := get_nodes_in_group("damaging").size()
	var b = _spawn_arca(lv, p)
	var seen := {}
	var inside := true
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	var shot_hit := false
	var hp_start: int = b.hp
	var buster_hit := false
	var beam_live := false
	var field_on := false
	var drone_seen := false
	var max_shots := 0
	var shield_cycles := 0
	var was_solid := false
	for i in 1200:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 75) % 2 == 0 else -1
		p.in_jump = (i % 50) < 12
		seen[b.state] = true
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		var solid: bool = b.shield_solid()
		if was_solid and not solid:
			shield_cycles += 1
		was_solid = solid
		# First 7 s: real tap shots from the left at the core's height ...
		if i < 420:
			if b.hp < hp_start:
				shot_hit = true
			if i % 10 == 0 and b.active:
				var s = PlayerShot.new()
				s.setup(0, 1)
				s.position = b.position + Vector2(-60, 0)
				lv.add_child(s)
		# ... then, before 8 s, direct buster damage (always lands once active).
		elif i < 480 and not buster_hit:
			var hp1: int = b.hp
			b.take_damage(1, "buster")
			buster_hit = b.hp < hp1
		if i == 600:
			b._invuln = 0.0
			b.take_damage(maxi(b.hp - 20, 1), "buster")  # down to 20 HP: phase 2
		for h in get_nodes_in_group("arca_hazard"):
			if h.collision_layer != 0:
				if h.get("live") == true:
					beam_live = true
				elif h.has_method("is_on"):
					field_on = true
		for s in get_nodes_in_group("enemy_shot"):
			if s.get("slot") != null:
				drone_seen = true
		max_shots = maxi(max_shots, get_nodes_in_group("enemy_shot").size())
	print("  states seen: ", seen.keys().map(func(k): return Arca.S.keys()[k]))
	_check(seen.size() >= 6, "ARCA cycles through its patterns (%d states seen)" % seen.size())
	for st in ["LASER_FIRE", "DRONES", "RING", "BREAK"]:
		_check(seen.has(Arca.S[st]), "pattern state %s visited" % st)
	_check(seen.has(Arca.S.SPIRAL) or seen.has(Arca.S.FIELD), "a phase-2 pattern (SPIRAL / FIELD) visited")
	_check(inside, "ARCA stays inside its arena")
	_check(shield_cycles >= 2, "shield panels open regularly (%d openings)" % shield_cycles)
	_check(shot_hit, "real buster tap shots get through to the core within 7 s")
	_check(buster_hit, "take_damage(1, buster) lowers HP in the first 8 s")
	_check(b.phase2, "ARCA enters phase 2 at half HP")
	_check(b._panels.is_empty(), "phase 2: the shield panels are gone (core exposed)")
	_check(beam_live, "eye laser beam fired (live damage zone)")
	_check(drone_seen, "drones launched")
	_check(max_shots < 120, "bullet count stays sane (peak %d)" % max_shots)
	# Make sure a control field happens, then kill ARCA while hazards are out.
	if not field_on:
		b._start(Arca.S.FIELD)
		for i in 120:
			await physics_frame
			p.invuln_timer = 1.0
			for h in get_nodes_in_group("arca_hazard"):
				if h.collision_layer != 0 and h.has_method("is_on"):
					field_on = true
	_check(field_on, "control field stripes electrify the floor")
	b._start(Arca.S.FIELD)
	for i in 40:
		await physics_frame
	_check(not get_nodes_in_group("arca_hazard").is_empty(), "hazards are out when the killing blow lands")
	b._invuln = 0.0
	b.take_damage(99, "buster")
	for i in 200:
		await physics_frame
		p.invuln_timer = 1.0
	_check(done[0] and not is_instance_valid(b), "ARCA's death sequence emits defeated")
	_check(get_nodes_in_group("arca_hazard").is_empty(), "no boss-owned hazard remains after defeat")
	_check(get_nodes_in_group("damaging").size() == damaging_before,
			"only the stage's own damage zones remain (%d / %d)" % [get_nodes_in_group("damaging").size(), damaging_before])
	_check(get_nodes_in_group("enemy_shot").filter(func(s): return not s.is_queued_for_deletion()).is_empty(),
			"no ARCA shots remain")
	lv.queue_free()
	await process_frame


# --- helpers ------------------------------------------------------------------------

func _load_stage():
	var lv = Level.new()
	lv.stage_id = "final_eden_core"
	root.add_child(lv)
	lv.load_from_file(STAGE)
	return lv


func _spawn_arca(lv, p):
	var b = Arca.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	return b


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
