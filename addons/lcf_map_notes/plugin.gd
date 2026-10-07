@tool
extends EditorPlugin
## Example plugin for the LCF Editor. It shows every part of the plugin API:
##   - a map tool (notes_tool.gd, an LcfMapTool) that draws on the map,
##   - a tab in the LCF Editor screen listing all notes,
##   - a panel in the event editor for a note on the event,
##   - plugin data stored with the project (lcf-plugins/map_notes.json),
##   - undo/redo through Godot's editor undo,
##   - a dialog for an event command (Shake Screen) through LcfCommands.
## Copy this folder to start your own plugin.

const Notes := preload("res://addons/lcf_map_notes/notes.gd")
const NotesTool := preload("res://addons/lcf_map_notes/notes_tool.gd")
const SHAKE_SCREEN := 11050

var api: LcfEditorAPI
var notes: RefCounted
var notes_tool: LcfMapTool
var tab: VBoxContainer
var tab_list: ItemList
var dialog: ConfirmationDialog
var dialog_text: LineEdit
var _editing := {}  # { map_id, cell } of the note in the dialog


func _enter_tree() -> void:
	var found := LcfEditorAPI.get_api()
	if found:
		_lcf_editor_ready(found)


func _exit_tree() -> void:
	if api:
		_lcf_editor_closing(api)


## Called when the LCF Editor is available (see LcfEditorAPI).
func _lcf_editor_ready(p_api: LcfEditorAPI) -> void:
	if api:
		return
	api = p_api
	notes = Notes.new()
	notes.api = api
	notes.changed.connect(_refresh_tab)
	notes.changed.connect(api.redraw_map)

	notes_tool = NotesTool.new(notes)
	notes_tool.edit_requested.connect(_edit_note)
	notes_tool.change_requested.connect(_change_note)
	api.add_map_tool(notes_tool)

	tab = VBoxContainer.new()
	var info := Label.new()
	info.text = "Notes on all maps (double-click to open the map). Add notes with the Notes tool in the Map tab."
	tab.add_child(info)
	tab_list = ItemList.new()
	tab_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_list.item_activated.connect(_on_note_activated)
	tab.add_child(tab_list)
	api.add_tab(tab, "Notes")

	dialog = ConfirmationDialog.new()
	dialog_text = LineEdit.new()
	dialog_text.custom_minimum_size = Vector2(360, 0)
	dialog_text.text_submitted.connect(func(_t: String) -> void:
		dialog.hide()
		_on_dialog_confirmed())
	dialog.add_child(dialog_text)
	dialog.confirmed.connect(_on_dialog_confirmed)
	tab.add_child(dialog)

	LcfCommands.register({
		"code": SHAKE_SCREEN, "name": "Shake Screen", "group": "Screen", "length": 4,
		"params": [
			{ "index": 0, "label": "Strength", "type": "int", "min": 1, "max": 9, "default": 3 },
			{ "index": 1, "label": "Speed", "type": "int", "min": 1, "max": 9, "default": 3 },
			{ "index": 2, "label": "Duration (tenths of a second)", "type": "int", "min": 0, "max": 6000, "default": 10 },
			{ "index": 3, "label": "Wait until done", "type": "bool" },
		],
		"summary": _shake_summary,
	})

	api.add_event_panel("Notes", _make_event_panel)

	api.project_opened.connect(_on_project_opened)
	if api.get_project():
		_on_project_opened(api.get_project())


## Called before the LCF Editor goes away (or when this plugin is disabled).
func _lcf_editor_closing(p_api: LcfEditorAPI) -> void:
	if api != p_api:
		return
	LcfCommands.unregister(SHAKE_SCREEN)
	api.remove_event_panel("Notes")
	api.project_opened.disconnect(_on_project_opened)
	api.remove_map_tool(notes_tool)
	api.remove_tab(tab)
	tab.queue_free()
	notes.changed.disconnect(api.redraw_map)
	api = null


func _on_project_opened(_project: RefCounted) -> void:
	notes.load_from_project()


func _shake_summary(command: Dictionary, _names: Variant) -> String:
	var p: PackedInt32Array = command.parameters
	return "Strength %d, speed %d, %.1f s%s" % [p[0], p[1], p[2] / 10.0, ", wait" if p.size() > 3 and p[3] != 0 else ""]


# --- editing notes ---------------------------------------------------------------------

func _edit_note(map_id: int, cell: Vector2i, text: String) -> void:
	_editing = { "map_id": map_id, "cell": cell }
	dialog.title = "Note at (%d, %d)" % [cell.x, cell.y]
	dialog_text.text = text
	dialog.popup_centered()
	dialog_text.grab_focus()
	dialog_text.select_all()


func _on_dialog_confirmed() -> void:
	_change_note(_editing.map_id, _editing.cell, dialog_text.text.strip_edges())


## Changes a note with undo/redo.
func _change_note(map_id: int, cell: Vector2i, text: String) -> void:
	var before: String = notes.get_note(map_id, cell)
	if before == text:
		return
	var undo := get_undo_redo()
	undo.create_action("Delete note" if text == "" else "Edit note")
	undo.add_do_method(notes, "set_note", map_id, cell, text)
	undo.add_undo_method(notes, "set_note", map_id, cell, before)
	undo.commit_action()


## The event editor's "Notes" panel for one event (see LcfEditorAPI.add_event_panel()).
func _make_event_panel(context: Dictionary) -> Control:
	var map_id: int = context.map_id
	var event_id: int = context.event_id
	var box := VBoxContainer.new()
	var info := Label.new()
	info.text = "A note on this event, for you and your team (not shown in the game)."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var text := TextEdit.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = notes.get_event_note(map_id, event_id)
	box.add_child(text)
	var apply := Button.new()
	apply.text = "Save note"
	apply.pressed.connect(_change_event_note.bind(map_id, event_id, text))
	box.add_child(apply)
	return box


func _change_event_note(map_id: int, event_id: int, edit: TextEdit) -> void:
	var text := edit.text.strip_edges()
	var before: String = notes.get_event_note(map_id, event_id)
	if before == text:
		return
	var undo := get_undo_redo()
	undo.create_action("Edit event note")
	undo.add_do_method(notes, "set_event_note", map_id, event_id, text)
	undo.add_undo_method(notes, "set_event_note", map_id, event_id, before)
	undo.commit_action()


func _refresh_tab() -> void:
	tab_list.clear()
	var project := api.get_project() if api else null
	var map_names := {}
	if project:
		for entry: Dictionary in project.get_map_tree():
			map_names[entry.id] = entry.name
	for note: Dictionary in notes.all_notes():
		var place := "(%d, %d)" % [note.cell.x, note.cell.y] if note.has("cell") else "event %d" % note.event_id
		tab_list.add_item("%s  %s   %s" % [map_names.get(note.map_id, "Map%04d" % note.map_id), place, note.text])
		tab_list.set_item_metadata(tab_list.item_count - 1, note.map_id)


func _on_note_activated(index: int) -> void:
	api.open_map(tab_list.get_item_metadata(index))
