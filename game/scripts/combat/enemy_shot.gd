extends Area2D
## Enemy projectile. The player's hurtbox detects it and calls hit().

const Layers = preload("res://scripts/core/layers.gd")
const PixelArt = preload("res://scripts/fx/pixel_art.gd")

var velocity := Vector2.ZERO
var damage := 2
var life := 3.0


func _ready() -> void:
	add_to_group("enemy_shot")
	collision_layer = Layers.ENEMY_SHOT
	collision_mask = Layers.WORLD
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 3.0
	cs.shape = circle
	add_child(cs)
	body_entered.connect(func(_body: Node) -> void: hit())


func hit() -> void:
	if not is_queued_for_deletion():
		queue_free()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


# Red energy pellet, 7 px plus its own 1 px outline (it lives in the enemy
# CanvasGroup and is drawn pre-shaded, so pixel_shade leaves it as drawn).
# The hot core pulses between white and pink.
const TONES := [Color("8e1d31"), Color("e34f5b"), Color("ff9c9c"), Color("fff0ee")]
const OUTLINE := Color("0d1429")


func _draw() -> void:
	var pulse := int(life * 16.0) % 2
	var tex := PixelArt.cached("enemy_shot%d" % pulse, func() -> Image:
		var img := PixelArt.blank(9, 9)
		var tones: Array = TONES.duplicate()
		if pulse == 1:
			tones[3] = tones[2]
		PixelArt.glow_ellipse(img, Vector2(4.5, 4.5), Vector2(3.6, 3.6), tones)
		return PixelArt.outline(img, OUTLINE))
	draw_texture(tex, Vector2(-4, -4), Color(1, 1, 1, PixelArt.PRESHADED))
