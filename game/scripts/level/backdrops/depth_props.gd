extends Node2D
## 2.5D layer (GDD §7-1 "Neo 32-bit + 2.5D"): boxes standing just behind the play
## field, projected every frame from the camera with a one-point perspective, so
## their side and top faces turn as the camera moves. Collision and controls stay
## 2D; this is background only. A theme adds one with a style dictionary:
##   spacing  world px between props        jitter    random x offset
##   w, h     [min, max] width / height     z, d      [min, max] depth / box depth
##   base     how far below the horizon the bases sit (screen px at scale 1)
##   front, side, top, line, light   colours (fog-blended by depth)
##   deco     "windows" | "bands" | "crystal" | "girder" | "tank" | "ice" | "pylon" | "monolith"
##   fog      colour the props fade towards with depth
## Stays darker and lower in contrast than the tiles (see theme_base.gd rules).

const W := 384.0
const H := 216.0
const REF_TOP := 104.0
const FOCAL := 220.0

## Prop style per stage theme (see the header for the keys).
const PRESETS := {
	"training": {"deco": "windows", "spacing": 90.0, "jitter": 30.0, "w": [26, 44], "h": [90, 190],
			"z": [40, 120], "d": [20, 40], "front": "1a2c4a", "side": "12203a", "top": "24406a",
			"line": "0e1a30", "light": "3de0ee", "fog": "101b36"},
	"prism_gecko": {"deco": "crystal", "spacing": 70.0, "jitter": 24.0, "w": [14, 24], "h": [60, 150],
			"z": [40, 130], "d": [14, 24], "front": "241c44", "side": "181232", "top": "4a3a8a",
			"line": "120c26", "light": "9d7ae6", "fog": "120c26"},
	"gravity_albatross": {"deco": "girder", "spacing": 120.0, "jitter": 40.0, "w": [16, 26], "h": [100, 200],
			"z": [50, 140], "d": [16, 26], "front": "1c2436", "side": "131a28", "top": "2c3850",
			"line": "0e1420", "light": "f0b84a", "fog": "0a0f1c"},
	"solar_fennec": {"deco": "tank", "spacing": 130.0, "jitter": 40.0, "w": [30, 50], "h": [40, 110],
			"z": [40, 130], "d": [24, 40], "front": "3a2430", "side": "2a1824", "top": "5a3a40",
			"line": "1e1018", "light": "f0b84a", "fog": "2a1428"},
	"cryo_narwhal": {"deco": "ice", "spacing": 110.0, "jitter": 36.0, "w": [20, 40], "h": [50, 130],
			"z": [40, 140], "d": [18, 30], "front": "1e3450", "side": "162640", "top": "5a86b0",
			"line": "0e1a30", "light": "8fd8ff", "fog": "0c1a30"},
	"terra_pangolin": {"deco": "bands", "spacing": 100.0, "jitter": 10.0, "w": [16, 22], "h": [170, 230],
			"z": [30, 90], "d": [16, 22], "front": "2a221e", "side": "1e1814", "top": "3a302a",
			"line": "14100c", "light": "f0b84a", "fog": "151010"},
	"pulse_cicada": {"deco": "pylon", "spacing": 140.0, "jitter": 30.0, "w": [8, 12], "h": [120, 190],
			"z": [50, 140], "d": [8, 12], "front": "1c2030", "side": "121520", "top": "2a3044",
			"line": "0c0e18", "light": "71dedf", "fog": "0c0e18"},
	"final_eden_core": {"deco": "monolith", "spacing": 100.0, "jitter": 30.0, "w": [18, 30], "h": [80, 170],
			"z": [40, 130], "d": [18, 30], "front": "1a1430", "side": "120e22", "top": "2c2350",
			"line": "0c0a18", "light": "b78af3", "fog": "0e0a1c"},
}

var style := {}
var _seed := 0


func _ready() -> void:
	_seed = str(style.get("deco", "")).hash() & 0xffff


func _process(_delta: float) -> void:
	queue_redraw()


static func _h(i: int, k: int, seed: int) -> float:
	var n := (i * 374761393 + k * 668265263 + seed * 2246822519) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n % 10007) / 10007.0


func _range(key: String, t: float) -> float:
	var r: Array = style.get(key, [0.0, 0.0])
	return lerpf(float(r[0]), float(r[1]), t)


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center := cam.get_screen_center_position()
	var origin := center - Vector2(W, H) * 0.5   # world position of the screen's top-left
	var cam_top := origin.y
	# Horizon and ground move a little with the camera (like the parallax layers).
	var vy := 96.0 - (cam_top - REF_TOP) * 0.08
	var base: float = style.get("base", 135.0)
	var spacing: float = style.get("spacing", 110.0)
	var boxes := []
	var i0 := int(floor((center.x - W * 1.6) / spacing))
	var i1 := int(ceil((center.x + W * 1.6) / spacing))
	for i in range(i0, i1 + 1):
		if _h(i, 9, _seed) < float(style.get("gap", 0.0)):
			continue
		var x0 := i * spacing + (_h(i, 1, _seed) - 0.5) * float(style.get("jitter", 0.0))
		var w := _range("w", _h(i, 2, _seed))
		var h := _range("h", _h(i, 3, _seed))
		var z := _range("z", _h(i, 4, _seed))
		var d := _range("d", _h(i, 5, _seed))
		boxes.append({"i": i, "x0": x0, "x1": x0 + w, "h": h, "z": z, "d": d})
	boxes.sort_custom(func(a, b): return a.z + a.d > b.z + b.d)
	for b in boxes:
		_box(b, center.x, vy, base, origin)


## Projects a point (world x, height above the ground, depth) to world draw coords.
func _p(x: float, up: float, z: float, cx: float, vy: float, base: float, origin: Vector2) -> Vector2:
	var s := FOCAL / (FOCAL + z)
	return origin + Vector2(W * 0.5 + (x - cx) * s, vy + (base - up) * s)


func _box(b: Dictionary, cx: float, vy: float, base: float, origin: Vector2) -> void:
	var z: float = b.z
	var zb: float = b.z + b.d
	var fog := Color(style.get("fog", "101b36"))
	var fade := clampf(z / 260.0, 0.0, 0.85) * 0.55 + 0.35
	var front: Color = Color(style.front).lerp(fog, fade)
	var side: Color = Color(style.side).lerp(fog, fade)
	# Top faces stay close to the sides so a prop never reads as a platform.
	var top: Color = Color(style.top).lerp(Color(style.side), 0.45).lerp(fog, fade)
	var line: Color = Color(style.line).lerp(fog, fade)
	var light: Color = Color(style.get("light", "00b8be")).lerp(fog, fade * 0.6)
	var x0: float = b.x0
	var x1: float = b.x1
	var h: float = b.h
	var p := func(x: float, up: float, zz: float) -> Vector2: return _p(x, up, zz, cx, vy, base, origin)
	# Side face toward the camera axis.
	if x1 < cx:
		draw_colored_polygon(PackedVector2Array([p.call(x1, 0, z), p.call(x1, h, z), p.call(x1, h, zb),
				p.call(x1, 0, zb)]), side)
	elif x0 > cx:
		draw_colored_polygon(PackedVector2Array([p.call(x0, 0, z), p.call(x0, h, z), p.call(x0, h, zb),
				p.call(x0, 0, zb)]), side)
	# Top face when the top is below eye level.
	var ftl: Vector2 = p.call(x0, h, z)
	var btl: Vector2 = p.call(x0, h, zb)
	if btl.y < ftl.y:
		draw_colored_polygon(PackedVector2Array([ftl, p.call(x1, h, z), p.call(x1, h, zb), btl]), top)
	# Front face + outline.
	var fbl: Vector2 = p.call(x0, 0, z)
	var ftr: Vector2 = p.call(x1, h, z)
	var rect := Rect2(ftl.x, ftl.y, ftr.x - ftl.x, fbl.y - ftl.y)
	draw_rect(rect, front)
	draw_rect(rect, line, false, 1.0)
	_deco(b, rect, line, light, top, p)


func _deco(b: Dictionary, r: Rect2, line: Color, light: Color, top: Color, p: Callable) -> void:
	var i: int = b.i
	match style.get("deco", ""):
		"windows":
			# Lit window grid on the front face.
			var cols := maxi(int(r.size.x / 7.0), 1)
			var rows := int(r.size.y / 8.0)
			for row in rows:
				for col in cols:
					if _h(i * 31 + row, col, _seed) < 0.72:
						continue
					var wx := r.position.x + 2.0 + col * (r.size.x - 3.0) / cols
					draw_rect(Rect2(wx, r.position.y + 3.0 + row * 8.0, 2, 3), light)
		"bands":
			for k in range(1, 6):
				var y := r.position.y + r.size.y * k / 6.0
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line, 1.0)
			draw_rect(Rect2(r.get_center().x - 1, r.position.y + 4, 2, r.size.y - 8), Color(light, 0.4))
		"crystal":
			# Faceted crystal tip on top of a dark plinth.
			var c := Vector2(r.get_center().x, r.position.y)
			var hw := r.size.x * 0.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(-hw, 0), c + Vector2(0, -hw * 1.6),
					c + Vector2(hw, 0)]), top)
			draw_line(c + Vector2(0, -hw * 1.6), c + Vector2(0, 0), light, 1.0)
		"girder":
			var n := maxi(int(r.size.y / r.size.x), 1)
			for k in n:
				var y0 := r.position.y + k * r.size.y / n
				var y1 := r.position.y + (k + 1) * r.size.y / n
				draw_line(Vector2(r.position.x, y0), Vector2(r.end.x, y1), line, 1.0)
				draw_line(Vector2(r.end.x, y0), Vector2(r.position.x, y1), line, 1.0)
			draw_rect(Rect2(r.get_center().x - 1, r.position.y - 2, 2, 2), light)
		"tank":
			for k in range(1, 4):
				var y := r.position.y + r.size.y * k / 4.0
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line, 1.0)
			draw_rect(Rect2(r.position.x + 2, r.position.y + 2, 1, r.size.y - 4), top)
		"ice":
			var c := Vector2(r.get_center().x, r.position.y)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r.size.x * 0.5, 0), c + Vector2(-2, -9),
					c + Vector2(3, -4), c + Vector2(r.size.x * 0.5, 0)]), top)
			draw_line(r.position + Vector2(3, 4), r.position + Vector2(3, r.size.y - 4), top, 1.0)
		"pylon":
			draw_line(Vector2(r.position.x, r.position.y + 6), Vector2(r.end.x, r.position.y + 6), line, 1.0)
			for k in 3:
				var y := r.position.y + 10 + k * 10
				draw_line(Vector2(r.position.x - 4, y), Vector2(r.end.x + 4, y), line, 1.0)
				draw_rect(Rect2(r.position.x - 4, y, 2, 2), light)
		"monolith":
			for k in 4:
				var y := r.position.y + 4 + k * r.size.y / 4.0
				if _h(i, k + 20, _seed) < 0.5:
					draw_rect(Rect2(r.position.x + 2, y, r.size.x - 4, 1), light)
