extends SceneTree
## 81-combination armor check (GDD v0.2 §4-1, prototype checklist 8-3).
## 1) Rules: every loadout's stats match the part / set-bonus rules.
## 2) Physics: all 81 loadouts run side by side on one floor and must keep the
##    jump height and the dash-jump reach the stages are built around
##    ("the neutral frame alone can clear every required section").
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/armor_combos.gd

const ArmorData = preload("res://scripts/armor/armor_data.gd")
const Player = preload("res://scripts/player/player.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const SPACING := 600.0
const SPIKE_GAP := 7 * 16 + 12  # widest required dash-jump gap (+ body width)

var _problems: Array = []


func _initialize() -> void:
	InputSetup.register()
	_run.call_deferred()


func _run() -> void:
	var loadouts := ArmorData.all_loadouts()
	var unique := {}
	for lo in loadouts:
		unique[str(lo)] = true
	_expect(loadouts.size() == 81 and unique.size() == 81, "81 unique loadouts")
	for lo in loadouts:
		_check_rules(lo)
	print("rules checked for %d loadouts" % loadouts.size())
	await _check_physics(loadouts)
	if _problems.is_empty():
		print("\nALL 81 LOADOUTS OK")
		quit(0)
	else:
		print("\n%d PROBLEM(S):" % _problems.size())
		for p in _problems:
			print("  - ", p)
		quit(1)


func _check_rules(lo: Dictionary) -> void:
	var s := ArmorData.compute(lo)
	var v := ArmorData.count(lo, "vanguard")
	var a := ArmorData.count(lo, "aero")
	var tag := _tag(lo)
	for key in ["walk_speed", "dash_speed", "dash_time", "core_regen_ground"]:
		var x: float = s[key]
		_expect(is_finite(x) and x > 0.0, "%s: %s must be positive" % [tag, key])
	var dash_px: float = s.dash_speed * s.dash_time
	_expect(dash_px >= 70.0 and dash_px <= 100.0, "%s: dash length %.0f out of range" % [tag, dash_px])
	_expect((s.special == "overdrive") == (v == 4), "%s: overdrive iff 4 Vanguard" % tag)
	_expect((s.special == "skybreaker") == (a == 4), "%s: skybreaker iff 4 Aero" % tag)
	_expect(s.dual_core == (v == 2 and a == 2), "%s: dual core iff 2+2" % tag)
	_expect(s.flight == (lo.leg == "aero") and s.air_dashes == (1 if lo.leg == "aero" else 0),
			"%s: flight / air dash only with Aero LEG" % tag)
	_expect(s.reveal == (lo.head == "vanguard"), "%s: reveal only with Vanguard HEAD" % tag)
	_expect(s.breaker == (lo.arm == "vanguard"), "%s: breaker only with Vanguard ARM" % tag)
	_expect(s.spread == (lo.arm == "aero"), "%s: spread only with Aero ARM" % tag)
	_expect(s.glide == (lo.body == "aero"), "%s: glide only with Aero BODY" % tag)
	_expect(s.dash_chain == (2 if lo.leg == "vanguard" else 1), "%s: dash chain only with Vanguard LEG" % tag)


func _check_physics(loadouts: Array) -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SPACING * loadouts.size() + 1000.0, 32)
	cs.shape = shape
	cs.position = Vector2(shape.size.x / 2.0 - 200.0, 116)
	floor_body.add_child(cs)
	world.add_child(floor_body)

	var players := []
	for i in loadouts.size():
		var p = Player.new()
		p.scripted = true
		p.position = Vector2(i * SPACING, 99)
		world.add_child(p)
		p.apply_loadout(loadouts[i])
		players.append(p)
	for i in 5:
		await physics_frame

	# Full jump height.
	var y0 := []
	var top := []
	for p in players:
		y0.append(p.position.y)
		top.append(p.position.y)
		p.in_jump = true
	for f in 70:
		await physics_frame
		for i in players.size():
			top[i] = minf(top[i], players[i].position.y)
	for i in players.size():
		var rise: float = y0[i] - top[i]
		_expect(rise > 55.0 and rise < 70.0, "%s: jump height %.0f" % [_tag(loadouts[i]), rise])
		players[i].in_jump = false
	for i in 40:
		await physics_frame

	# Dash jump reach (no air dash / flight used: pure ground dash jump).
	var x0 := []
	for p in players:
		x0.append(p.position.x)
		p.in_dir = 1
		p.in_dash = true
		p.in_jump = true
	await physics_frame
	await physics_frame
	var landed := []
	landed.resize(players.size())
	landed.fill(false)
	for f in 150:
		await physics_frame
		for i in players.size():
			if not landed[i] and players[i].is_on_floor():
				landed[i] = true
				var reach: float = players[i].position.x - x0[i]
				_expect(reach >= SPIKE_GAP, "%s: dash jump reach %.0f < %d" % [_tag(loadouts[i]), reach, SPIKE_GAP])
	for i in players.size():
		_expect(landed[i], "%s: never landed after dash jump" % _tag(loadouts[i]))
	print("physics checked for %d loadouts" % players.size())
	world.queue_free()
	await process_frame


func _tag(lo: Dictionary) -> String:
	return "[%s %s %s %s]" % [lo.head.substr(0, 1).to_upper(), lo.body.substr(0, 1).to_upper(),
			lo.arm.substr(0, 1).to_upper(), lo.leg.substr(0, 1).to_upper()]


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_problems.append(message)
