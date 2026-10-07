extends SceneTree
## Renders one map of an RPG Maker 2000/2003 project to a PNG, without the editor.
## Run: godot --headless --path . --script res://tests/render_map.gd -- <project_dir> <map_id> <out.png>
## Defaults: res://demo, map 1, user://map.png

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var project_dir: String = args[0] if args.size() > 0 else "res://demo"
	var map_id := int(args[1]) if args.size() > 1 else 1
	var out_path: String = args[2] if args.size() > 2 else "user://map.png"

	var project: RefCounted = ClassDB.instantiate("LcfProject")
	if project.load(project_dir) != OK:
		_fail(project.get_last_error())
		return
	var map: Dictionary = project.get_map(map_id)
	if map.is_empty():
		_fail(project.get_last_error())
		return
	var chipset_info: Dictionary = project.get_chipset(map.chipset_id)
	var chipset: RefCounted = ClassDB.instantiate("LcfChipset")
	var file: String = project.find_image("ChipSet", chipset_info.get("file", ""))
	if file == "" or chipset.load(file) != OK:
		_fail("Chipset not found: %s" % chipset_info.get("file", "?"))
		return

	var ids := PackedInt32Array()
	ids.append_array(map.lower)
	ids.append_array(map.upper)
	var atlas: Dictionary = chipset.build_atlas(ids)
	var tiles: Image = atlas.image
	var coords: Dictionary = atlas.coords

	var w: int = map.width
	var h: int = map.height
	var image := Image.create_empty(w * 16, h * 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	for layer in [map.lower, map.upper]:
		for i in w * h:
			var cell: Vector2i = coords[layer[i]]
			image.blend_rect(tiles, Rect2i(cell * 16, Vector2i(16, 16)), Vector2i(i % w, i / w) * 16)
	image.save_png(out_path)
	print("Rendered map %d (%dx%d) to %s" % [map_id, w, h, out_path])
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
