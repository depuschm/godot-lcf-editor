@tool
extends EditorPlugin

const ProjectDock := preload("res://addons/lcf_editor/project_dock.gd")
const MapView := preload("res://addons/lcf_editor/map_view.gd")

var dock: Control
var map_view: Control


func _enter_tree() -> void:
	map_view = MapView.new()
	map_view.visible = false
	EditorInterface.get_editor_main_screen().add_child(map_view)

	dock = ProjectDock.new()
	dock.name = "LCF Project"
	dock.map_activated.connect(_on_map_activated)
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	if map_view:
		map_view.queue_free()
		map_view = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if map_view:
		map_view.visible = visible


func _get_plugin_name() -> String:
	return "RPG Map"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMapLayer", "EditorIcons")


func _on_map_activated(map_id: int, map_name: String) -> void:
	EditorInterface.set_main_screen_editor("RPG Map")
	map_view.show_map(dock.project, map_id, map_name)
