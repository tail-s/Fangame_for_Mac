extends SceneTree
## Bakes the small sprite effects into res://art/fx/<name>.png: one horizontal strip
## per effect (equal cells), hand-shaded pixel clusters with dithered fade-outs.
##   godot --headless --path game -s res://tools/bake_fx.gd [-- --preview=/abs/dir]
## Cell sizes and frame counts are listed in FX (read by scripts/fx/sprite_fx.gd).

const FX := {
	"dash_smoke": {"cell": Vector2i(16, 12), "frames": 4},
	"land_dust": {"cell": Vector2i(28, 10), "frames": 4},
	"muzzle": {"cell": Vector2i(12, 12), "frames": 3, "tones": ["e8ffff", "3de0ee"]},
	"muzzle_gold": {"cell": Vector2i(16, 16), "frames": 3, "fn": "muzzle", "big": true,
			"tones": ["fff8e0", "f0b84a"]},
	# Armor full-charge muzzles (scripts/fx/armor_fx.gd families): core, star, outer rays.
	"muzzle_vanguard": {"cell": Vector2i(16, 16), "frames": 3, "fn": "muzzle", "big": true,
			"tones": ["ffe4f0", "ff3d8a", "c2283c"], "motif": "claw"},
	"muzzle_aero": {"cell": Vector2i(16, 16), "frames": 3, "fn": "muzzle", "big": true,
			"tones": ["ffffff", "6fb4ff", "e8b040"], "motif": "lance"},
	"muzzle_ultimate": {"cell": Vector2i(16, 16), "frames": 3, "fn": "muzzle", "big": true,
			"tones": ["fff0b0", "f0b84a", "8a6cc8"]},
	"wall_spark": {"cell": Vector2i(8, 8), "frames": 3},
	"charge": {"cell": Vector2i(36, 36), "frames": 4, "tones": ["d8ffff", "3de0ee", "1f8c9a"]},
	"charge_gold": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["fff3c4", "f0b84a", "a3681a"]},
	# Armor charge auras, level 1 and 2. Level 2 adds the family motif.
	"charge_vanguard1": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["ffb4a8", "ec5a5a", "86142a"]},
	"charge_vanguard2": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["ffc8e4", "ff3d8a", "86142a"], "motif": "claw", "motif_tones": ["fff0b0", "e8b040"]},
	"charge_aero1": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["c8ecff", "2f8cff", "1f5fb8"]},
	"charge_aero2": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["ffffff", "c8ecff", "2f8cff"], "motif": "wing", "motif_tones": ["fff0b0", "e8b040"]},
	"charge_ultimate1": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["c8b4f0", "8a6cc8", "3a2860"]},
	"charge_ultimate2": {"cell": Vector2i(36, 36), "frames": 4, "fn": "charge",
			"tones": ["fff3c4", "f0b84a", "a3681a"], "motif": "nova", "motif_tones": ["e2d2ff", "8a6cc8"]},
}
const OUT := "res://art/fx"
const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

var _img: Image
var _ox := 0


func _init() -> void:
	var preview := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			preview = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sheets := []
	for name in FX:
		var cell: Vector2i = FX[name].cell
		var n: int = FX[name].frames
		_img = Image.create(cell.x * n, cell.y, false, Image.FORMAT_RGBA8)
		_img.fill(Color(0, 0, 0, 0))
		for f in n:
			_ox = f * cell.x
			call("_" + FX[name].get("fn", name), f, cell, FX[name])
		_img.save_png(ProjectSettings.globalize_path(OUT.path_join(name + ".png")))
		sheets.append(_img)
	if preview != "":
		var w := 0
		var h := 0
		for sh in sheets:
			w = maxi(w, sh.get_width())
			h += sh.get_height() + 2
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color("1c2a48"))
		var y := 0
		for sh in sheets:
			img.blend_rect(sh, Rect2i(Vector2i.ZERO, sh.get_size()), Vector2i(0, y))
			y += sh.get_height() + 2
		img.resize(img.get_width() * 6, img.get_height() * 6, Image.INTERPOLATE_NEAREST)
		img.save_png(preview.path_join("fx.png"))
	print("baked %d effects" % FX.size())
	quit()


func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < _img.get_width() - _ox and y < _img.get_height():
		_img.set_pixel(_ox + x, y, c)


## Filled disc with a lit top-left and a shaded bottom-right; `fade` 0..1 dithers it away.
func _puff(c: Vector2, r: float, tones: Array, fade := 0.0) -> void:
	for y in range(int(c.y - r) - 1, int(c.y + r) + 2):
		for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			if d.length() > r:
				continue
			# 4x4 ordered (Bayer) dither for the fade-out.
			if fade > 0.0 and BAYER[posmod(y, 4)][posmod(x, 4)] / 16.0 < fade:
				continue
			var lit := -(d.x + d.y) / (r * 1.4)
			var col: Color = tones[1]
			if lit > 0.35:
				col = tones[2]
			elif lit < -0.35:
				col = tones[0]
			_px(x, y, col)


const SMOKE := [Color("7d8fb0"), Color("b9c7dc"), Color("eef3fa")]


func _dash_smoke(f: int, cell: Vector2i, _e: Dictionary) -> void:
	var base := Vector2(cell.x * 0.5, cell.y - 3.0)
	var r: float = [2.5, 3.6, 4.2, 4.4][f]
	var rise: float = [0.0, 1.5, 3.0, 4.5][f]
	var fade: float = [0.0, 0.0, 0.35, 0.7][f]
	_puff(base + Vector2(-1.5, -rise), r, SMOKE, fade)
	if f >= 1:
		_puff(base + Vector2(3.0, -rise * 0.6 + 1.0), r * 0.6, SMOKE, fade)


func _land_dust(f: int, cell: Vector2i, _e: Dictionary) -> void:
	var spread: float = [3.0, 6.0, 9.0, 11.0][f]
	var r: float = [2.2, 2.8, 3.0, 2.8][f]
	var fade: float = [0.0, 0.0, 0.3, 0.65][f]
	var y := cell.y - 3.5
	for s in [-1.0, 1.0]:
		_puff(Vector2(cell.x * 0.5 + s * spread, y - f * 0.4), r, SMOKE, fade)


func _muzzle(f: int, cell: Vector2i, e: Dictionary) -> void:
	var c := Vector2(cell) * 0.5
	var tones: Array = e.tones.map(func(h): return Color(h))
	var core: Color = tones[0]
	var mid: Color = tones[1]
	var big: bool = e.get("big", false)
	var size: float = ([4.5, 7.0, 5.0] if big else [3.0, 5.0, 3.5])[f]
	# Four-point star with a round core.
	for k in 4:
		var dir := Vector2.RIGHT.rotated(k * PI * 0.5 + (PI * 0.25 if f == 1 else 0.0))
		for t in int(size):
			var p := c + dir * t
			_px(int(p.x), int(p.y), mid if t > 1 else core)
	match e.get("motif", ""):
		"claw":
			# Three talon marks raking forward past the star.
			for k in 3:
				var y := c.y - 4.0 + k * 4.0
				for t in int(size) + 1:
					_px(int(c.x + 2.0 + t), int(y + t * 0.35 - (k - 1) * t * 0.15), tones[2] if t < 2 else mid)
		"lance":
			# A long forward spike with gold edges.
			for t in int(size * 1.4):
				_px(int(c.x + t), int(c.y), core if t < size else mid)
				if t > 1 and t < size:
					_px(int(c.x + t), int(c.y) - 1, tones[2])
					_px(int(c.x + t), int(c.y) + 1, tones[2])
		_:
			if tones.size() > 2:
				for k in 4:
					var dir := Vector2.RIGHT.rotated(k * PI * 0.5 + PI * 0.25 + (PI * 0.25 if f == 1 else 0.0))
					for t in range(2, int(size * 0.8)):
						var p := c + dir * t
						_px(int(p.x), int(p.y), tones[2])
	_puff(c, size * 0.45, [mid, core, Color.WHITE])


func _wall_spark(f: int, _cell: Vector2i, _e: Dictionary) -> void:
	var cols := [Color("fff3c4"), Color("f0b84a"), Color("c8781f")]
	var pts: Array = [[Vector2(3, 3), Vector2(4, 4)], [Vector2(2, 2), Vector2(5, 3), Vector2(3, 5)],
			[Vector2(1, 1), Vector2(6, 2), Vector2(2, 6)]][f]
	for p in pts:
		_px(int(p.x), int(p.y), cols[f])


func _charge(f: int, cell: Vector2i, e: Dictionary) -> void:
	var c := Vector2(cell) * 0.5
	var bright := Color(e.tones[0])
	var mid := Color(e.tones[1])
	var dim := Color(e.tones[2])
	if e.has("motif"):
		_charge_motif(f, c, e.motif, e.motif_tones.map(func(h): return Color(h)), bright)
	# Particles spiralling in, plus a thin ring that pulses.
	for k in 8:
		var a := k * TAU / 8.0 + f * 0.35
		var rad := 14.0 - fmod(f * 3.0 + k * 1.7, 9.0)
		var p := c + Vector2(cos(a), sin(a)) * rad
		_px(int(p.x), int(p.y), bright)
		var q := c + Vector2(cos(a - 0.18), sin(a - 0.18)) * (rad + 1.5)
		_px(int(q.x), int(q.y), mid)
		var t := c + Vector2(cos(a - 0.34), sin(a - 0.34)) * (rad + 3.0)
		_px(int(t.x), int(t.y), dim)
	if f % 2 == 0:
		var rr := 15.0 if f == 0 else 13.0
		for k in 48:
			var a := k * TAU / 48.0
			if k % 3 != 0:
				var p := c + Vector2(cos(a), sin(a)) * rr
				_px(int(p.x), int(p.y), Color(mid, 0.8))


## Level 2 armor charge motifs, drawn under the spiralling particles.
##   claw: three talon slashes turning around the core (Vanguard)
##   wing: a pair of swept wing chevrons beating open (Aero)
##   nova: a four-point star with violet sparks (Ultimate)
func _charge_motif(f: int, c: Vector2, motif: String, tones: Array, bright: Color) -> void:
	match motif:
		"claw":
			for k in 3:
				var a := f * 0.42 + k * TAU / 3.0
				var base := c + Vector2.from_angle(a) * 9.0
				var along := Vector2.from_angle(a + PI * 0.5)
				for t in range(-3, 4):
					var p := base + along * t + Vector2.from_angle(a) * (absf(t) * 0.45)
					_px(int(p.x), int(p.y), tones[1] if absi(t) == 3 else tones[0])
		"wing":
			var open: float = [0.0, 1.5, 3.0, 1.5][f]
			for s in [-1.0, 1.0]:
				for k in 3:
					var y0 := c.y - 5.0 + k * 3.0
					for t in 6:
						var x: float = c.x + s * (7.0 + t)
						var y := y0 - t * (0.55 + open * 0.12) + k * 0.4
						_px(int(x), int(y), bright if t == 5 else tones[k % 2])
		"nova":
			var r: float = [10.0, 12.0, 14.0, 12.0][f]
			for k in 4:
				var dir := Vector2.RIGHT.rotated(k * PI * 0.5 + PI * 0.25)
				for t in range(int(r * 0.5), int(r)):
					var p := c + dir * t
					_px(int(p.x), int(p.y), tones[0] if t < r - 2 else bright)
			for k in 5:
				var a := k * TAU / 5.0 - f * 0.5
				var p := c + Vector2.from_angle(a) * (6.0 + fmod(k * 2.3 + f * 2.0, 6.0))
				_px(int(p.x), int(p.y), tones[1])
