extends SceneTree
## GDD v0.2 §5-4 stage links: conditional tiles (`; @alt`), change notes (`; @change`)
## and the revisit HP-ups in five stages. A linked stage is built in its BEFORE layout
## (`condition` unset, as on a first visit) and its AFTER layout (every requirement met):
## exactly the expected cells differ, the required-route corridor from P to B keeps the
## same collision, rewards are only ever added, and a scripted player shows each new
## HP-up is reachable in its intended state while the gates hold before.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/stage_link_test.gd

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const T := 16.0
const EXPECTED_CHECKS := 44

const TERRA_NOTE := "전력 복구 — 자기부상 열차 구간 개통"
const SOLAR_NOTE := "발전소 냉각 — 열기 분출 감소 · 숨은 통로 노출"
const GRAVITY_NOTE := "중력 안정화 — 상층 구역 진입 가능"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	InputSetup.register()
	_run_all.call_deferred()


func _run_all() -> void:
	test_headers()
	await test_terra_layout()
	await test_terra_maglev_route()
	await test_solar_layout()
	await test_solar_duct()
	await test_gravity_layout()
	await test_gravity_hatches()
	await test_pulse_capsule()
	await test_cryo_ledge()
	# A script error aborts a test function silently; make sure every check ran.
	_check(_pass + _fail == EXPECTED_CHECKS, "all %d checks ran (%d)" % [EXPECTED_CHECKS, _pass + _fail])
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# --- headers ------------------------------------------------------------------------------

## The registry (what main.gd reads) carries each stage's `; @alt` / `; @change` lines,
## all keyed to the stage named in the GDD, and the note shows only when it is met.
func test_headers() -> void:
	var expect := {
		"terra_pangolin": ["cleared:pulse_cicada", 3, TERRA_NOTE],
		"solar_fennec": ["cleared:cryo_narwhal", 3, SOLAR_NOTE],
		"gravity_albatross": ["cleared:gravity_albatross", 2, GRAVITY_NOTE],
		"pulse_cicada": ["", 0, ""],
		"cryo_narwhal": ["", 0, ""],
	}
	var reg := {}
	for s in Level.load_registry("res://levels"):
		reg[s.id] = s
	for id in expect:
		var e: Array = expect[id]
		var m: Dictionary = reg.get(id, {})
		var alts: Array = m.get("alts", [])
		var ok: bool = alts.size() == e[1]
		for line in alts:
			ok = ok and line.split(" ", false)[1] == e[0]
		if e[2] == "":
			ok = ok and m.get("changes", []).is_empty()
		else:
			ok = ok and reg.has(e[0].trim_prefix("cleared:"))
			ok = ok and Level.changes_met(m, func(r): return r == e[0]) == [e[2]]
			ok = ok and Level.changes_met(m, func(_r): return false).is_empty()
		_check(ok, "%s: header (%d @alt, %s)" % [id, alts.size(), e[0] if e[0] != "" else "no stage link"])


# --- TERRA PANGOLIN: maglev service line (after PULSE CICADA) ------------------------------

func test_terra_layout() -> void:
	var a = _load("terra_pangolin", false)
	var b = _load("terra_pangolin", true)
	_check(a.width == b.width and a.height == b.height and a.spawn == b.spawn and a.boss_arena == b.boss_arena
			and a.arenas.hidden.rect == b.arenas.hidden.rect,
			"terra: both layouts parse (%dx%d), same spawn and boss rooms" % [b.width, b.height])
	var want := {}
	for y in [18, 19]:
		want[Vector2i(113, y)] = "g>."
	for x in [104, 105, 106, 115, 116, 117]:
		want[Vector2i(x, 23)] = ".>m"
	want[Vector2i(122, 22)] = ".>+"
	_check(_fmt(_diff(a, b)) == _fmt(want), "terra: only the gate, 2 maglev cars and the HP-up change %s"
			% str(_fmt(_diff(a, b))))
	_check(a.active_changes.is_empty() and b.active_changes == [TERRA_NOTE], "terra: change note only after")
	_check(_rewards(a) == ["terra_pangolin_hp_91_9"] and _rewards(b) == ["terra_pangolin_hp_122_22", "terra_pangolin_hp_91_9"],
			"terra: new HP-up only after %s -> %s" % [str(_rewards(a)), str(_rewards(b))])
	_check(_movers(a) == 4 and _movers(b) == 6, "terra: maglev cars %d -> %d" % [_movers(a), _movers(b)])
	var hp := Vector2i(122, 22)
	_check(not _linked(a, hp, _spawn_cell(a)) and _linked(b, hp, _spawn_cell(b)),
			"terra: the service line is sealed before, open after")
	# Required route P -> B: main level (rows 4-17, incl. the upper walkway), the dip and
	# collapse gallery under the entrance, and the safe trench under the first car.
	var route := [_r(0, 4, 169, 17), _r(11, 18, 50, 20), _r(114, 18, 122, 20)]
	_check(_corridor_diff(a, b, route) == "", "terra: required route corridor unchanged %s" % _corridor_diff(a, b, route))
	await _free([a, b])


## Before: the trench's left wall holds. After: walk through the gate, drop to the lower
## line, ride both cars over the spikes to the HP-up, then hop back up and leave the trench.
func test_terra_maglev_route() -> void:
	var a = _load("terra_pangolin", false)
	var p = await _put(a, Vector2(118.5 * T, 20 * T))
	await _walk(p, 105 * T, 90)
	_check(p.position.x > 114 * T and p.is_on_floor(), "terra before: the gate seals the trench wall (x=%.0f)" % p.position.x)
	await _free([a])

	var b = _load("terra_pangolin", true)
	var got := []
	b.pickup_collected.connect(func(pk) -> void: got.append(pk.pickup_id))
	p = await _put(b, Vector2(118.5 * T, 20 * T))
	await _walk(p, 99 * T, 400)
	await _settle(p)
	_check(p.is_on_floor() and absf(p.position.y - 23 * T) < 1.0 and p.position.x < 101 * T,
			"terra after: trench -> open gate -> service tunnel -> lower line (%s)" % str(p.position))
	var car1 = _mover(b, 104, 23)
	var car2 = _mover(b, 115, 23)
	var ok: bool = car1 != null and car2 != null
	if ok:
		await _walk(p, 100.5 * T - 8.0)
		ok = await _ride(p, car1, 111 * T)
		ok = ok and absf(p.position.y - 23 * T) < 1.0 and p.position.x > 110 * T
		await _walk(p, 112 * T - 8.0)
		ok = ok and await _ride(p, car2, 122.5 * T)
	_check(ok and p.is_alive() and got.has("terra_pangolin_hp_122_22"),
			"terra after: car 1 -> car 2 over the spikes reaches the new HP-up (%s, %s)" % [str(p.position), str(got)])
	# Way back: hop up the gap to the upper tunnel, walk into the trench, climb out.
	_teleport(p, Vector2(99.3 * T, 23 * T))
	await _settle(p)
	await _jump(p, 101 * T, 20 * T - 2.0)
	var up: bool = p.is_on_floor() and absf(p.position.y - 20 * T) < 1.0
	await _walk(p, 122.4 * T)
	var trench_car = _mover(b, 117, 17)
	await _wait_phase(trench_car, -0.6, false)
	await _jump(p, 124.5 * T, 17 * T - 4.0)
	_check(up and p.is_on_floor() and absf(p.position.y - 17 * T) < 1.0 and p.position.x > 123 * T,
			"terra after: hop back up the gap and climb out of the trench (%s)" % str(p.position))
	await _free([b])


# --- SOLAR FENNEC: cooled vents and a duct (after CRYO NARWHAL) ----------------------------

func test_solar_layout() -> void:
	var a = _load("solar_fennec", false)
	var b = _load("solar_fennec", true)
	_check(a.width == b.width and a.height == b.height and a.spawn == b.spawn and a.boss_arena == b.boss_arena,
			"solar: both layouts parse (%dx%d), same spawn and boss room" % [b.width, b.height])
	var want := {}
	for v in [Vector2i(25, 17), Vector2i(28, 17), Vector2i(65, 17), Vector2i(149, 17)]:
		want[v] = "u>#"
	for y in range(9, 14):
		for x in [133, 134]:
			want[Vector2i(x, y)] = "#>."
	for y in range(6, 9):
		for x in range(133, 139):
			want[Vector2i(x, y)] = "#>."
	want[Vector2i(138, 8)] = "#>+"
	_check(_fmt(_diff(a, b)) == _fmt(want), "solar: only 4 vents, the duct and its HP-up change (%d cells)" % _diff(a, b).size())
	_check(a.active_changes.is_empty() and b.active_changes == [SOLAR_NOTE], "solar: change note only after")
	var va := _vents(a)
	var vb := _vents(b)
	var subset := true
	for v in vb:
		subset = subset and va.has(v)
	_check(va.size() == 9 and vb.size() == 5 and subset and _bent(a) == _bent(b),
			"solar: flame vents %d -> %d, the mirror-bent ones (%d) stay" % [va.size(), vb.size(), _bent(b)])
	_check(_rewards(a) == ["solar_fennec_hp_155_9"] and _rewards(b) == ["solar_fennec_hp_138_8", "solar_fennec_hp_155_9"],
			"solar: new HP-up only after %s -> %s" % [str(_rewards(a)), str(_rewards(b))])
	_check(a.is_solid(138, 8) and _linked(b, Vector2i(138, 8), _spawn_cell(b)),
			"solar: the duct chamber is rock before, open to the route after")
	# Required route P -> B: the open-sky section and the collector tunnel under the tower
	# (vents that turn into plain rock count as the same collision).
	var route := [_r(0, 0, 131, 19), _r(132, 14, 165, 19)]
	_check(_corridor_diff(a, b, route) == "", "solar: required route corridor unchanged %s" % _corridor_diff(a, b, route))
	await _free([a, b])


## Before: the collector tunnel ceiling is solid. After: wall-kick up the duct opening
## (cols 133-134) into the tower chamber and take the HP-up.
func test_solar_duct() -> void:
	var a = _load("solar_fennec", false)
	var p = await _put(a, Vector2(133.8 * T, 17 * T))
	var top := INF
	p.in_jump = true
	for i in 50:
		await _tick(p)
		top = minf(top, p.position.y - Player.BODY_SIZE.y)
	p.in_jump = false
	_check(top >= 14 * T - 0.5, "solar before: the tunnel ceiling over the duct holds (head at %.0f)" % top)
	await _free([a])

	var b = _load("solar_fennec", true)
	var got := []
	b.pickup_collected.connect(func(pk) -> void: got.append(pk.pickup_id))
	p = await _put(b, Vector2(133.8 * T, 17 * T))
	p.in_jump = true
	for i in 16:
		await _tick(p)
	var hold := 0
	var in_room := false
	for i in 600:
		var above: bool = p.position.y < 9 * T - 1.0
		p.in_dir = 1 if above else -1
		if hold > 0:
			hold -= 1
			if hold == 0:
				p.in_jump = false
		elif not above and p.wall_dir != 0:
			p.in_jump = true
			hold = 10
		await _tick(p)
		if p.is_on_floor() and absf(p.position.y - 9 * T) < 1.0 and p.position.x > 135 * T:
			in_room = true
			break
	p.in_jump = false
	p.in_dir = 0
	await _walk(p, 138.5 * T)
	_check(in_room and got.has("solar_fennec_hp_138_8"),
			"solar after: wall kicks up the duct reach the chamber HP-up (%s, %s)" % [str(p.position), str(got)])
	await _free([b])


# --- GRAVITY ALBATROSS: relay hatches (after its own boss) ---------------------------------

func test_gravity_layout() -> void:
	var a = _load("gravity_albatross", false)
	var b = _load("gravity_albatross", true)
	_check(a.width == b.width and a.height == b.height and a.spawn == b.spawn and a.boss_arena == b.boss_arena
			and a.arenas.hidden.rect == b.arenas.hidden.rect,
			"gravity: both layouts parse (%dx%d), same spawn and boss rooms" % [b.width, b.height])
	var want := {}
	for x in [145, 146]:
		want[Vector2i(x, 20)] = "g>."
	for x in [151, 152]:
		want[Vector2i(x, 20)] = "g>|"
	_check(_fmt(_diff(a, b)) == _fmt(want), "gravity: only the 2 hatches in the hangar ceiling change %s"
			% str(_fmt(_diff(a, b))))
	_check(a.active_changes.is_empty() and b.active_changes == [GRAVITY_NOTE], "gravity: change note only after")
	_check(_rewards(a) == _rewards(b) and _rewards(a).size() == 2, "gravity: rewards unchanged %s" % str(_rewards(b)))
	var trigger := Vector2i(166, 11)
	_check(a.cell(166, 11) == "b" and not _linked(a, trigger, _spawn_cell(a)) and _linked(b, trigger, _spawn_cell(b)),
			"gravity: upper relay and Fragment room sealed before, open after")
	# Required route P -> B: everything below the relay up to the hangar, then the hangar.
	var route := [_r(0, 12, 131, 31), _r(132, 21, 166, 31)]
	_check(_corridor_diff(a, b, route) == "", "gravity: required route corridor unchanged %s" % _corridor_diff(a, b, route))
	await _free([a, b])


## Aero LEG flight into the relay lift: stopped by the hatch before (and the player can
## steer out of the lift), carried to the upper relay after. The return drop lands on
## its hatch before and in the hangar after.
func test_gravity_hatches() -> void:
	var under := Vector2(152 * T, 29 * T)
	var results := []
	for after in [false, true]:
		var lv = _load("gravity_albatross", after)
		var p = await _put(lv, under)
		p.apply_loadout({"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "aero"})
		p.set_core(100.0)
		p.in_jump = true
		await _frames(20)
		p.in_jump = false
		await _frames(2)
		p.in_jump = true
		var top := INF
		for i in 200:
			await _tick(p)
			top = minf(top, p.position.y - Player.BODY_SIZE.y)
		p.in_jump = false
		var out := false
		if not after:
			# Steer out of the lift column and land on the hangar floor.
			p.in_dir = -1
			for i in 240:
				await _tick(p)
				if p.is_on_floor() and absf(p.position.y - 29 * T) < 1.0:
					out = true
					break
			p.in_dir = 0
		_teleport(p, Vector2(148.5 * T, 12 * T))
		await _settle(p)
		await _walk(p, 145.6 * T, 60)
		await _settle(p, 240)
		results.append([top, out, p.position.y, p.is_on_floor()])
		await _free([lv])
	var bef: Array = results[0]
	var aft: Array = results[1]
	_check(bef[0] >= 21 * T - 0.5 and bef[1], "gravity before: flight stops under the lift hatch, player steers out (head %.0f)" % bef[0])
	_check(bef[3] and absf(bef[2] - 20 * T) < 1.0, "gravity before: the return drop lands on its hatch (y=%.0f)" % bef[2])
	_check(aft[0] < 12 * T, "gravity after: flight + lift reach the upper relay (head %.0f)" % aft[0])
	_check(aft[3] and absf(aft[2] - 29 * T) < 1.0, "gravity after: the return drop leads into the hangar (y=%.0f)" % aft[2])


# --- PULSE CICADA: niche behind a cracked panel (always) ----------------------------------

func test_pulse_capsule() -> void:
	var a = _load("pulse_cicada", false)
	var b = _load("pulse_cicada", true)
	_check(_diff(a, b).is_empty() and a.active_changes.is_empty() and b.active_changes.is_empty(),
			"pulse: no stage link, both layouts are the same")
	var wall = null
	for w in a.breakables:
		if w.rect == Rect2(140 * T, 18 * T, T, 2 * T):
			wall = w
	_check(wall != null and a.cell(139, 19) == "+" and a.cell(139, 18) == "." and a.is_solid(138, 19)
			and a.is_solid(139, 20), "pulse: cracked panel (col 140) in front of a 1x2 niche in tower 2")
	_check(_rewards(a).has("pulse_cicada_hp_139_19") and _rewards(a).size() == 2
			and not _linked(a, Vector2i(139, 19), _spawn_cell(a)),
			"pulse: the niche HP-up is sealed off by the panel %s" % str(_rewards(a)))
	await _free([b])
	var got := []
	a.pickup_collected.connect(func(pk) -> void: got.append(pk.pickup_id))
	# Bottom of the descent shaft (off the route, which heads right to the boss door).
	var p = await _put(a, Vector2(143.5 * T, 20 * T))
	p.in_dir = -1
	await _frames(2)
	p.in_dir = 0
	await _charge_shot(p)
	var intact: bool = is_instance_valid(wall) and not wall.is_queued_for_deletion()
	await _walk(p, 139.5 * T, 90)
	_check(intact and p.position.x > 141 * T and got.is_empty(),
			"pulse: neutral charge shot leaves the panel, the niche stays shut (x=%.0f)" % p.position.x)
	_teleport(p, Vector2(143.5 * T, 20 * T))
	await _settle(p)
	p.apply_loadout({"head": "neutral", "body": "neutral", "arm": "vanguard", "leg": "neutral"})
	p.in_dir = -1
	await _frames(2)
	p.in_dir = 0
	await _charge_shot(p)
	var broken: bool = not is_instance_valid(wall) or wall.is_queued_for_deletion()
	await _frames(3)
	await _walk(p, 139.5 * T, 120)
	_check(broken and got.has("pulse_cicada_hp_139_19"),
			"pulse: Vanguard ARM charge breaks the panel, the niche HP-up is taken (%s)" % str(got))
	await _free([a])


# --- CRYO NARWHAL: high ledge over the flooded hangar (always) ------------------------------

func test_cryo_ledge() -> void:
	var a = _load("cryo_narwhal", false)
	var b = _load("cryo_narwhal", true)
	_check(_diff(a, b).is_empty() and a.active_changes.is_empty(), "cryo: no stage link, both layouts are the same")
	var ledge := true
	for x in range(63, 67):
		ledge = ledge and a.is_solid(x, 1) and not a.is_solid(x, 2) and not a.is_solid(x, 0)
	_check(ledge and a.cell(65, 0) == "+" and _rewards(a).has("cryo_narwhal_hp_65_0") and _rewards(a).size() == 2,
			"cryo: 4-wide ledge on row 1 (cols 63-66) with the new HP-up %s" % str(_rewards(a)))
	await _free([b])
	var got := []
	a.pickup_collected.connect(func(pk) -> void: got.append(pk.pickup_id))
	# Without flight: jumps, dash jumps and ECHO's hover from the blocks under the ledge.
	var head := INF
	var tries := [[60.9, 1, false, false], [59.5, 1, true, false], [60.9, 1, false, true],
			[78.5, -1, true, false], [78.5, -1, true, true]]
	for t in tries:
		var p = await _put(a, Vector2(t[0] * T, 8 * T))
		if t[3]:
			p.setup_party(["echo"], 16)
		head = minf(head, await _reach(p, t[1], t[2], t[3]))
		p.queue_free()
		await _frames(2)
	_check(head > 2 * T and got.is_empty(),
			"cryo: jumps, dash jumps and ECHO hover cannot reach the ledge (best head %.0f, ledge underside %.0f)" % [head, 2 * T])
	# Aero LEG: fly up beside the ledge, slide over its edge, walk to the HP-up.
	var p = await _put(a, Vector2(61.9 * T - 2.0, 8 * T))
	p.apply_loadout({"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "aero"})
	p.set_core(100.0)
	p.in_jump = true
	await _frames(20)
	p.in_jump = false
	await _frames(2)
	p.in_jump = true
	var landed := false
	for i in 240:
		p.in_dir = 1 if p.position.y < 2 * T + Player.BODY_SIZE.y - 4.0 else 0
		if p.position.x > 63 * T + 4.0:
			p.in_jump = false
		await _tick(p)
		if p.is_on_floor() and absf(p.position.y - 1 * T) < 1.0:
			landed = true
			break
	p.in_jump = false
	await _walk(p, 65.5 * T)
	_check(landed and got.has("cryo_narwhal_hp_65_0"), "cryo: Aero LEG flight reaches the ledge HP-up (%s, %s)"
			% [str(p.position), str(got)])
	await _free([a])


## One attempt toward the ledge: (dash) jump in `dir`, hover with ECHO at the peak.
## Returns the highest head position (smallest y) reached.
func _reach(p, dir: int, dash: bool, hover: bool) -> float:
	var head := INF
	p.in_dir = dir
	p.in_dash = dash
	await _frames(2)
	p.in_jump = true
	for i in 120:
		if hover and i == 24:
			p.in_jump = false
		if hover and i == 26:
			p.in_jump = true
		await _tick(p)
		head = minf(head, p.position.y - Player.BODY_SIZE.y)
		if i > 10 and p.is_on_floor():
			break
	p.in_jump = false
	p.in_dash = false
	p.in_dir = 0
	return head


# --- helpers -------------------------------------------------------------------------------

## A stage in its BEFORE layout (after = false, `condition` unset) or AFTER layout
## (every requirement met). Enemies are removed: only the terrain is under test.
func _load(id: String, after: bool):
	var lv = Level.new()
	lv.stage_id = id
	if after:
		lv.condition = func(_r): return true
	root.add_child(lv)
	lv.load_from_file("res://levels/%s.txt" % id)
	for c in lv.entities():
		if c.is_in_group("enemy"):
			c.queue_free()
	return lv


## {Vector2i: "before>after"} for every cell that differs.
func _diff(a, b) -> Dictionary:
	var out := {}
	for y in maxi(a.height, b.height):
		for x in maxi(a.width, b.width):
			if a.cell(x, y) != b.cell(x, y):
				out[Vector2i(x, y)] = a.cell(x, y) + ">" + b.cell(x, y)
	return out


func _fmt(d: Dictionary) -> Array:
	var out := []
	for k in d:
		out.append("%d,%d:%s" % [k.x, k.y, d[k]])
	out.sort()
	return out


## Pickup ids (HP-ups and armor capsules) the level spawned, sorted.
func _rewards(lv) -> Array:
	var out := []
	for c in lv.entities():
		if c.get("pickup_id") != null and not c.is_queued_for_deletion():
			out.append(c.pickup_id)
	out.sort()
	return out


func _movers(lv) -> int:
	return lv.entities().filter(func(c): return c is AnimatableBody2D).size()


func _vents(lv) -> Array:
	var out := []
	for l in lv.lasers:
		if l.style == "flame":
			out.append(l.emitter_rect.position)
	return out


func _bent(lv) -> int:
	return lv.lasers.filter(func(l): return l.style == "flame" and l.segments.size() >= 2).size()


func _spawn_cell(lv) -> Vector2i:
	return Vector2i(floori(lv.spawn.x / T), floori(lv.spawn.y / T) - 1)


## Flood fill over open cells (cracked walls count as solid): is `from` connected to `to`?
func _linked(lv, from: Vector2i, to: Vector2i) -> bool:
	var seen := {from: true}
	var todo := [from]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		if c == to:
			return true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= lv.width or n.y >= lv.height or seen.has(n):
				continue
			if lv.is_solid(n.x, n.y) or lv.cell(n.x, n.y) == "x":
				continue
			seen[n] = true
			todo.append(n)
	return false


## Inclusive tile rect.
func _r(x0: int, y0: int, x1: int, y1: int) -> Rect2i:
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## "" when every cell in `rects` has the same collision in both layouts (a heat vent
## that turns into plain rock counts as the same), else the first difference.
func _corridor_diff(a, b, rects: Array) -> String:
	for r in rects:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var ca: String = "#" if a.cell(x, y) == "u" else a.cell(x, y)
				var cb: String = "#" if b.cell(x, y) == "u" else b.cell(x, y)
				if ca != cb:
					return "(%d,%d: %s -> %s)" % [x, y, ca, cb]
	return ""


func _put(lv, feet: Vector2):
	var p = Player.new()
	p.scripted = true
	p.position = feet - Vector2(0, 1)
	lv.add_child(p)
	p.env = lv
	p.kill_y = lv.pixel_size().y + 48.0
	await _frames(4)
	return p


func _teleport(p, feet: Vector2) -> void:
	p.in_dir = 0
	p.in_jump = false
	p.in_dash = false
	p.in_shoot = false
	p.position = feet - Vector2(0, 1)
	p.velocity = Vector2.ZERO


## One frame with damage off (flames / spikes ignored): used where only reach matters.
func _tick(p) -> void:
	await physics_frame
	if is_instance_valid(p):
		p.invuln_timer = 1.0


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _settle(p, limit := 120) -> void:
	for i in limit:
		await physics_frame
		if p.is_on_floor():
			break


## Walks toward x; stops within 2 px or after `limit` frames (e.g. against a wall).
func _walk(p, x: float, limit := 600) -> void:
	for i in limit:
		var d: float = x - p.position.x
		if absf(d) < 2.0 or not p.is_alive():
			break
		p.in_dir = 1 if d > 0.0 else -1
		await physics_frame
	p.in_dir = 0
	await physics_frame


## Full jump; rises straight up until the feet clear `rise_to`, then steers to x.
func _jump(p, x: float, rise_to := INF) -> void:
	p.in_jump = false
	await physics_frame
	p.in_jump = true
	var airborne := false
	for i in 150:
		var d: float = x - p.position.x
		if rise_to != INF and p.position.y > rise_to and p.velocity.y <= 0.0:
			p.in_dir = 0
		else:
			p.in_dir = (1 if d > 0.0 else -1) if absf(d) > 2.0 else 0
		await physics_frame
		if not p.is_on_floor():
			airborne = true
		elif airborne:
			break
	p.in_jump = false
	p.in_dir = 0
	await physics_frame


## Holds the buster for a level-1+ charge and releases it.
func _charge_shot(p) -> void:
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(30)


func _mover(lv, cx: int, cy: int):
	for c in lv.entities():
		if c is AnimatableBody2D and c.rect.position == Vector2(cx * T, cy * T):
			return c
	return null


## -1 .. 1 along the mover's axis (1 = right end).
func _phase(mover) -> float:
	return (mover.position - mover.rect.position).dot(mover.axis) / 48.0


func _wait_phase(mover, value: float, above: bool) -> void:
	for i in 400:
		await physics_frame
		var ph := _phase(mover)
		if (above and ph > value) or (not above and ph < value):
			return


## From the edge next to a car's left end: board it there, ride to its right end, step off to x.
func _ride(p, car, off_x: float) -> bool:
	await _wait_phase(car, -0.95, false)
	for i in 60:
		var d: float = car.position.x + 36.0 - p.position.x
		p.in_dir = 0 if absf(d) < 2.0 else int(signf(d))
		await physics_frame
	p.in_dir = 0
	var aboard: bool = p.is_on_floor() and absf(p.position.y - car.position.y) < 1.5
	await _wait_phase(car, 0.95, true)
	await _walk(p, off_x, 120)
	await _frames(4)
	return aboard and p.is_alive() and p.is_on_floor()


func _free(levels: Array) -> void:
	for s in get_nodes_in_group("enemy_shot"):
		s.queue_free()
	for lv in levels:
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
