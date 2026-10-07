@tool
class_name LcfEditorAPI
extends Object
## The LCF Editor's interface for other Godot editor plugins.
##
## While the LCF Editor plugin is enabled, one instance is registered as the engine
## singleton "LcfEditor"; get it with LcfEditorAPI.get_api(). Plugins can be enabled
## before or after the LCF Editor, so use both entry points:
##
##     @tool
##     extends EditorPlugin
##
##     func _enter_tree() -> void:
##         var api := LcfEditorAPI.get_api()
##         if api:
##             _lcf_editor_ready(api)
##
##     # Also called by the LCF Editor when it starts after this plugin.
##     func _lcf_editor_ready(api: LcfEditorAPI) -> void:
##         api.add_map_tool(my_tool)
##
##     # Called before the LCF Editor goes away; drop references to it.
##     func _lcf_editor_closing(api: LcfEditorAPI) -> void:
##         api.remove_map_tool(my_tool)
##
## Event commands are added with LcfCommands.register() (see command_registry.gd).

## A project was opened (LcfProject).
signal project_opened(project: RefCounted)
## A map was opened in the Map tab.
signal map_shown(map_id: int)
## Tiles or events of a map changed (also on undo/redo).
signal map_changed(map_id: int)
## A map was saved to its file.
signal map_saved(map_id: int)
## The database got unsaved changes, or was saved or reverted.
signal database_modified_changed(modified: bool)
## The selected event on the Events layer changed (event_id -1: none).
signal event_selected(map_id: int, event_id: int)

const SINGLETON := "LcfEditor"
## Increases when the API changes in a way plugins may need to check.
const VERSION := 1
## Folder inside the RPG Maker project where plugin data is stored.
const DATA_FOLDER := "lcf-plugins"

var _plugin: Object        # the LCF Editor EditorPlugin (may be null in tests)
var _main_screen: TabContainer
var _map_view: Control
var _database_view: Control
var _project: RefCounted
var _tabs: Array[Control] = []
var _tools: Array = []
var _event_panels: Array = []  # [{ title, factory }], shared with the event editor


## The active API, or null when the LCF Editor plugin is not enabled.
static func get_api() -> LcfEditorAPI:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON) as LcfEditorAPI
	return null


func _init(plugin: Object = null, main_screen: TabContainer = null, map_view: Control = null, database_view: Control = null) -> void:
	_plugin = plugin
	_main_screen = main_screen
	_map_view = map_view
	_database_view = database_view
	if _map_view:
		_map_view.map_shown.connect(map_shown.emit)
		_map_view.map_changed.connect(map_changed.emit)
		_map_view.map_saved.connect(map_saved.emit)
		_map_view.event_selected.connect(event_selected.emit)
		if _map_view.event_editor:
			_map_view.event_editor.panels = _event_panels
	if _database_view:
		_database_view.modified_changed.connect(database_modified_changed.emit)


## Called by the LCF Editor when a project is opened.
func set_project(project: RefCounted) -> void:
	_project = project
	project_opened.emit(project)


## Removes everything plugins added (when the LCF Editor shuts down).
func shutdown() -> void:
	for map_tool in _tools.duplicate():
		remove_map_tool(map_tool)
	for tab in _tabs.duplicate():
		remove_tab(tab)
	for panel: Dictionary in _event_panels.duplicate():
		remove_event_panel(panel.title)
	set_map_material(null)


# --- project and maps ------------------------------------------------------------

## The open project (an LcfProject), or null.
func get_project() -> RefCounted:
	return _project if _project and _project.is_loaded() else null


## The ID of the map in the Map tab, or 0.
func get_map_id() -> int:
	return _map_view.map_id if _map_view and not _map_view.map.is_empty() else 0


## The map in the Map tab as LcfProject.get_map() returns it (with the editor's
## current tiles and events), or an empty Dictionary.
func get_map() -> Dictionary:
	return _map_view.map if _map_view else {}


## Opens a map in the Map tab.
func open_map(map_id: int) -> void:
	var project := get_project()
	if project == null:
		return
	var map_name := "Map%04d" % map_id
	for entry: Dictionary in project.get_map_tree():
		if entry.id == map_id:
			map_name = entry.name
	if _plugin and _plugin.has_method("open_map"):
		_plugin.open_map(map_id, map_name)
	elif _map_view:
		_map_view.show_map(project, map_id, map_name)


## The Map tab's zoom (1.0 = one map pixel per screen pixel).
func get_map_zoom() -> float:
	return _map_view.canvas.scale.x if _map_view else 1.0


## Redraws the map, e.g. after a tool's data changed.
func redraw_map() -> void:
	if _map_view:
		_map_view.overlay.queue_redraw()


## The selected event on the Events layer (its ID), or -1.
func get_selected_event() -> int:
	return _map_view.selected_event if _map_view else -1


## Saves the project and runs it in EasyRPG Player (Test Play); with a map ID, a new
## game starts on that map at (x, y).
func start_test_play(map_id := 0, x := 0, y := 0) -> void:
	if _plugin and _plugin.has_method("start_test_play"):
		_plugin.start_test_play({ "map_id": map_id, "x": x, "y": y } if map_id > 0 else {})


## Opens the event editor on an event of the open map.
func edit_event(event_id: int) -> void:
	if _map_view:
		_map_view._edit_event(event_id)


# --- adding to the editor ----------------------------------------------------------

## Adds a map tool (an LcfMapTool) to the Map tab.
func add_map_tool(map_tool: LcfMapTool) -> void:
	if map_tool in _tools:
		return
	map_tool.api = self
	_tools.append(map_tool)
	if _map_view:
		_map_view.add_tool(map_tool)


func remove_map_tool(map_tool: LcfMapTool) -> void:
	if not map_tool in _tools:
		return
	_tools.erase(map_tool)
	if _map_view:
		_map_view.remove_tool(map_tool)
	map_tool.api = null


## Adds a panel to the event editor, as a tab next to the command list. `factory`
## is called whenever the editor shows an event page, with
## { project, map_id, event_id, page, editor }, and returns a new Control (or null to
## show nothing for that event). The editor frees the control when it moves on. Use a
## method callable. If the panel changes the event itself, call editor.reload().
func add_event_panel(title: String, factory: Callable) -> void:
	for panel: Dictionary in _event_panels:
		if panel.title == title:
			panel.factory = factory
			_refresh_event_panels()
			return
	_event_panels.append({ "title": title, "factory": factory })
	_refresh_event_panels()


func remove_event_panel(title: String) -> void:
	for panel: Dictionary in _event_panels.duplicate():
		if panel.title == title:
			_event_panels.erase(panel)
	_refresh_event_panels()


func _refresh_event_panels() -> void:
	if _map_view and _map_view.event_editor.visible:
		_map_view.event_editor.refresh_panels()


## Sets a material on the map's tile layers, e.g. to preview a shader; null removes it.
## The map view keeps it for every map until it is changed.
func set_map_material(material: Material) -> void:
	if _map_view:
		_map_view.set_map_material(material)


## Adds a tab to the LCF Editor screen (next to Map and Database). The control is
## not freed by the editor; free it yourself after remove_tab().
func add_tab(control: Control, title: String) -> void:
	if control in _tabs or _main_screen == null:
		return
	control.name = title.validate_node_name()
	_tabs.append(control)
	_main_screen.add_child(control)
	_main_screen.set_tab_title(_main_screen.get_tab_idx_from_control(control), title)


func remove_tab(control: Control) -> void:
	if not control in _tabs:
		return
	_tabs.erase(control)
	if control.get_parent() == _main_screen:
		_main_screen.remove_child(control)


## Shows a tab (one added with add_tab(), or the Map and Database tabs).
func show_tab(control: Control) -> void:
	if _main_screen and control.get_parent() == _main_screen:
		if _plugin:
			EditorInterface.set_main_screen_editor("LCF Editor")
		_main_screen.current_tab = _main_screen.get_tab_idx_from_control(control)


# --- plugin data --------------------------------------------------------------------
# Plugins keep their own data next to the project, in lcf-plugins/<plugin_id>.json,
# so it travels with the game (and can be read by the runtime half of a plugin).
# RPG Maker and EasyRPG Player ignore the folder.

## The stored data of a plugin, or `default` if there is none (or no project).
func get_plugin_data(plugin_id: String, default: Variant = null) -> Variant:
	var path := get_plugin_data_path(plugin_id)
	if path == "" or not FileAccess.file_exists(path):
		return default
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else default


## Stores a plugin's data (anything JSON can hold) right away. The file is written
## to a temporary name first and then renamed, so it is never left half-written.
func set_plugin_data(plugin_id: String, data: Variant) -> Error:
	var path := get_plugin_data_path(plugin_id)
	if path == "":
		return ERR_UNCONFIGURED if get_project() == null else ERR_INVALID_PARAMETER
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path)


## Where a plugin's data is stored, or "" without a project or with an invalid ID
## (IDs use lowercase letters, digits, "_" and "-").
func get_plugin_data_path(plugin_id: String) -> String:
	var project := get_project()
	if project == null or plugin_id == "" or not _valid_id(plugin_id):
		return ""
	return String(project.get_project_dir()).path_join(DATA_FOLDER).path_join(plugin_id + ".json")


func _valid_id(plugin_id: String) -> bool:
	for c in plugin_id:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "_" and c != "-":
			return false
	return true
