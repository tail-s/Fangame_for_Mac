extends RefCounted
## Shared helpers for the code-drawn pixel art: HUD gauges, pickups, shots and
## explosions. Everything lands on whole pixels of the 384x216 canvas.
##   - Small fixed sprites are built once into ImageTextures (cached by key), either
##     from ASCII rows + a palette or from a per-pixel shading pass, then drawn as
##     one texture so each pixel is written exactly once.
##   - Shapes that change size every frame (rings, puffs) are drawn as one rect per
##     pixel row (disc / ring), so they stay crisp and symmetric at any radius.
## Enemy-side things live inside the Actors CanvasGroup (fx/pixel_shade.gdshader).
## Sprites drawn there at PRESHADED alpha pass through it untouched: they carry
## their own outline and shading, so the shader must not add a second set.

const PRESHADED := 0.98
const INK := Color("0a1326")
const CLEAR := Color(0, 0, 0, 0)
## 3x5 pixel font for HUD chips and short tags ("1" = lit), rows top to bottom.
const FONT := {
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "J": ["001", "001", "001", "101", "010"],
	"K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"],
	"O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
	"Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
	"S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
	"U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"],
	"W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
	"+": ["000", "010", "111", "010", "000"],
}

static var _cache := {}


## Texture for `key`, built on first use by `build` (a Callable returning an Image).
static func cached(key: String, build: Callable) -> Texture2D:
	var t = _cache.get(key)
	if t == null:
		t = ImageTexture.create_from_image(build.call())
		_cache[key] = t
	return t


static func blank(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


## Image from equal-length ASCII rows; characters missing from `pal` stay clear.
static func from_rows(rows: Array, pal: Dictionary) -> Image:
	var img := blank(String(rows[0]).length(), rows.size())
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return img


## Adds a 1 px outline of `c` around every pixel with alpha >= `min_a`.
static func outline(img: Image, c: Color, min_a := 0.6) -> Image:
	var src := img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a >= min_a:
				continue
			if _alpha(src, x - 1, y) >= min_a or _alpha(src, x + 1, y) >= min_a \
					or _alpha(src, x, y - 1) >= min_a or _alpha(src, x, y + 1) >= min_a:
				img.set_pixel(x, y, c)
	return img


static func _alpha(img: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0.0
	return img.get_pixel(x, y).a


## Energy blob: `tones` = [rim, mid, light, core] from the edge in; the hot centre
## sits a little up-left so the light reads as coming from the upper left.
static func glow_ellipse(img: Image, c: Vector2, r: Vector2, tones: Array) -> void:
	var hot := c + Vector2(-r.x * 0.18, -r.y * 0.22)
	for y in range(int(c.y - r.y) - 1, int(c.y + r.y) + 2):
		for x in range(int(c.x - r.x) - 1, int(c.x + r.x) + 2):
			var p := Vector2(x + 0.5, y + 0.5)
			var n := (p - c) / r
			if n.length() > 1.0:
				continue
			var h := ((p - hot) / r).length()
			var col: Color = tones[0]
			if h < 0.36:
				col = tones[3]
			elif h < 0.62:
				col = tones[2]
			elif h < 0.86 and n.x + n.y < 0.9:
				col = tones[1]
			elif n.x + n.y < -0.2:
				col = tones[1]
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)


# --- immediate-mode shapes (one rect per pixel row) -----------------------------

## Filled disc of every pixel whose centre lies within `r` of `c` (c on a pixel corner).
static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.3:
		return
	var cx := roundf(c.x)
	var cy := roundf(c.y)
	var ri := int(ceil(r))
	for y in range(-ri, ri):
		var yy := y + 0.5
		if absf(yy) >= r:
			continue
		var hw := roundf(sqrt(r * r - yy * yy))
		if hw > 0.0:
			ci.draw_rect(Rect2(cx - hw, cy + y, hw * 2.0, 1), col)


## Ring between radii r_in and r_out. With `lo` given, the lower-right half of the
## ring uses it (light from the upper left).
static func ring(ci: CanvasItem, c: Vector2, r_in: float, r_out: float, col: Color, lo := Color(0, 0, 0, 0)) -> void:
	if r_out <= 0.3:
		return
	var cx := roundf(c.x)
	var cy := roundf(c.y)
	var ri := int(ceil(r_out))
	var shade := lo.a > 0.0
	for y in range(-ri, ri):
		var yy := y + 0.5
		if absf(yy) >= r_out:
			continue
		var ho := roundf(sqrt(r_out * r_out - yy * yy))
		var hi := roundf(sqrt(r_in * r_in - yy * yy)) if absf(yy) < r_in else 0.0
		if ho <= hi:
			continue
		var left := col
		var right := col
		if shade:
			left = col if yy < r_out * 0.35 else lo
			right = lo if yy > -r_out * 0.35 else col
		if hi <= 0.0:
			if shade and left != right:
				ci.draw_rect(Rect2(cx - ho, cy + y, ho, 1), left)
				ci.draw_rect(Rect2(cx, cy + y, ho, 1), right)
			else:
				ci.draw_rect(Rect2(cx - ho, cy + y, ho * 2.0, 1), left)
		else:
			ci.draw_rect(Rect2(cx - ho, cy + y, ho - hi, 1), left)
			ci.draw_rect(Rect2(cx + hi, cy + y, ho - hi, 1), right)


## 1 px line from a to b, one rect per pixel.
static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxf(n, 1)).round()
		ci.draw_rect(Rect2(p, Vector2.ONE), col)


## 3x5 pixel text; returns the width drawn. Characters missing from FONT are skipped.
static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color) -> int:
	var x := 0
	for ch in s.to_upper():
		if ch == " ":
			x += 3
			continue
		var g = FONT.get(ch)
		if g == null:
			continue
		for row in 5:
			var bits: String = g[row]
			for col_i in 3:
				if bits[col_i] == "1":
					ci.draw_rect(Rect2(pos.x + x + col_i, pos.y + row, 1, 1), col)
		x += 4
	return maxi(x - 1, 0)
