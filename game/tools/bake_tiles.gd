extends SceneTree
## Bakes one 16x16 tileset per stage theme into res://art/tiles/<theme>.png.
##   godot --headless --path game -s res://tools/bake_tiles.gd [-- --preview=/abs/dir]
##
## Atlas layout: 16 columns = exposed-side mask (1 up, 2 right, 4 down, 8 left),
## 4 rows = surface variants (0 plain, 1-3 details). level.gd picks the column from
## the neighbouring cells and the row from a position hash.
## Every theme follows the same rules as the sprites: 1 px dark outline on exposed
## sides, lit top / left bevel, shadowed bottom / right bevel, a coloured cap on
## top surfaces. Original patterns; deterministic (re-running gives identical PNGs).

const T := 16
const OUT := "res://art/tiles"
const OUTLINE := Color("0a1326")

## pattern / cap / under: see _fill, _cap, _under.
const THEMES := {
	"training": {"fill": "1c375b", "dark": "142a47", "light": "2b4f7c", "cap": "00b8be", "cap_light": "8af5f8",
			"accent": "00b8be", "pattern": "panel", "cap_style": "trim", "under": "shadow"},
	"prism_gecko": {"fill": "2b2452", "dark": "1d1838", "light": "40377a", "cap": "9d7ae6", "cap_light": "e2d4ff",
			"accent": "3de0ee", "pattern": "crystal", "cap_style": "glass", "under": "shadow"},
	"gravity_albatross": {"fill": "2f384c", "dark": "202737", "light": "47536c", "cap": "f0b84a", "cap_light": "ffe3a0",
			"accent": "e34f5b", "pattern": "hull", "cap_style": "hazard", "under": "shadow"},
	"solar_fennec": {"fill": "8a5a3c", "dark": "684230", "light": "ad7a52", "cap": "deae6c", "cap_light": "f7da9c",
			"accent": "f0b84a", "pattern": "sandstone", "cap_style": "sand", "under": "shadow"},
	"cryo_narwhal": {"fill": "2f4b70", "dark": "22385a", "light": "4a6f98", "cap": "cfe6f7", "cap_light": "ffffff",
			"accent": "8fd8ff", "pattern": "frost", "cap_style": "snow", "under": "icicles"},
	"terra_pangolin": {"fill": "4c3e35", "dark": "382d27", "light": "6a574b", "cap": "927d66", "cap_light": "c7ae90",
			"accent": "f0b84a", "pattern": "rock", "cap_style": "rubble", "under": "shadow"},
	"pulse_cicada": {"fill": "283045", "dark": "1a2030", "light": "3d4760", "cap": "f0d24a", "cap_light": "fff3a8",
			"accent": "71dedf", "pattern": "grate", "cap_style": "trim", "under": "shadow"},
	"final_eden_core": {"fill": "1c1634", "dark": "120e24", "light": "2c2350", "cap": "3de0ee", "cap_light": "c8fbff",
			"accent": "b78af3", "pattern": "circuit", "cap_style": "glow", "under": "shadow"},
	"ice": {"fill": "5a8ab5", "dark": "466f99", "light": "86b2d8", "cap": "e6f5ff", "cap_light": "ffffff",
			"accent": "d7edf3", "pattern": "ice", "cap_style": "snow", "under": "icicles"},
}

var _img: Image
var _ox := 0
var _oy := 0
var _p := {}


func _init() -> void:
	var preview := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			preview = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for theme in THEMES:
		_p = {}
		for k in THEMES[theme]:
			var v = THEMES[theme][k]
			_p[k] = Color(v) if k in ["fill", "dark", "light", "cap", "cap_light", "accent"] else v
		var atlas := Image.create(T * 16, T * 4, false, Image.FORMAT_RGBA8)
		for variant in 4:
			for mask in 16:
				_img = atlas
				_ox = mask * T
				_oy = variant * T
				_tile(mask, variant, theme.hash())
		atlas.save_png(ProjectSettings.globalize_path(OUT.path_join(theme + ".png")))
		if preview != "":
			_preview(theme, atlas, preview)
	print("baked %d tilesets" % THEMES.size())
	quit()


# --- helpers ---------------------------------------------------------------------------

func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < T and y < T:
		_img.set_pixel(_ox + x, _oy + y, c)


func _at(x: int, y: int) -> Color:
	return _img.get_pixel(_ox + x, _oy + y)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)


## Deterministic hash noise in [0, 1).
static func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 10007) / 10007.0


# --- tile ---------------------------------------------------------------------------

func _tile(mask: int, variant: int, seed: int) -> void:
	var up := mask & 1 != 0
	var right := mask & 2 != 0
	var down := mask & 4 != 0
	var left := mask & 8 != 0
	_fill(variant, seed)
	# Bevels on exposed sides (inside the outline).
	if left:
		for y in T:
			_px(1, y, _at(1, y).lerp(_p.light, 0.6))
	if right:
		for y in T:
			_px(T - 2, y, _at(T - 2, y).lerp(_p.dark, 0.7))
	if down:
		_under(seed)
	if up:
		_cap(seed, left, right)
	# 1 px outline on exposed sides.
	if left:
		_rect(0, 0, 1, T, OUTLINE)
	if right:
		_rect(T - 1, 0, 1, T, OUTLINE)
	if down and _p.under != "icicles":
		_rect(0, T - 1, T, 1, OUTLINE)
	if up:
		_rect(0, 0, T, 1, OUTLINE)


## Interior pattern; tiles seamlessly across neighbours (16 px period).
func _fill(variant: int, seed: int) -> void:
	var fill: Color = _p.fill
	var dark: Color = _p.dark
	var light: Color = _p.light
	var acc: Color = _p.accent
	_rect(0, 0, T, T, fill)
	match _p.pattern:
		"panel":
			# Two panels with seams, bevel and rivets.
			_rect(0, 7, T, 1, dark)
			_rect(0, 15, T, 1, dark)
			_rect(0, 0, T, 1, light.lerp(fill, 0.4))
			_rect(0, 8, T, 1, light.lerp(fill, 0.4))
			for ry in [3, 11]:
				_px(3, ry, light)
				_px(12, ry, light)
				_px(3, ry + 1, dark)
				_px(12, ry + 1, dark)
			if variant == 1:
				for vx in range(5, 11, 2):
					_rect(vx, 2, 1, 4, dark)
			elif variant == 2:
				_rect(6, 10, 4, 3, dark)
				_rect(7, 11, 2, 1, acc.darkened(0.2))
			elif variant == 3:
				_rect(0, 3, T, 1, dark.lerp(fill, 0.5))
		"crystal":
			# Dark stone blocks with crystal inclusions.
			_rect(0, 15, T, 1, dark)
			_rect(7, 0, 1, 8, dark)
			_rect(0, 7, T, 1, dark)
			_rect(12, 8, 1, 7, dark)
			_rect(0, 8, T, 1, light.lerp(fill, 0.5))
			for i in 3:
				var cx := int(_h(i, variant, seed) * 12.0) + 2
				var cy := int(_h(i + 7, variant, seed) * 12.0) + 2
				if variant == 0 and i > 0:
					break
				var c: Color = acc if i % 2 == 0 else Color("b78af3")
				_px(cx, cy, c.lightened(0.3))
				_px(cx, cy + 1, c)
				_px(cx + 1, cy + 1, c.darkened(0.3))
				_px(cx, cy + 2, c.darkened(0.45))
		"hull":
			# Hull plating, rivet rows; variant 2/3 shows a cross brace.
			_rect(0, 15, T, 1, dark)
			_rect(15, 0, 1, T, dark)
			_rect(0, 0, T, 1, light.lerp(fill, 0.5))
			for rx in range(2, 15, 4):
				_px(rx, 2, light)
				_px(rx, 13, light)
			if variant >= 2:
				for i in range(2, 14):
					_px(i, i, dark)
					_px(15 - i, i, dark)
					_px(i, i - 1, light.lerp(fill, 0.5))
			elif variant == 1:
				_rect(5, 6, 6, 4, dark)
				_rect(6, 7, 4, 2, acc.darkened(0.35))
		"sandstone":
			# Layered bricks (offset rows) with grain.
			for row in 4:
				var y0 := row * 4
				_rect(0, y0 + 3, T, 1, dark)
				_rect(0, y0, T, 1, light.lerp(fill, 0.5))
				var off := 0 if row % 2 == 0 else 6
				for bx in [off, off + 8]:
					_rect(bx % T, y0, 1, 3, dark)
			for i in 6:
				var gx := int(_h(i, variant, seed) * 15.0)
				var gy := int(_h(i + 11, variant, seed) * 15.0)
				_px(gx, gy, light if i % 2 == 0 else dark)
			if variant == 3:
				_rect(4, 5, 8, 6, Color("2b4f7c"))
				_rect(5, 6, 6, 4, Color("3a6aa0"))
				_rect(5, 6, 6, 1, Color("8fc4ff"))
		"frost":
			# Steel with frosted streaks and cracks.
			_rect(0, 15, T, 1, dark)
			_rect(0, 0, T, 1, light.lerp(fill, 0.4))
			for i in 7:
				var fx := int(_h(i, variant, seed) * 15.0)
				var fy := int(_h(i + 5, variant, seed) * 15.0)
				_px(fx, fy, light)
				_px(fx + 1, fy, light.lerp(fill, 0.5))
			if variant >= 1:
				var x := 4 + variant * 2
				for y in range(3, 12):
					_px(x, y, acc.lerp(fill, 0.35))
					if y % 3 == 0:
						x += 1
		"rock":
			# Rock strata with cracks and pebbles.
			_rect(0, 5, T, 1, dark)
			_rect(0, 11, T, 1, dark)
			_rect(0, 6, T, 1, light.lerp(fill, 0.6))
			_rect(0, 12, T, 1, light.lerp(fill, 0.6))
			for i in 5:
				var px := int(_h(i, variant, seed) * 14.0) + 1
				var py := int(_h(i + 3, variant, seed) * 14.0) + 1
				_px(px, py, light)
				_px(px + 1, py, dark)
			if variant >= 2:
				var cx := 6 + variant
				for y in range(1, 10):
					_px(cx + (y % 3) - 1, y, dark)
		"grate":
			# Grating: grid of dark holes, cyan pilot light on some tiles.
			_rect(0, 0, T, 1, light.lerp(fill, 0.4))
			for gy in range(3, 15, 4):
				for gx in range(2, 15, 4):
					_rect(gx, gy, 2, 2, dark)
					_px(gx, gy - 1, light.lerp(fill, 0.5))
			if variant == 2:
				_rect(7, 6, 2, 2, acc)
				_px(7, 6, acc.lightened(0.5))
		"circuit":
			# Dark data blocks with traces and nodes.
			_rect(0, 15, T, 1, dark)
			var trace: Color = (acc if variant % 2 == 0 else Color("3de0ee")).darkened(0.35)
			var ty := 4 + variant * 2
			_rect(0, ty, 9, 1, trace)
			_rect(8, ty, 1, 15 - ty, trace)
			_rect(8, 14, 8, 1, trace)
			_rect(7, ty - 1, 3, 3, trace.lightened(0.3))
			_px(8, ty, trace.lightened(0.7))
			if variant == 3:
				_rect(2, 9, 3, 3, dark)
				_px(3, 10, acc)
		"ice":
			_rect(0, 15, T, 1, dark)
			for i in 3:
				var x := 3 + i * 4 + variant
				for k in 5:
					_px(x + k, 11 - k * 2 + (i % 2), light)
			_px(5 + variant, 4, Color.WHITE)


## Coloured cap on a top surface.
func _cap(seed: int, left: bool, right: bool) -> void:
	var cap: Color = _p.cap
	var cap_l: Color = _p.cap_light
	match _p.cap_style:
		"trim":
			_rect(0, 1, T, 2, cap)
			_rect(0, 1, T, 1, cap_l)
			_rect(0, 3, T, 1, cap.darkened(0.55))
		"glass":
			_rect(0, 1, T, 3, cap)
			_rect(0, 1, T, 1, cap_l)
			_rect(0, 4, T, 1, cap.darkened(0.5))
			_px(4, 2, cap_l)
			_px(11, 2, cap_l)
		"hazard":
			_rect(0, 1, T, 3, cap)
			for x in T:
				if (x / 2) % 2 == 0:
					_px(x, 2, Color("202737"))
					_px(x, 3, Color("202737"))
			_rect(0, 1, T, 1, cap_l)
			_rect(0, 4, T, 1, cap.darkened(0.6))
		"sand":
			for x in T:
				var hgt := 3 + int(_h(x, 0, seed) * 2.0)
				_rect(x, 1, 1, hgt, cap)
				_px(x, 1, cap_l)
				_px(x, hgt + 1, cap.darkened(0.35))
		"snow":
			for x in T:
				var hgt := 2 + int(round(sin(x * 0.9) + 1.0))
				_rect(x, 1, 1, hgt, cap)
				_px(x, 1, cap_l)
				_px(x, hgt + 1, cap.darkened(0.3))
		"rubble":
			_rect(0, 1, T, 2, cap)
			_rect(0, 1, T, 1, cap_l)
			for x in range(1, T, 3):
				_px(x, 3, cap.darkened(0.4))
				_px(x + 1, 3, _p.light)
		"glow":
			_rect(0, 1, T, 1, cap_l)
			_rect(0, 2, T, 1, cap)
			_rect(0, 3, T, 1, cap.darkened(0.6))
	if left:
		_px(1, 1, cap_l)
	if right:
		_px(T - 2, 2, cap.darkened(0.3))


## Underside of an overhang.
func _under(seed: int) -> void:
	var dark: Color = _p.dark
	_rect(0, T - 3, T, 2, dark)
	if _p.under == "icicles":
		_rect(0, T - 1, T, 1, Color(0, 0, 0, 0))
		for x in range(1, T, 5):
			var lenx := 2 + int(_h(x, 1, seed) * 3.0)
			for k in lenx:
				if T - 2 + k < T:
					_px(x, T - 2 + k, _p.accent)
			_px(x, T - 2, _p.cap_light)


func _preview(theme: String, atlas: Image, dir: String) -> void:
	# A sample wall: platform, overhang, pillar.
	var shape := [
		"..............",
		"..####........",
		"..####....##..",
		"..........##..",
		"####......##..",
		"##############",
		"##############",
	]
	var img := Image.create(T * 14, T * 7, false, Image.FORMAT_RGBA8)
	img.fill(Color("101b36"))
	var solid := func(x: int, y: int) -> bool:
		if y < 0 or y >= shape.size() or x < 0 or x >= 14:
			return y >= shape.size()
		return shape[y][x] == "#"
	for y in shape.size():
		for x in 14:
			if not solid.call(x, y):
				continue
			var m := (1 if not solid.call(x, y - 1) else 0) | (2 if not solid.call(x + 1, y) else 0) \
					| (4 if not solid.call(x, y + 1) else 0) | (8 if not solid.call(x - 1, y) else 0)
			var v := (x * 7 + y * 3) % 4
			img.blend_rect(atlas, Rect2i(m * T, v * T, T, T), Vector2i(x * T, y * T))
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(dir.path_join("tiles_%s.png" % theme))
