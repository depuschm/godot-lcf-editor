@tool
extends EditorPlugin
## Screen shaders, editor half (showcase for the LCF Editor's plugin API):
##   - a "Screen Shader" dock: the open map's shader and its parameters, the default
##     for other maps, example shaders,
##   - a live preview of the shader on the map (LcfEditorAPI.set_map_screen_material),
##   - comment commands: Set Screen Shader, Set Shader Parameter.
## The runtime half is a patch for EasyRPG Player: runtime/easyrpg-player.

const Logic := preload("res://addons/lcf_shaders/screen_shaders.gd")
const COMMANDS := ["shader", "shader_param"]

var api: LcfEditorAPI
var logic: RefCounted
var panel: Control


func _enter_tree() -> void:
	var found := LcfEditorAPI.get_api()
	if found:
		_lcf_editor_ready(found)


func _exit_tree() -> void:
	if api:
		_lcf_editor_closing(api)


func _lcf_editor_ready(p_api: LcfEditorAPI) -> void:
	if api:
		return
	api = p_api
	logic = Logic.new()
	logic.api = api
	logic.undo_redo = get_undo_redo()
	panel = logic.make_panel()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, panel)
	api.project_opened.connect(_on_project_opened)
	api.map_shown.connect(_on_map_shown)
	logic.library_changed.connect(_register_commands)
	_register_commands()
	logic.update_preview()


func _lcf_editor_closing(p_api: LcfEditorAPI) -> void:
	if api != p_api:
		return
	for name in COMMANDS:
		LcfCommands.unregister_comment(name)
	api.project_opened.disconnect(_on_project_opened)
	api.map_shown.disconnect(_on_map_shown)
	api.set_map_screen_material(null)
	remove_control_from_docks(panel)
	panel.queue_free()
	api = null


func _on_project_opened(_project: RefCounted) -> void:
	logic.reload_library()


func _on_map_shown(_map_id: int) -> void:
	logic.update_preview()


func _register_commands() -> void:
	for schema in schemas(logic.list_shaders()):
		LcfCommands.register(schema)


## The comment commands of screen shaders, with the game's shaders to choose from
## (also used by the tests).
static func schemas(shaders := PackedStringArray()) -> Array:
	var runtime: String = Logic.RUNTIME
	var choices := { "": "The map's shader", "none": "None" }
	for name in shaders:
		choices[name] = name
	return [
		{
			"comment": "shader", "name": "Set Screen Shader", "group": "Screen", "runtime": runtime,
			"params": [{ "index": 0, "label": "Shader", "type": "string", "choices": choices, "default": "" }],
		},
		{
			"comment": "shader_param", "name": "Set Shader Parameter", "group": "Screen", "runtime": runtime,
			"params": [
				{ "index": 0, "label": "Parameter", "type": "string" },
				{ "index": 1, "label": "Value", "type": "int", "min": -99999, "max": 99999, "default": 100 },
				{ "index": 2, "label": "Divided by", "type": "int", "min": 1, "max": 10000, "default": 100 },
			],
		},
	]
