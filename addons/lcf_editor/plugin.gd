@tool
extends EditorPlugin

const ProjectDock := preload("res://addons/lcf_editor/project_dock.gd")
const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")

var dock: Control
var main_screen: TabContainer
var map_view: Control
var database_view: Control
var api: LcfEditorAPI


func _enter_tree() -> void:
	main_screen = TabContainer.new()
	main_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_screen.visible = false
	map_view = MapView.new()
	map_view.name = "Map"
	map_view.undo_redo = get_undo_redo()
	main_screen.add_child(map_view)
	database_view = DatabaseView.new()
	database_view.name = "Database"
	main_screen.add_child(database_view)
	EditorInterface.get_editor_main_screen().add_child(main_screen)

	# The plugin API (editor_api.gd): registered before the dock opens the last project,
	# so plugins see project_opened for it.
	api = LcfEditorAPI.new(self, main_screen, map_view, database_view)
	Engine.register_singleton(LcfEditorAPI.SINGLETON, api)

	dock = ProjectDock.new()
	dock.name = "LCF Project"
	dock.map_activated.connect(_on_map_activated)
	dock.project_opened.connect(_on_project_opened)
	dock.database_requested.connect(_show_tab.bind(1))
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	# Plugins enabled before this one learn about the API now; later ones find it
	# with LcfEditorAPI.get_api() in their _enter_tree().
	for plugin in _other_plugins():
		if plugin.has_method("_lcf_editor_ready"):
			plugin._lcf_editor_ready(api)


func _exit_tree() -> void:
	if api:
		for plugin in _other_plugins():
			if plugin.has_method("_lcf_editor_closing"):
				plugin._lcf_editor_closing(api)
		api.shutdown()
		Engine.unregister_singleton(LcfEditorAPI.SINGLETON)
		api.free()
		api = null
	LcfCommands.clear()
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	if main_screen:
		main_screen.queue_free()
		main_screen = null


func _other_plugins() -> Array:
	var out := []
	var parent := get_parent()
	if parent:
		for node in parent.get_children():
			if node is EditorPlugin and node != self:
				out.append(node)
	return out


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if main_screen:
		main_screen.visible = visible


func _get_plugin_name() -> String:
	return "LCF Editor"


func _get_unsaved_status(for_scene: String) -> String:
	if for_scene != "":
		return ""
	var parts: PackedStringArray = []
	if database_view and database_view.is_modified():
		parts.append("the database")
	if map_view and map_view.has_unsaved_maps():
		parts.append("%d map(s)" % map_view.project.get_modified_maps().size())
	if parts.is_empty():
		return ""
	return "The RPG Maker project has unsaved changes in %s. Save them before closing?" % " and ".join(parts)


func _save_external_data() -> void:
	if database_view:
		database_view.save_if_safe()
	if map_view:
		map_view.save_if_safe()


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMapLayer", "EditorIcons")


func _show_tab(index: int) -> void:
	EditorInterface.set_main_screen_editor("LCF Editor")
	main_screen.current_tab = index


func _on_project_opened(project: RefCounted) -> void:
	database_view.set_project(project)
	if api:
		api.set_project(project)


## Opens a map in the Map tab (used by the API).
func open_map(map_id: int, map_name: String) -> void:
	_on_map_activated(map_id, map_name)


func _on_map_activated(map_id: int, map_name: String) -> void:
	_show_tab(0)
	map_view.show_map(dock.project, map_id, map_name)
