extends SceneTree
## Stage backdrop tests (scripts/level/backdrop_set.gd + scripts/level/backdrops/):
## every theme builds a sky and parallax layers, theme switching is a no-op when
## unchanged and leaks no nodes, lightning obeys flashes_enabled, and the
## per-frame process / redraw cost stays small.
## Run: godot --headless --fixed-fps 60 --path game -s res://tests/backdrop_test.gd

const BackdropSet = preload("res://scripts/level/backdrop_set.gd")
const Painter = preload("res://scripts/level/backdrops/painter.gd")
const Level = preload("res://scripts/level/level.gd")

const DT := 1.0 / 60.0
## Per-frame budgets (generous; typical numbers are printed in the cost table).
const MAX_PROCESS_USEC := 200.0
const MAX_DRAW_USEC := 250.0
const MAX_REDRAWS := 1.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	await test_every_theme_builds()
	await test_stage_ids()
	await test_switching()
	await test_flashes()
	await test_cost()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func test_every_theme_builds() -> void:
	var bs = BackdropSet.new()
	root.add_child(bs)
	await _frames(2)
	_check(bs.is_in_group("backdrop") and bs.theme == "training" and bs.current() != null,
			"backdrop joins group 'backdrop' and starts with the training theme")
	for id in BackdropSet.THEMES:
		bs.set_theme(id)
		await _frames(2)
		var th: Node = bs.current()
		var skies := th.get_children().filter(func(n): return n is CanvasLayer)
		var layers := th.get_children().filter(func(n): return n is Parallax2D)
		var sky_ok: bool = skies.size() == 1 and skies[0].layer < 0 \
				and skies[0].get_child(0) is TextureRect
		var repeating := layers.filter(func(l): return l.repeat_size.x > 0.0)
		var ordered := true
		var gentle := true
		for i in layers.size():
			var s: Vector2 = layers[i].scroll_scale
			gentle = gentle and s.y <= 0.15 and s.y <= s.x and layers[i].z_index < 0
			if i > 0:
				var prev: Vector2 = layers[i - 1].scroll_scale
				ordered = ordered and s.x >= prev.x and s.y >= prev.y
		var repeat_ok := repeating.all(func(l): return l.repeat_size.x >= 384.0 and l.repeat_times >= 2)
		# The title theme never scrolls (no camera), so it needs no repeating layers.
		var scrolls: bool = id != "title"
		_check(bs.theme == id and sky_ok and layers.size() >= 3 and (repeating.size() >= 2 or not scrolls)
				and ordered and gentle and repeat_ok,
				"%s: sky layer + %d parallax layers (%d repeating), far -> near, small vertical scroll"
				% [id, layers.size(), repeating.size()])
		var painters := _painters(th).filter(func(p): return p.is_visible_in_tree())
		var undrawn := painters.filter(func(p): return p.draws == 0)
		_check(not painters.is_empty() and undrawn.is_empty(),
				"%s: all %d painters drew without errors" % [id, painters.size()])
	bs.set_theme("no_such_stage")
	_check(bs.theme == "training", "unknown stage id falls back to the training theme")
	bs.set_theme("")
	_check(bs.theme == "training", "empty stage id falls back to the training theme")
	bs.queue_free()
	await _frames(2)


func test_stage_ids() -> void:
	var missing := []
	for meta in Level.load_registry("res://levels"):
		if not BackdropSet.THEMES.has(meta.id):
			missing.append(meta.id)
	_check(missing.is_empty(), "every registered stage has its own theme (missing: %s)" % str(missing))


func test_switching() -> void:
	var bs = BackdropSet.new()
	root.add_child(bs)
	bs.set_theme("prism_gecko")
	await _frames(3)
	var first: Node = bs.current()
	bs.set_theme("prism_gecko")
	_check(bs.current() == first, "set_theme with the current theme is a no-op")
	# Warm-up round (first builds may fill engine caches), then measure.
	for id in BackdropSet.THEMES:
		bs.set_theme(id)
		await process_frame
	bs.set_theme("prism_gecko")
	await _frames(3)
	var sub := _count(bs)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	for r in 3:
		for id in BackdropSet.THEMES:
			bs.set_theme(id)
			await process_frame
	call_group("backdrop", "set_theme", "cryo_narwhal")
	_check(bs.theme == "cryo_narwhal", "call_group('backdrop', 'set_theme', id) switches the theme")
	bs.set_theme("prism_gecko")
	await _frames(3)
	_check(not is_instance_valid(first), "the replaced theme node is freed")
	_check(_count(bs) == sub and Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes
			and Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans,
			"24 theme switches leak no nodes (%d in backdrop, %d total)" % [sub, nodes])
	# <= : other autoloads (Audio's worker jobs) may free objects meanwhile.
	_check(Performance.get_monitor(Performance.OBJECT_COUNT) <= objects,
			"24 theme switches leak no objects (%d -> %d)" % [objects,
			Performance.get_monitor(Performance.OBJECT_COUNT)])
	bs.queue_free()
	await _frames(2)


func test_flashes() -> void:
	var bs = BackdropSet.new()
	root.add_child(bs)
	bs.set_theme("pulse_cicada")
	await _frames(2)
	var th = bs.current()
	th._start_strike()
	await _frames(1)
	_check(th._bolt.draws >= 1, "pulse_cicada: a strike redraws the bolt painter")
	var seen := false
	for i in 60 * 25:
		th._process(DT)
		seen = seen or (th._flash.visible and th._flash.color.a > 0.0 and th._bolt.visible)
	_check(th.flash_count >= 2 and seen, "pulse_cicada: lightning flashes now and then (%d in 25 s)"
			% th.flash_count)
	# Switching off mid-strike hides it at once (no frame needed: works while paused).
	th._start_strike()
	th._process(DT)
	var was_on: bool = th._flash.visible
	bs.flashes_enabled = false
	_check(was_on and not th._flash.visible and not th._bolt.visible and not th.is_striking(),
			"pulse_cicada: turning flashes off mid-strike hides the flash at once")
	var count0: int = th.flash_count
	var shown := false
	for i in 60 * 30:
		th._process(DT)
		shown = shown or th._flash.visible or th._bolt.visible
	_check(th.flash_count == count0 and not shown, "pulse_cicada: no lightning while flashes are off")
	bs.flashes_enabled = true
	for i in 60 * 12:
		th._process(DT)
	_check(th.flash_count > count0, "pulse_cicada: lightning resumes when flashes are back on")
	# No theme flashes anything while flashes are off.
	bs.flashes_enabled = false
	var flashing := []
	for id in BackdropSet.THEMES:
		bs.set_theme(id)
		var t = bs.current()
		for i in 60 * 20:
			t._process(DT)
		if t.flash_count > 0:
			flashing.append(id)
	_check(flashing.is_empty(), "no theme flashes with flashes_enabled = false (%s)" % str(flashing))
	bs.queue_free()
	await _frames(2)


## Build time, first draw, then 120 frames of steady state per theme.
func test_cost() -> void:
	var bs = BackdropSet.new()
	root.add_child(bs)
	await _frames(2)
	print("\n  theme               nodes  build ms  1st draw ms  process us/f  redraws/f  draw us/f")
	for id in BackdropSet.THEMES:
		bs.set_theme("training" if id != "training" else "prism_gecko")
		await _frames(2)
		var t0 := Time.get_ticks_usec()
		bs.set_theme(id)
		var build_usec := Time.get_ticks_usec() - t0
		var d0 := Painter.draw_usec
		await _frames(2)
		var first_draw := Painter.draw_usec - d0
		var th = bs.current()
		# Steady state: count redraws and their cost over real frames.
		var c0 := Painter.draw_count
		d0 = Painter.draw_usec
		await _frames(120)
		var redraws := (Painter.draw_count - c0) / 120.0
		var draw_usec := (Painter.draw_usec - d0) / 120.0
		# Process cost: the theme's own per-frame work, timed directly.
		t0 = Time.get_ticks_usec()
		for i in 600:
			th._process(DT)
		var process_usec := (Time.get_ticks_usec() - t0) / 600.0
		print("  %-18s %6d %9.2f %12.2f %13.2f %10.2f %10.2f" % [id, _count(th), build_usec / 1000.0,
				first_draw / 1000.0, process_usec, redraws, draw_usec])
		_check(process_usec < MAX_PROCESS_USEC and redraws <= MAX_REDRAWS and draw_usec < MAX_DRAW_USEC,
				"%s: per-frame cost small (process %.1f us, %.2f redraws, draw %.1f us)"
				% [id, process_usec, redraws, draw_usec])
	bs.queue_free()
	await _frames(2)


# --- helpers ---------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


func _painters(node: Node) -> Array:
	var out := []
	if node.get_script() == Painter:
		out.append(node)
	for c in node.get_children():
		out.append_array(_painters(c))
	return out


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
