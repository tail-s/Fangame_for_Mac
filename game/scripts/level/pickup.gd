extends Area2D
## Armor part capsule ('1'..'8') or HP-up tank ('+').

signal collected(pickup)

const Layers = preload("res://scripts/core/layers.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")

var kind := "part"  # "part" | "hp"
var part_id := ""
var pickup_id := ""
var _t := 0.0
var _taken := false


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 20)
	cs.shape = rect
	cs.position = Vector2(0, -10)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	collected.emit(self)
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# --- drawing ----------------------------------------------------------------------
# Part capsule: steel caps around an armor-colour glass core with the slot letter,
# a pulsing halo ring and two orbiting sparkles. HP-up: a squat teal cell with a
# white cross. Both bob as before; sprites are built once per colour.

const PixelArt = preload("res://scripts/fx/pixel_art.gd")
const STEEL := {"o": Color("0a1326"), "W": Color("ffffff"), "S": Color("d3e3ec"), "s": Color("8aa7bd"),
		"d": Color("3f5c7a")}
const CAPSULE_ROWS := [
	"...oooooo...",
	"..oSSSSSso..",
	".oSWSSSSsso.",
	".osssssssdo.",
	"oddddddddddo",
	"oggggGGGGGho",
	"ogwgGGGGGGho",
	"ogwGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGhho",
	"oGGGGGGGhhho",
	"oddddddddddo",
	".osSSSSSsdo.",
	".osssssssdo.",
	"..oddddddo..",
	"...oooooo...",
]
const CELL_ROWS := [
	"..oooooooo..",
	".oSWSSSSSso.",
	"oddddddddddo",
	"ogggggggGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"ogGGGGGGGGho",
	"oGGGGGGGGhho",
	"oddddddddddo",
	".osSSSSSsdo.",
	"..oooooooo..",
]
const HP_TEAL := Color("00b8be")


func _draw() -> void:
	var bob := roundf(sin(_t * 3.0) * 1.5)
	if kind == "hp":
		_draw_cell(bob)
		return
	var armor := ArmorData.part_armor(part_id)
	var c: Color = ArmorData.ARMOR_COLOR[armor]
	var mid := Vector2(0, -10 + bob)
	# Halo: soft disc plus a crisp ring that breathes.
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	PixelArt.disc(self, mid, 10.0, Color(c, 0.1 + 0.08 * pulse))
	var rr := 10.0 + roundf(pulse)
	PixelArt.ring(self, mid, rr - 1.0, rr, Color(c, 0.35 + 0.25 * pulse))
	var tex := PixelArt.cached("capsule_" + armor, func() -> Image: return _glass_sprite(CAPSULE_ROWS, c))
	var at := Vector2(-6, -19 + bob)
	draw_texture(tex, at)
	var letter: String = ArmorData.SLOT_LABEL[ArmorData.part_slot(part_id)].substr(0, 1)
	var ink := Color("0a1326") if c.get_luminance() > 0.6 else Color("f4fbff")
	PixelArt.text(self, at + Vector2(5, 7), letter, ink)
	_draw_glint(at + Vector2(2, 5), 8)
	for i in 2:
		_sparkle(mid + (Vector2.from_angle(_t * 2.2 + i * PI) * Vector2(12, 9)).round(), c)


func _draw_cell(bob: float) -> void:
	var at := Vector2(-6, -15 + bob)
	var tex := PixelArt.cached("hp_cell", func() -> Image:
		var img := _glass_sprite(CELL_ROWS, HP_TEAL)
		# Bold cross with a dark drop shadow (2 px arms).
		var shade := HP_TEAL.darkened(0.45)
		for p in _cross(3, 4):
			img.set_pixel(p.x + 1, p.y + 1, shade)
		for p in _cross(3, 4):
			img.set_pixel(p.x, p.y, Color.WHITE)
		return img)
	draw_texture(tex, at)
	_draw_glint(at + Vector2(2, 3), 7)
	_sparkle(at + (Vector2(6, 7) + Vector2.from_angle(_t * 2.6) * Vector2(10, 9)).round(), HP_TEAL)


## Pixels of a 6x6 cross with 2 px arms whose top-left is (x, y).
static func _cross(x: int, y: int) -> Array:
	var pts := []
	for i in 6:
		for j in 2:
			pts.append(Vector2i(x + 2 + j, y + i))
			pts.append(Vector2i(x + i, y + 2 + j))
	return pts


## Steel-capped glass sprite: g / G / h are the glass light / mid / dark tones.
static func _glass_sprite(rows: Array, c: Color) -> Image:
	var pal := STEEL.duplicate()
	pal["g"] = c.lightened(0.45)
	pal["G"] = c
	pal["h"] = c.darkened(0.32)
	pal["w"] = Color("ffffff")
	return PixelArt.from_rows(rows, pal)


## A light band that sweeps down the glass every 1.6 s.
func _draw_glint(top_left: Vector2, rows: int) -> void:
	var k := fmod(_t, 1.6) / 0.5
	if k >= 1.0:
		return
	var y := floorf(k * rows)
	draw_rect(Rect2(top_left + Vector2(0, y), Vector2(3, 1)), Color(1, 1, 1, 0.75))


## Four-point twinkle: white centre, coloured arms.
func _sparkle(p: Vector2, c: Color) -> void:
	var arm := Color(c.lightened(0.3), 0.85)
	draw_rect(Rect2(p + Vector2(-1, 0), Vector2(1, 1)), arm)
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), arm)
	draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), arm)
	draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 1)), arm)
	draw_rect(Rect2(p, Vector2(1, 1)), Color.WHITE)
