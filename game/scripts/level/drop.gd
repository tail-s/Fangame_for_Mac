extends Area2D
## Small capsule dropped by enemies: "hp" heals 3, "energy" refills 6 weapon energy.

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")
const PixelArt = preload("res://scripts/fx/pixel_art.gd")

var kind := "hp"
var life := 7.0
var _t := 0.0
var _vy := -80.0
var _landed := false


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	cs.shape = rect
	cs.position = Vector2(0, -5)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	if not _landed:
		_vy = minf(_vy + 600.0 * delta, 240.0)
		var step := Vector2(0, _vy * delta)
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, 1), Layers.WORLD)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or _vy < 0.0:
			global_position += step
		else:
			global_position = hit.position
			_landed = true
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or is_queued_for_deletion():
		return
	if kind == "hp":
		body.heal(3)
	else:
		body.add_weapon_energy(6.0)
	Autoloads.sfx("pickup")
	queue_free()


# Drops spawn inside the enemy CanvasGroup, so they are drawn pre-shaded with their
# own outline. HP: teal pill with a white cross. Energy: amber cell with a bolt.
const PAL := {
	"o": Color("0d1429"), "w": Color("ffffff"), "s": Color("c9dbe6"), "m": Color("7d9bb3"),
	"t": Color("7cf3ec"), "T": Color("00b8be"), "D": Color("00737e"),
	"y": Color("ffe5a3"), "Y": Color("f0b84a"), "A": Color("a8651c"),
}
const HP_ROWS := [
	"..oooooo..",
	".ottTTTTo.",
	"ottTTwTTDo",
	"otTTwwwTDo",
	"oTTTTwTTDo",
	"oTTTTTTDDo",
	".oDDDDDDo.",
	"..oooooo..",
]
const ENERGY_ROWS := [
	"...oooo...",
	"..osmmmo..",
	".oyyyYYAo.",
	".oyYYYwAo.",
	".oyYYwwAo.",
	".oywwwwAo.",
	".oYwwYYAo.",
	".oYwYYAAo.",
	"..oAAAAo..",
	"...oooo...",
]


func _draw() -> void:
	if life - _t < 2.0 and int(_t * 12.0) % 2 == 0:
		return
	var hp := kind == "hp"
	var tex := PixelArt.cached("drop_hp" if hp else "drop_energy", func() -> Image:
		return PixelArt.from_rows(HP_ROWS if hp else ENERGY_ROWS, PAL))
	var at := Vector2(-5, -9) if hp else Vector2(-5, -11)
	draw_texture(tex, at, Color(1, 1, 1, PixelArt.PRESHADED))
	# Travelling glint.
	if int(_t * 3.0) % 3 == 0:
		var g := int(fmod(_t * 3.0, 1.0) * 4.0)
		draw_rect(Rect2(at + Vector2(2 + g, 2), Vector2(1, 1)), Color(1, 1, 1, PixelArt.PRESHADED))
