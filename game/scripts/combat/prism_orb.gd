extends "res://scripts/combat/enemy_shot.gd"
## Boss projectile: flies toward the player, then refracts into `split_count`
## shards fanned around its travel direction.

const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")

var split_after := 0.5
var split_count := 3
var spread := 0.45
var shard_speed := 150.0
var _age := 0.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_age += delta
	if split_count > 0 and _age >= split_after and not is_queued_for_deletion():
		_split()


func _split() -> void:
	var base := velocity.angle()
	for i in split_count:
		var k := 0.0 if split_count == 1 else (float(i) / (split_count - 1) - 0.5) * 2.0
		var shard := EnemyShot.new()
		shard.velocity = Vector2.from_angle(base + k * spread) * shard_speed
		shard.position = position
		get_parent().add_child(shard)
	queue_free()


# Faceted prism crystal (lit upper-left facet, dark lower-right) with a white
# core, flickering purple / cyan; pre-shaded with its own outline like EnemyShot.
const FACETS := [
	[Color("e4d4ff"), Color("b78af3"), Color("8a63d2"), Color("553894")],
	[Color("c4fbff"), Color("3de0ee"), Color("22a9bd"), Color("15697f")],
]


func _draw() -> void:
	var f := int(_age * 20.0) % 2
	var tex := PixelArt.cached("prism_orb%d" % f, func() -> Image:
		var tones: Array = FACETS[f]
		var img := PixelArt.blank(13, 15)
		var c := Vector2(6.5, 7.5)
		for y in 15:
			for x in 13:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var m := absf(d.x) / 5.6 + absf(d.y) / 6.6
				if m > 1.0:
					continue
				var col: Color
				if d.y < 0.0:
					col = tones[0] if d.x < 0.0 else tones[1]
				else:
					col = tones[2] if d.x < 0.0 else tones[3]
				if m < 0.3:
					col = Color.WHITE
				img.set_pixel(x, y, col)
		img.set_pixel(4, 5, Color.WHITE)
		return PixelArt.outline(img, OUTLINE))
	draw_texture(tex, Vector2(-6, -7), Color(1, 1, 1, PixelArt.PRESHADED))
