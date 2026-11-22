extends SceneTree
## Headless tests for the Pulse Cicada stage (levels/pulse_cicada.txt) and its boss
## (scripts/enemies/pulse_cicada.gd).
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_pulse_cicada_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const Cicada = preload("res://scripts/enemies/pulse_cicada.gd")
const BossBase = preload("res://scripts/enemies/boss_base.gd")
const STAGE := "res://levels/pulse_cicada.txt"
const HAZARD_GROUP := "pulse_cicada_hazard"
const HAZARD_LAYER := 32

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_stage_file()
	await test_route()
	await test_fight()
	await test_weakness()
	await test_death_cleanup()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage ----------------------------------------------------------------------------

func test_stage_file() -> void:
	var lv = _load_level()
	var m: Dictionary = lv.meta
	_check(m.get("id") == "pulse_cicada" and m.get("name") == "PULSE CICADA"
			and m.get("desc") == "초고압 송전 기지 · 약점 CORE DRILL" and m.get("order") == "6",
			"metadata: id / name / desc / order (%s)" % str(m))
	_check(m.get("boss") == "res://scripts/enemies/pulse_cicada.gd" and m.get("weapon") == "pulse_ring",
			"metadata: boss script and Pulse Ring reward")
	_check(ResourceLoader.exists(m.get("boss", "")), "boss script path exists")
	var reg: Array = Level.load_registry("res://levels")
	var entry = null
	for s in reg:
		if s.id == "pulse_cicada":
			entry = s
	_check(entry != null and entry.order == 6, "stage registry lists pulse_cicada at order 6")
	_check(lv.width >= 150 and lv.width <= 190 and lv.height >= 20,
			"stage size %dx%d tiles" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO, "stage has a player spawn")
	_check(lv.has_boss(), "stage has a boss room")
	_check(lv.boss_arena.size == Vector2(352, 176), "boss arena is 22x11 tiles (%s)" % str(lv.boss_arena.size))

	# Boss room shape: solid floor / ceiling / far wall, a 4-tall door, trigger inside.
	var a: Rect2 = lv.boss_arena
	var ax0 := int(a.position.x / 16)
	var ax1 := int(a.end.x / 16) - 1
	var ay0 := int(a.position.y / 16)
	var ay1 := int(a.end.y / 16) - 1
	var shell_ok := true
	for x in range(ax0, ax1 + 1):
		if not (lv.is_solid(x, ay0 - 1) and lv.is_solid(x, ay1 + 1)):
			shell_ok = false
	var door_rows := 0
	for y in range(ay0, ay1 + 1):
		if not lv.is_solid(ax1 + 1, y):
			shell_ok = false
		if lv.cell(ax0 - 1, y) == "D":
			door_rows += 1
		elif not lv.is_solid(ax0 - 1, y):
			shell_ok = false
	_check(shell_ok, "arena has a solid floor, ceiling and walls")
	_check(door_rows == 4 and lv.cell(ax0 - 1, ay1) == "D", "door column is 4 tiles tall at floor level (%d)" % door_rows)
	var trigger_x := -1
	for x in range(ax0, ax1 + 1):
		if lv.cell(x, ay1) == "B":
			trigger_x = x
	_check(trigger_x - (ax0 - 1) in [2, 3], "boss trigger is 2-3 tiles inside the door")

	# Checkpoints: one mid-stage, one right before the door.
	var cps: Array = lv.checkpoints.map(func(c): return c.position.x)
	cps.sort()
	var door_x: float = (ax0 - 1) * 16.0
	_check(cps.size() >= 2, "stage has 2+ checkpoints (%d)" % cps.size())
	if cps.size() >= 2:
		_check(door_x - cps[-1] > 0.0 and door_x - cps[-1] <= 10 * 16, "last checkpoint is right before the boss door")
		_check(cps[0] > lv.width * 16 * 0.3 and cps[0] < lv.width * 16 * 0.7, "a checkpoint sits mid-stage")

	# Gimmicks.
	var three_segments := false
	for laser in lv.lasers:
		if laser.segments.size() == 3:
			three_segments = true
	_check(lv.lasers.size() >= 5, "laser emitters (%d)" % lv.lasers.size())
	_check(three_segments, "two mirrors bend a beam into a U")
	var kinds := {}
	var hp_ups := 0
	var walkers := 0
	var turrets := 0
	for c in lv.entities():
		var path: String = c.get_script().resource_path if c.get_script() != null else ""
		kinds[path.get_file()] = true
		if c.get("kind") == "hp":
			hp_ups += 1
		if path.ends_with("walker.gd"):
			walkers += 1
		if path.ends_with("turret.gd"):
			turrets += 1
	_check(kinds.has("electric_floor.gd"), "rhythm electric floors are built")
	var phases := {}
	for c in lv.entities():
		if c.get_script() != null and c.get_script().resource_path.ends_with("blink_platform.gd"):
			phases[c.phase_b] = true
	_check(phases.size() == 2, "both hologram phases (o / O) are present")
	# The shaft alcove and the revisit niche behind the cracked panel (stage_link_test.gd).
	_check(hp_ups == 2, "two optional HP-ups (%d)" % hp_ups)
	_check(walkers >= 2 and turrets >= 1, "a few walkers / turrets (%d / %d)" % [walkers, turrets])
	var area := 0
	for r in lv.solid_rects:
		area += r.size.x * r.size.y
	var tiles := 0
	for y in lv.height:
		for x in lv.width:
			if lv.is_solid(x, y):
				tiles += 1
	_check(area == tiles, "merged collision covers every solid tile (%d tiles)" % tiles)
	lv.queue_free()
	await process_frame


## Drives a scripted neutral IX along the required path with real player physics:
## damage is ignored (i-frames), but hologram phases are respected and pits kill.
func test_route() -> void:
	var lv = _load_level()
	var triggered := [false]
	lv.boss_triggered.connect(func(_k) -> void: triggered[0] = true)
	var holo := {}
	for c in lv.entities():
		if c.get_script() != null and c.get_script().resource_path.ends_with("blink_platform.gd"):
			holo[c.phase_b] = c
	var p = _player(lv, lv.spawn)
	p.env = lv
	p.kill_y = lv.pixel_size().y + 48.0
	await _r_ticks(p, 10)
	await _r_walk(p, 85 * 16 + 8)
	_r_at(p, "route: electric floors, insulator tunnel, relay hall", 1360, 320)
	# hologram bridge: board each step as it phases in, leave as the current one flickers
	await _r_wait_holo(p, holo[false], 1.0, true)
	await _r_jump(p, 88 * 16 + 8)
	_r_at(p, "route: hologram step 1 (o)", 1400, 304)
	var steps := [[90, 93, 272, true], [95, 98, 240, false], [100, 103, 208, true]]
	for s in steps:
		await _r_walk(p, s[0] * 16 - 7)
		await _r_wait_holo(p, holo[not s[3]], 0.4, false)
		await _r_jump(p, s[1] * 16 + 8)
		_r_at(p, "route: hologram step to col %d" % s[1], s[1] * 16 - 16, s[2])
	await _r_walk(p, 105 * 16 - 7)
	await _r_jump(p, 107 * 16 + 8)
	_r_at(p, "route: cliff below tower 1", 1700, 208)
	# tower 1: hop beside the ledge, then wall-kick up the roof block
	await _r_walk(p, 114 * 16 + 8)
	await _r_jump(p, 116 * 16, 156.0)
	_r_at(p, "route: tower 1 rest ledge", 1840, 160)
	await _r_wall_climb(p, 1, 60.0)
	_r_at(p, "route: wall kicks reach the substation roof", 1872, 64)
	# rooftop plates and the hologram high wire
	await _r_walk(p, 128 * 16 + 8)
	await _r_wait_holo(p, holo[true], 1.0, true)
	await _r_jump(p, 131 * 16)
	_r_at(p, "route: high wire (O)", 2080, 64)
	await _r_wait_holo(p, holo[true], 0.4, false)
	await _r_jump(p, 135 * 16)
	_r_at(p, "route: high wire (o)", 2144, 64)
	await _r_jump(p, 139 * 16 + 8)
	_r_at(p, "route: tower 2 top", 2208, 64)
	# descent shaft -> checkpoint -> boss door
	await _r_walk(p, 143 * 16)
	for i in 300:
		if p.is_on_floor():
			break
		await _r_tick(p)
	_r_at(p, "route: bottom of the descent shaft", 2250, 320)
	await _r_walk(p, 159 * 16 + 8)
	_check(triggered[0] and p.state != Player.State.DEAD, "route: neutral IX reaches the boss trigger")
	# optional HP-up: hold toward tower 2 while dropping down the shaft
	var got := [false]
	lv.pickup_collected.connect(func(pk) -> void:
		if pk.kind == "hp":
			got[0] = true)
	p.position = Vector2(142 * 16 + 8, 6 * 16)
	p.velocity = Vector2.ZERO
	p.in_dir = -1
	await _r_ticks(p, 150)
	p.in_dir = 0
	_check(got[0], "route: the optional HP-up alcove is reachable")
	lv.queue_free()
	await _settle()


# --- boss -----------------------------------------------------------------------------

func test_fight() -> void:
	var lv = _load_level()
	var arena: Rect2 = lv.boss_arena
	var p = _player(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _spawn_boss(lv, p)
	_check(b.get_script().get_base_script() == BossBase, "boss extends boss_base.gd")
	_check(b.get_max_hp() == 32 and b.weakness == "core_drill" and b.boss_name == "PULSE CICADA",
			"boss tunables (hp %d, weakness %s)" % [b.get_max_hp(), b.weakness])
	_check(b.contact_damage >= 2 and b.contact_damage <= 3, "contact damage 2-3")
	var seen := {}
	var inside := true
	var lanes := false
	var bolts := false
	var live_hazard := false
	var ring_shots := 0
	var beat_before := 0.0
	var active_frames := 0
	var in_reach := 0
	for i in 1260:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 80) % 2 == 0 else -1
		seen[b.state] = true
		if b.active:
			active_frames += 1
			# Buster reach: a jump shot leaves the muzzle up to ~78 px above the floor.
			if arena.end.y - b.position.y <= 78.0 + b.hit_radius:
				in_reach += 1
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		for h in get_nodes_in_group(HAZARD_GROUP):
			if h.bolt:
				bolts = true
			else:
				lanes = true
			if h.is_live() and h.collision_layer == HAZARD_LAYER:
				live_hazard = true
			if not arena.grow(1.0).encloses(h.rects[0]):
				inside = false
		ring_shots = maxi(ring_shots, b._ring_shots.size())
		if i == 540:
			beat_before = b.beat_len
			b._invuln = 0.0
			b.take_damage(17)  # into phase 2
	var attacks := 0
	for s in [Cicada.S.RING, Cicada.S.FLOOR, Cicada.S.STRIKE]:
		if seen.has(s):
			attacks += 1
	_check(attacks == 3, "boss uses all 3 attack patterns (RING / FLOOR / STRIKE: %d)" % attacks)
	_check(seen.size() >= 5, "boss cycles through its states (%d seen)" % seen.size())
	_check(inside, "boss and its hazards stay inside the arena")
	_check(ring_shots >= 5, "RING fires a ring of beat-driven shots (%d)" % ring_shots)
	var reach := float(in_reach) / maxf(active_frames, 1.0)
	_check(reach >= 0.6, "buster can reach it most of the fight (%d%% of active time)" % roundi(reach * 100.0))
	_check(lanes and bolts and live_hazard, "boss spawns floor lanes and lightning columns that go live")
	_check(b.phase2 and b.beat_len < beat_before, "phase 2 at half HP speeds up the beat (%.2f -> %.2f)"
			% [beat_before, b.beat_len])
	lv.queue_free()
	await _settle()


func test_weakness() -> void:
	var lv = _load_level()
	var arena: Rect2 = lv.boss_arena
	var p = _player(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _spawn_boss(lv, p)
	for i in 100:
		await physics_frame
	_check(b.active, "boss is active after its intro")
	b.state = Cicada.S.FLOOR
	b._spawn_lanes(0)
	var hp0: int = b.hp
	b.take_damage(2, "buster")
	_check(hp0 - b.hp == 2 and b.state == Cicada.S.FLOOR, "buster hit: normal damage, no stagger")
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(2, "core_drill")
	await physics_frame
	_check(hp0 - b.hp == ceili(2 * 2.5), "Core Drill hit deals ceil(2 x 2.5) = %d (%d)" % [ceili(2 * 2.5), hp0 - b.hp])
	_check(b.state == Cicada.S.STAGGER, "Core Drill staggers the boss")
	await physics_frame
	_check(get_nodes_in_group(HAZARD_GROUP).is_empty(), "stagger removes the boss's hazards")
	_check(b.get_contact_damage() < b.contact_damage, "softer contact damage while dazed")
	b._invuln = 0.0
	b.state = Cicada.S.RING
	hp0 = b.hp
	b.take_damage(2, "core_drill")
	_check(hp0 - b.hp == 5 and b.state == Cicada.S.RING, "second weakness hit inside the cooldown does not stagger")
	# Recovery: after the cooldown it can be staggered again; it climbs back to a pylon.
	b.state = Cicada.S.CLING
	var recovered := false
	for i in 170:
		await physics_frame
		p.invuln_timer = 1.0
	b._invuln = 0.0
	b.state = Cicada.S.RING
	b.take_damage(2, "core_drill")
	_check(b.state == Cicada.S.STAGGER, "stagger is available again after the cooldown")
	for i in 240:
		await physics_frame
		p.invuln_timer = 1.0
		if b.state in [Cicada.S.HOP, Cicada.S.CLING] and b.position.y < arena.end.y - 30.0:
			recovered = true
		if not arena.grow(1.0).has_point(b.position):
			recovered = false
			break
	_check(recovered, "after the daze it flies back up to a pylon")
	lv.queue_free()
	await _settle()


func test_death_cleanup() -> void:
	var lv = _load_level()
	var arena: Rect2 = lv.boss_arena
	var p = _player(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _spawn_boss(lv, p)
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	for i in 100:
		await physics_frame
	# Make sure hazards and ring shots are on screen at the moment of death.
	b.state = Cicada.S.FLOOR
	b._spawn_lanes(1)
	b._mark_volley()
	b._fire_ring(0.0)
	await physics_frame
	_check(get_nodes_in_group(HAZARD_GROUP).size() >= 2, "hazards present before the lethal hit")
	b._invuln = 0.0
	var killed: bool = b.take_damage(99)
	_check(killed, "lethal hit reports the kill")
	await physics_frame
	await physics_frame
	_check(get_nodes_in_group(HAZARD_GROUP).is_empty(), "no boss-owned hazard remains after death")
	_check(get_nodes_in_group("enemy_shot").is_empty(), "boss shots are cleared on death")
	for i in 150:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "death sequence emits defeated and frees the boss")
	_check(get_nodes_in_group(HAZARD_GROUP).is_empty() and get_nodes_in_group("boss_hazard").is_empty(),
			"still no hazards after the death sequence")
	lv.queue_free()
	await _settle()


# --- helpers --------------------------------------------------------------------------

func _load_level():
	var lv = Level.new()
	lv.stage_id = "pulse_cicada"
	root.add_child(lv)
	lv.load_from_file(STAGE)
	return lv


func _player(lv, pos: Vector2):
	var p = Player.new()
	p.scripted = true
	p.position = pos
	lv.add_child(p)
	return p


func _spawn_boss(lv, p):
	var b = Cicada.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	return b


func _settle() -> void:
	await process_frame
	await physics_frame


# Route helpers: the player keeps i-frames, so only geometry and holograms matter.

func _r_tick(p) -> void:
	await physics_frame
	p.invuln_timer = 1.0


func _r_ticks(p, n: int) -> void:
	for i in n:
		await _r_tick(p)


func _r_walk(p, x: float) -> void:
	for i in 900:
		var d: float = x - p.position.x
		if absf(d) < 2.0:
			break
		p.in_dir = 1 if d > 0.0 else -1
		await _r_tick(p)
	p.in_dir = 0
	await _r_tick(p)


## Jump and steer toward x until landing. With `rise_to`, rise straight up until the
## feet are above that y first (for a ledge right beside the take-off spot).
func _r_jump(p, x: float, rise_to := INF) -> void:
	p.in_jump = false
	await _r_tick(p)
	p.in_jump = true
	var airborne := false
	for i in 150:
		var d: float = x - p.position.x
		if rise_to != INF and p.position.y > rise_to and p.velocity.y <= 0.0:
			p.in_dir = 0
		else:
			p.in_dir = (1 if d > 0.0 else -1) if absf(d) > 2.0 else 0
		await _r_tick(p)
		if not p.is_on_floor():
			airborne = true
		elif airborne:
			break
	p.in_jump = false
	p.in_dir = 0
	await _r_tick(p)


## Repeated wall kicks toward `dir` until standing above `top_y`.
func _r_wall_climb(p, dir: int, top_y: float) -> void:
	p.in_dir = dir
	var hold := 0
	for i in 400:
		await _r_tick(p)
		if p.is_on_floor() and p.position.y < top_y + 8.0:
			break
		if hold > 0:
			hold -= 1
			if hold == 0:
				p.in_jump = false
		elif p.wall_dir != 0 or p.is_on_floor():
			p.in_jump = true
			hold = 10
	p.in_jump = false
	p.in_dir = 0
	await _r_tick(p)


## fresh = true: wait until `platform` is on with more than `t` s left;
## fresh = false: wait until it is on with less than `t` s left (about to switch).
func _r_wait_holo(p, platform, t: float, fresh: bool) -> void:
	for i in 300:
		if platform.solid and (platform._time_left_on() > t) == fresh:
			return
		await _r_tick(p)


func _r_at(p, label: String, min_x: float, feet_y: float) -> void:
	var ok: bool = p.is_on_floor() and p.position.x >= min_x and absf(p.position.y - feet_y) < 1.5 \
			and p.state != Player.State.DEAD
	_check(ok, "%s (x=%.0f y=%.0f)" % [label, p.position.x, p.position.y])


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
