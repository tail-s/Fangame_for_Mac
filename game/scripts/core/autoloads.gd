## Static access to the autoloads (Game, Audio) for gameplay scripts that also
## run inside `-s` test scripts, where autoload names are not compile-time globals.


static func node(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null


static func sfx(sfx_name: String, pitch := 1.0) -> void:
	var a := node("Audio")
	if a != null:
		a.sfx(sfx_name, pitch)


## "Reduce flashes" option is off (bright flashes allowed).
static func flashes() -> bool:
	var g := node("Game")
	return g == null or g.settings.get("flashes", true)
