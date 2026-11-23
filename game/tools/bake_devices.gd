extends SceneTree
## Bakes the stage-device sprites into res://art/devices/<name>.png.
##   godot --headless --path game -s res://tools/bake_devices.gd [-- --preview=/abs/dir]
##
## Same rules as the tiles (tools/bake_tiles.gd) and the character sprites: 1 px dark
## outline, light from the upper left (lit top / left, shadowed bottom / right), 3-5
## tones per material, 1-2 px glints, panel lines and rivets. Each device keeps the
## colour of its old flat drawing (navy steel, hazard red, gold, olive, cyan).
## Original designs; deterministic (re-running gives identical PNGs).
## Moving light (beams, arcs, hologram fields, glows, lamps) is drawn in code by each
## device script on top of these. Layouts (read by the scripts):
##   checkpoint  5 frames 18x46 (0 off, 1-4 lit chase), origin = feet at (9, 46)
##   goal        1 frame 32x50 (pylons and lintel), origin = feet at (16, 50)
##   emitter     16x16: column = style * 3 + state (laser / flame; off, warn, on),
##               row = facing (right, left, down, up)
##   crumble     16x16: column = piece (single, left, middle, right), row = crack stage
##   mover       16x16: column = piece, row = axis (0 slides, 1 bobs)
##   cracked_wall 16x16: column = exposed-side mask (1 up, 2 right, 4 down, 8 left),
##               row = crack variant
##   spikes 1 cell · mirror 2 cells ('/', '\') · gate / door 4 cells (single, top,
##   middle, bottom)

const T := 16
const OUT := "res://art/devices"
const OUTLINE := Color("0a1326")
const CLEAR := Color(0, 0, 0, 0)

## Palettes run deep -> glint: [deep, dark, mid, light, glint].
const STEEL := [Color("161d33"), Color("2a3550"), Color("3c5576"), Color("5f88a8"), Color("b4d4e6")]
const RED := [Color("4a1020"), Color("a3243a"), Color("e34f5b"), Color("ff9aa2"), Color("ffe3e3")]
const GOLD := [Color("4a3412"), Color("a3772a"), Color("f0b84a"), Color("ffe3a0"), Color("fff8e0")]
const CYAN := [Color("0b3f4a"), Color("00838a"), Color("00b8be"), Color("8af5f8"), Color("e6ffff")]
const VIOLET := [Color("231a40"), Color("3f2d70"), Color("6543a2"), Color("9d7ae6"), Color("e2d4ff")]
const FLAME := [Color("4a1e12"), Color("a3502a"), Color("ef9352"), Color("f0b84a"), Color("fff0b0")]
const OLIVE := [Color("1e2616"), Color("33402a"), Color("4a5a3a"), Color("6b7d52"), Color("9fc274"), Color("d4ecb0")]
## Cracked wall: the navy plate of the old drawing (1c375b) with its panel line (142a47).
const WALL := [Color("0d1a30"), Color("142a47"), Color("1c375b"), Color("2b4f7c"), Color("4a72a0")]
const SPIKE := [Color("3b4d66"), Color("8fa8bd"), Color("bcd2e0"), Color("d7edf3"), Color("ffffff")]

const CP_W := 18
const CP_H := 46
const GOAL_W := 32
const GOAL_H := 50

var _img: Image
var _ox := 0
var _oy := 0
var _clip := Rect2i()


func _init() -> void:
	var preview := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			preview = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sheets := {}
	sheets["checkpoint"] = _sheet(CP_W * 5, CP_H, func(img: Image) -> void:
		for f in 5:
			_checkpoint(img, f))
	sheets["goal"] = _sheet(GOAL_W, GOAL_H, _goal)
	sheets["emitter"] = _sheet(T * 6, T * 4, func(img: Image) -> void:
		var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
		for row in 4:
			for col in 6:
				_emitter(img, col, row, dirs[row], "flame" if col >= 3 else "laser", col % 3))
	sheets["crumble"] = _sheet(T * 4, T * 3, func(img: Image) -> void:
		for stage in 3:
			for piece in 4:
				_crumble(img, piece, stage))
	sheets["mover"] = _sheet(T * 4, T * 2, func(img: Image) -> void:
		for axis in 2:
			for piece in 4:
				_mover(img, piece, axis))
	sheets["cracked_wall"] = _sheet(T * 16, T * 2, func(img: Image) -> void:
		for variant in 2:
			for mask in 16:
				_cracked(img, mask, variant))
	sheets["spikes"] = _sheet(T, T, _spikes)
	sheets["mirror"] = _sheet(T * 2, T, func(img: Image) -> void:
		_mirror(img, 0, true)
		_mirror(img, 1, false))
	sheets["gate"] = _sheet(T * 4, T, func(img: Image) -> void:
		for piece in 4:
			_gate(img, piece))
	sheets["door"] = _sheet(T * 4, T, func(img: Image) -> void:
		for piece in 4:
			_door(img, piece))
	for sheet_name in sheets:
		sheets[sheet_name].save_png(ProjectSettings.globalize_path(OUT.path_join(sheet_name + ".png")))
	if preview != "":
		_preview(sheets, preview)
	print("baked %d device sheets" % sheets.size())
	quit()


func _sheet(w: int, h: int, painter: Callable) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	painter.call(img)
	return img


# --- helpers ---------------------------------------------------------------------------

## Paint into `cell` (absolute rect in `img`); pixel (0, 0) is `origin` (absolute).
func _begin(img: Image, cell: Rect2i, origin: Vector2i) -> void:
	_img = img
	_clip = cell
	_ox = origin.x
	_oy = origin.y


func _cell(img: Image, col: int, row: int) -> void:
	_begin(img, Rect2i(col * T, row * T, T, T), Vector2i(col * T, row * T))


func _px(x: int, y: int, c: Color) -> void:
	var p := Vector2i(_ox + x, _oy + y)
	if _clip.has_point(p):
		_img.set_pixelv(p, c)


func _at(x: int, y: int) -> Color:
	var p := Vector2i(_ox + x, _oy + y)
	return _img.get_pixelv(p) if _clip.has_point(p) else CLEAR


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)


func _line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_px(x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## Bevelled block: fill pal[2], lit top / left pal[3], shadowed bottom / right
## pal[1], glint pal[4] in the lit corner, 1 px outline around when `outline`.
func _box(x: int, y: int, w: int, h: int, pal: Array, outline := true) -> void:
	if outline:
		_rect(x, y, w, h, OUTLINE)
		x += 1
		y += 1
		w -= 2
		h -= 2
	_rect(x, y, w, h, pal[2])
	_rect(x, y, w, 1, pal[3])
	_rect(x, y, 1, h, pal[3])
	_rect(x, y + h - 1, w, 1, pal[1])
	_rect(x + w - 1, y, 1, h, pal[1])
	_px(x, y, pal[4])


## Rivet: lit dot with its shadow below-right.
func _rivet(x: int, y: int, pal: Array) -> void:
	_px(x, y, pal[4])
	_px(x + 1, y + 1, pal[0])


## 1 px outline around every opaque pixel of the current cell.
func _auto_outline() -> void:
	var pts: Array[Vector2i] = []
	for y in range(_clip.position.y, _clip.end.y):
		for x in range(_clip.position.x, _clip.end.x):
			if _img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if _clip.has_point(n) and _img.get_pixelv(n).a > 0.0 and _img.get_pixelv(n) != OUTLINE:
					pts.append(Vector2i(x, y))
					break
	for p in pts:
		_img.set_pixelv(p, OUTLINE)


## Deterministic hash noise in [0, 1).
static func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 10007) / 10007.0


# --- checkpoint --------------------------------------------------------------------------

## Beacon post: base plate, collar, pole with two LED rings, lamp head with a lens.
## Frame 0 is unlit; frames 1-4 are lit, a bright LED climbing base -> lamp.
func _checkpoint(img: Image, frame: int) -> void:
	_begin(img, Rect2i(frame * CP_W, 0, CP_W, CP_H), Vector2i(frame * CP_W + 9, CP_H))
	var s := STEEL
	var lit := frame > 0
	var chase := frame - 1
	var led := func(on: bool) -> Color:
		if not lit:
			return s[0]
		return CYAN[3] if on else CYAN[1]
	# Base plate and collar.
	_shade_box(-6, -4, 12, 3, s)
	_rivet(-4, -4, s)
	_rivet(2, -4, s)
	_px(-1, -3, led.call(chase == 0))
	_px(0, -3, led.call(chase == 0))
	_shade_box(-4, -8, 8, 4, s)
	_rect(-3, -6, 6, 1, s[1])
	# Pole.
	_rect(-2, -31, 4, 23, s[2])
	_rect(-2, -31, 1, 23, s[3])
	_rect(1, -31, 1, 23, s[1])
	_rect(-2, -29, 1, 3, s[4])
	for ring in [[-14, chase == 1], [-22, chase == 2]]:
		var ry: int = ring[0]
		_shade_box(-3, ry, 6, 3, s)
		_px(-1, ry + 1, led.call(ring[1]))
		_px(0, ry + 1, led.call(ring[1]))
	# Lamp head: housing, side fins, dome, antenna.
	_shade_box(-5, -41, 10, 10, s)
	_rect(-6, -39, 1, 5, s[2])
	_rect(5, -39, 1, 5, s[1])
	_rect(-3, -43, 6, 2, s[2])
	_rect(-2, -43, 4, 1, s[3])
	_px(-1, -44, CYAN[3] if lit and chase == 3 else (CYAN[1] if lit else s[1]))
	_px(0, -44, CYAN[2] if lit else s[1])
	# Lens: dark rim, glass gradient lit from the top.
	_rect(-3, -39, 6, 6, s[0])
	var glass: Array = [s[2], s[1], s[1], s[0]]
	if lit:
		glass = [CYAN[3], CYAN[2], CYAN[2], CYAN[1]]
		if chase == 3:
			glass = [CYAN[4], CYAN[3], CYAN[2], CYAN[2]]
	for i in 4:
		_rect(-2, -38 + i, 4, 1, glass[i])
	_px(-2, -38, CYAN[4] if lit else s[3])
	_px(1, -35, CYAN[2] if lit else s[1])
	_auto_outline()


## _box without its own outline (the auto outline goes around the whole sprite).
func _shade_box(x: int, y: int, w: int, h: int, pal: Array) -> void:
	_box(x, y, w, h, pal, false)


# --- goal --------------------------------------------------------------------------------

## Exit gate: two pylons with cyan emitter strips facing the field, a lintel with
## a diamond emblem. The field between the pylons is drawn by goal.gd.
func _goal(img: Image) -> void:
	_begin(img, Rect2i(0, 0, GOAL_W, GOAL_H), Vector2i(16, GOAL_H))
	var s := STEEL
	for side in [-1, 1]:
		var x0 := -14 if side < 0 else 9
		# Foot.
		_shade_box(x0 - 1, -5, 7, 4, s)
		_rivet(x0, -4, s)
		# Pylon.
		_rect(x0, -41, 5, 36, s[2])
		_rect(x0, -41, 1, 36, s[3])
		_rect(x0 + 3, -41, 1, 36, s[1])
		_rect(x0 + 4, -41, 1, 36, s[1] if side < 0 else s[2])
		_rect(x0, -39, 1, 4, s[4])
		# Panel seams.
		for sy in [-32, -23, -14]:
			_rect(x0, sy, 5, 1, s[0])
			_rect(x0, sy + 1, 5, 1, s[3])
		# Emitter strip on the side facing the field.
		var ex := x0 + 4 if side < 0 else x0
		for ey in [-38, -29, -20, -11]:
			_rect(ex, ey, 1, 4, CYAN[2])
			_px(ex, ey, CYAN[4])
			_px(ex, ey + 3, CYAN[1])
	# Lintel.
	_shade_box(-15, -46, 30, 5, s)
	_rect(-14, -43, 28, 1, s[2])
	for rx in [-13, -9, 6, 10]:
		_rivet(rx, -45, s)
	# Emblem plate with a diamond.
	_shade_box(-4, -48, 8, 8, s)
	_rect(-1, -46, 2, 1, CYAN[3])
	_rect(-2, -45, 4, 2, CYAN[2])
	_rect(-1, -43, 2, 1, CYAN[1])
	_px(-2, -45, CYAN[4])
	_px(-1, -46, CYAN[4])
	_auto_outline()


# --- laser emitter / heat vent -----------------------------------------------------------

## Steel housing with a barrel facing `dir`. Lasers: lens dim violet (off), hot
## red (warn), white-red (on), red hazard bands on the back. Flame vents: a grille
## throat dark / glowing / blazing, orange bands.
func _emitter(img: Image, col: int, row: int, dir: Vector2i, style: String, state: int) -> void:
	_cell(img, col, row)
	var s := STEEL
	var hot: Array = RED if style == "laser" else FLAME
	_box(0, 0, T, T, s)
	_rect(2, 2, 12, 12, s[2])
	_rect(2, 2, 12, 1, s[1])
	_rect(2, 2, 1, 12, s[1])
	_rect(2, 13, 12, 1, s[3])
	_rect(13, 2, 1, 12, s[3])
	# Hazard bands on the back half (the side away from the barrel).
	var back := Rect2i(3, 3, 10, 10)
	match dir:
		Vector2i.RIGHT:
			back = Rect2i(3, 3, 4, 10)
		Vector2i.LEFT:
			back = Rect2i(9, 3, 4, 10)
		Vector2i.DOWN:
			back = Rect2i(3, 3, 10, 4)
		Vector2i.UP:
			back = Rect2i(3, 9, 10, 4)
	for y in range(back.position.y, back.end.y):
		for x in range(back.position.x, back.end.x):
			_px(x, y, hot[1] if posmod(x + y, 4) < 2 else s[0])
	for p in [Vector2i(2, 2), Vector2i(12, 2), Vector2i(2, 12), Vector2i(12, 12)]:
		_rivet(p.x, p.y, s)
	# Barrel and muzzle, drawn in facing space: u runs back -> front, v across.
	# Shading follows v, which is y for sideways barrels and x for vertical ones,
	# so both stay lit from the top / left.
	var to_xy := func(u: int, v: int) -> Vector2i:
		match dir:
			Vector2i.LEFT:
				return Vector2i(T - 1 - u, v)
			Vector2i.DOWN:
				return Vector2i(v, u)
			Vector2i.UP:
				return Vector2i(v, T - 1 - u)
		return Vector2i(u, v)
	var put := func(u: int, v: int, c: Color) -> void:
		var p: Vector2i = to_xy.call(u, v)
		_px(p.x, p.y, c)
	var tube := [s[4], s[3], s[3], s[2], s[2], s[1]]
	for u in range(6, 12):
		put.call(u, 4, OUTLINE)
		put.call(u, 11, OUTLINE)
		for v in range(5, 11):
			put.call(u, v, tube[v - 5])
	put.call(8, 5, s[4].lightened(0.3))
	var collar := [s[4], s[3], s[3], s[2], s[2], s[1], s[1], s[0]]
	for u in range(11, 16):
		for v in range(3, 13):
			var edge := u == 11 or v == 3 or v == 12 or (u == 15 and (v < 5 or v > 10))
			put.call(u, v, OUTLINE if edge else collar[v - 4])
	for v in range(4, 12):
		put.call(13, v, s[0])
	# Lens / throat on the muzzle face.
	var glass: Array
	if style == "laser":
		glass = [VIOLET[3], VIOLET[2], VIOLET[2], VIOLET[1], VIOLET[1], VIOLET[0]] if state == 0 else \
				([RED[3], RED[2], RED[2], RED[2], RED[1], RED[1]] if state == 1 else
				[RED[4], RED[4], RED[3], RED[3], RED[2], RED[2]])
	else:
		glass = [s[2], s[1], s[0], s[1], s[0], s[0]] if state == 0 else \
				([FLAME[3], FLAME[2], FLAME[1], FLAME[2], FLAME[1], FLAME[1]] if state == 1 else
				[FLAME[4], FLAME[3], FLAME[2], FLAME[3], FLAME[2], FLAME[2]])
	for v in range(5, 11):
		put.call(14, v, glass[v - 5])
		put.call(15, v, glass[v - 5] if style == "laser" or v % 2 == 1 else OUTLINE)
	put.call(15, 5, glass[0].lightened(0.4))
	# Status LED on the housing (lit while warning / firing).
	put.call(4, 13, hot[3] if state > 0 else s[0])


# --- crumbling floor ----------------------------------------------------------------------

## Olive slab with a pale top crust; piece 0 single, 1 left end, 2 middle, 3 right
## end; stage 0 intact, 1 cracking, 2 breaking apart (chips missing).
func _crumble(img: Image, piece: int, stage: int) -> void:
	_cell(img, piece, stage)
	var o := OLIVE
	var left := piece == 0 or piece == 1
	var right := piece == 0 or piece == 3
	var seed := piece * 31 + 7
	_rect(0, 0, T, T, o[2])
	# Top crust.
	_rect(0, 1, T, 1, o[5])
	_rect(0, 2, T, 2, o[4])
	_rect(0, 4, T, 1, o[3])
	_rect(0, 5, T, 1, o[1])
	for x in range(1, T, 4):
		_px(x + (piece % 2), 3, o[3])
	# Two stone courses with offset joints.
	_rect(0, 10, T, 1, o[1])
	_rect(0, 11, T, 1, o[3])
	var j1 := 7 + (piece % 2) * 2
	_rect(j1, 6, 1, 4, o[1])
	_rect(j1 + 1, 6, 1, 4, o[3])
	_rect(3, 11, 1, 3, o[1])
	_rect(12, 11, 1, 3, o[1])
	# Grain.
	for i in 6:
		var gx := int(_h(i, piece, seed) * 14.0) + 1
		var gy := 6 + int(_h(i + 9, piece, seed) * 7.0)
		if _at(gx, gy) == o[2]:
			_px(gx, gy, o[3] if i % 2 == 0 else o[1])
	# Seam to the neighbouring block of the same run.
	if not left:
		_rect(0, 5, 1, 10, o[3])
	if not right:
		_rect(T - 1, 5, 1, 10, o[1])
	# Ragged underside.
	_rect(0, 14, T, 1, o[1])
	_rect(0, 15, T, 1, OUTLINE)
	for x in range(1, T, 5):
		_px(x + (seed % 3), 15, CLEAR)
		_px(x + (seed % 3), 14, OUTLINE)
	# Exposed ends: bevel and outline, rounded top corners.
	if left:
		_rect(1, 1, 1, 14, o[4])
		_rect(0, 0, 1, T, OUTLINE)
		_px(0, 0, CLEAR)
	if right:
		_rect(T - 2, 2, 1, 13, o[1])
		_rect(T - 1, 0, 1, T, OUTLINE)
		_px(T - 1, 0, CLEAR)
	_rect(1 if left else 0, 0, T - (1 if left else 0) - (1 if right else 0), 1, OUTLINE)
	# Cracks.
	if stage >= 1:
		var cx := 4 + (seed % 5)
		_crack([Vector2i(cx, 1), Vector2i(cx + 2, 5), Vector2i(cx + 1, 8), Vector2i(cx + 3, 11)])
	if stage >= 2:
		var cx2 := 11 - (seed % 4)
		_crack([Vector2i(cx2, 1), Vector2i(cx2 - 2, 4), Vector2i(cx2 - 1, 9), Vector2i(cx2 - 3, 14)])
		_crack([Vector2i(cx2 - 1, 9), Vector2i(cx2 + 3, 11)])
		# Chips falling out of the underside.
		for x in [2 + seed % 3, 9 + seed % 2]:
			_rect(x, 13, 2, 3, CLEAR)
			_px(x, 12, OUTLINE)
			_px(x + 1, 12, OUTLINE)


## Dark fracture line with a lit chipped edge on its left.
func _crack(points: Array) -> void:
	for i in points.size() - 1:
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		_line(a.x - 1, a.y, b.x - 1, b.y, OLIVE[4])
	for i in points.size() - 1:
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		_line(a.x, a.y, b.x, b.y, OLIVE[0])


# --- moving platform -----------------------------------------------------------------------

## Navy car with a gold deck trim and gold window lights. Axis 0 (slides): maglev
## skids with glowing pads; axis 1 (bobs): thruster nozzles under the hull.
## End pieces carry an unlit direction lamp (lit by mover.gd).
func _mover(img: Image, piece: int, axis: int) -> void:
	_cell(img, piece, axis)
	var s := STEEL
	var g := GOLD
	var left := piece == 0 or piece == 1
	var right := piece == 0 or piece == 3
	# Hull.
	_rect(0, 0, T, 13, s[2])
	_rect(0, 1, T, 1, g[3])
	_rect(0, 2, T, 1, g[2])
	_rect(0, 3, T, 1, g[1])
	_rect(0, 4, T, 1, s[0])
	_rect(0, 5, T, 1, s[3])
	_rect(0, 11, T, 1, s[1])
	_rect(0, 12, T, 1, s[0])
	# Hazard ticks on the deck edge.
	for x in range(2, T, 4):
		_px(x, 3, g[0])
	# Window band with a gold light slot.
	_rect(0, 7, T, 2, s[0])
	_rect(0, 9, T, 1, s[3])
	_rect(6, 7, 4, 2, g[1])
	_rect(6, 7, 3, 1, g[2])
	_px(6, 7, g[3])
	# Panel seam between pieces of a run.
	if not right:
		_rect(T - 1, 5, 1, 7, s[0])
	if not left:
		_rect(0, 5, 1, 7, s[3])
	_rivet(3, 5, s)
	_rivet(12, 10, s)
	# Undercarriage.
	_rect(0, 13, T, 3, CLEAR)
	if axis == 0:
		_rect(0, 13, T, 1, OUTLINE)
		for px in [2, 10]:
			_rect(px, 13, 4, 3, OUTLINE)
			_rect(px + 1, 13, 2, 1, s[1])
			_rect(px + 1, 14, 2, 1, g[2])
			_px(px + 1, 14, g[3])
	else:
		_rect(0, 13, T, 1, OUTLINE)
		for px in [3, 10]:
			_rect(px - 1, 13, 5, 2, OUTLINE)
			_rect(px, 13, 3, 1, s[2])
			_px(px, 13, s[3])
			_rect(px, 15, 3, 1, OUTLINE)
			_rect(px, 14, 3, 1, s[1])
			_px(px + 1, 14, FLAME[1])
	# Ends: rounded nose with a lamp bezel, bevel and outline.
	if left:
		_rect(1, 5, 1, 7, s[3])
		_rect(1, 6, 2, 4, OUTLINE)
		_rect(2, 7, 1, 2, s[1])
		_rect(0, 0, 1, 13, OUTLINE)
		_px(0, 0, CLEAR)
		_px(0, 12, CLEAR)
		_px(1, 12, OUTLINE)
		_px(1, 1, g[4])
	if right:
		_rect(T - 2, 5, 1, 7, s[1])
		_rect(T - 3, 6, 2, 4, OUTLINE)
		_rect(T - 3, 7, 1, 2, s[1])
		_rect(T - 1, 0, 1, 13, OUTLINE)
		_px(T - 1, 0, CLEAR)
		_px(T - 1, 12, CLEAR)
		_px(T - 2, 12, OUTLINE)
	_rect(1 if left else 0, 0, T - (1 if left else 0) - (1 if right else 0), 1, OUTLINE)


# --- cracked wall ---------------------------------------------------------------------------

## Navy armour plate split by deep cracks with chipped lit edges; outline and bevel
## on the sides exposed to the open (mask bits as in the tilesets).
func _cracked(img: Image, mask: int, variant: int) -> void:
	_cell(img, mask, variant)
	var w := WALL
	var up := mask & 1 != 0
	var right := mask & 2 != 0
	var down := mask & 4 != 0
	var left := mask & 8 != 0
	_rect(0, 0, T, T, w[2])
	# Inset plate edge.
	_rect(1, 1, 14, 1, w[3])
	_rect(1, 1, 1, 14, w[3])
	_rect(1, 14, 14, 1, w[1])
	_rect(14, 1, 1, 14, w[1])
	_rect(0, 0, T, 1, w[1])
	_rect(0, 0, 1, T, w[1])
	_rivet(3, 3, w)
	_rivet(11, 11, w)
	# Cracks (deep line, lit chipped rim on the upper-left side).
	var paths := [
		[Vector2i(2, 1), Vector2i(6, 6), Vector2i(5, 9), Vector2i(9, 14)],
		[Vector2i(14, 2), Vector2i(10, 5), Vector2i(11, 9), Vector2i(7, 14)],
	]
	var branch := [
		[Vector2i(6, 6), Vector2i(12, 4)],
		[Vector2i(11, 9), Vector2i(3, 11)],
	]
	for path in [paths[variant], branch[variant]]:
		for i in path.size() - 1:
			_line(path[i].x, path[i].y - 1, path[i + 1].x, path[i + 1].y - 1, w[4])
		for i in path.size() - 1:
			_line(path[i].x, path[i].y, path[i + 1].x, path[i + 1].y, OUTLINE)
			_line(path[i].x + 1, path[i].y, path[i + 1].x + 1, path[i + 1].y, w[0])
	# Chips knocked out of the plate.
	var chip := Vector2i(10, 2) if variant == 0 else Vector2i(3, 6)
	_rect(chip.x, chip.y, 2, 2, w[0])
	_px(chip.x, chip.y, OUTLINE)
	_px(chip.x - 1, chip.y - 1, w[4])
	# Exposed sides.
	if left:
		_rect(1, 0, 1, T, w[4])
	if right:
		_rect(T - 2, 0, 1, T, w[0])
	if up:
		_rect(0, 1, T, 1, w[4])
	if down:
		_rect(0, T - 2, T, 1, w[0])
	if left:
		_rect(0, 0, 1, T, OUTLINE)
	if right:
		_rect(T - 1, 0, 1, T, OUTLINE)
	if up:
		_rect(0, 0, T, 1, OUTLINE)
	if down:
		_rect(0, T - 1, T, 1, OUTLINE)


# --- spikes / mirror / gate / door ----------------------------------------------------------

## Two steel spikes (lit left face, shaded right face, red tips) on a bolted base.
func _spikes(img: Image) -> void:
	_cell(img, 0, 0)
	var k := SPIKE
	for i in 2:
		var bx := i * 8
		# Row widths from the tip down (half-width each side of the centre line).
		for r in 8:
			var y := 5 + r
			var hw := 1 + (r >> 1)
			var x0 := bx + 4 - hw
			var x1 := bx + 3 + hw
			for x in range(x0, x1 + 1):
				var c: Color = k[3] if x < bx + 4 else k[1]
				if x == bx + 3 and r > 1:
					c = k[4] if r < 5 else k[3]
				if x == x1 and r > 2:
					c = k[0]
				_px(x, y, c)
		# Red tip.
		_rect(bx + 3, 5, 2, 2, RED[2])
		_px(bx + 3, 5, RED[3])
		_px(bx + 4, 6, RED[1])
	# Base strip.
	_rect(0, 13, T, 2, STEEL[2])
	_rect(0, 13, T, 1, STEEL[3])
	_rivet(3, 13, STEEL)
	_rivet(11, 13, STEEL)
	_auto_outline()
	_rect(0, 15, T, 1, OUTLINE)


## Reflector plate on the diagonal: silver lit face, violet mirror band, dark
## back, a pivot hub behind its middle and clamps at both ends.
func _mirror(img: Image, col: int, slash: bool) -> void:
	_cell(img, col, 0)
	# Pivot hub (behind the plate).
	_rect(6, 6, 4, 4, STEEL[2])
	_rect(6, 6, 4, 1, STEEL[3])
	_rect(6, 9, 4, 1, STEEL[1])
	_auto_outline()
	for i in 12:
		var x := 2 + i
		var y := (13 - i) if slash else (2 + i)
		_px(x, y - 2, SPIKE[4] if i % 5 == 2 else SPIKE[3])
		_px(x, y - 1, VIOLET[4])
		_px(x, y, VIOLET[3])
		_px(x, y + 1, VIOLET[1])
	# Clamps at the ends.
	var ends := [Vector2i(1, 11), Vector2i(12, 0)] if slash else [Vector2i(1, 0), Vector2i(12, 11)]
	for e in ends:
		_rect(e.x, e.y, 3, 4, STEEL[2])
		_px(e.x, e.y, STEEL[4])
		_px(e.x + 2, e.y + 3, STEEL[1])
	_auto_outline()


## Sealed gate: gold posts, dark shutter slats with a black / gold hazard band;
## the top cell carries the red lock. Piece 0 single, 1 top, 2 middle, 3 bottom.
func _gate(img: Image, piece: int) -> void:
	_cell(img, piece, 0)
	var g := GOLD
	var top := piece == 0 or piece == 1
	var bottom := piece == 0 or piece == 3
	var slat := [Color("1a1d2c"), Color("2a2f45"), Color("3c4260")]
	# Shutter slats.
	for y in T:
		var c: Color = slat[1]
		if y % 4 == 0:
			c = slat[2]
		elif y % 4 == 3:
			c = slat[0]
		_rect(3, y, 10, 1, c)
	if not top:
		for y in range(6, 10):
			for x in range(3, 13):
				_px(x, y, g[2] if posmod(x + y, 4) < 2 else slat[0])
		_rect(3, 5, 10, 1, OUTLINE)
		_rect(3, 10, 10, 1, OUTLINE)
	# Posts.
	_rect(0, 0, 1, T, OUTLINE)
	_rect(1, 0, 1, T, g[3])
	_rect(2, 0, 1, T, g[1])
	_rect(13, 0, 1, T, g[2])
	_rect(14, 0, 1, T, g[1])
	_rect(T - 1, 0, 1, T, OUTLINE)
	for py in [4, 12]:
		_px(1, py, g[4])
		_px(2, py, g[0])
		_px(13, py, g[3])
	if top:
		_rect(0, 0, T, 1, OUTLINE)
		_rect(1, 1, 14, 1, g[3])
		_rect(1, 2, 14, 1, g[1])
		# Lock: shackle and body with a keyhole.
		_rect(6, 3, 4, 1, OUTLINE)
		_rect(5, 4, 1, 2, OUTLINE)
		_rect(10, 4, 1, 2, OUTLINE)
		_rect(6, 4, 4, 1, STEEL[4])
		_px(6, 5, STEEL[3])
		_px(9, 5, STEEL[2])
		_box(4, 6, 8, 7, RED)
		_rect(7, 8, 2, 2, RED[0])
		_px(7, 10, RED[0])
	if bottom:
		_rect(1, T - 2, 14, 1, g[1])
		_rect(0, T - 1, T, 1, OUTLINE)


## Arena shutter (closed): steel side rails, split blast plate, red warning bars.
func _door(img: Image, piece: int) -> void:
	_cell(img, piece, 0)
	var s := STEEL
	var top := piece == 0 or piece == 1
	var bottom := piece == 0 or piece == 3
	_rect(0, 0, T, T, s[2])
	# Plate bands.
	_rect(3, 0, 10, 1, s[3])
	_rect(3, 7, 10, 1, s[0])
	_rect(3, 8, 10, 1, s[3])
	_rect(3, 15, 10, 1, s[0])
	# Centre split.
	_rect(7, 0, 1, T, s[0])
	_rect(8, 0, 1, T, s[3])
	# Warning bars.
	for by in [3, 11]:
		_rect(3, by - 1, 10, 4, OUTLINE)
		_rect(4, by, 8, 1, RED[2])
		_rect(4, by + 1, 8, 1, RED[1])
		_px(4, by, RED[3])
		_px(5, by, RED[3])
	# Side rails.
	_rect(0, 0, 1, T, OUTLINE)
	_rect(1, 0, 1, T, s[3])
	_rect(2, 0, 1, T, s[1])
	_rect(13, 0, 1, T, s[3])
	_rect(14, 0, 1, T, s[1])
	_rect(T - 1, 0, 1, T, OUTLINE)
	_rivet(1, 5, s)
	_rivet(13, 13, s)
	if top:
		_rect(0, 0, T, 1, OUTLINE)
		_rect(1, 1, 14, 1, s[4])
		_rect(1, 2, 14, 1, s[3])
	if bottom:
		_rect(1, T - 2, 14, 1, s[0])
		_rect(0, T - 1, T, 1, OUTLINE)


func _preview(sheets: Dictionary, dir: String) -> void:
	var w := 0
	var h := 0
	for k in sheets:
		w = maxi(w, sheets[k].get_width())
		h += sheets[k].get_height() + 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("26304a"))
	var y := 0
	for k in sheets:
		var sh: Image = sheets[k]
		img.blend_rect(sh, Rect2i(Vector2i.ZERO, sh.get_size()), Vector2i(0, y))
		y += sh.get_height() + 4
	img.resize(img.get_width() * 6, img.get_height() * 6, Image.INTERPOLATE_NEAREST)
	img.save_png(dir.path_join("devices.png"))
