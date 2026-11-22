extends SceneTree
## CRYO NARWHAL stage + boss tests (headless).
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_cryo_narwhal_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const Narwhal = preload("res://scripts/enemies/cryo_narwhal.gd")
const Walker = preload("res://scripts/enemies/walker.gd")
const Turret = preload("res://scripts/enemies/turret.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const STAGE := "res://levels/cryo_narwhal.txt"
const T := 16.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_stage_file()
	await test_traversal()
	await test_fight()
	await test_each_pattern()
	await test_buster_only()
	await test_weakness()
	await test_defeat()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage -------------------------------------------------------------------------------

func test_stage_file() -> void:
	var lv = _load_level()
	var m: Dictionary = lv.meta
	_check(m.get("id") == "cryo_narwhal" and m.get("name") == "CRYO NARWHAL" and m.get("order") == "4",
			"metadata: id / name / order (%s)" % str(m))
	_check(m.get("desc") == "극지 심해 기지 · 약점 HEAT MIRAGE", "metadata: desc")
	_check(m.get("boss") == "res://scripts/enemies/cryo_narwhal.gd" and m.get("weapon") == "freeze_lance",
			"metadata: boss script and Freeze Lance reward")
	_check(lv.width >= 150 and lv.width <= 190 and lv.height == 20, "stage size %dx%d" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO, "stage has a spawn point")
	_check(lv.has_boss(), "stage has a boss room")
	var arena: Rect2 = lv.boss_arena
	_check(arena.size == Vector2(352, 176), "boss arena is 22 x 11 tiles (%s)" % str(arena.size))
	var door: Rect2 = lv.arenas.main.door_rect
	_check(door.size == Vector2(16, 64) and door.end.x == arena.position.x, "door column is 4 tiles tall, left of the arena")
	var trig := _find_cells(lv, "B")
	_check(trig.size() == 1 and trig[0].x - int(door.position.x / T) in [2, 3],
			"boss trigger is 2-3 tiles inside the door (%s)" % str(trig))
	var cps: Array = lv.checkpoints.map(func(cp): return cp.position.x)
	cps.sort()
	_check(cps.size() == 2, "two checkpoints (%d)" % cps.size())
	_check(cps[-1] < door.position.x and door.position.x - cps[-1] <= 6 * T,
			"second checkpoint right before the boss door")
	_check(cps[0] > lv.width * T * 0.3 and cps[0] < lv.width * T * 0.65, "first checkpoint mid-stage")
	# Gimmicks and enemies are present.
	_check(_find_cells(lv, "~").size() > 300 and _find_cells(lv, "i").size() > 20 and _find_cells(lv, "^").size() > 40,
			"water, ice and spike tiles are used")
	var enemies := 0
	var hp_up := 0
	for c in lv.get_children():
		if c.get_script() == Walker or c.get_script() == Turret:
			enemies += 1
		if c.get("kind") == "hp":
			hp_up += 1
	_check(enemies >= 3, "a few walkers / turrets (%d)" % enemies)
	# The tank alcove and the Aero LEG ledge over the hangar (stage_link_test.gd).
	_check(hp_up == 2, "two optional HP-ups (%d)" % hp_up)
	# The boss room has a flooded seabed band; ~ cells count as empty for the arena.
	_check(lv.zone_at(Vector2(arena.get_center().x, arena.end.y - 8.0)) == "water"
			and lv.zone_at(arena.get_center()) == "", "boss room seabed band is flooded")
	var reg: Array = Level.load_registry("res://levels")
	var entry = null
	for s in reg:
		if s.id == "cryo_narwhal":
			entry = s
	_check(entry != null and entry.order == 4, "stage registry lists CRYO NARWHAL at order 4")
	lv.queue_free()
	await process_frame


## Key jumps of the required path, with a neutral IX and real tile physics (no armor).
func test_traversal() -> void:
	var lv = _load_level()
	for c in lv.get_children():
		if c.get_script() == Walker or c.get_script() == Turret:
			c.queue_free()
	var p = null
	# Ice shelf: ice ledge -> pillar A -> pillar B -> landing ice (spikes below).
	p = await _spawn(lv, p, 25.0 * T, 9)
	await _jump_to(p, 1, 26.6 * T)
	_check(_on(p, 30, 32, 8), "ice shelf: ledge -> pillar A over spikes (%s)" % str(p.position))
	await _jump_to(p, 1, 32.6 * T)
	_check(_on(p, 36, 38, 7), "ice shelf: pillar A -> pillar B (%s)" % str(p.position))
	await _jump_to(p, 1, 38.6 * T)
	_check(_on(p, 43, 50, 9), "ice shelf: pillar B -> landing over a 4-wide spike gap (%s)" % str(p.position))
	# Hangar: walk off into the sea, sink onto L1, floaty jump onto the tall pillar.
	p = await _spawn(lv, p, 48.0 * T, 9)
	await _walk(p, 1, 54.0 * T)
	_check(_on(p, 51, 58, 13), "hangar: sinks onto the submerged ledge (%s)" % str(p.position))
	p = await _spawn(lv, p, 56.0 * T, 13)
	var y0: float = p.position.y
	var top := [y0]
	await _jump_to(p, 1, 57.5 * T, 40, 240, top)
	_check(_on(p, 59, 61, 8), "hangar: water jump climbs the 5-tile pillar (%s)" % str(p.position))
	_check(y0 - top[0] > 4.5 * T, "water jump rises %.1f tiles (dry jump ~3.9)" % ((y0 - top[0]) / T))
	p = await _spawn(lv, p, 60.5 * T, 8)
	await _jump_to(p, 1, 61.6 * T, 24, 240, [], false, 66.0 * T)  # steer onto P2 while sinking
	_check(_on(p, 65, 67, 14), "hangar: pillar -> P2 across the spiked seabed (%s)" % str(p.position))
	p = await _spawn(lv, p, 66.5 * T, 14)
	await _jump_to(p, 1, 67.6 * T, 40)
	_check(_on(p, 73, 75, 12), "hangar: P2 -> P3 (%s)" % str(p.position))
	p = await _spawn(lv, p, 74.5 * T, 12)
	await _jump_to(p, 1, 75.6 * T, 40)
	_check(_on(p, 78, 87, 8), "hangar: P3 -> exit ledge (%s)" % str(p.position))
	# Trench: sink down the shaft, cross the submerged tunnel's spike patches.
	p = await _spawn(lv, p, 86.0 * T, 8)
	await _walk(p, 1, 92.5 * T, 240)
	_check(_on(p, 91, 93, 18), "trench: sinks to the safe floor of the shaft (%s)" % str(p.position))
	for patch in [97, 103, 109]:
		p = await _spawn(lv, p, (patch - 2.0) * T, 18)
		await _jump_to(p, 1, (patch - 0.4) * T, 40)
		_check(_on(p, patch + 3, patch + 5, 18),
				"trench: tunnel spike patch at %d cleared (%s)" % [patch, str(p.position)])
	# Ballast tank: floor -> shelf 1 (bonk shelf 2) -> over its spikes -> exit floor.
	p = await _spawn(lv, p, 112.5 * T, 18)
	await _walk(p, 1, 114.5 * T)
	await _jump_to(p, 1, 114.5 * T, 40)
	_check(_on(p, 118, 120, 13), "tank: floor -> shelf 1 through the left gap (%s)" % str(p.position))
	p = await _spawn(lv, p, 119.5 * T, 13)
	await _jump_to(p, 1, 120.6 * T, 40)
	_check(_on(p, 123, 128, 13), "tank: jumps the spikes on shelf 1 (%s)" % str(p.position))
	p = await _spawn(lv, p, 126.5 * T, 13)
	await _jump_to(p, 1, 126.5 * T, 40)
	_check(_on(p, 129, 133, 8), "tank: shelf 1 -> exit floor through the right gap (%s)" % str(p.position))
	# Optional HP-up: a dash jump under the tank ceiling over 4 spikes, and back.
	p = await _spawn(lv, p, 123.5 * T, 8)
	await _dash_jump(p, -1, 122.3 * T)
	await _walk(p, -1, 114.5 * T)
	var hp_left := 0
	for c in lv.get_children():
		# Only the tank's HP-up (the hangar ledge one is tested in stage_link_test.gd).
		if c.get("kind") == "hp" and c.position.x > 100 * T and not c.is_queued_for_deletion():
			hp_left += 1
	_check(_on(p, 114, 117, 8) and hp_left == 0, "tank: dash jump under the ceiling reaches the HP-up (%s)" % str(p.position))
	await _walk(p, 1, 117.0 * T)
	await _dash_jump(p, 1, 117.7 * T)
	_check(_on(p, 122, 124, 8), "tank: and dash-jumps back (%s)" % str(p.position))
	# Reservoir: hop the ice floes (the 2-wide one is taken without stopping).
	p = await _spawn(lv, p, 132.0 * T, 8)
	await _jump_to(p, 1, 133.6 * T)
	_check(_on(p, 136, 138, 8), "reservoir: exit floor -> floe 1 (%s)" % str(p.position))
	await _jump_to(p, 1, 138.6 * T)
	_check(_on(p, 142, 144, 8), "reservoir: floe 1 -> floe 2 (%s)" % str(p.position))
	await _jump_to(p, 1, 144.6 * T, 24, 240, [], true)
	await _jump_to(p, 1, 149.0 * T)
	_check(_on(p, 153, 156, 8), "reservoir: floe 2 -> floe 3 -> far landing (%s)" % str(p.position))
	# Falling into the reservoir is recoverable: from the safe seabed under a floe, a
	# water jump rises above the floe tops.
	p = await _spawn(lv, p, 143.0 * T, 14)
	var fall_top := [p.position.y]
	await _jump_to(p, 1, 144.6 * T, 40, 240, fall_top)
	_check(fall_top[0] < 8.0 * T - 4.0, "reservoir: a water jump from the seabed clears the floes (top y %.0f)" % fall_top[0])
	# Corridor: drop to the boss door.
	p = await _spawn(lv, p, 155.0 * T, 8)
	await _walk(p, 1, 160.0 * T, 240)
	_check(_on(p, 157, 161, 13), "corridor: drop to the pre-boss checkpoint (%s)" % str(p.position))
	lv.queue_free()
	await process_frame


# --- boss --------------------------------------------------------------------------------

func test_fight() -> void:
	var lv = _load_level()
	var arena: Rect2 = lv.boss_arena
	var p = Player.new()
	p.scripted = true
	p.env = lv
	p.position = Vector2(arena.position.x + 60.0, arena.end.y - 1.0)
	lv.add_child(p)
	var b = Narwhal.new()
	b.arena = arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	_check(b.boss_name == "CRYO NARWHAL" and b.get_max_hp() == 32 and b.weakness == "heat_mirage"
			and b.contact_damage in [2, 3], "boss tunables: name, 32 HP, Heat Mirage weakness, contact damage")
	var states := {}
	var patterns := {}
	var p2_patterns := {}
	var inside := true
	var seen := {"icicle": false, "shard": false, "pillar": false}
	for i in 1020:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 90) % 2 == 0 else -1
		states[b.state] = true
		if b.pattern in Narwhal.PATTERNS:
			patterns[b.pattern] = true
			if b.phase2:
				p2_patterns[b.pattern] = true
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		for n in lv.get_children():
			if n.get_script() == Narwhal.Icicle:
				seen.icicle = true
			elif n.get_script() == Narwhal.Shard:
				seen.shard = true
			elif n.get_script() == Narwhal.IcePillar:
				seen.pillar = true
		if i == 360:
			b._invuln = 0.0
			b.take_damage(17)  # into phase 2
	_check(patterns.size() >= 3, "boss uses >= 3 attack patterns (%s)" % str(patterns.keys()))
	_check(states.size() >= 10, "boss visits many pattern states (%d)" % states.size())
	_check(inside, "boss stays inside its arena")
	_check(b.phase2, "boss enters phase 2 after 17 damage (hp %d)" % b.hp)
	_check(p2_patterns.has("wave") and seen.pillar, "phase 2 opens with the glacier wave (ice pillars)")
	_check(seen.shard == patterns.has("breath") and seen.icicle == patterns.has("rain"),
			"attacks fire their projectiles (%s)" % str(seen))
	b.queue_free()
	lv.queue_free()
	await process_frame


## Forces each attack on a fresh boss and checks its wind-up and its effect.
func test_each_pattern() -> void:
	for name in Narwhal.PATTERNS:
		var lv = _load_level()
		var arena: Rect2 = lv.boss_arena
		var p = Player.new()
		p.scripted = true
		p.env = lv
		p.position = Vector2(arena.position.x + 70.0, arena.end.y - 1.0)
		lv.add_child(p)
		var b = Narwhal.new()
		b.arena = arena
		b.position = lv.boss_spawn
		b.player = p
		lv.add_child(b)
		b._force_next = name
		b.phase2 = name == "wave"
		var windup: int = {"charge": Narwhal.S.CHARGE_WIND, "rain": Narwhal.S.RAIN_MARK,
				"breath": Narwhal.S.BREATH_WIND, "wave": Narwhal.S.WAVE_AIM}[name]
		var wound := false
		var effect := false
		var min_x := INF
		var max_x := -INF
		for i in 480:
			await physics_frame
			p.invuln_timer = 1.0
			if b.state == windup:
				wound = true
			if b.state == Narwhal.S.CHARGE:
				min_x = minf(min_x, b.position.x)
				max_x = maxf(max_x, b.position.x)
			for n in lv.get_children():
				if (name == "rain" and n.get_script() == Narwhal.Icicle) \
						or (name == "breath" and n.get_script() == Narwhal.Shard) \
						or (name == "wave" and n.get_script() == Narwhal.IcePillar):
					effect = true
			if name == "charge" and b.state == Narwhal.S.BONK:
				effect = max_x - min_x > arena.size.x * 0.6
			if effect and b.state == Narwhal.S.RECOVER:
				break
		_check(b.pattern == name and wound and effect and b.state == Narwhal.S.RECOVER,
				"%s: telegraphs, attacks, then recovers" % name)
		lv.queue_free()
		await process_frame


## The plain buster can win: an invulnerable scripted IX that only taps the buster,
## keeps some distance and jumps now and then defeats the boss.
func test_buster_only() -> void:
	var lv = _load_level()
	var arena: Rect2 = lv.boss_arena
	var p = Player.new()
	p.scripted = true
	p.env = lv
	p.position = Vector2(arena.position.x + 40.0, arena.end.y - 1.0)
	lv.add_child(p)
	var b = Narwhal.new()
	b.arena = arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	var frames := 0
	for i in 3600:
		await physics_frame
		frames = i
		if done[0]:
			break
		p.invuln_timer = 1.0
		if is_instance_valid(b):
			# Keep some distance and face the boss.
			var dx: float = b.position.x - p.position.x
			p.in_dir = 0
			if absf(dx) < 48.0:
				# Too close: back off, unless cornered against a wall.
				var cornered: bool = p.position.x < arena.position.x + 40.0 or p.position.x > arena.end.x - 40.0
				p.in_dir = int(signf(dx)) if cornered else -int(signf(dx))
			elif (i / 30) % 6 == 0:
				p.in_dir = int(signf(dx))
			if p.in_dir == 0 and p.facing != int(signf(dx)) and dx != 0.0:
				p.in_dir = int(signf(dx))
		p.in_shoot = i % 10 < 5
		p.in_jump = (i % 70) < 22 and (i / 70) % 2 == 1
	_check(done[0], "buster-only IX defeats the boss (%.1f s)" % (frames / 60.0))
	lv.queue_free()
	await process_frame


func test_weakness() -> void:
	var lv = _load_level()
	var b = Narwhal.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	lv.add_child(b)
	await _frames(2)
	b.active = true
	b.state = Narwhal.S.CHARGE
	var hp0: int = b.hp
	b.take_damage(3, "heat_mirage")
	_check(hp0 - b.hp == ceili(3 * 2.5), "Heat Mirage hits x2.5 (%d -> %d)" % [hp0, b.hp])
	_check(b.state == Narwhal.S.STAGGER, "Heat Mirage interrupts the charge (stagger)")
	b._invuln = 0.0
	b.state = Narwhal.S.CHARGE
	hp0 = b.hp
	b.take_damage(3, "heat_mirage")
	_check(hp0 - b.hp == 8 and b.state == Narwhal.S.CHARGE, "stagger has a cooldown (no stun lock)")
	b._invuln = 0.0
	hp0 = b.hp
	b.take_damage(2, "buster")
	_check(hp0 - b.hp == 2, "buster damage is not boosted")
	# After the cooldown a weakness hit staggers again and melts pending ice pillars.
	await _frames(int(b.stagger_cooldown * 60.0) + 5)
	b._invuln = 0.0
	b.position = Vector2(b.arena.position.x + 30.0, b._lane_y)
	b._slam()
	await _frames(2)
	var pillars := 0
	for n in lv.get_children():
		if n.get_script() == Narwhal.IcePillar and not n.is_queued_for_deletion():
			pillars += 1
	b.take_damage(1, "heat_mirage")
	var left := 0
	for n in lv.get_children():
		if n.get_script() == Narwhal.IcePillar and not n.is_queued_for_deletion():
			left += 1
	_check(pillars > 5 and left == 0 and b.state == Narwhal.S.STAGGER,
			"stagger after the cooldown melts the glacier wave (%d pillars -> %d)" % [pillars, left])
	lv.queue_free()
	await process_frame


func test_defeat() -> void:
	var lv = _load_level()
	var b = Narwhal.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	lv.add_child(b)
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	await _frames(80)  # intro
	_check(b.active, "boss becomes active after its intro")
	b._invuln = 0.0
	_check(b.take_damage(99), "lethal damage reports the kill")
	for i in 150:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "death sequence emits defeated and frees the boss")
	var leftovers := 0
	for n in lv.get_children():
		if n.is_in_group("enemy_shot") or n.is_in_group("damaging"):
			leftovers += 1
	_check(leftovers == 0, "no boss projectiles left behind")
	lv.queue_free()
	await process_frame


# --- helpers -----------------------------------------------------------------------------

func _load_level():
	var lv = Level.new()
	lv.stage_id = "cryo_narwhal"
	root.add_child(lv)
	lv.load_from_file(STAGE)
	return lv


func _find_cells(lv, ch: String) -> Array:
	var out := []
	for y in lv.height:
		for x in lv.width:
			if lv.cell(x, y) == ch:
				out.append(Vector2i(x, y))
	return out


## Standing (feet on the top of `top_row`) with the centre over columns x0..x1.
func _on(p, x0: int, x1: int, top_row: int) -> bool:
	return p.is_alive() and p.is_on_floor() and absf(p.position.y - top_row * T) < 1.0 \
			and p.position.x >= x0 * T - 5.0 and p.position.x <= (x1 + 1) * T + 5.0


## A live scripted neutral IX standing at `x` on the top of `top_row` (respawned if the
## previous section killed it, so one failure does not hide the rest).
func _spawn(lv, p, x: float, top_row: int):
	if p == null or not p.is_alive():
		if p != null:
			p.queue_free()
		p = Player.new()
		p.scripted = true
		p.env = lv
		lv.add_child(p)
	p.position = Vector2(x, top_row * T)
	p.velocity = Vector2.ZERO
	p.in_dir = 0
	p.in_jump = false
	await _frames(10)
	return p


## Walks toward `x` (falling / sinking on the way) and stops once there and grounded.
func _walk(p, dir: int, x: float, limit := 180) -> void:
	p.in_dir = dir
	for i in limit:
		await physics_frame
		if (p.position.x - x) * dir >= 0.0:
			p.in_dir = 0
		if p.in_dir == 0 and p.is_on_floor():
			break
		if not p.is_alive():
			break
	p.in_dir = 0
	await _settle(p)


func _settle(p) -> void:
	for i in 90:
		await physics_frame
		if p.is_on_floor() and absf(p.velocity.x) < 1.0:
			break


## Holds `dir`, jumps once the grounded player passes `takeoff_x` (jump held `hold`
## frames), keeps steering until landing (or until past `stop_x`), then lets go (ice
## may slide a little). `top` (optional [y]) records the highest point. `chain` keeps
## holding after landing.
func _jump_to(p, dir: int, takeoff_x: float, hold := 24, limit := 240, top := [], chain := false,
		stop_x := INF) -> void:
	p.in_dir = dir
	var jumped := false
	var airborne := false
	var held := 0
	for i in limit:
		if not jumped and p.is_on_floor() and (p.position.x - takeoff_x) * dir >= 0.0:
			jumped = true
			p.in_jump = true
		elif jumped:
			held += 1
			if held >= hold:
				p.in_jump = false
		await physics_frame
		if not top.is_empty():
			top[0] = minf(top[0], p.position.y)
		if jumped and not p.is_on_floor():
			airborne = true
		if airborne and stop_x != INF and (p.position.x - stop_x) * dir >= 0.0:
			p.in_dir = 0
		if (airborne and p.is_on_floor()) or not p.is_alive():
			break
	p.in_jump = false
	if chain:
		return
	p.in_dir = 0
	await _settle(p)


## Dashes toward `dir` and jumps once past `takeoff_x`; holds both until landing.
func _dash_jump(p, dir: int, takeoff_x: float) -> void:
	p.in_dir = dir
	p.in_dash = true
	var jumped := false
	var airborne := false
	for i in 120:
		if not jumped and p.is_on_floor() and (p.position.x - takeoff_x) * dir >= 0.0:
			jumped = true
			p.in_jump = true
		await physics_frame
		if jumped and not p.is_on_floor():
			airborne = true
		if (airborne and p.is_on_floor()) or not p.is_alive():
			break
	p.in_dir = 0
	p.in_dash = false
	p.in_jump = false
	await _settle(p)


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
