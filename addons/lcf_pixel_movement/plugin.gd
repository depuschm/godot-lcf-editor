@tool
extends EditorPlugin
## Pixel movement, editor half (showcase for the LCF Editor's plugin API):
##   - a "Pixel Movement" tab: turn it on for the game, set the hero's hitbox,
##   - a "Hitbox" panel in the event editor: per page, stored as @pixel_hitbox,
##   - a "Hitboxes" map tool that shows them,
##   - comment commands: Pixel Movement On/Off, Move by Pixels, Pixel Hitbox.
## The runtime half is a patch for EasyRPG Player: runtime/easyrpg-player.

const Logic := preload("res://addons/lcf_pixel_movement/pixel_movement.gd")
const HitboxTool := preload("res://addons/lcf_pixel_movement/hitbox_tool.gd")
const COMMANDS := ["pixel_movement", "pixel_move", "pixel_hitbox"]

var api: LcfEditorAPI
var logic: RefCounted
var hitbox_tool: LcfMapTool
var tab: Control


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
	hitbox_tool = HitboxTool.new(logic)
	api.add_map_tool(hitbox_tool)
	api.add_event_panel("Hitbox", logic.make_event_panel)
	tab = logic.make_settings_tab()
	api.add_tab(tab, "Pixel Movement")
	api.project_opened.connect(_on_project_opened)
	api.map_changed.connect(_on_map_changed)
	logic.settings_changed.connect(hitbox_tool.redraw)
	for schema in schemas():
		LcfCommands.register(schema)


func _lcf_editor_closing(p_api: LcfEditorAPI) -> void:
	if api != p_api:
		return
	for name in COMMANDS:
		LcfCommands.unregister_comment(name)
	api.project_opened.disconnect(_on_project_opened)
	api.map_changed.disconnect(_on_map_changed)
	api.remove_event_panel("Hitbox")
	api.remove_map_tool(hitbox_tool)
	api.remove_tab(tab)
	tab.queue_free()
	api = null


func _on_project_opened(_project: RefCounted) -> void:
	tab.get_meta("reload").call()


func _on_map_changed(_map_id: int) -> void:
	hitbox_tool.refresh()


## The comment commands of pixel movement (also used by the tests).
static func schemas() -> Array:
	var runtime: String = Logic.RUNTIME
	return [
		{
			"comment": "pixel_movement", "name": "Pixel Movement On/Off", "group": "Map", "runtime": runtime,
			"params": [{ "index": 0, "label": "Pixel movement", "type": "enum", "choices": ["Off", "On"], "default": 1 }],
		},
		{
			"comment": "pixel_move", "name": "Move by Pixels", "group": "Map", "runtime": runtime,
			"params": [
				{ "index": 0, "label": "Character", "type": "event", "default": 10001 },
				{ "index": 1, "label": "Right (pixels)", "type": "int", "min": -320, "max": 320 },
				{ "index": 2, "label": "Down (pixels)", "type": "int", "min": -240, "max": 240 },
			],
		},
		{
			"comment": "pixel_hitbox", "name": "Pixel Hitbox", "group": "Map", "runtime": runtime,
			"params": [
				{ "index": 0, "label": "X", "type": "int", "min": -16, "max": 16 },
				{ "index": 1, "label": "Y", "type": "int", "min": -16, "max": 16 },
				{ "index": 2, "label": "Width", "type": "int", "min": 1, "max": 32, "default": 16 },
				{ "index": 3, "label": "Height", "type": "int", "min": 1, "max": 32, "default": 16 },
			],
		},
	]
