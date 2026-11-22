extends SceneTree
## GRAVITY ALBATROSS: stage layout, route checks and boss fight (headless).
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/boss_gravity_albatross_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const Albatross = preload("res://scripts/enemies/gravity_albatross.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const STAGE := "res://levels/gravity_albatross.txt"
const T := 16.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_stage_layout()
	await test_low_gravity_route()
	await test_lift_route()
	await test_mover_route()
	await test_relay_needs_flight()
	await test_relay_and_boss_doors()
	await test_fight()
	await test_weakness_and_death()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- stage ---------------------------------------------------------------------------

func test_stage_layout() -> void:
	var lv = _level()
	var m: Dictionary = lv.meta
	_check(m.get("id") == "gravity_albatross" and m.get("name") == "GRAVITY ALBATROSS"
			and m.get("order") == "2" and m.get("desc", "").contains("REFRACTION BEAM"),
			"metadata: id / name / order / desc")
	_check(m.get("boss") == "res://scripts/enemies/gravity_albatross.gd" and m.get("weapon") == "gravity_wing",
			"metadata: boss script and Gravity Wing reward")
	_check(m.get("hidden_boss") == "res://scripts/enemies/fragment_lambda.gd" and m.get("hidden_id") == "fragment"
			and m.get("hidden_require") == "bosses:6+eclipse", "metadata: hidden boss FRAGMENT")
	_check(lv.has_boss(), "stage has a boss room")
	_check(lv.boss_arena.size == Vector2(352, 176), "main arena is 22 x 11 tiles (%s)" % str(lv.boss_arena.size))
	_check(lv.has_arena("hidden") and lv.arenas.hidden.rect.size == Vector2(352, 176),
			"hidden arena (b / d / Y) is 22 x 11 tiles")
	_check(lv.arenas.main.door != null and lv.arenas.hidden.door != null, "both arenas have a door")
	_check(lv.width >= 150 and lv.width <= 190 and lv.height >= 20, "stage size %dx%d" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO and lv.checkpoints.size() == 2, "spawn and 2 checkpoints")
	var parts := []
	var hp_tanks := 0
	var movers := {"m": 0, "n": 0}
	for c in lv.get_children():
		if c.get("part_id") != null and c.get("kind") == "part":
			parts.append(c.part_id)
		elif c.get("kind") == "hp":
			hp_tanks += 1
		elif c is AnimatableBody2D:
			movers["m" if c.axis == Vector2.RIGHT else "n"] += 1
	_check(parts == ["aero_leg"], "Aero LEG capsule (GDD §4-4) %s" % str(parts))
	_check(hp_tanks == 1, "one optional HP-up")
	_check(movers.m >= 2 and movers.n >= 2, "moving platforms: %d slide, %d bob" % [movers.m, movers.n])
	var zones := {"lowg": 0, "lift": 0}
	for y in lv.height:
		for x in lv.width:
			var z: String = lv.zone_at(Vector2(x * T + 8.0, y * T + 8.0))
			if zones.has(z):
				zones[z] += 1
	_check(zones.lowg > 100 and zones.lift > 50, "low-g zones and updraft lifts (%s)" % str(zones))
	var reg: Array = Level.load_registry("res://levels")
	var ids := reg.map(func(s): return s.id)
	_check(ids.has("gravity_albatross") and ids.find("gravity_albatross") > ids.find("prism_gecko"),
			"registry lists the stage after Prism Gecko %s" % str(ids))
	await _free(lv)


# --- routes (neutral IX, no armor) ------------------------------------------------------

## Low-g bay: the 6-tile step, then stepping stones over the spike pit.
func test_low_gravity_route() -> void:
	var lv = _level()
	var got := []
	lv.pickup_collected.connect(func(pk) -> void: got.append(pk.part_id))
	var p = await _put(lv, Vector2(19 * T + 8.0, 29 * T))
	# Capsule shelf: rise straight up in low gravity, then drift over it.
	p.in_jump = true
	for i in 180:
		var dx: float = 16.5 * T - p.position.x
		p.in_dir = 0 if i < 54 or absf(dx) < 3.0 else int(signf(dx))
		await physics_frame
		if i > 60 and p.is_on_floor():
			break
	p.in_jump = false
	p.in_dir = 0
	_check(got.has("aero_leg") and absf(p.position.y - 18 * T) < 1.0,
			"low gravity: a high jump reaches the Aero LEG shelf")
	p.position = Vector2(19 * T + 8.0, 29 * T - 1.0)
	p.velocity = Vector2.ZERO
	await _frames(4)
	var ok: bool = await _hop(p, 24 * T, 23 * T)
	_check(ok, "low gravity: jump onto the 6-tile step")
	p.position.x = 26 * T + 8.0
	await _frames(2)
	var route := [[31 * T, 24 * T], [36 * T, 21 * T], [40 * T, 24 * T], [45 * T, 22 * T]]
	for spot in route:
		ok = ok and await _hop(p, spot[0], spot[1])
	_check(ok and p.is_alive(), "low gravity: spike pit crossed on the stepping stones")
	await _free(lv)


## Lift up the 11-tile wall, then ride the updraft chain over the spike floor.
func test_lift_route() -> void:
	var lv = _level()
	var p = await _put(lv, Vector2(51 * T, 29 * T))
	var on_top := false
	for i in 240:
		p.in_dir = 1 if p.position.x < 58 * T else 0
		await physics_frame
		if p.is_on_floor() and absf(p.position.y - 18 * T) < 1.0 and p.position.x > 57 * T:
			on_top = true
			break
	_check(on_top, "updraft lift carries IX up the 11-tile wall")
	var landed := false
	for i in 900:
		var c: Vector2 = p.position + Vector2(0, -13)
		if lv.zone_at(c) == "lift":
			p.in_dir = 1 if c.y < _lift_top(lv, c.x) + 4.0 else 0
		else:
			p.in_dir = 1
		await physics_frame
		if not p.is_alive():
			break
		if p.is_on_floor() and p.position.x > 82 * T:
			landed = absf(p.position.y - 18 * T) < 1.0
			break
	_check(landed and p.is_alive(), "lift chain over the spikes reaches the mid checkpoint")
	await _free(lv)


## Teach: ride the slide platform over the spike trench, the bobbing one up to S.
## Test (bottomless pit): slide platform M1 -> bobbing N1 (at its top) -> ledge H.
func test_mover_route() -> void:
	var lv = _level()
	var mt = _mover(lv, 93, 29)
	var nt = _mover(lv, 105, 25)
	var m1 = _mover(lv, 117, 21)
	var n1 = _mover(lv, 124, 21)
	if null in [mt, nt, m1, n1]:
		_check(false, "D section movers found")
		await _free(lv)
		return
	var p = await _put(lv, Vector2(88 * T + 8.0, 29 * T))
	await _wait_phase(mt, -0.95, false)
	for i in 50:
		p.in_dir = 1 if p.position.x < mt.position.x + 32.0 else 0
		await physics_frame
	p.in_dir = 0
	await _wait_phase(mt, 0.95, true)
	for i in 60:
		p.in_dir = 1
		await physics_frame
		if p.position.x > 101 * T:
			break
	p.in_dir = 0
	_check(p.is_alive() and p.is_on_floor() and absf(p.position.y - 29 * T) < 1.0 and p.position.x > 100 * T,
			"slide platform carries IX over the spike trench")
	p.position = Vector2(103 * T + 8.0, 29 * T - 1.0)
	await _frames(4)
	await _wait_phase(nt, -0.95, false)
	var at_nt := func() -> bool: return p.position.x > 105 * T and p.position.x < 108 * T
	var at_s := func() -> bool: return p.position.x > 108 * T and absf(p.position.y - 21 * T) < 1.0
	var on_nt: bool = await _jump_to(p, at_nt)
	await _wait_phase(nt, 0.95, true)
	var on_s: bool = await _jump_to(p, at_s)
	_check(on_nt and on_s, "bobbing platform lifts IX onto the 6-tile block")
	p.position = Vector2(112 * T + 8.0, 21 * T - 1.0)
	await _frames(4)
	# Board M1 at its left end, ride to the right end: N1 is at its top then.
	await _wait_phase(m1, -0.95, false)
	for i in 60:
		p.in_dir = 1 if p.position.x < m1.position.x + 24.0 else 0
		await physics_frame
	p.in_dir = 0
	var ok: bool = p.is_on_floor() and absf(p.position.y - 21 * T) < 2.0
	await _wait_phase(m1, 0.93, true)
	var at_n1 := func() -> bool: return p.position.x > n1.position.x and p.position.x < n1.position.x + 48.0
	var at_h := func() -> bool: return p.position.x > 128 * T - 6.0 and absf(p.position.y - 19 * T) < 1.0
	var on_n1: bool = await _jump_to(p, at_n1)
	var on_h: bool = await _jump_to(p, at_h)
	_check(ok and on_n1 and on_h, "moving platforms: M1 -> N1 -> ledge H with plain jumps")
	await _free(lv)


## The relay lift hangs out of reach of a plain jump; Aero LEG flight reaches it.
func test_relay_needs_flight() -> void:
	var lv = _level()
	var under := Vector2(152 * T, 29 * T)
	var p = await _put(lv, under)
	var touched := false
	var rise := 0.0
	for i in 70:
		p.in_jump = i < 40
		p.in_dir = 0
		await physics_frame
		rise = maxf(rise, under.y - p.position.y)
		if lv.zone_at(p.position + Vector2(0, -13)) == "lift":
			touched = true
	_check(not touched and rise > 55.0, "neutral jump (%.0f px) cannot reach the relay lift" % rise)
	await _free(lv)
	# The relay hatches only open once this stage's boss is beaten (GDD §5-4, `; @alt`).
	lv = _level(true)
	p = await _put(lv, under)
	p.apply_loadout({"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "aero"})
	p.set_core(100.0)
	p.in_jump = true
	await _frames(20)
	p.in_jump = false
	await _frames(2)
	p.in_jump = true
	var up := false
	for i in 200:
		await physics_frame
		if p.position.y < 12 * T:
			up = true
			break
	p.in_jump = false
	_check(up, "Aero LEG flight reaches the relay lift and rides it to the upper relay")
	p.in_dir = 1
	var landed := false
	for i in 90:
		await physics_frame
		if p.is_on_floor() and absf(p.position.y - 12 * T) < 1.0:
			landed = true
			break
	p.in_dir = 0
	_check(landed, "upper relay floor is walkable next to the lift")
	await _free(lv)


## Upper relay: float over the spike strip into the hidden room (its trigger
## fires), then walk back through the lift column and drop into the hangar.
## The hangar leads on into the main boss room. Loaded in the after-boss layout: the
## return-drop hatch is sealed until then (as is the hidden room, which needs bosses:6).
func test_relay_and_boss_doors() -> void:
	var lv = _level(true)
	var kinds := []
	lv.boss_triggered.connect(func(kind: String) -> void: kinds.append(kind))
	var p = await _put(lv, Vector2(154 * T + 8.0, 12 * T))
	var ok: bool = await _hop(p, 161.5 * T, 12 * T)
	for i in 120:
		p.in_dir = 1
		await physics_frame
		if p.position.x > 168 * T:
			break
	p.in_dir = 0
	await _frames(3)
	_check(ok and kinds == ["hidden"], "upper relay: low-g float over the spikes, hidden room trigger fires")
	p.position = Vector2(161.5 * T, 12 * T - 1.0)
	await _frames(4)
	ok = await _hop(p, 154 * T + 8.0, 12 * T)
	var down := false
	for i in 400:
		p.in_dir = -1 if p.position.x > 146 * T else 0
		await physics_frame
		if p.is_on_floor() and absf(p.position.y - 29 * T) < 1.0:
			down = true
			break
	p.in_dir = 0
	_check(ok and down and p.position.x > 135 * T, "return shaft drops back into the hangar")
	p.position = Vector2(159 * T + 8.0, 29 * T - 1.0)
	await _frames(4)
	for i in 120:
		p.in_dir = 1
		await physics_frame
		if p.position.x > 167 * T:
			break
	p.in_dir = 0
	await _frames(3)
	_check(kinds == ["hidden", "main"], "hangar checkpoint -> boss door -> main trigger fires")
	await _free(lv)


# --- boss ------------------------------------------------------------------------------

func test_fight() -> void:
	var lv = _level()
	var arena: Rect2 = lv.boss_arena
	var p = await _put(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _boss(lv, p)
	var seen := {}
	var inside := true
	var pulled := false
	var dived := false
	for i in 900:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 90) % 2 == 0 else -1
		if Albatross.PATTERN_STATES.has(b.state):
			seen[b.state] = true
		pulled = pulled or b.pulling
		dived = dived or b.state == Albatross.S.DIVE
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if i == 420:
			b.take_damage(17)
			_check(b.phase2, "boss enters phase 2 after 17 damage (hp %d)" % b.hp)
	_check(seen.size() >= 3, "boss cycles through %d attack patterns %s" % [seen.size(), str(seen.keys())])
	_check(pulled, "gravity well pulls the player")
	_check(inside, "boss stays inside its arena")
	await _free(lv)


func test_weakness_and_death() -> void:
	var lv = _level()
	var arena: Rect2 = lv.boss_arena
	var p = await _put(lv, Vector2(arena.position.x + 60.0, arena.end.y - 1.0))
	var b = _boss(lv, p)
	for i in 90:
		p.invuln_timer = 1.0
		await physics_frame
	_check(b.active, "intro ends, boss is active")
	b.state = Albatross.S.FEATHER
	b.take_damage(2, "buster")
	_check(b.hp == 30 and b.state == Albatross.S.FEATHER, "buster deals plain damage, no stagger")
	b._invuln = 0.0
	var hp0: int = b.hp
	b.take_damage(3, "refraction_beam")
	_check(hp0 - b.hp == ceili(3 * 2.5) and b.state == Albatross.S.STAGGER and b.staggers == 1,
			"Refraction Beam: x2.5 damage (%d) and a stagger" % (hp0 - b.hp))
	b._invuln = 0.0
	b.state = Albatross.S.FEATHER
	hp0 = b.hp
	b.take_damage(3, "refraction_beam")
	_check(hp0 - b.hp == 8 and b.staggers == 1 and b.state == Albatross.S.FEATHER,
			"weakness stagger respects the cooldown (no stun lock)")
	for i in 160:
		p.invuln_timer = 1.0
		await physics_frame
	b._invuln = 0.0
	b.take_damage(1, "refraction_beam")
	_check(b.staggers == 2, "stagger available again after the cooldown")
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	b._invuln = 0.0
	b.take_damage(99)
	for i in 150:
		p.invuln_timer = 1.0
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "lethal damage plays the death sequence and emits defeated")
	await _free(lv)


# --- helpers ------------------------------------------------------------------------------

## after = true: every `; @alt` / `; @change` requirement met (boss already beaten).
func _level(after := false):
	var lv = Level.new()
	lv.stage_id = "gravity_albatross"
	if after:
		lv.condition = func(_r): return true
	root.add_child(lv)
	lv.load_from_file(STAGE)
	for c in lv.get_children():
		if c.is_in_group("enemy"):
			c.queue_free()
	return lv


func _put(lv, feet: Vector2):
	var p = Player.new()
	p.scripted = true
	p.position = feet - Vector2(0, 1)
	lv.add_child(p)
	p.env = lv
	await _frames(4)
	return p


func _boss(lv, p):
	var b = Albatross.new()
	b.arena = lv.boss_arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	return b


## Jumps (full hold) and steers toward x; true once standing at floor height y.
func _hop(p, x: float, y: float) -> bool:
	p.in_jump = false
	await physics_frame
	p.in_jump = true
	for i in 420:
		var dx: float = x - p.position.x
		p.in_dir = 0 if absf(dx) < 3.0 else int(signf(dx))
		await physics_frame
		if not p.is_alive():
			break
		if i > 4 and p.is_on_floor() and absf(p.position.y - y) < 1.0 and absf(dx) < 12.0:
			p.in_jump = false
			p.in_dir = 0
			return true
	p.in_jump = false
	p.in_dir = 0
	return false


## Full jump to the right; true once on the floor where `landed` holds.
func _jump_to(p, landed: Callable) -> bool:
	p.in_jump = false
	await physics_frame
	p.in_jump = true
	p.in_dir = 1
	var ok := false
	for i in 90:
		await physics_frame
		if i > 4 and p.is_on_floor():
			ok = landed.call()
			break
	p.in_jump = false
	p.in_dir = 0
	return ok


func _mover(lv, cx: int, cy: int):
	for c in lv.get_children():
		if c is AnimatableBody2D and c.rect.position == Vector2(cx * T, cy * T):
			return c
	return null


## -1 .. 1 along the mover's axis (1 = right end / top).
func _phase(mover) -> float:
	return (mover.position - mover.rect.position).dot(mover.axis) / 48.0


func _wait_phase(mover, value: float, above: bool) -> void:
	for i in 400:
		await physics_frame
		var ph := _phase(mover)
		if (above and ph > value) or (not above and ph < value):
			return


## Top edge (world y) of the lift column under world x.
func _lift_top(lv, x: float) -> float:
	var cx := floori(x / T)
	for y in lv.height:
		if lv.cell(cx, y) == "|":
			return y * T
	return 0.0


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _free(node: Node) -> void:
	for s in get_nodes_in_group("enemy_shot"):
		s.queue_free()
	node.queue_free()
	await process_frame
	await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
