extends SceneTree
## Tests the editor plugin API (LcfEditorAPI, LcfMapTool) with the real map and
## database views and the example plugin's notes tool, on a copy of the demo project.
## Run: godot --headless --path . --script res://tests/test_plugin_api.gd

const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")
const Notes := preload("res://addons/lcf_map_notes/notes.gd")
const NotesTool := preload("res://addons/lcf_map_notes/notes_tool.gd")

var _failures := 0
var _log: Array = []
var _contexts: Array = []


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var work := ProjectSettings.globalize_path("user://plugin_api_test")
	_clear(work)
	DirAccess.make_dir_recursive_absolute(work.path_join("ChipSet"))
	var source := ProjectSettings.globalize_path("res://demo")
	for file in DirAccess.get_files_at(source):
		DirAccess.copy_absolute(source.path_join(file), work.path_join(file))
	for file in DirAccess.get_files_at(source.path_join("ChipSet")):
		DirAccess.copy_absolute(source.path_join("ChipSet").path_join(file), work.path_join("ChipSet").path_join(file))
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	project.load(work)
	print("Plugin API on ", work)

	var main := TabContainer.new()
	main.size = Vector2(1200, 800)
	var map_view: Control = MapView.new()
	map_view.name = "Map"
	main.add_child(map_view)
	var db_view: Control = DatabaseView.new()
	db_view.name = "Database"
	main.add_child(db_view)
	root.add_child(main)
	await process_frame

	var api := LcfEditorAPI.new(null, main, map_view, db_view)
	_check(LcfEditorAPI.get_api() == null, "no API singleton while the LCF Editor is not running")
	Engine.register_singleton(LcfEditorAPI.SINGLETON, api)
	_check(LcfEditorAPI.get_api() == api, "get_api() finds the registered API")
	for sig in ["project_opened", "map_shown", "map_changed", "map_saved", "database_modified_changed"]:
		api.connect(sig, func(a: Variant = null) -> void: _log.append([sig, a]))
	api.event_selected.connect(func(m: int, e: int) -> void: _log.append(["event_selected", Vector2i(m, e)]))

	# Project and maps.
	_check(api.get_project() == null and api.get_map_id() == 0, "nothing open yet")
	db_view.set_project(project)
	api.set_project(project)
	_check(api.get_project() == project and _logged("project_opened"), "project_opened reaches plugins")
	api.open_map(4)
	_check(api.get_map_id() == 4 and api.get_map().width == 15, "open_map() shows the house")
	_check(_logged("map_shown", 4), "map_shown(4) reaches plugins")
	map_view.apply_tiles(4, 0, PackedInt32Array([0]), PackedInt32Array([5001]))
	_check(_logged("map_changed", 4), "map_changed reaches plugins when tiles change")
	map_view._save()
	_check(_logged("map_saved", 4), "map_saved reaches plugins")

	# Tabs.
	var tab := Label.new()
	api.add_tab(tab, "Plugin Tab")
	var index := main.get_tab_idx_from_control(tab)
	_check(index == 2 and main.get_tab_title(index) == "Plugin Tab", "add_tab() adds a tab after Map and Database")
	api.show_tab(tab)
	_check(main.current_tab == 2, "show_tab() switches to it")
	api.remove_tab(tab)
	_check(main.get_tab_count() == 2 and tab.get_parent() == null, "remove_tab() takes it out again")
	tab.free()

	# Plugin data.
	_check(api.set_plugin_data("Bad Id!", {}) == ERR_INVALID_PARAMETER, "invalid plugin IDs are rejected")
	_check(api.get_plugin_data("nothing_here", 42) == 42, "missing data gives the default")
	_check(api.set_plugin_data("test_plugin", { "a": [1, 2], "b": "x" }) == OK, "plugin data is written")
	var path := api.get_plugin_data_path("test_plugin")
	_check(path.begins_with(work) and path.ends_with("lcf-plugins/test_plugin.json") and FileAccess.file_exists(path), "it lives in the project: lcf-plugins/test_plugin.json")
	_check(api.get_plugin_data("test_plugin") == { "a": [1.0, 2.0], "b": "x" }, "and reads back")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left")

	# A map tool: the example plugin's notes.
	var notes: RefCounted = Notes.new()
	notes.api = api
	var map_tool: LcfMapTool = NotesTool.new(notes)
	var requests := []
	map_tool.edit_requested.connect(func(m: int, c: Vector2i, t: String) -> void: requests.append(["edit", m, c, t]))
	map_tool.change_requested.connect(func(m: int, c: Vector2i, t: String) -> void: requests.append(["change", m, c, t]))
	api.add_map_tool(map_tool)
	var button: Button = map_view.plugin_buttons.get(map_tool)
	_check(button != null and button.text == "Notes" and button.get_index() == map_view.layer_buttons[2].get_index() + 1, "the tool's button sits after Events")
	button.button_pressed = true
	button.pressed.emit()
	_check(map_view.layer == MapView.Layer.PLUGIN and map_view.active_tool == map_tool, "pressing it selects the tool")
	_check(not map_view.palette_scroll.visible and map_view.status_label.text == map_tool.help, "the palette hides and the status line shows the tool's help")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map_view.canvas.position + (Vector2(3, 2) + Vector2(0.5, 0.5)) * 16 * map_view.canvas.scale.x
	map_view._on_gui_input(click)
	_check(requests == [["edit", 4, Vector2i(3, 2), ""]], "a click on the map reaches the tool with its cell: %s" % [requests])
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = click.position
	var zoom_before: int = map_view.zoom_index
	map_view._on_gui_input(wheel)
	_check(requests.size() == 1 and map_view.zoom_index != zoom_before, "the wheel still zooms the map")

	notes.set_note(4, Vector2i(3, 2), "Bookshelf: add a secret switch")
	notes.set_note(1, Vector2i(11, 16), "Sign text needs a rewrite")
	await process_frame  # draws the overlay with the tool's notes
	var stored: Variant = api.get_plugin_data("map_notes")
	_check(stored is Dictionary and stored.maps.has("4") and stored.maps["4"][0].text == "Bookshelf: add a secret switch", "notes are stored as plugin data")
	var reloaded: RefCounted = Notes.new()
	reloaded.api = api
	reloaded.load_from_project()
	_check(reloaded.all_notes().size() == 2 and reloaded.get_note(1, Vector2i(11, 16)) == "Sign text needs a rewrite", "notes load back from the project")
	var right := click.duplicate()
	right.button_index = MOUSE_BUTTON_RIGHT
	map_view._on_gui_input(right)
	_check(requests.back() == ["change", 4, Vector2i(3, 2), ""], "right-click asks to delete the note")

	# Notes on events, stored with the cell notes.
	notes.set_event_note(4, 1, "Chest: should it respawn?")
	var with_events: Variant = api.get_plugin_data("map_notes")
	_check(with_events.events["4"]["1"] == "Chest: should it respawn?", "event notes are stored as plugin data")
	reloaded.load_from_project()
	_check(reloaded.get_event_note(4, 1) == "Chest: should it respawn?" and reloaded.all_notes().size() == 3, "event notes load back and are listed")

	# Event selection and event editor panels.
	map_view.selected_event = 1
	_check(_logged("event_selected", Vector2i(4, 1)), "event_selected reaches plugins")
	api.add_event_panel("Test panel", _make_panel)
	map_view._edit_event(1)
	var editor: AcceptDialog = map_view.event_editor
	var titles := []
	for i in editor.side.get_tab_count():
		titles.append(editor.side.get_tab_title(i))
	_check(titles == ["Commands", "Test panel"], "the event editor shows the plugin panel next to Commands: %s" % [titles])
	_check(_contexts.back().map_id == 4 and _contexts.back().event_id == 1 and _contexts.back().page == 0 and _contexts.back().editor == editor, "the panel gets the event and page")
	editor.show_panel("Test panel")
	editor.tabs.current_tab = 1
	_check(_contexts.back().page == 1 and editor.side.get_tab_title(editor.side.current_tab) == "Test panel", "changing the page rebuilds the panel and keeps it shown")
	api.remove_event_panel("Test panel")
	_check(editor.side.get_tab_count() == 1, "remove_event_panel() takes it out")
	api.add_event_panel("Test panel", _make_panel)
	editor.hide()

	# A material for the map, e.g. a shader preview.
	var material := CanvasItemMaterial.new()
	api.set_map_material(material)
	_check(map_view.lower_layer.material == material and map_view.upper_layer.material == material, "set_map_material() applies to both tile layers")

	map_view.layer_buttons[0].button_pressed = true
	map_view._set_layer(MapView.Layer.LOWER)
	_check(map_view.active_tool == null and map_view.palette_scroll.visible, "choosing a layer leaves the tool")
	map_view._activate_tool(map_tool)
	api.shutdown()
	_check(map_view.plugin_tools.is_empty() and map_view.layer == MapView.Layer.EVENTS and map_tool.api == null, "shutdown removes plugin tools (and leaves the active one)")
	_check(map_view.event_editor.panels.is_empty() and map_view.lower_layer.material == null, "shutdown removes event panels and the map material")

	Engine.unregister_singleton(LcfEditorAPI.SINGLETON)
	api.free()
	main.queue_free()
	await process_frame
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _make_panel(context: Dictionary) -> Control:
	_contexts.append(context)
	var label := Label.new()
	label.text = "Event %d, page %d" % [context.event_id, context.page + 1]
	return label


func _logged(sig: String, arg: Variant = null) -> bool:
	for entry: Array in _log:
		if entry[0] == sig and (arg == null or entry[1] == arg):
			return true
	return false


func _clear(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_clear(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
