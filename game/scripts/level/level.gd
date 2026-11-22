extends Node2D
## Builds a stage from an ASCII map. The full tile legend and the `; @key value`
## metadata header are documented in levels/README.md.
## Placeholder until real tile art exists: solid tiles are merged into as few
## collision rectangles as possible and drawn with draw_* calls.
##
## The level does not touch save data: the caller passes `collected` ids and the
## `reveal` flag, and listens to the signals below.

signal pickup_collected(pickup)
## kind: "main" (B / D / K markers) or "hidden" (b / d / Y markers).
signal boss_triggered(kind: String)

const TILE := 16
const Layers = preload("res://scripts/core/layers.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")
const Walker = preload("res://scripts/enemies/walker.gd")
const Turret = preload("res://scripts/enemies/turret.gd")
const PIXEL_SHADE = preload("res://scripts/fx/pixel_shade.gdshader")
const Checkpoint = preload("res://scripts/level/checkpoint.gd")
const Goal = preload("res://scripts/level/goal.gd")
const Breakable = preload("res://scripts/level/breakable.gd")
const BlinkPlatform = preload("res://scripts/level/blink_platform.gd")
const Laser = preload("res://scripts/level/laser.gd")
const Pickup = preload("res://scripts/level/pickup.gd")
const Crumble = preload("res://scripts/level/crumble_block.gd")
const Mover = preload("res://scripts/level/mover.gd")
const ElectricFloor = preload("res://scripts/level/electric_floor.gd")
const LevelChunk = preload("res://scripts/level/level_chunk.gd")
## Tiles are drawn in CHUNK x CHUNK blocks so off-screen blocks are culled.
const CHUNK := 16
const TILESET_DIR := "res://art/tiles/"

const C_FILL := Color("1c375b")
const C_PANEL := Color("142a47")
const C_EDGE := Color("00b8be")
const C_SPIKE := Color("d7edf3")
const C_SPIKE_TIP := Color("e34f5b")

## Emitter char -> [direction, style]
const EMITTERS := {
	">": [Vector2i.RIGHT, "laser"], "<": [Vector2i.LEFT, "laser"],
	"v": [Vector2i.DOWN, "laser"], "u": [Vector2i.UP, "flame"],
}
## Map chars that are solid for collision (cracked walls, doors, crumbling and
## moving blocks have their own bodies).
const SOLID_CHARS := ["#", ">", "<", "v", "u", "i", "e", "g"]
## Non-solid zones the player reacts to (see player.gd _zone_effects).
const ZONES := {"~": "water", "z": "lowg", "|": "lift"}
const ARENA_MARKERS := {
	"main": {"trigger": "B", "door": "D", "spawn": "K"},
	"hidden": {"trigger": "b", "door": "d", "spawn": "Y"},
}

var stage_id := ""
var collected: Array = []
## `; @key value` header lines (id, name, desc, order, boss, weapon, ...).
var meta := {}
var rows := PackedStringArray()
var width := 0
var height := 0
var spawn := Vector2.ZERO
var checkpoints: Array = []
var goal: Area2D = null
var solid_rects: Array[Rect2i] = []
var breakables: Array = []
var lasers: Array = []
## kind -> {"rect": Rect2 (inner arena), "camera": Rect2, "spawn": Vector2,
##          "door": StaticBody2D, "door_rect": Rect2, "closed": bool}
var arenas := {}
var reveal := false
var chunks: Array = []
## Canvas item the tile helpers draw on (the chunk being drawn).
var _ci: CanvasItem
## `func(req: String) -> bool` used for `; @alt` / `; @change` lines (GDD §5-4
## cross-stage changes). Unset = every requirement unmet (original layout).
var actors: CanvasGroup
var _tileset: Texture2D
var _ice_tiles: Texture2D
static var _tilesets := {}
var condition := Callable()
## `; @change` texts whose requirement is met for this load.
var active_changes: Array = []

# Main-arena shortcuts kept for older code / tests.
var boss_spawn := Vector2.INF
var boss_arena := Rect2()
var boss_camera := Rect2()


## Stage list from every `*.txt` in `dir` with an `@id`, sorted by `@order`.
static func load_registry(dir: String) -> Array:
	var out := []
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".txt"):
			continue
		var path := dir.path_join(file)
		var m := parse_meta(FileAccess.get_file_as_string(path))
		if not m.has("id"):
			continue
		m["path"] = path
		m["order"] = int(m.get("order", "99"))
		out.append(m)
	out.sort_custom(func(a, b): return a.order < b.order)
	return out


## Repeatable keys `alt` and `change` are collected into the arrays `alts` and
## `changes` (one entry per line); every other key keeps its last value.
static func parse_meta(text: String) -> Dictionary:
	var out := {"alts": [], "changes": []}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("; @"):
			var body := line.substr(3)
			var space := body.find(" ")
			if space > 0:
				var key := body.substr(0, space)
				var value := body.substr(space + 1).strip_edges()
				if key == "alt" or key == "change":
					out[key + "s"].append(value)
				else:
					out[key] = value
	return out


## `; @change <requirement> <text>` lines of a stage whose requirement `check` meets.
static func changes_met(m: Dictionary, check: Callable) -> Array:
	var out := []
	for line in m.get("changes", []):
		var space: int = line.find(" ")
		if space > 0 and check.is_valid() and check.call(line.substr(0, space)):
			out.append(line.substr(space + 1).strip_edges())
	return out


func load_from_file(path: String) -> void:
	load_from_text(FileAccess.get_file_as_string(path))


func load_from_text(text: String) -> void:
	meta = parse_meta(text)
	rows.clear()
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.begins_with(";"):
			continue
		rows.append(line)
	while rows.size() > 0 and rows[rows.size() - 1].strip_edges().is_empty():
		rows.remove_at(rows.size() - 1)
	_apply_alts()
	active_changes = changes_met(meta, condition)
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, r.length())
	_build()


## `; @alt <char> <requirement> <before> <after>`: every <char> in the map
## becomes <after> when the requirement is met, otherwise <before>.
func _apply_alts() -> void:
	for line in meta.get("alts", []):
		var bits: PackedStringArray = line.split(" ", false)
		if bits.size() < 4 or bits[0].length() != 1:
			push_warning("bad @alt line: " + line)
			continue
		var met: bool = condition.is_valid() and condition.call(bits[1])
		var to: String = bits[3] if met else bits[2]
		for i in rows.size():
			rows[i] = rows[i].replace(bits[0], to)


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func cell(x: int, y: int) -> String:
	if y < 0 or y >= height or x < 0:
		return "."
	var r := rows[y]
	return r[x] if x < r.length() else "."


func cell_at(pos: Vector2) -> String:
	return cell(floori(pos.x / TILE), floori(pos.y / TILE))


func is_solid(x: int, y: int) -> bool:
	return SOLID_CHARS.has(cell(x, y))


## "water", "lowg", "lift" or "" for the tile at a world position.
func zone_at(pos: Vector2) -> String:
	return ZONES.get(cell_at(pos), "")


func is_ice_at(pos: Vector2) -> bool:
	return cell_at(pos) == "i"


func set_reveal(value: bool) -> void:
	reveal = value
	for b in breakables:
		if is_instance_valid(b):
			b.reveal = value
	for c in chunks:
		c.queue_redraw()


func has_boss() -> bool:
	return has_arena("main")


func has_arena(kind: String) -> bool:
	return arenas.has(kind) and arenas[kind].has("rect")


## Seals an arena behind the player.
func close_door(kind := "main") -> void:
	if not arenas.has(kind) or arenas[kind].closed:
		return
	arenas[kind].closed = true
	if arenas[kind].door != null:
		arenas[kind].door.collision_layer = Layers.WORLD
	queue_redraw()


## Reopens an arena door (after a hidden boss, so the player can leave).
func open_door(kind := "main") -> void:
	if not arenas.has(kind):
		return
	arenas[kind].closed = false
	if arenas[kind].door != null:
		arenas[kind].door.collision_layer = 0
	queue_redraw()


# --- build ----------------------------------------------------------------------

func _build() -> void:
	_tileset = tileset(meta.get("id", "training"))
	_ice_tiles = tileset("ice")
	for cy in range(0, height, CHUNK):
		for cx in range(0, width, CHUNK):
			var chunk := LevelChunk.new()
			chunk.level = self
			chunk.cells = Rect2i(cx, cy, mini(CHUNK, width - cx), mini(CHUNK, height - cy))
			add_child(chunk)
			chunks.append(chunk)
	solid_rects = []
	for ch in SOLID_CHARS:
		solid_rects.append_array(_merge_rects(ch))
	var body := StaticBody2D.new()
	body.name = "Solids"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	for r in solid_rects:
		body.add_child(_rect_shape(_px(r)))
	# Invisible ceiling 5 tiles above the map: full jumps from the top rows still
	# work, but flight / lifts cannot carry the player off the top of the stage.
	body.add_child(_rect_shape(Rect2(-TILE, -TILE * 6, (width + 2) * TILE, TILE)))
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

	for r in _runs("c"):
		var crumble := Crumble.new()
		crumble.rect = _px(r)
		add_child(crumble)
	for pair in [["m", Vector2.RIGHT], ["n", Vector2.UP]]:
		for r in _runs(pair[0]):
			var mover := Mover.new()
			mover.rect = _px(r)
			mover.axis = pair[1]
			add_child(mover)
	var electric := _merge_rects("e")
	if not electric.is_empty():
		var floor_node := ElectricFloor.new()
		for r in electric:
			floor_node.rects.append(_px(r))
		add_child(floor_node)

	for kind in ARENA_MARKERS:
		_build_arena_door(kind)

	_make_actors()  # above the tiles, below the player
	var laser_index := 0
	for y in height:
		for x in width:
			var c := cell(x, y)
			var feet := Vector2(x * TILE + TILE / 2.0, (y + 1) * TILE)
			if EMITTERS.has(c):
				_add_laser(x, y, EMITTERS[c][0], EMITTERS[c][1], laser_index)
				laser_index += 1
			elif ArmorData.CAPSULE_CODES.has(c):
				var part: String = ArmorData.CAPSULE_CODES[c]
				if not collected.has(part):
					_add_pickup("part", part, part, feet)
			match c:
				"P":
					spawn = feet
				"w":
					add_actor(Walker.new(), feet)
				"t":
					add_actor(Turret.new(), feet)
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
				"K", "Y":
					var kind := "main" if c == "K" else "hidden"
					_compute_arena(kind, x, y)
	if has_arena("main"):
		boss_spawn = arenas.main.spawn
		boss_arena = arenas.main.rect
		boss_camera = arenas.main.camera
	for kind in ARENA_MARKERS:
		for r in _merge_rects(ARENA_MARKERS[kind].trigger):
			var trig := Area2D.new()
			trig.collision_layer = Layers.TRIGGER
			trig.collision_mask = Layers.PLAYER
			trig.monitorable = false
			var px := _px(r)
			trig.add_child(_rect_shape(Rect2(px.position.x, px.position.y - TILE * 3, px.size.x, px.size.y + TILE * 3)))
			trig.body_entered.connect(_on_arena_trigger.bind(kind))
			add_child(trig)
	queue_redraw()


func _build_arena_door(kind: String) -> void:
	var door_rects := _merge_rects(ARENA_MARKERS[kind].door)
	if door_rects.is_empty():
		return
	var door := StaticBody2D.new()
	door.collision_layer = 0
	door.collision_mask = 0
	for r in door_rects:
		door.add_child(_rect_shape(_px(r)))
	add_child(door)
	var entry: Dictionary = arenas.get(kind, {})
	entry["door"] = door
	entry["door_rect"] = _px(door_rects[0])
	entry["closed"] = false
	arenas[kind] = entry


func _add_pickup(kind: String, part: String, id: String, pos: Vector2) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.part_id = part
	p.pickup_id = id
	p.collected.connect(func(pk) -> void: pickup_collected.emit(pk))
	_place(p, pos)


func _add_laser(x: int, y: int, d: Vector2i, style: String, index: int) -> void:
	var laser := Laser.new()
	laser.style = style
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
		if is_solid(pos.x, pos.y) or c in ["x", "D", "d", "c", "m", "n"]:
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


## Arena: the empty area around the spawn marker, bounded by solids / doors.
func _compute_arena(kind: String, kx: int, ky: int) -> void:
	var blocked := func(cx: int, cy: int) -> bool:
		return is_solid(cx, cy) or cell(cx, cy) in ["D", "d"] or cx < 0 or cx >= width \
				or cy < 0 or cy >= height
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
	var rect := Rect2(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE)
	var view := Vector2(384, 216)
	var cam_pos := Vector2(rect.get_center().x - view.x / 2.0, rect.end.y + TILE * 2 - view.y)
	var entry: Dictionary = arenas.get(kind, {"door": null, "door_rect": Rect2(), "closed": false})
	entry["rect"] = rect
	entry["camera"] = Rect2(cam_pos, view)
	entry["spawn"] = Vector2(kx * TILE + TILE / 2.0, ky * TILE + TILE / 2.0)
	arenas[kind] = entry


func _on_arena_trigger(body: Node, kind: String) -> void:
	if body.is_in_group("player") and has_arena(kind) and not arenas[kind].closed:
		# Deferred: listeners add physics bodies, which is not allowed mid-flush.
		boss_triggered.emit.call_deferred(kind)


## Greedy merge: horizontal runs of `ch`, then stacked runs with identical spans.
func _merge_rects(ch: String) -> Array[Rect2i]:
	var done: Array[Rect2i] = []
	var open := {}
	for y in height + 1:
		var spans := {}
		if y < height:
			for span in _row_spans(ch, y):
				spans[span] = true
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


## Horizontal runs only (each run is its own object: crumbling / moving blocks).
func _runs(ch: String) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for y in height:
		for span in _row_spans(ch, y):
			out.append(Rect2i(span.x, y, span.y - span.x, 1))
	return out


func _row_spans(ch: String, y: int) -> Array:
	var spans := []
	var x := 0
	while x < width:
		if cell(x, y) == ch:
			var x0 := x
			while x < width and cell(x, y) == ch:
				x += 1
			spans.append(Vector2i(x0, x))
		else:
			x += 1
	return spans


func _px(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)


func _place(node: Node2D, pos: Vector2) -> void:
	node.position = pos
	add_child(node)


## Enemies, bosses and everything they spawn live in `actors`, a CanvasGroup
## whose shader gives the vector drawing a pixel-art outline and edge shading.
func add_actor(node: Node2D, pos := Vector2.INF) -> void:
	if pos != Vector2.INF:
		node.position = pos
	_make_actors()
	actors.add_child(node)


## Level children plus everything inside the actor layer (enemies, bosses).
func entities() -> Array:
	var out: Array = get_children()
	if actors != null:
		out.append_array(actors.get_children())
	return out


func _make_actors() -> void:
	if actors != null:
		return
	actors = CanvasGroup.new()
	actors.name = "Actors"
	var mat := ShaderMaterial.new()
	mat.shader = PIXEL_SHADE
	actors.material = mat
	actors.fit_margin = 4.0
	add_child(actors)


func _rect_shape(rect: Rect2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.get_center()
	return cs


# --- drawing ----------------------------------------------------------------------

## Draws the tiles of `r` onto `ci` (called from LevelChunk._draw).
func draw_cells(ci: CanvasItem, r: Rect2i) -> void:
	_ci = ci
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := cell(x, y)
			var pos := Vector2(x * TILE, y * TILE)
			if c != "~" and not is_solid(x, y) and _in_water(x, y):
				_ci.draw_rect(Rect2(pos, Vector2(TILE, TILE)), Color(0.2, 0.5, 0.85, 0.28))
			match c:
				"#", "e":
					_draw_solid(x, y, pos)
				"g":
					_draw_gate(x, y, pos)
				"i":
					_draw_ice(x, y, pos)
				"^":
					_draw_spikes(pos)
				"f":
					_draw_fake(x, y, pos)
				"/", "\\":
					_draw_mirror(pos, c == "/")
				"~":
					_draw_water(x, y, pos)
				"z":
					if (x + y) % 3 == 0:
						_ci.draw_rect(Rect2(pos + Vector2(7, 7), Vector2(2, 2)), Color("b78af3", 0.35))
				"|":
					_ci.draw_rect(Rect2(pos + Vector2(3, 0), Vector2(10, TILE)), Color("71dedf", 0.22))
					_ci.draw_rect(Rect2(pos + Vector2(4, 0), Vector2(1, TILE)), Color("71dedf", 0.5))
					_ci.draw_rect(Rect2(pos + Vector2(11, 0), Vector2(1, TILE)), Color("71dedf", 0.5))
					_ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(5, 10 - (y % 2) * 5),
							pos + Vector2(8, 6 - (y % 2) * 5), pos + Vector2(11, 10 - (y % 2) * 5)]), Color("d7edf3", 0.7))


## Arena doors (the tiles themselves are drawn by the chunks).
func _draw() -> void:
	for kind in arenas:
		var a: Dictionary = arenas[kind]
		if a.get("door") == null:
			continue
		var r: Rect2 = a.door_rect
		if a.closed:
			draw_rect(r, Color("2a3550"))
			var yy := r.position.y + 3.0
			while yy < r.end.y:
				draw_rect(Rect2(r.position.x + 2, yy, r.size.x - 4, 2), Color("e34f5b"))
				yy += 8.0
		else:
			draw_rect(Rect2(r.position.x + 6, r.position.y, 4, r.size.y), Color("497593", 0.4))


func _draw_solid(x: int, y: int, pos: Vector2) -> void:
	_draw_tile(_tileset, x, y, pos)
	if cell(x, y) == "e" and not _looks_solid(x, y - 1):
		_ci.draw_rect(Rect2(pos + Vector2(0, 1), Vector2(TILE, 2)), Color("efcf5f"))


## One tile from a baked tileset (tools/bake_tiles.gd): the column is the mask of
## exposed sides (1 up, 2 right, 4 down, 8 left), the row a surface variant picked
## from the position (plain most of the time).
func _draw_tile(tex: Texture2D, x: int, y: int, pos: Vector2) -> void:
	var m := (1 if not _looks_solid(x, y - 1) else 0) | (2 if not _looks_solid(x + 1, y) else 0) \
			| (4 if not _looks_solid(x, y + 1) else 0) | (8 if not _looks_solid(x - 1, y) else 0)
	var hsh := absi((x * 73856093) ^ (y * 19349663)) % 20
	var v := 0 if hsh < 11 else (1 if hsh < 15 else (2 if hsh < 18 else 3))
	_ci.draw_texture_rect_region(tex, Rect2(pos, Vector2(TILE, TILE)), Rect2(m * TILE, v * TILE, TILE, TILE))
	# Deep inside a wall: darker, so the surfaces read first.
	if m == 0:
		var depth := 1 if _surrounded(x, y, 1) else 0
		if depth == 1 and _surrounded(x, y, 2):
			depth = 2
		if depth > 0:
			_ci.draw_rect(Rect2(pos, Vector2(TILE, TILE)), Color(0.02, 0.03, 0.09, 0.2 * depth))


func _surrounded(x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (absi(dx) == r or absi(dy) == r) and not _looks_solid(x + dx, y + dy):
				return false
	return true


## Tileset for a stage theme (falls back to the training set).
static func tileset(theme: String) -> Texture2D:
	var path := TILESET_DIR + theme + ".png"
	if not ResourceLoader.exists(path):
		path = TILESET_DIR + "training.png"
	if not _tilesets.has(path):
		_tilesets[path] = load(path)
	return _tilesets[path]


## A non-water cell that sits inside a body of water (water above, or on both sides).
func _in_water(x: int, y: int) -> bool:
	return cell(x, y - 1) == "~" or (cell(x - 1, y) == "~" and cell(x + 1, y) == "~")


func _draw_ice(x: int, y: int, pos: Vector2) -> void:
	_draw_tile(_ice_tiles, x, y, pos)


func _draw_water(x: int, y: int, pos: Vector2) -> void:
	_ci.draw_rect(Rect2(pos, Vector2(TILE, TILE)), Color(0.2, 0.5, 0.85, 0.28))
	if cell(x, y - 1) != "~":
		_ci.draw_rect(Rect2(pos, Vector2(TILE, 1)), Color(0.7, 0.9, 1.0, 0.7))


## Fake tiles look like solid ground unless Vanguard HEAD reveals them.
func _draw_fake(x: int, y: int, pos: Vector2) -> void:
	if reveal:
		_ci.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color("f0b84a", 0.7), false, 1.0)
		_ci.draw_line(pos + Vector2(4, 4), pos + Vector2(12, 12), Color("f0b84a", 0.5), 1.0)
		_ci.draw_line(pos + Vector2(12, 4), pos + Vector2(4, 12), Color("f0b84a", 0.5), 1.0)
	else:
		_draw_solid(x, y, pos)


func _looks_solid(x: int, y: int) -> bool:
	var c := cell(x, y)
	return is_solid(x, y) or (c == "f" and not reveal)


## Sealed gate: solid until a cross-stage change opens it (see `; @alt`).
func _draw_gate(x: int, y: int, pos: Vector2) -> void:
	_ci.draw_rect(Rect2(pos, Vector2(TILE, TILE)), Color("2a2f45"))
	for i in 3:
		var bx := pos.x + 1 + i * 5 + (y % 2) * 2
		_ci.draw_line(Vector2(bx, pos.y + TILE), Vector2(minf(bx + 4, pos.x + TILE), pos.y), Color("efcf5f", 0.55), 2.0)
	_ci.draw_rect(Rect2(pos + Vector2(0.5, 0.5), Vector2(TILE - 1, TILE - 1)), Color("efcf5f", 0.8), false, 1.0)
	if cell(x, y - 1) != "g":
		_ci.draw_rect(Rect2(pos + Vector2(5, 4), Vector2(6, 5)), Color("e34f5b"))
		_ci.draw_rect(Rect2(pos + Vector2(6, 1), Vector2(4, 4)), Color("e34f5b"), false, 1.0)


func _draw_spikes(pos: Vector2) -> void:
	for i in 2:
		var bx := pos.x + i * 8
		_ci.draw_colored_polygon(PackedVector2Array([
			Vector2(bx, pos.y + TILE), Vector2(bx + 4, pos.y + 6), Vector2(bx + 8, pos.y + TILE)]), C_SPIKE)
		_ci.draw_rect(Rect2(bx + 3, pos.y + 6, 2, 2), C_SPIKE_TIP)


func _draw_mirror(pos: Vector2, slash: bool) -> void:
	var a := pos + (Vector2(2, TILE - 2) if slash else Vector2(2, 2))
	var b := pos + (Vector2(TILE - 2, 2) if slash else Vector2(TILE - 2, TILE - 2))
	_ci.draw_line(a, b, Color("d7edf3"), 3.0)
	_ci.draw_line(a, b, Color("b78af3"), 1.0)
