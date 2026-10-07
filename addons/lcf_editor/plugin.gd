@tool
extends EditorPlugin

const ProjectDock := preload("res://addons/lcf_editor/project_dock.gd")
const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")
const TestPlay := preload("res://addons/lcf_editor/test_play.gd")
const TestPlayPanel := preload("res://addons/lcf_editor/test_play_panel.gd")

var dock: Control
var main_screen: TabContainer
var map_view: Control
var database_view: Control
var api: LcfEditorAPI
var test_play: TestPlay
var test_play_panel: Control
var unsaved_dialog: ConfirmationDialog
var _pending_start := {}


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

	# Test Play: EasyRPG Player in its own window, its log in a bottom panel. Created
	# before the dock, which may open the last project right away.
	test_play = TestPlay.new()
	test_play.load_settings()
	add_child(test_play)
	test_play_panel = TestPlayPanel.new()
	test_play_panel.attach(test_play)
	test_play_panel.play_requested.connect(start_test_play)
	add_control_to_bottom_panel(test_play_panel, "Test Play")
	map_view.play_from_here.connect(func(id: int, x: int, y: int) -> void:
		start_test_play({ "map_id": id, "x": x, "y": y }))
	unsaved_dialog = ConfirmationDialog.new()
	unsaved_dialog.title = "Test Play"
	unsaved_dialog.dialog_autowrap = true
	unsaved_dialog.min_size = Vector2i(460, 0)
	unsaved_dialog.get_ok_button().text = "Play saved version"
	unsaved_dialog.confirmed.connect(func() -> void: _launch(_pending_start))
	test_play_panel.add_child(unsaved_dialog)

	dock = ProjectDock.new()
	dock.name = "LCF Project"
	dock.map_activated.connect(_on_map_activated)
	dock.project_opened.connect(_on_project_opened)
	dock.database_requested.connect(_show_tab.bind(1))
	dock.test_play_requested.connect(start_test_play)
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
	if test_play_panel:
		remove_control_from_bottom_panel(test_play_panel)
		test_play_panel.queue_free()
		test_play_panel = null
	if test_play:
		test_play.queue_free()  # a running game keeps running
		test_play = null
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
	if test_play_panel:
		test_play_panel.project = project
	if api:
		api.set_project(project)


## Opens a map in the Map tab (used by the API).
func open_map(map_id: int, map_name: String) -> void:
	_on_map_activated(map_id, map_name)


func _on_map_activated(map_id: int, map_name: String) -> void:
	_show_tab(0)
	map_view.show_map(dock.project, map_id, map_name)


## Saves the project and runs it in EasyRPG Player. `start` may hold { map_id, x, y }
## to start a new game at that cell. Changes that cannot be saved without asking
## (files that would not save byte for byte) are left out after a confirmation.
func start_test_play(start := {}) -> void:
	var project: RefCounted = dock.project
	if project == null or not project.is_loaded():
		test_play_panel.show_message("Open a project first.", true)
		make_bottom_panel_item_visible(test_play_panel)
		return
	database_view.save_if_safe()
	map_view.save_if_safe()
	if database_view.is_modified() or map_view.has_unsaved_maps():
		_pending_start = start
		unsaved_dialog.dialog_text = "Some changes were not saved, because saving would change the files beyond your edits (see the warnings in the Map and Database tabs). Save them there first, or play the last saved version."
		unsaved_dialog.popup_centered()
		return
	_launch(start)


func _launch(start: Dictionary) -> void:
	make_bottom_panel_item_visible(test_play_panel)
	var problem: String = test_play.check_player()
	if problem != "":
		test_play_panel.show_message(problem, true)
		test_play_panel.open_settings()
		return
	if test_play.start(dock.project.get_project_dir(), start) != OK:
		test_play_panel.show_message("Could not start %s." % test_play.get_player(), true)
