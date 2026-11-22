extends SceneTree
## Headless movement / combat / armor / stage / save tests.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/run_tests.gd

const Player = preload("res://scripts/player/player.gd")
const Level = preload("res://scripts/level/level.gd")
const Breakable = preload("res://scripts/level/breakable.gd")
const Shockwave = preload("res://scripts/combat/shockwave.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const FLOOR := Rect2(-400, 100, 1200, 32)
const N := "neutral"
const V := "vanguard"
const A := "aero"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	await test_landing()
	await test_walk_speed()
	await test_jump_height()
	await test_jump_cut()
	await test_dash_distance()
	await test_dash_jump_reach()
	await test_wall_slide()
	await test_single_wall_climb()
	await test_buster_limit()
	await test_charge_levels()
	await test_iframes()
	await test_shot_hits_wall()
	await test_hazards()
	await test_air_dash()
	await test_flight()
	await test_glide()
	await test_dash_chain()
	await test_dual_core()
	await test_vanguard_body()
	await test_spread_shot()
	await test_breaker()
	await test_overdrive()
	await test_skybreaker()
	await test_level_file()
	await test_prism_stage()
	await test_boss()
	test_save_roundtrip()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- collision regression tests -------------------------------------------------------

func test_shot_hits_wall() -> void:
	var w := _world([FLOOR, Rect2(60, 40, 16, 60)])
	var p = await _grounded(w)
	p.in_shoot = true
	await _frames(2)
	p.in_shoot = false
	await _frames(25)
	_check(_count_shots(0) == 0, "tap shot stops at a wall (moving Area2D vs StaticBody2D)")
	await _free(w)


func test_hazards() -> void:
	var w := _world([FLOOR])
	var spikes := Area2D.new()
	spikes.add_to_group("hazard")
	spikes.collision_layer = 32
	spikes.monitoring = false
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 8)
	cs.shape = shape
	cs.position = Vector2(80, 96)
	spikes.add_child(cs)
	w.add_child(spikes)
	var zone = load("res://scripts/level/damage_zone.gd").new()
	zone.collision_layer = 32
	var zs := CollisionShape2D.new()
	var zshape := RectangleShape2D.new()
	zshape.size = Vector2(4, 60)
	zs.shape = zshape
	zs.position = Vector2(-40, 70)
	zone.add_child(zs)
	w.add_child(zone)
	var p = await _grounded(w)
	var hp0: int = p.hp
	p.in_dir = -1
	await _frames(40)
	_check(p.hp == hp0 - zone.damage, "laser beam zone deals its damage once (hp %d)" % p.hp)
	p.in_dir = 1
	p.invuln_timer = 0.0
	await _frames(90)
	_check(p.state == Player.State.DEAD, "spikes kill on touch")
	await _free(w)


# --- armor tests -------------------------------------------------------------------

func test_air_dash() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, N, N, A))
	p.in_jump = true
	await _frames(12)
	var y0: float = p.position.y
	var x0: float = p.position.x
	p.in_dash = true
	await _frames(11)
	_check(p.position.x - x0 > 30.0 and absf(p.position.y - y0) < 1.0,
			"Aero LEG: air dash keeps altitude (dx=%.0f, dy=%.1f)" % [p.position.x - x0, p.position.y - y0])
	p.in_dash = false
	p.in_jump = false
	await _wait_land(p)
	p.apply_loadout(_lo(N, N, N, N))
	p.in_jump = true
	await _frames(12)
	x0 = p.position.x
	p.in_dash = true
	await _frames(10)
	_check(not p.air_dashing and absf(p.position.x - x0) < 1.0, "no air dash without Aero LEG")
	await _free(w)


func test_flight() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, N, N, A))
	p.set_core(100.0)
	p.in_jump = true
	await _frames(30)
	p.in_jump = false
	await _frames(2)
	var y0: float = p.position.y
	p.in_jump = true
	await _frames(20)
	_check(p.position.y < y0 - 15.0 and p.core < 100.0,
			"Aero LEG: second jump press flies up and spends core (core=%.0f)" % p.core)
	await _free(w)


func test_glide() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, A, N, N))
	p.in_jump = true
	await _frames(40)
	_check(p.gliding and p.velocity.y <= p.glide_fall_speed + 0.01,
			"Aero BODY: holding jump while falling glides (vy=%.0f)" % p.velocity.y)
	await _free(w)


func test_dash_chain() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, N, N, V))
	var x0: float = p.position.x
	p.in_dash = true
	await _frames(10)
	p.in_dash = false
	await _frames(2)
	p.in_dash = true
	await _frames(40)
	var dx: float = p.position.x - x0
	_check(dx > 105.0, "Vanguard LEG: re-press chains a second dash (%.0f px)" % dx)
	await _free(w)


func test_dual_core() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(A, A, V, V))
	p.in_dir = 1
	p.in_dash = true
	p.in_jump = true
	await _frames(3)
	_check(p.air_dashes_left == 1, "hybrid 2+2: dash jump grants one air dash")
	p.in_dash = false
	await _frames(1)
	p.in_dash = true
	await _frames(2)
	_check(p.air_dashing, "hybrid 2+2: that air dash can be used")
	await _free(w)


func test_vanguard_body() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, V, N, N))
	p.in_dash = true
	await _frames(2)
	var hp0: int = p.hp
	p.take_damage(4, p.position.x - 10.0)
	_check(p.hp == hp0 - 2 and p.state == Player.State.DASH,
			"Vanguard BODY: half damage while dashing and no knockback")
	await _free(w)


func test_spread_shot() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(N, N, A, N))
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(2)
	_check(_count_shots(1) == 3, "Aero ARM: charge shot splits into 3")
	await _free(w)


func test_breaker() -> void:
	var w := _world([FLOOR])
	var wall = Breakable.new()
	wall.rect = Rect2(60, 68, 16, 32)
	w.add_child(wall)
	var p = await _grounded(w)
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(20)
	_check(is_instance_valid(wall) and not wall.is_queued_for_deletion(),
			"neutral charge shot does not break a cracked wall")
	p.apply_loadout(_lo(N, N, V, N))
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(20)
	_check(not is_instance_valid(wall) or wall.is_queued_for_deletion(),
			"Vanguard ARM charge shot breaks a cracked wall")
	await _free(w)


func test_overdrive() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(V, V, V, V))
	p.set_core(100.0)
	var x0: float = p.position.x
	p.in_special = true
	await _frames(2)
	p.in_special = false
	_check(p.state == Player.State.SPECIAL, "full Vanguard set: Overdrive Rush starts at full core")
	await _frames(40)
	_check(p.position.x - x0 > 180.0 and p.core < 5.0,
			"Overdrive Rush travels %.0f px and spends the core" % (p.position.x - x0))
	await _free(w)


func test_skybreaker() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.apply_loadout(_lo(A, A, A, A))
	p.set_core(100.0)
	p.in_special = true
	await _frames(2)
	p.in_special = false
	var waves := 0
	for i in 90:
		await physics_frame
		waves = 0
		for c in w.get_children():
			if c.get_script() == Shockwave:
				waves += 1
		if waves > 0:
			break
	_check(waves == 2, "full Aero set: Sky Breaker dives and sends 2 shockwaves")
	await _free(w)


func test_prism_stage() -> void:
	var lv = Level.new()
	lv.stage_id = "prism_gecko"
	root.add_child(lv)
	lv.load_from_file("res://levels/prism_gecko.txt")
	_check(lv.has_boss(), "Prism Gecko stage has a boss spawn")
	_check(lv.boss_arena.size == Vector2(22 * 16, 11 * 16),
			"boss arena detected (%s)" % str(lv.boss_arena.size))
	_check(lv.lasers.size() == 3, "3 laser emitters (%d)" % lv.lasers.size())
	var reflected := false
	for laser in lv.lasers:
		if laser.segments.size() == 2:
			reflected = true
	_check(reflected, "mirror bends a laser beam")
	_check(lv.breakables.size() == 1, "one cracked wall")
	var capsule := false
	for c in lv.get_children():
		if c.get("part_id") == "vanguard_head":
			capsule = true
	_check(capsule, "Vanguard HEAD capsule is in the Prism Gecko stage")
	lv.queue_free()
	await process_frame


func test_boss() -> void:
	var Gecko = load("res://scripts/enemies/prism_gecko.gd")
	var lv = Level.new()
	lv.stage_id = "prism_gecko"
	root.add_child(lv)
	lv.load_from_file("res://levels/prism_gecko.txt")
	var arena: Rect2 = lv.boss_arena
	var p = Player.new()
	p.scripted = true
	p.position = Vector2(arena.position.x + 60.0, arena.end.y - 1.0)
	lv.add_child(p)
	var b = Gecko.new()
	b.arena = arena
	b.position = lv.boss_spawn
	b.player = p
	lv.add_child(b)
	var seen := {}
	var inside := true
	var done := [false]
	b.defeated.connect(func() -> void: done[0] = true)
	for i in 900:
		await physics_frame
		p.invuln_timer = 1.0  # keep the player alive; we only watch the boss
		p.in_dir = 1 if (i / 90) % 2 == 0 else -1
		seen[b.state] = true
		if not arena.grow(1.0).has_point(b.position):
			inside = false
		if i == 420:
			b.take_damage(17)  # into phase 2
	_check(b.phase2, "boss enters phase 2 at half HP")
	_check(seen.size() >= 6, "boss cycles through its patterns (%d states seen)" % seen.size())
	_check(inside, "boss stays inside its arena")
	b._invuln = 0.0
	b.take_damage(99)
	for i in 150:
		await physics_frame
	_check(done[0] and not is_instance_valid(b), "boss death sequence emits defeated")
	lv.queue_free()
	await process_frame


func test_save_roundtrip() -> void:
	var GameScript = load("res://scripts/autoload/game.gd")
	var path := "user://test_save.json"
	var g = GameScript.new()
	g.save_path = path
	g.new_game()
	_check(not g.set_slot("head", V), "cannot equip a locked part")
	g.unlock("vanguard_head")
	g.unlock("aero_leg")
	g.set_slot("head", V)
	g.set_slot("leg", A)
	g.save_preset(1)
	g.collect("prism_gecko_hp_130_16")
	g.add_hp_bonus(2)
	g.mark_cleared("training")
	g.save_game()
	var g2 = GameScript.new()
	g2.save_path = path
	g2.new_game()
	_check(g2.load_game(), "save file loads")
	_check(g2.loadout() == _lo(V, N, N, A), "loadout restored")
	_check(g2.preset(1) == _lo(V, N, N, A) and g2.preset(0) == null, "presets restored")
	_check(g2.max_hp() == 18 and g2.is_cleared("training") and g2.is_collected("prism_gecko_hp_130_16"),
			"progress restored (HP, clears, pickups)")
	_check(g2.stats.reveal and g2.stats.flight, "stats recomputed from the loaded loadout")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f = null
	var g3 = GameScript.new()
	g3.save_path = path
	g3.new_game()
	_check(not g3.load_game() and g3.loadout() == _lo(N, N, N, N), "broken save file is rejected safely")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	g.free()
	g2.free()
	g3.free()


# --- tests ---------------------------------------------------------------------

func test_landing() -> void:
	var w := _world([FLOOR])
	var p = _player(w, Vector2(0, 40))
	await _frames(60)
	_check(p.is_on_floor() and absf(p.position.y - 100.0) < 1.0,
			"falls and lands on the floor (y=%.2f)" % p.position.y)
	await _free(w)


func test_walk_speed() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	var x0: float = p.position.x
	p.in_dir = 1
	await _frames(30)
	var dx: float = p.position.x - x0
	_check(absf(dx - 45.0) <= 2.0, "walk: 30 frames -> %.1f px (expect ~45)" % dx)
	await _free(w)


func test_jump_height() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	var rise: float = await _max_rise(p, 70, 999)
	_check(rise > 55.0 and rise < 66.0, "full jump height %.1f px (expect ~63)" % rise)
	await _free(w)


func test_jump_cut() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	var rise: float = await _max_rise(p, 70, 4)
	_check(rise > 15.0 and rise < 30.0, "tap jump height %.1f px (variable jump)" % rise)
	await _free(w)


func test_dash_distance() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	var x0: float = p.position.x
	p.in_dash = true
	await _frames(40)
	var dx: float = p.position.x - x0
	_check(dx > 70.0 and dx < 82.0, "dash distance %.1f px (expect ~77)" % dx)
	_check(p.state != Player.State.DASH, "dash ends on its own while the button is held")
	await _free(w)


func test_dash_jump_reach() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.in_dir = 1
	await _frames(10)
	var x0: float = p.position.x
	p.in_jump = true
	await _frames(3)
	await _wait_land(p)
	var normal: float = p.position.x - x0
	p.in_jump = false
	p.in_dir = 0
	await _frames(5)

	x0 = p.position.x
	p.in_dir = 1
	p.in_dash = true
	p.in_jump = true
	await _frames(3)
	await _wait_land(p)
	var dashed: float = p.position.x - x0
	_check(dashed > normal * 1.8,
			"dash jump reach %.0f px vs running jump %.0f px" % [dashed, normal])
	_check(normal < 7 * 16, "running jump cannot clear the 7-tile spike gap (%.0f px)" % normal)
	_check(dashed > 7 * 16 + 12, "dash jump clears the 7-tile spike gap (%.0f px)" % dashed)
	await _free(w)


func test_wall_slide() -> void:
	var w := _world([FLOOR, Rect2(40, -400, 32, 500)])
	var p = _player(w, Vector2(20, -150))
	p.in_dir = 1
	await _frames(60)
	_check(p.state == Player.State.WALL_SLIDE, "wall slide when holding toward a wall")
	_check(p.velocity.y <= p.wall_slide_speed + 0.01, "slide speed capped (%.1f)" % p.velocity.y)
	await _free(w)


func test_single_wall_climb() -> void:
	var w := _world([FLOOR, Rect2(40, -600, 32, 700)])
	var p = await _grounded(w, 33.0)
	var y0: float = p.position.y
	var top := y0
	p.in_dir = 1
	var hold := 0
	for i in 300:
		await physics_frame
		top = minf(top, p.position.y)
		if hold > 0:
			hold -= 1
			if hold == 0:
				p.in_jump = false
		elif p.wall_dir != 0 or p.is_on_floor():
			p.in_jump = true
			hold = 10
	var rise := y0 - top
	_check(rise > 180.0, "climbs a single wall with repeated wall kicks (+%.0f px)" % rise)
	await _free(w)


func test_buster_limit() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	for i in 5:
		p.in_shoot = true
		await _frames(1)
		p.in_shoot = false
		await _frames(1)
	var n := _count_shots(0)
	_check(n == 3, "at most 3 tap shots on screen (got %d)" % n)
	await _free(w)


func test_charge_levels() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(2)
	_check(_count_shots(1) == 1, "0.67 s hold -> mid charge shot")
	p.in_shoot = true
	await _frames(90)
	_check(p.charge_level() == 2, "1.5 s hold -> full charge ready")
	p.in_shoot = false
	await _frames(2)
	_check(_count_shots(2) == 1, "release -> full charge shot")
	await _free(w)


func test_iframes() -> void:
	var w := _world([FLOOR])
	var p = await _grounded(w)
	var hp0: int = p.hp
	p.take_damage(2, p.position.x - 10.0)
	p.take_damage(2, p.position.x - 10.0)
	_check(p.hp == hp0 - 2, "invulnerable right after a hit")
	await _frames(int(p.invuln_time * 60.0) + 2)
	p.take_damage(2, p.position.x - 10.0)
	_check(p.hp == hp0 - 4, "takes damage again after i-frames")
	await _free(w)


func test_level_file() -> void:
	var lv = Level.new()
	root.add_child(lv)
	lv.load_from_file("res://levels/test_stage.txt")
	_check(lv.width >= 100 and lv.height >= 15, "stage loads (%dx%d tiles)" % [lv.width, lv.height])
	_check(lv.spawn != Vector2.ZERO, "stage has a spawn point")
	_check(lv.goal != null, "stage has a goal")
	_check(lv.checkpoints.size() >= 1, "stage has checkpoints (%d)" % lv.checkpoints.size())
	var area := 0
	for r in lv.solid_rects:
		area += r.size.x * r.size.y
	var tiles := 0
	for y in lv.height:
		for x in lv.width:
			if lv.is_solid(x, y):
				tiles += 1
	_check(area == tiles, "merged collision covers every solid tile (%d tiles -> %d rects)"
			% [tiles, lv.solid_rects.size()])
	lv.queue_free()
	await process_frame


# --- helpers ---------------------------------------------------------------------

func _lo(h: String, b: String, a: String, l: String) -> Dictionary:
	return {"head": h, "body": b, "arm": a, "leg": l}


func _world(rects: Array) -> Node2D:
	var w := Node2D.new()
	root.add_child(w)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	for r in rects:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center()
		body.add_child(cs)
	w.add_child(body)
	return w


func _player(w: Node2D, pos: Vector2):
	var p = Player.new()
	p.scripted = true
	p.position = pos
	w.add_child(p)
	return p


func _grounded(w: Node2D, x := 0.0):
	var p = _player(w, Vector2(x, 99))
	await _frames(5)
	return p


## Presses jump for `hold` frames and returns the highest rise within `frames`.
func _max_rise(p, frames: int, hold: int) -> float:
	var y0: float = p.position.y
	var top := y0
	p.in_jump = true
	for i in frames:
		await physics_frame
		if i == hold:
			p.in_jump = false
		top = minf(top, p.position.y)
	p.in_jump = false
	return y0 - top


func _wait_land(p, limit := 150) -> void:
	for i in limit:
		if p.is_on_floor():
			return
		await physics_frame


func _count_shots(level: int) -> int:
	var n := 0
	for s in get_nodes_in_group("player_shot"):
		if s.level == level and not s.is_queued_for_deletion():
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _free(w: Node) -> void:
	for s in get_nodes_in_group("player_shot"):
		s.queue_free()
	w.queue_free()
	await process_frame
	await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
