extends SceneTree
## rows: v1 neutral, v2 neutral, v1 vanguard, v2 vanguard; cols: chosen frames. 6x.
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var v1: String = a[0]
	var v2: String = ProjectSettings.globalize_path("res://art/characters/ix")
	var out: String = a[1]
	var frames := [0, 6, 9, 14, 17, 20, 23, 26]
	var layers := ["wings", "far_arm", "far_leg", "body", "near_leg", "head", "near_arm"]
	var cw := 48
	var ch := 46
	var sheet := Image.create(cw * frames.size(), ch * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1c2a48"))
	var row := 0
	for variant in [0, 1]:
		for dir in [v1, v2]:
			for fi in frames.size():
				for l in layers:
					var img := Image.load_from_file(dir.path_join(l + ".png"))
					img.convert(Image.FORMAT_RGBA8)
					sheet.blend_rect(img, Rect2i(frames[fi] * 64 + 8, variant * 56 + 8, cw, ch), Vector2i(fi * cw, row * ch))
			row += 1
	sheet.resize(sheet.get_width() * 5, sheet.get_height() * 5, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	quit()
