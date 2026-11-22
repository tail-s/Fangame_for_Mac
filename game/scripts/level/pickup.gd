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


func _draw() -> void:
	var bob := sin(_t * 3.0) * 1.5
	if kind == "hp":
		var c := Color("00b8be")
		draw_rect(Rect2(-6, -16 + bob, 12, 14), Color("2a3550"))
		draw_rect(Rect2(-2, -14 + bob, 4, 10), c)
		draw_rect(Rect2(-5, -11 + bob, 10, 4), c)
		draw_rect(Rect2(-6, -17 + bob, 12, 1), Color("d7edf3"))
		return
	var armor := ArmorData.part_armor(part_id)
	var c: Color = ArmorData.ARMOR_COLOR[armor]
	var glow := 0.25 + 0.15 * sin(_t * 5.0)
	draw_circle(Vector2(0, -10 + bob), 11.0, Color(c, glow))
	draw_rect(Rect2(-6, -18 + bob, 12, 16), Color("2a3550"))
	draw_rect(Rect2(-4, -16 + bob, 8, 12), c)
	var letter: String = ArmorData.SLOT_LABEL[ArmorData.part_slot(part_id)].substr(0, 1)
	draw_string(ThemeDB.fallback_font, Vector2(-3, -7 + bob), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("0a1326"))
