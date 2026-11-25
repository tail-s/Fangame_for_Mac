extends Node2D
## Afterimage: a coloured copy of a character's current sprite layers that stays
## where it was made and fades out. Used for rushes, dives and armor dashes.
## The copy is drawn just behind the character (same z, earlier sibling).

const FLASH := preload("res://scripts/player/sprite_flash.gdshader")

static var _materials := {}

var life := 0.22
var _t := 0.0
var _start_alpha := 0.6


## Copies the visible Sprite2D children of `rig` (a SpriteVisual's rig node) into a
## new afterimage at the rig's world position. Returns null if nothing was visible.
static func capture(rig: Node2D, actor: Node2D, color: Color, alpha := 0.6, duration := 0.22) -> Node2D:
	var host := actor.get_parent()
	if host == null:
		return null
	var ghost = load("res://scripts/fx/afterimage.gd").new()
	ghost.life = duration
	ghost._start_alpha = alpha
	ghost.z_index = actor.z_index
	ghost.z_as_relative = actor.z_as_relative
	var mat := _material(color)
	var n := 0
	for s in rig.get_children():
		if not (s is Sprite2D) or not s.visible:
			continue
		var c := Sprite2D.new()
		c.texture = s.texture
		c.centered = s.centered
		c.offset = s.offset
		c.region_enabled = s.region_enabled
		c.region_rect = s.region_rect
		c.position = s.position
		c.rotation = s.rotation
		c.scale = s.scale
		c.material = mat
		ghost.add_child(c)
		n += 1
	if n == 0:
		ghost.free()
		return null
	ghost.modulate.a = alpha
	host.add_child(ghost)
	host.move_child(ghost, actor.get_index())
	# Whole transform: keeps the rig's facing flip.
	ghost.global_transform = rig.global_transform
	return ghost


static func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLASH
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("amount", 0.6)
		_materials[key] = m
	return _materials[key]


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	var k := _t / life
	modulate.a = _start_alpha * (1.0 - k * k)
