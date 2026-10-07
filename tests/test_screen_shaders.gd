extends SceneTree
## Tests the screen shader plugin's editor half (addons/lcf_shaders) on a copy of the
## demo: parameters in shader files, the Godot wrapper, the settings file the
## runtime reads, the panel, the preview on the map and the comment commands.
## Run: godot --headless --path . --script res://tests/test_screen_shaders.gd
## Without --headless (with a display, e.g. xvfb-run) it also renders the preview
## and checks its colours.

const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")
const Logic := preload("res://addons/lcf_shaders/screen_shaders.gd")
const Plugin := preload("res://addons/lcf_shaders/plugin.gd")
const CommandText := preload("res://addons/lcf_editor/command_text.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Shader files.
	var night := FileAccess.get_file_as_string("res://addons/lcf_shaders/examples/night.glsl")
	var params := Logic.parse_params(night)
	_check(params.size() == 2, "night.glsl declares two parameters")
	_check(params[0].name == "strength" and params[0].default == [0.7] and params[0].min == 0.0 and params[0].max == 1.0,
		"a float with its default and range: %s" % [params[0]])
	_check(params[1].name == "tint" and params[1].color and params[1].default == [0.45, 0.55, 1.0], "a colour: %s" % [params[1]])
	var odd := Logic.parse_params("uniform vec4 c; // color 1, 0.5, 0\nuniform float plain;\nuniform sampler2D s;\nuniform float x; // 2")
	_check(odd.size() == 3 and odd[0].default == [1.0, 0.5, 0.0, 1.0] and odd[1].default == [0.0] and odd[2].max == 4.0,
		"defaults: alpha 1, 0 without a value, a range around the default; samplers are not parameters")
	var godot := Logic.to_godot(night)
	_check("shader_type canvas_item;" in godot and "uniform float strength = 0.7000;" in godot and "uniform vec3 tint = vec3(0.4500, 0.5500, 1.0000);" in godot,
		"to_godot() wraps the file for Godot with the defaults")
	_check("vec4 pixel(vec2 uv)" in godot and "COLOR = vec4(effect(UV).rgb, 1.0);" in godot, "and defines pixel() and calls effect()")
	_check(Logic.list_examples() == PackedStringArray(["crt", "heat_haze", "night", "sepia"]), "four example shaders: %s" % [Logic.list_examples()])

	# Comment commands.
	for schema in Plugin.schemas(PackedStringArray(["night"])):
		LcfCommands.register(schema)
	var set_shader := LcfCommands.get_comment_schema("shader")
	_check(LcfCommands.encode_comment(set_shader, PackedInt32Array(), { 0: "night" }) == "@shader \"night\"", "Set Screen Shader is stored as @shader \"night\"")
	_check(set_shader.params[0].choices.has("night") and set_shader.params[0].choices.has("none"), "and offers the game's shaders and None")
	var set_param := LcfCommands.get_comment_schema("shader_param")
	_check(LcfCommands.encode_comment(set_param, PackedInt32Array([0, 50, 100]), { 0: "strength" }) == "@shader_param \"strength\", 50, 100",
		"Set Shader Parameter is stored as @shader_param \"strength\", 50, 100")
	var line := CommandText.line(null, { "code": 12410, "indent": 0, "string": "@shader \"night\"", "parameters": PackedInt32Array() })
	_check(line.begins_with("◆Set Screen Shader"), "the comment reads as a command: %s" % line)

	# A project, the API and the views.
	var work := ProjectSettings.globalize_path("user://screen_shaders_test")
	_copy_demo(work)
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	project.load(work)
	var main := TabContainer.new()
	main.size = Vector2(1000, 700)
	var map_view: Control = MapView.new()
	map_view.name = "Map"
	main.add_child(map_view)
	var db_view: Control = DatabaseView.new()
	db_view.name = "Database"
	main.add_child(db_view)
	root.add_child(main)
	await process_frame
	var api := LcfEditorAPI.new(null, main, map_view, db_view)
	api.set_project(project)
	api.open_map(1)

	var logic: RefCounted = Logic.new()
	logic.api = api
	_check(logic.list_shaders().is_empty(), "the demo has no shaders yet")
	_check(logic.add_example("sepia") == OK and logic.add_example("night") == OK, "examples are copied into the game's Shader folder")
	_check(FileAccess.file_exists(work.path_join("Shader/sepia.glsl")) and logic.add_example("sepia") == ERR_ALREADY_EXISTS,
		"Shader/sepia.glsl exists (and is not overwritten)")
	_check(logic.list_shaders() == PackedStringArray(["night", "sepia"]), "the library lists them")

	# Settings: what the runtime reads.
	_check(logic.choice_for(1).shader == "", "no shader by default")
	logic.set_default_choice({ "shader": "night", "params": {} })
	logic.set_map_choice(3, { "shader": "none" })
	logic.set_map_choice(1, { "shader": "sepia", "params": { "amount": 0.5 } })
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(work.path_join("lcf-plugins/shaders.json")))
	_check(stored is Dictionary and stored.default.shader == "night" and stored.maps["1"].shader == "sepia" and stored.maps["1"].params.amount == 0.5 and stored.maps["3"].shader == "none",
		"lcf-plugins/shaders.json holds the default and the maps: %s" % [stored])
	_check(logic.choice_for(1).shader == "sepia" and logic.choice_for(4).shader == "night" and logic.choice_for(4).source == "default" and logic.choice_for(3).shader == "",
		"each map's shader: its own, the default, or none")
	logic.set_param(4, "strength", 0.25)
	_check(logic.get_settings().default.params.strength == 0.25, "a parameter of a map using the default changes the default")
	logic.set_map_choice(1, {})
	_check(logic.choice_for(1).shader == "night", "removing a map's shader goes back to the default")
	logic.set_map_choice(1, { "shader": "sepia", "params": {} })

	# The preview on the map.
	logic.update_preview()
	var rect: ColorRect = map_view.screen_rect
	_check(rect != null and rect.material is ShaderMaterial and rect.size == Vector2(map_view.map.width, map_view.map.height) * 16,
		"the preview covers the whole map with the shader")
	await process_frame
	var mat: ShaderMaterial = rect.material
	_check(mat.get_shader_parameter("resolution") == rect.size and mat.get_shader_parameter("lcf_size") is Vector2, "the map view sets the uniforms every frame")
	logic.preview = false
	_check(map_view.screen_rect == null, "the preview can be turned off")
	logic.preview = true

	# The panel.
	var panel: Control = logic.make_panel()
	root.add_child(panel)
	var pick: OptionButton = _find(panel, func(n: Node) -> bool: return n is OptionButton and n.name == "map_shader")
	_check(pick != null and pick.get_item_text(pick.selected) == "sepia", "the panel shows the map's shader")
	var amount: Node = _find(panel, func(n: Node) -> bool: return n.name == "amount")
	_check(amount != null, "and a control for its parameter")
	var spin: SpinBox = _find(amount, func(n: Node) -> bool: return n is SpinBox)
	spin.value = 0.3
	_check(is_equal_approx(float(logic.choice_for(1).params.amount), 0.3) and is_instance_valid(spin) and spin.is_inside_tree(),
		"changing it stores it (and keeps the control while editing)")
	pick.select(1)  # None
	pick.item_selected.emit(1)
	_check(logic.get_settings().maps["1"].shader == "none", "choosing None stores \"none\" for the map")
	pick = _find(panel, func(n: Node) -> bool: return n is OptionButton and n.name == "map_shader")
	_check(pick.get_item_text(pick.selected) == "None", "the panel is rebuilt with the new choice")
	pick.item_selected.emit(3)  # sepia
	panel.queue_free()

	# Rendering (only with a display).
	if DisplayServer.get_name() != "headless":
		await _check_rendering(logic, map_view)

	api.shutdown()
	for name in Plugin.COMMANDS:
		LcfCommands.unregister_comment(name)
	api.free()
	main.queue_free()
	await process_frame
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _check_rendering(logic: RefCounted, map_view: Control) -> void:
	root.size = Vector2i(1000, 700)
	logic.preview = false
	for i in 4:
		await process_frame
	var plain := _stats(map_view)
	logic.preview = true
	logic.set_map_choice(1, { "shader": "sepia", "params": { "amount": 1.0 } })
	for i in 4:
		await process_frame
	var sepia := _stats(map_view)
	_check(plain.green > 0.3, "without the preview the map is green: %s" % [plain])
	_check(sepia.green == 0.0 and sepia.not_sepia < 0.02, "the sepia preview tints the map: %s" % [sepia])


## Shares of green and of non-sepia pixels on the visible part of the map.
func _stats(map_view: Control) -> Dictionary:
	var image := root.get_texture().get_image()
	if OS.get_environment("LCF_TEST_SHOT") != "":
		image.save_png(OS.get_environment("LCF_TEST_SHOT"))
	var map_size := Vector2(map_view.map.width, map_view.map.height) * 16
	var area: Rect2 = (map_view.canvas.get_global_transform() * Rect2(Vector2.ZERO, map_size)).intersection(map_view.viewport_area.get_global_rect())
	var green := 0
	var not_sepia := 0
	var count := 0
	for y in range(int(area.position.y) + 10, int(area.end.y) - 10, 4):
		for x in range(int(area.position.x) + 10, int(area.end.x) - 10, 4):
			var c := image.get_pixel(x, y)
			if c.g8 > c.r8 + 12 and c.g8 > c.b8 + 12:
				green += 1
			if c.r8 + 3 < c.g8 or c.g8 + 3 < c.b8:
				not_sepia += 1
			count += 1
	return { "green": snappedf(float(green) / maxi(1, count), 0.01), "not_sepia": snappedf(float(not_sepia) / maxi(1, count), 0.01) }


func _find(node: Node, test: Callable) -> Node:
	if test.call(node):
		return node
	for child in node.get_children():
		var found := _find(child, test)
		if found:
			return found
	return null


func _copy_demo(work: String) -> void:
	var demo := ProjectSettings.globalize_path("res://demo")
	DirAccess.make_dir_recursive_absolute(work.path_join("ChipSet"))
	for dir in [work, work.path_join("lcf-plugins"), work.path_join("Shader")]:
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
	for f in DirAccess.get_files_at(demo):
		DirAccess.copy_absolute(demo.path_join(f), work.path_join(f))
	for f in DirAccess.get_files_at(demo.path_join("ChipSet")):
		DirAccess.copy_absolute(demo.path_join("ChipSet").path_join(f), work.path_join("ChipSet").path_join(f))
