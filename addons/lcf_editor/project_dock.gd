@tool
extends VBoxContainer
## Dock that opens an RPG Maker 2000/2003 project and shows its map tree.

## Emitted when the user selects a map (not the project root or an area).
signal map_activated(map_id: int, map_name: String)

const SETTINGS_SECTION := "lcf_editor"
const SETTINGS_KEY := "last_project"

var project: RefCounted  # LcfProject, created via ClassDB so this script loads without the extension
var dialog: EditorFileDialog
var summary: Label
var tree: Tree
var details: Label


func _ready() -> void:
	custom_minimum_size = Vector2(260, 0)

	var open_button := Button.new()
	open_button.text = "Open RPG Maker project…"
	open_button.pressed.connect(_on_open_pressed)
	add_child(open_button)

	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.item_selected.connect(_on_map_selected)
	add_child(tree)

	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(details)

	dialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.title = "Select an RPG Maker 2000/2003 project folder"
	dialog.dir_selected.connect(open_project)
	add_child(dialog)

	if not ClassDB.class_exists("LcfProject"):
		open_button.disabled = true
		summary.text = "The LCF extension is not built yet.\nSee README.md → Building."
		return

	project = ClassDB.instantiate("LcfProject")
	var last: String = _settings().get_project_metadata(SETTINGS_SECTION, SETTINGS_KEY, "")
	if last != "" and DirAccess.dir_exists_absolute(last):
		open_project(last)
	else:
		summary.text = "No project loaded."


func _settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()


func _on_open_pressed() -> void:
	dialog.popup_file_dialog()


func open_project(path: String) -> void:
	tree.clear()
	details.text = ""
	if project.load(path) != OK:
		summary.text = "Could not open project:\n" + project.get_last_error()
		return
	_settings().set_project_metadata(SETTINGS_SECTION, SETTINGS_KEY, path)

	var title: String = project.get_game_title()
	if title == "":
		title = path.get_file()
	var entries: Array = project.get_map_tree()
	var map_count := entries.filter(func(e: Dictionary) -> bool: return e.type == "map").size()
	var db: Dictionary = project.get_database_summary()
	summary.text = "%s\nRPG Maker %s · %s\nMaps: %d   Actors: %d\nCommon events: %d" % [
		title, project.get_engine(), project.get_encoding(),
		map_count, db.actors, db.common_events,
	]
	_build_tree(entries)


func _build_tree(entries: Array) -> void:
	var root := tree.create_item()
	var items := {}  # map id -> TreeItem
	for entry: Dictionary in entries:
		var parent: TreeItem = items.get(entry.parent_id, root)
		var item := tree.create_item(parent)
		var label: String = entry.name
		if entry.type == "area":
			label += "  (area)"
		item.set_text(0, label)
		item.set_metadata(0, entry)
		items[entry.id] = item


func _on_map_selected() -> void:
	var entry: Dictionary = tree.get_selected().get_metadata(0)
	if entry.type != "map":
		details.text = "%s: %s" % [entry.type.capitalize(), entry.name]
		return
	var info: Dictionary = project.get_map_info(entry.id)
	if info.is_empty():
		details.text = project.get_last_error()
		return
	details.text = "Map%04d · %d×%d tiles · chipset %d · %d events" % [
		entry.id, info.width, info.height, info.chipset_id, info.event_count,
	]
	map_activated.emit(entry.id, entry.name)
