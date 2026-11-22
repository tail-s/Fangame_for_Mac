extends Node2D
## Builds a stage from an ASCII map (legend at the top of levels/*.txt).
## Placeholder until real tile art exists: solid tiles are merged into as few
## collision rectangles as possible and drawn with draw_* calls.
##
## The level does not touch save data: the caller passes `collected` ids and the
## `reveal` flag, and listens to the signals below.

signal pickup_collected(pickup)
signal boss_triggered

const TILE := 16
const Layers = preload("res://scripts/core/layers.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")
const Walker = preload("res://scripts/enemies/walker.gd")
const Turret = preload("res://scripts/enemies/turret.gd")
const Checkpoint = preload("res://scripts/level/checkpoint.gd")
const Goal = preload("res://scripts/level/goal.gd")
const Breakable = preload("res://scripts/level/breakable.gd")
const BlinkPlatform = preload("res://scripts/level/blink_platform.gd")
const Laser = preload("res://scripts/level/laser.gd")
const Pickup = preload("res://scripts/level/pickup.gd")

const C_FILL := Color("1c375b")
const C_PANEL := Color("142a47")
const C_EDGE := Color("00b8be")
const C_SPIKE := Color("d7edf3")
const C_SPIKE_TIP := Color("e34f5b")

const EMITTERS := {">": Vector2i.RIGHT, "<": Vector2i.LEFT, "v": Vector2i.DOWN}
## Map chars that are solid for collision (cracked walls and door are handled apart).
const SOLID_CHARS := ["#", ">", "<", "v"]

var stage_id := ""
var collected: Array = []
var rows := PackedStringArray()
var width := 0
var height := 0
var spawn := Vector2.ZERO
var checkpoints: Array = []
var goal: Area2D = null
var solid_rects: Array[Rect2i] = []
var breakables: Array = []
var lasers: Array = []
var boss_spawn := Vector2.INF
## Inner empty rect of the boss room (world space), and the camera rect for it.
var boss_arena := Rect2()
var boss_camera := Rect2()
var reveal := false

var _door: StaticBody2D = null
var _door_rect := Rect2()
var _door_closed := false


func load_from_file(path: String) -> void:
	load_from_text(FileAccess.get_file_as_string(path))


func load_from_text(text: String) -> void:
	rows.clear()
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.begins_with(";"):
			continue
		rows.append(line)
	while rows.size() > 0 and rows[rows.size() - 1].strip_edges().is_empty():
		rows.remove_at(rows.size() - 1)
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, r.length())
	_build()


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func cell(x: int, y: int) -> String:
	if y < 0 or y >= height or x < 0:
		return "."
	var r := rows[y]
	return r[x] if x < r.length() else "."


func is_solid(x: int, y: int) -> bool:
	return SOLID_CHARS.has(cell(x, y))


func set_reveal(value: bool) -> void:
	reveal = value
	for b in breakables:
		if is_instance_valid(b):
			b.reveal = value
	queue_redraw()


func has_boss() -> bool:
	return boss_spawn != Vector2.INF


## Seals the boss room behind the player.
func close_door() -> void:
	if _door == null or _door_closed:
		return
	_door_closed = true
	_door.collision_layer = Layers.WORLD
	queue_redraw()


# --- build ----------------------------------------------------------------------

func _build() -> void:
	solid_rects = []
	for ch in SOLID_CHARS:
		solid_rects.append_array(_merge_rects(ch))
	var body := StaticBody2D.new()
	body.name = "Solids"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	for r in solid_rects:
		body.add_child(_rect_shape(_px(r)))
	add_child(body)

	for r in _merge_rects("^"):
		var hazard := Area2D.new()
		hazard.add_to_group("hazard")
		hazard.collision_layer = Layers.HAZARD
		hazard.collision_mask = 0
		hazard.monitoring = false
		var px := _px(r)
		hazard.add_child(_rect_shape(Rect2(px.position.x + 2, px.end.y - 8, px.size.x - 4, 8)))
		add_child(hazard)

	for r in _merge_rects("x"):
		var wall := Breakable.new()
		wall.rect = _px(r)
		add_child(wall)
		breakables.append(wall)

	for pair in [["o", false], ["O", true]]:
		var rects := _merge_rects(pair[0])
		if rects.is_empty():
			continue
		var blink := BlinkPlatform.new()
		blink.phase_b = pair[1]
		for r in rects:
			blink.rects.append(_px(r))
		add_child(blink)

	var door_rects := _merge_rects("D")
	if not door_rects.is_empty():
		_door = StaticBody2D.new()
		_door.collision_layer = 0
		_door.collision_mask = 0
		_door_rect = _px(door_rects[0])
		for r in door_rects:
			_door.add_child(_rect_shape(_px(r)))
		add_child(_door)

	var boss_trigger_rects := _merge_rects("B")
	for r in boss_trigger_rects:
		var trig := Area2D.new()
		trig.collision_layer = Layers.TRIGGER
		trig.collision_mask = Layers.PLAYER
		trig.monitorable = false
		var px := _px(r)
		trig.add_child(_rect_shape(Rect2(px.position.x, px.position.y - TILE * 3, px.size.x, px.size.y + TILE * 3)))
		trig.body_entered.connect(_on_boss_trigger)
		add_child(trig)

	var laser_index := 0
	for y in height:
		for x in width:
			var c := cell(x, y)
			var feet := Vector2(x * TILE + TILE / 2.0, (y + 1) * TILE)
			if EMITTERS.has(c):
				_add_laser(x, y, EMITTERS[c], laser_index)
				laser_index += 1
			elif ArmorData.CAPSULE_CODES.has(c):
				var part: String = ArmorData.CAPSULE_CODES[c]
				if not collected.has(part):
					_add_pickup("part", part, part, feet)
			match c:
				"P":
					spawn = feet
				"w":
					_place(Walker.new(), feet)
				"t":
					_place(Turret.new(), feet)
				"C":
					var cp := Checkpoint.new()
					_place(cp, feet)
					checkpoints.append(cp)
				"G":
					goal = Goal.new()
					_place(goal, feet)
				"+":
					var id := "%s_hp_%d_%d" % [stage_id, x, y]
					if not collected.has(id):
						_add_pickup("hp", "", id, feet)
				"K":
					boss_spawn = Vector2(x * TILE + TILE / 2.0, y * TILE + TILE / 2.0)
					_compute_arena(x, y)
	queue_redraw()


func _add_pickup(kind: String, part: String, id: String, pos: Vector2) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.part_id = part
	p.pickup_id = id
	p.collected.connect(func(pk) -> void: pickup_collected.emit(pk))
	_place(p, pos)


func _add_laser(x: int, y: int, d: Vector2i, index: int) -> void:
	var laser := Laser.new()
	laser.emitter_rect = Rect2(x * TILE, y * TILE, TILE, TILE)
	laser.phase_offset = index * 1.1
	var pos := Vector2i(x, y)
	var start := _cell_center(pos) + Vector2(d) * (TILE / 2.0)
	var guard := 0
	while guard < 400:
		guard += 1
		pos += d
		var c := cell(pos.x, pos.y)
		if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
			laser.segments.append([start, _cell_center(pos - d) + Vector2(d) * (TILE / 2.0)])
			break
		if is_solid(pos.x, pos.y) or c == "x" or c == "D":
			laser.segments.append([start, _cell_center(pos) - Vector2(d) * (TILE / 2.0)])
			break
		if c == "/" or c == "\\":
			laser.segments.append([start, _cell_center(pos)])
			start = _cell_center(pos)
			if c == "/":
				d = Vector2i(-d.y, -d.x)
			else:
				d = Vector2i(d.y, d.x)
	add_child(laser)
	lasers.append(laser)


## Boss room: the empty area around 'K', bounded by solids / the door column.
func _compute_arena(kx: int, ky: int) -> void:
	var blocked := func(cx: int, cy: int) -> bool:
		return is_solid(cx, cy) or cell(cx, cy) == "D" or cx < 0 or cx >= width or cy < 0 or cy >= height
	var x0 := kx
	while not blocked.call(x0 - 1, ky):
		x0 -= 1
	var x1 := kx
	while not blocked.call(x1 + 1, ky):
		x1 += 1
	var y0 := ky
	while not blocked.call(kx, y0 - 1):
		y0 -= 1
	var y1 := ky
	while not blocked.call(kx, y1 + 1):
		y1 += 1
	boss_arena = Rect2(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE)
	var view := Vector2(384, 216)
	var cam_pos := Vector2(boss_arena.get_center().x - view.x / 2.0, boss_arena.end.y + TILE * 2 - view.y)
	boss_camera = Rect2(cam_pos, view)


func _on_boss_trigger(body: Node) -> void:
	if body.is_in_group("player") and not _door_closed:
		# Deferred: listeners add physics bodies, which is not allowed mid-flush.
		boss_triggered.emit.call_deferred()


## Greedy merge: horizontal runs of `ch`, then stacked runs with identical spans.
func _merge_rects(ch: String) -> Array[Rect2i]:
	var done: Array[Rect2i] = []
	var open := {}
	for y in height + 1:
		var spans := {}
		if y < height:
			var x := 0
			while x < width:
				if cell(x, y) == ch:
					var x0 := x
					while x < width and cell(x, y) == ch:
						x += 1
					spans[Vector2i(x0, x)] = true
				else:
					x += 1
		var next_open := {}
		for key in open:
			if spans.has(key):
				var r: Rect2i = open[key]
				r.size.y += 1
				next_open[key] = r
			else:
				done.append(open[key])
		for key in spans:
			if not next_open.has(key):
				next_open[key] = Rect2i(key.x, y, key.y - key.x, 1)
		open = next_open
	return done


func _px(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)


func _place(node: Node2D, pos: Vector2) -> void:
	node.position = pos
	add_child(node)


func _rect_shape(rect: Rect2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	return cs


# --- drawing ----------------------------------------------------------------------

func _draw() -> void:
	for y in height:
		for x in width:
			var c := cell(x, y)
			var pos := Vector2(x * TILE, y * TILE)
			match c:
				"#":
					_draw_solid(x, y, pos)
				"^":
					_draw_spikes(pos)
				"f":
					_draw_fake(x, y, pos)
				"/", "\\":
					_draw_mirror(pos, c == "/")
	if _door != null:
		if _door_closed:
			draw_rect(_door_rect, Color("2a3550"))
			var yy := _door_rect.position.y + 3.0
			while yy < _door_rect.end.y:
				draw_rect(Rect2(_door_rect.position.x + 2, yy, _door_rect.size.x - 4, 2), Color("e34f5b"))
				yy += 8.0
		else:
			draw_rect(Rect2(_door_rect.position.x + 6, _door_rect.position.y, 4, _door_rect.size.y), Color("497593", 0.4))


func _draw_solid(x: int, y: int, pos: Vector2) -> void:
	draw_rect(Rect2(pos, Vector2(TILE, TILE)), C_FILL)
	draw_rect(Rect2(pos + Vector2(1.5, 1.5), Vector2(TILE - 3, TILE - 3)), C_PANEL, false, 1.0)
	if (x * 7 + y * 13) % 5 == 0:
		draw_rect(Rect2(pos + Vector2(7, 7), Vector2(2, 2)), C_EDGE.darkened(0.55))
	if not _looks_solid(x, y - 1):
		draw_rect(Rect2(pos, Vector2(TILE, 2)), C_EDGE)
	if not _looks_solid(x - 1, y):
		draw_rect(Rect2(pos, Vector2(1, TILE)), C_EDGE.darkened(0.4))
	if not _looks_solid(x + 1, y):
		draw_rect(Rect2(pos + Vector2(TILE - 1, 0), Vector2(1, TILE)), C_EDGE.darkened(0.4))


## Fake tiles look like solid ground unless Vanguard HEAD reveals them.
func _draw_fake(x: int, y: int, pos: Vector2) -> void:
	if reveal:
		draw_rect(Rect2(pos + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color("f0b84a", 0.7), false, 1.0)
		draw_line(pos + Vector2(4, 4), pos + Vector2(12, 12), Color("f0b84a", 0.5), 1.0)
		draw_line(pos + Vector2(12, 4), pos + Vector2(4, 12), Color("f0b84a", 0.5), 1.0)
	else:
		_draw_solid(x, y, pos)


func _looks_solid(x: int, y: int) -> bool:
	var c := cell(x, y)
	return is_solid(x, y) or (c == "f" and not reveal)


func _draw_spikes(pos: Vector2) -> void:
	for i in 2:
		var bx := pos.x + i * 8
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx, pos.y + TILE), Vector2(bx + 4, pos.y + 6), Vector2(bx + 8, pos.y + TILE)]), C_SPIKE)
		draw_rect(Rect2(bx + 3, pos.y + 6, 2, 2), C_SPIKE_TIP)


func _draw_mirror(pos: Vector2, slash: bool) -> void:
	var a := pos + (Vector2(2, TILE - 2) if slash else Vector2(2, 2))
	var b := pos + (Vector2(TILE - 2, 2) if slash else Vector2(TILE - 2, TILE - 2))
	draw_line(a, b, Color("d7edf3"), 3.0)
	draw_line(a, b, Color("b78af3"), 1.0)
