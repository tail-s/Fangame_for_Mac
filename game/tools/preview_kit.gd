extends SceneTree
## Look-dev: every hand-drawn part of a kit in every palette, enlarged.
##   godot --headless --path game -s res://tools/preview_kit.gd -- /abs/out.png

const Raster = preload("res://tools/sprites/raster.gd")
const Kit = preload("res://tools/sprites/ix_kit.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var parts := [Kit.HEAD, Kit.HEAD_VFIN, Kit.HEAD_KNIGHT_FINS, Kit.HEAD_HORN_SWEEP, Kit.TORSO,
			Kit.TORSO_KNIGHT, Kit.TORSO_BRAWLER, Kit.TORSO_PACK, Kit.BOOT, Kit.BOOT_DOWN, Kit.BOOT_BRAWLER,
			Kit.BOOT_KNIGHT, Kit.PAD, Kit.PAD_BRAWLER, Kit.PAD_KNIGHT, Kit.BUSTER, Kit.BUSTER_LANCE]
	var variants := ["neutral", "vanguard", "aero", "ultimate"]
	var cell := Vector2i(24, 18)
	var sheet := Image.create(cell.x * parts.size(), cell.y * variants.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1c2a48"))
	for vi in variants.size():
		var pal := Kit.palette(variants[vi])
		for pi in parts.size():
			var r := Raster.new(cell.x, cell.y)
			r.selout = true
			r.stamp(parts[pi], pal, Vector2(2, 2), Vector2i.ZERO)
			r.finish(Color("0d1428"))
			sheet.blend_rect(r.img, Rect2i(Vector2i.ZERO, cell), Vector2i(pi * cell.x, vi * cell.y))
	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	quit()
