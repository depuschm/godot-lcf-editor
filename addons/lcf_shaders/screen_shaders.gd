@tool
extends RefCounted
## Screen shaders' editor logic, separate from the EditorPlugin so it can be tested:
## the game's shader library (.glsl files in its Shader folder), which shader each
## map uses (lcf-plugins/shaders.json), the live preview on the map and the panel.
##
## A shader file is GLSL that works both in EasyRPG Player (GLSL 1.20) and, wrapped
## by to_godot(), in Godot. It defines `vec4 effect(vec2 uv)` and may call
## `pixel(uv)` (the screen, uv 0..1 from the top left) and use `resolution` (the
## screen's size in pixels) and `time` (seconds). Parameters are uniforms with their
## default value, an optional range and "color" in a trailing comment:
##
##     uniform float strength; // 0.7 [0, 1]
##     uniform vec3 tint; // color 0.45, 0.55, 1.0
##
## The runtime half (runtime/easyrpg-player) reads the same files and settings.

## The settings changed (a map's shader, the default or a parameter).
signal settings_changed
## The shader files in the game's Shader folder changed.
signal library_changed

const PLUGIN_ID := "shaders"
const FOLDER := "Shader"
const EXAMPLES := "res://addons/lcf_shaders/examples"
const RUNTIME := "EasyRPG Player with the screen shader patch (runtime/easyrpg-player)"
const NONE := "none"
const SIZES := { "float": 1, "vec2": 2, "vec3": 3, "vec4": 4 }

var api: Object  # LcfEditorAPI
## EditorUndoRedoManager for settings changes (null: no undo, e.g. in tests).
var undo_redo: Object
## Whether the open map shows its shader.
var preview := true:
	set(on):
		preview = on
		update_preview()

var _material: ShaderMaterial
var _shaders := {}  # name -> { source: String, shader: Shader }


# --- the shader library -----------------------------------------------------------------

## The game's shader folder ("" without a project).
func shader_dir() -> String:
	var project: RefCounted = api.get_project() if api else null
	return String(project.get_project_dir()).path_join(FOLDER) if project else ""


## The names of the game's shaders (Shader/<name>.glsl), sorted.
func list_shaders() -> PackedStringArray:
	var dir := shader_dir()
	var names := PackedStringArray()
	if dir != "" and DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() == "glsl":
				names.append(file.get_basename())
	names.sort()
	return names


## The example shaders that come with the plugin.
static func list_examples() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(EXAMPLES)):
		if file.get_extension() == "glsl":
			names.append(file.get_basename())
	names.sort()
	return names


## Copies an example into the game's Shader folder (an existing file is kept).
func add_example(name: String) -> Error:
	var dir := shader_dir()
	if dir == "":
		return ERR_UNCONFIGURED
	DirAccess.make_dir_recursive_absolute(dir)
	var target := dir.path_join(name + ".glsl")
	if FileAccess.file_exists(target):
		return ERR_ALREADY_EXISTS
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(EXAMPLES).path_join(name + ".glsl"), target)
	if err == OK:
		reload_library()
	return err


## The source of a game's shader ("" if there is no such file).
func read_source(name: String) -> String:
	var path := shader_dir().path_join(name + ".glsl")
	return FileAccess.get_file_as_string(path) if name != "" and FileAccess.file_exists(path) else ""


## Forgets compiled shaders (after the files changed) and updates the preview.
func reload_library() -> void:
	_shaders.clear()
	library_changed.emit()
	update_preview()


# --- shader files -------------------------------------------------------------------------

## The parameters a shader declares: [{ name, type, size, default: Array, min, max,
## color: bool }], like the runtime reads them.
static func parse_params(source: String) -> Array:
	var params := []
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("uniform "):
			continue
		var comment := ""
		var slashes := line.find("//")
		if slashes >= 0:
			comment = line.substr(slashes + 2)
			line = line.substr(0, slashes).strip_edges()
		var words := line.trim_suffix(";").split(" ", false)
		if words.size() != 3 or not SIZES.has(words[1]) or not words[2].is_valid_identifier():
			continue
		var size: int = SIZES[words[1]]
		var param := { "name": words[2], "type": words[1], "size": size, "default": [], "min": 0.0, "max": 1.0,
			"color": comment.strip_edges().begins_with("color") }
		var range_at := comment.find("[")
		if range_at >= 0:
			var limits := _numbers(comment.substr(range_at))
			if limits.size() >= 2:
				param.min = limits[0]
				param.max = limits[1]
			comment = comment.substr(0, range_at)
		var values := _numbers(comment)
		var defaults := []
		for i in size:
			defaults.append(values[i] if i < values.size() else (values[0] if values.size() == 1 else (1.0 if i == 3 else 0.0)))
		param.default = defaults
		if range_at < 0 and not param.color:
			param.max = maxf(1.0, defaults.max() * 2.0)
			param.min = minf(0.0, defaults.min() * 2.0)
		params.append(param)
	return params


static func _numbers(text: String) -> Array:
	var out := []
	var regex := RegEx.create_from_string("-?\\d*\\.?\\d+")
	for m in regex.search_all(text):
		out.append(float(m.get_string()))
	return out


## Wraps a shader file as a Godot canvas_item shader for set_map_screen_material().
static func to_godot(source: String) -> String:
	var lines := PackedStringArray()
	var params := {}
	for param: Dictionary in parse_params(source):
		params[param.name] = param
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		var words := line.split("//")[0].strip_edges().trim_suffix(";").split(" ", false)
		if line.begins_with("uniform ") and words.size() == 3 and params.has(words[2]):
			var param: Dictionary = params[words[2]]
			lines.append("uniform %s %s = %s;" % [param.type, param.name, _literal(param.type, param.default)])
		else:
			lines.append(raw)
	return "\n".join([
		"shader_type canvas_item;",
		"render_mode unshaded;",
		"uniform sampler2D lcf_screen : hint_screen_texture, filter_nearest;",
		"uniform vec2 lcf_origin;",
		"uniform vec2 lcf_size = vec2(1.0);",
		"uniform vec2 lcf_viewport = vec2(1.0);",
		"uniform vec2 resolution = vec2(320.0, 240.0);",
		"uniform float time;",
		"vec4 pixel(vec2 uv) { return texture(lcf_screen, (lcf_origin + clamp(uv, 0.0, 1.0) * lcf_size) / lcf_viewport); }",
		"\n".join(lines),
		"void fragment() { COLOR = vec4(effect(UV).rgb, 1.0); }",
		""])


static func _literal(type: String, values: Array) -> String:
	var parts := PackedStringArray()
	for v: float in values:
		parts.append("%.4f" % v)
	return parts[0] if type == "float" else "%s(%s)" % [type, ", ".join(parts)]


# --- settings: which shader each map uses --------------------------------------------------

## { "default": { shader, params } or null, "maps": { "<id>": { shader, params } } }.
func get_settings() -> Dictionary:
	var stored: Variant = api.get_plugin_data(PLUGIN_ID, {}) if api else {}
	var out := { "default": null, "maps": {} }
	if stored is Dictionary:
		if stored.get("default") is Dictionary:
			out.default = _clean_choice(stored.default)
		if stored.get("maps") is Dictionary:
			for key: String in stored.maps:
				if stored.maps[key] is Dictionary and key.is_valid_int():
					out.maps[key] = _clean_choice(stored.maps[key])
	return out


static func _clean_choice(choice: Dictionary) -> Dictionary:
	var params := {}
	if choice.get("params") is Dictionary:
		params = choice.params.duplicate(true)
	return { "shader": String(choice.get("shader", "")), "params": params }


## What a map shows: { shader, params, source: "map" | "default" | "" } (shader ""
## for none).
func choice_for(map_id: int) -> Dictionary:
	var settings := get_settings()
	if settings.maps.has(str(map_id)):
		var choice: Dictionary = settings.maps[str(map_id)]
		return { "shader": "" if choice.shader == NONE else choice.shader, "params": choice.params, "source": "map" }
	if settings.default is Dictionary and settings.default.shader not in ["", NONE]:
		return { "shader": settings.default.shader, "params": settings.default.params, "source": "default" }
	return { "shader": "", "params": {}, "source": "" }


## Gives a map its own shader ({ shader, params }; shader "none" for no shader), or
## lets it use the default again with {}.
func set_map_choice(map_id: int, choice: Dictionary, merge := false) -> void:
	var settings := get_settings()
	if choice.is_empty():
		settings.maps.erase(str(map_id))
	else:
		settings.maps[str(map_id)] = _clean_choice(choice)
	change_settings(settings, "Screen shader for map %d" % map_id, merge)


## Sets the shader of maps without their own ({} or shader "" for none).
func set_default_choice(choice: Dictionary, merge := false) -> void:
	var settings := get_settings()
	settings.default = null if choice.is_empty() or String(choice.get("shader", "")) == "" else _clean_choice(choice)
	change_settings(settings, "Default screen shader", merge)


## Sets a parameter where the map's shader comes from (the map or the default).
func set_param(map_id: int, name: String, value: Variant) -> void:
	var choice := choice_for(map_id)
	if choice.shader == "":
		return
	var params: Dictionary = choice.params.duplicate()
	params[name] = value
	var stored := { "shader": choice.shader, "params": params }
	if choice.source == "map":
		set_map_choice(map_id, stored, true)
	else:
		set_default_choice(stored, true)


## Stores the settings (with undo when an undo manager is set). `merge` joins the
## action with the previous one of the same name (dragging a value).
func change_settings(settings: Dictionary, action := "Screen shaders", merge := false) -> void:
	var before := get_settings()
	if before == settings:
		return
	if undo_redo:
		undo_redo.create_action(action, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
		undo_redo.add_do_method(self, "apply_settings", settings)
		undo_redo.add_undo_method(self, "apply_settings", before)
		undo_redo.commit_action()
	else:
		apply_settings(settings)


func apply_settings(settings: Dictionary) -> void:
	var stored := { "maps": settings.maps }
	if settings.default != null:
		stored.default = settings.default
	if api and api.set_plugin_data(PLUGIN_ID, stored) != OK:
		push_error("Screen shaders: could not store the settings")
	settings_changed.emit()
	update_preview()


# --- preview --------------------------------------------------------------------------------

## A material with a game's shader and parameter values (null if the file is missing).
func material_for(name: String, params: Dictionary, reuse: ShaderMaterial = null) -> ShaderMaterial:
	var source := read_source(name)
	if source == "":
		return null
	var cached: Dictionary = _shaders.get(name, {})
	if cached.get("source", "") != source:
		var shader := Shader.new()
		shader.code = to_godot(source)
		cached = { "source": source, "shader": shader }
		_shaders[name] = cached
	var material := reuse if reuse else ShaderMaterial.new()
	material.shader = cached.shader
	for param: Dictionary in parse_params(source):
		var value: Variant = params.get(param.name, param.default)
		material.set_shader_parameter(param.name, _to_uniform(param, value))
	return material


static func _to_uniform(param: Dictionary, value: Variant) -> Variant:
	var v: Array = value if value is Array else [value]
	var f := func(i: int) -> float: return float(v[i] if i < v.size() else (v[0] if v.size() == 1 else param.default[i]))
	match int(param.size):
		1: return f.call(0)
		2: return Vector2(f.call(0), f.call(1))
		3: return Vector3(f.call(0), f.call(1), f.call(2))
		_: return Vector4(f.call(0), f.call(1), f.call(2), f.call(3))


## Shows the open map's shader on the map view (or nothing with preview off).
func update_preview() -> void:
	if api == null:
		return
	var map_id: int = api.get_map_id()
	var choice := choice_for(map_id) if preview and map_id > 0 else { "shader": "" }
	var material := material_for(choice.shader, choice.get("params", {}), _material) if choice.shader != "" else null
	_material = material if material else _material
	api.set_map_screen_material(material)


# --- the panel ------------------------------------------------------------------------------

## The panel for the open map: its shader, the parameters, the default for other maps,
## the preview switch and the example shaders. Rebuilds itself when things change.
func make_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "Screen Shader"
	panel.custom_minimum_size = Vector2(240, 0)
	var state := { "editing": false }
	var body := VBoxContainer.new()
	var rebuild := func() -> void:
		if state.editing or not is_instance_valid(body):
			return
		for child in body.get_children():
			body.remove_child(child)
			child.queue_free()
		_fill_panel(body, state)
	panel.add_child(body)
	var connections := [[settings_changed, rebuild], [library_changed, rebuild]]
	if api:
		connections.append([api.map_shown, func(_id: int) -> void: rebuild.call()])
		connections.append([api.project_opened, func(_p: RefCounted) -> void: rebuild.call()])
	for c: Array in connections:
		c[0].connect(c[1])
	panel.tree_exiting.connect(func() -> void:
		for c: Array in connections:
			if is_instance_valid(c[0].get_object()) and c[0].is_connected(c[1]):
				c[0].disconnect(c[1]))
	panel.set_meta("reload", rebuild)
	_fill_panel(body, state)
	return panel


func _fill_panel(body: VBoxContainer, state: Dictionary) -> void:
	var project: RefCounted = api.get_project() if api else null
	if project == null:
		body.add_child(_label("Open a project to give its maps screen shaders."))
		return
	var shaders := list_shaders()
	var map_id: int = api.get_map_id()

	# The map's shader
	if map_id > 0:
		body.add_child(_label("Shader of Map%04d" % map_id, true))
		var choice := choice_for(map_id)
		var settings := get_settings()
		var own: Dictionary = settings.maps.get(str(map_id), {})
		var default_name: String = settings.default.shader if settings.default is Dictionary else ""
		var pick := OptionButton.new()
		pick.name = "map_shader"
		pick.add_item("Default (%s)" % (default_name if default_name != "" else "none"))
		pick.set_item_metadata(0, "")
		pick.add_item("None")
		pick.set_item_metadata(1, NONE)
		for name in shaders:
			pick.add_item(name)
			pick.set_item_metadata(pick.item_count - 1, name)
		var current: String = own.get("shader", "")
		for i in pick.item_count:
			if pick.get_item_metadata(i) == current:
				pick.select(i)
		pick.item_selected.connect(func(index: int) -> void:
			var name: String = pick.get_item_metadata(index)
			set_map_choice(map_id, {} if name == "" else { "shader": name, "params": {} }))
		body.add_child(pick)

		if choice.shader != "":
			var source := read_source(choice.shader)
			if source == "":
				body.add_child(_label("Shader/%s.glsl is missing." % choice.shader))
			else:
				if choice.source == "default":
					body.add_child(_label("Parameters (of the default, for all maps using it):"))
				var grid := GridContainer.new()
				grid.columns = 2
				grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for param: Dictionary in parse_params(source):
					var name_label := _label(param.name.capitalize())
					name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
					grid.add_child(name_label)
					var control := _param_control(map_id, param, choice.params.get(param.name, param.default), state)
					control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					grid.add_child(control)
				body.add_child(grid)
	else:
		body.add_child(_label("Open a map to choose its shader."))

	var preview_box := CheckBox.new()
	preview_box.name = "preview"
	preview_box.text = "Preview on the map"
	preview_box.button_pressed = preview
	preview_box.toggled.connect(func(on: bool) -> void: preview = on)
	body.add_child(preview_box)

	# Maps without their own
	body.add_child(HSeparator.new())
	body.add_child(_label("Default for maps without their own", true))
	var default_pick := OptionButton.new()
	default_pick.name = "default_shader"
	default_pick.add_item("None")
	default_pick.set_item_metadata(0, "")
	var settings := get_settings()
	for name in shaders:
		default_pick.add_item(name)
		default_pick.set_item_metadata(default_pick.item_count - 1, name)
		if settings.default is Dictionary and settings.default.shader == name:
			default_pick.select(default_pick.item_count - 1)
	default_pick.item_selected.connect(func(index: int) -> void:
		var name: String = default_pick.get_item_metadata(index)
		set_default_choice({} if name == "" else { "shader": name, "params": {} }))
	body.add_child(default_pick)

	# The library
	body.add_child(HSeparator.new())
	body.add_child(_label("Shaders in the game's Shader folder: %s" % (", ".join(shaders) if not shaders.is_empty() else "none yet")))
	var row := HBoxContainer.new()
	var examples := MenuButton.new()
	examples.name = "add_example"
	examples.text = "Add Example"
	examples.flat = false
	for name in list_examples():
		examples.get_popup().add_item(name)
		examples.get_popup().set_item_disabled(examples.get_popup().item_count - 1, name in shaders)
	examples.get_popup().index_pressed.connect(func(index: int) -> void:
		add_example(examples.get_popup().get_item_text(index)))
	row.add_child(examples)
	var reload := Button.new()
	reload.text = "Reload"
	reload.tooltip_text = "Read the shader files again after editing them"
	reload.pressed.connect(reload_library)
	row.add_child(reload)
	body.add_child(row)


func _param_control(map_id: int, param: Dictionary, value: Variant, state: Dictionary) -> Control:
	var values: Array = value if value is Array else [value]
	var commit := func(v: Variant) -> void:
		state.editing = true
		set_param(map_id, param.name, v)
		state.editing = false
	if param.color and int(param.size) >= 3:
		var picker := ColorPickerButton.new()
		picker.name = param.name
		picker.custom_minimum_size = Vector2(64, 0)
		picker.edit_alpha = int(param.size) == 4
		var c := _to_uniform(param, values)
		picker.color = Color(c.x, c.y, c.z, c.w if int(param.size) == 4 else 1.0)
		picker.color_changed.connect(func(color: Color) -> void:
			commit.call([color.r, color.g, color.b] + ([color.a] if int(param.size) == 4 else [])))
		return picker
	var row := HBoxContainer.new()
	row.name = param.name
	var current := values.duplicate()
	for i in int(param.size):
		var spin := SpinBox.new()
		spin.min_value = param.min
		spin.max_value = param.max
		spin.step = 0.01
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.custom_minimum_size = Vector2(72, 0)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value = float(values[i] if i < values.size() else param.default[i])
		spin.value_changed.connect(func(v: float) -> void:
			while current.size() < int(param.size):
				current.append(param.default[current.size()])
			current[i] = v
			commit.call(current[0] if int(param.size) == 1 else current.duplicate()))
		row.add_child(spin)
	return row


static func _label(text: String, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bold:
		label.add_theme_font_size_override("font_size", 15)
	return label
