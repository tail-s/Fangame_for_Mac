extends SceneTree
## Bakes the character sprite sheets into res://art/characters/<id>/.
##   godot --headless --path game -s res://tools/bake_characters.gd
##   ... -- --preview=/abs/dir   also writes enlarged contact sheets for look-dev
##
## Per character:
##   <layer>.png   one row per armor variant, one column per animation frame
##   <extra>.png   arm sprites (buster / saber / pistol), one row per variant, one column per angle
##   sheet.json    cell size, origin, layer order, variants, animations and per-frame anchors
## The PNGs are ordinary sprite sheets: they can be retouched by hand (Aseprite etc.)
## as long as the cell grid stays the same.

const Raster = preload("res://tools/sprites/raster.gd")
const Rig = preload("res://tools/sprites/rig.gd")
const Anims = preload("res://tools/sprites/anims.gd")

const CELL := Vector2i(64, 56)
const ORIGIN := Vector2(32, 52)
const OUT_DIR := "res://art/characters"

var preview_dir := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			preview_dir = a.substr(10)
	var t0 := Time.get_ticks_msec()
	var models := {
		"ix": preload("res://tools/sprites/ix_model.gd").new(),
		"sable": preload("res://tools/sprites/sable_model.gd").new(),
		"echo": preload("res://tools/sprites/echo_model.gd").new(),
		"eclipse": preload("res://tools/sprites/eclipse_model.gd").new(),
	}
	for id in models:
		_bake(id, models[id])
	print("baked %d characters in %d ms" % [models.size(), Time.get_ticks_msec() - t0])
	quit()


func _bake(id: String, model) -> void:
	var dir := OUT_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var rig := Rig.new()
	rig.scale = model.get_script().get_script_constant_map().get("RIG_SCALE", 1.0)
	var data := Anims.build()
	var frames: Array = data.frames
	var variants: Array = model.VARIANTS
	var joints := []
	for pose in frames:
		joints.append(rig.joints(pose, ORIGIN))
	var meta := {
		"cell": [CELL.x, CELL.y],
		"origin": [ORIGIN.x, ORIGIN.y],
		"layers": model.LAYERS,
		"layer_slot": model.LAYER_SLOT,
		"variants": variants,
		"anims": data.anims,
		"shoulder": [],
		"extras": {},
	}
	for j in joints:
		var sh: Vector2 = j.n_shoulder - ORIGIN
		meta.shoulder.append([snappedf(sh.x, 0.1), snappedf(sh.y, 0.1)])
	var sheets := {}
	for layer in model.LAYERS:
		var sheet := Image.create(CELL.x * frames.size(), CELL.y * variants.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0, 0, 0, 0))
		for vi in variants.size():
			var v: String = variants[vi]
			if not model.has_layer(layer, v):
				continue
			for fi in frames.size():
				var r := Raster.new(CELL.x, CELL.y)
				model.draw(r, joints[fi], layer, v)
				r.finish(model.OUTLINE)
				sheet.blit_rect(r.img, Rect2i(Vector2i.ZERO, CELL), Vector2i(fi * CELL.x, vi * CELL.y))
		_retouch(sheet, dir.path_join("retouch").path_join(layer + ".png"))
		sheet.save_png(ProjectSettings.globalize_path(dir.path_join(layer + ".png")))
		sheets[layer] = sheet
	# Arm sprites drawn on their own (origin = shoulder).
	var extra_imgs := {}
	for ex in model.extras():
		var ecell: Vector2i = ex.cell
		var eorigin: Vector2 = ex.origin
		var angles: Array = ex.get("angles", [0.0])
		var sheet := Image.create(ecell.x * angles.size(), ecell.y * variants.size(), false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0, 0, 0, 0))
		for vi in variants.size():
			for ai in angles.size():
				var r := Raster.new(ecell.x, ecell.y)
				model.draw_extra(r, ex.name, eorigin, variants[vi], angles[ai])
				r.finish(model.OUTLINE)
				sheet.blit_rect(r.img, Rect2i(Vector2i.ZERO, ecell), Vector2i(ai * ecell.x, vi * ecell.y))
		_retouch(sheet, dir.path_join("retouch").path_join(ex.name + ".png"))
		sheet.save_png(ProjectSettings.globalize_path(dir.path_join(ex.name + ".png")))
		extra_imgs[ex.name] = sheet
		meta.extras[ex.name] = {"cell": [ecell.x, ecell.y], "origin": [eorigin.x, eorigin.y],
				"angles": angles, "tip": ex.get("tip", [])}
	var f := FileAccess.open(ProjectSettings.globalize_path(dir.path_join("sheet.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("%s: %d frames x %d variants, %d layers" % [id, frames.size(), variants.size(), model.LAYERS.size()])
	if preview_dir != "":
		_preview(id, model, meta, sheets, extra_imgs)


## Hand retouch (X6-style finishing by a pixel artist): every opaque pixel of
## art/characters/<id>/retouch/<sheet>.png replaces the baked one, pure magenta
## (#ff00ff) erases it, transparent keeps the baked pixel. The retouch folder has a
## .gdignore so Godot never imports or ships it; rebakes keep the artist's work.
func _retouch(sheet: Image, path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return
	var t := Image.load_from_file(abs_path)
	t.convert(Image.FORMAT_RGBA8)
	var n := 0
	for y in mini(t.get_height(), sheet.get_height()):
		for x in mini(t.get_width(), sheet.get_width()):
			var c := t.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.r8 == 255 and c.g8 == 0 and c.b8 == 255:
				sheet.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				sheet.set_pixel(x, y, Color(c, 1.0))
			n += 1
	print("  retouch %s: %d px" % [path.get_file(), n])


## Contact sheets for look-dev: one image per variant, 9 frames per row, enlarged 3x.
func _preview(id: String, model, meta: Dictionary, sheets: Dictionary, extra_imgs: Dictionary) -> void:
	var variants: Array = meta.variants
	var nframes: int = meta.shoulder.size()
	var cols := 9
	var rows := int(ceil(nframes / float(cols)))
	for vi in variants.size():
		var img := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
		img.fill(Color("1c2a48"))
		for fi in nframes:
			var src := Rect2i(fi * CELL.x, vi * CELL.y, CELL.x, CELL.y)
			var dst := Vector2i((fi % cols) * CELL.x, (fi / cols) * CELL.y)
			for layer in model.LAYERS:
				img.blend_rect(sheets[layer], src, dst)
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		img.save_png(preview_dir.path_join("%s_%s.png" % [id, variants[vi]]))
	for name in extra_imgs:
		var e: Image = extra_imgs[name]
		var bg := Image.create(e.get_width(), e.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(Color("1c2a48"))
		bg.blend_rect(e, Rect2i(Vector2i.ZERO, e.get_size()), Vector2i.ZERO)
		bg.resize(e.get_width() * 4, e.get_height() * 4, Image.INTERPOLATE_NEAREST)
		bg.save_png(preview_dir.path_join("%s_%s.png" % [id, name]))
