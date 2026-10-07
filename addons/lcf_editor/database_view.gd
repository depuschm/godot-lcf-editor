@tool
extends HSplitContainer
## Browser and editor for the RPG Maker database: sections, entries and every field
## of the selected entry. Fields come from liblcf's own description of each entry
## (LcfProject.get_database_entry_xml), so all sections work without special code.
## Double-click a field to edit it; Save writes RPG_RT.ldb with a backup.

## Emitted when the database gets unsaved changes or is saved/reverted.
signal modified_changed(modified: bool)

const FieldTree := preload("res://addons/lcf_editor/field_tree.gd")
const CommandList := preload("res://addons/lcf_editor/command_list.gd")

var project: RefCounted  # LcfProject
var sections: Array = []

var section_list: ItemList
var filter_edit: LineEdit
var entry_list: ItemList
var fields: FieldTree
var commands: CommandList
var header: Label
var status: Label
var warning: Label
var save_button: Button
var revert_button: Button
var confirm_dialog: ConfirmationDialog

var current_section := ""
var current_entries: Array = []
var current_index := -1
var round_trip: Dictionary = {}
var normalising_confirmed := false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	section_list = ItemList.new()
	section_list.custom_minimum_size = Vector2(170, 0)
	section_list.item_selected.connect(_on_section_selected)
	add_child(section_list)

	var right := HSplitContainer.new()
	add_child(right)

	var entries_box := VBoxContainer.new()
	entries_box.custom_minimum_size = Vector2(170, 0)
	right.add_child(entries_box)
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter…"
	filter_edit.clear_button_enabled = true
	filter_edit.text_changed.connect(func(_t: String) -> void: _fill_entries())
	entries_box.add_child(filter_edit)
	entry_list = ItemList.new()
	entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entry_list.item_selected.connect(_on_entry_selected)
	entries_box.add_child(entry_list)

	var fields_box := VBoxContainer.new()
	fields_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(fields_box)
	var bar := HBoxContainer.new()
	fields_box.add_child(bar)
	header = Label.new()
	header.text = "Open a project in the LCF Project dock."
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	bar.add_child(header)
	status = Label.new()
	bar.add_child(status)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.disabled = true
	save_button.pressed.connect(_on_save_pressed)
	bar.add_child(save_button)
	revert_button = Button.new()
	revert_button.text = "Revert"
	revert_button.disabled = true
	revert_button.pressed.connect(_on_revert_pressed)
	bar.add_child(revert_button)
	warning = Label.new()
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	warning.visible = false
	fields_box.add_child(warning)
	fields = FieldTree.new()
	fields.setter = func(path: PackedInt32Array, value: String) -> String:
		if project.set_database_field(current_section, current_index, path, value) != OK:
			return project.get_last_error()
		return ""
	fields.field_changed.connect(_on_field_changed)
	fields.edit_failed.connect(func(message: String) -> void: _update_status(message, true))
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields_box.add_child(split)
	split.add_child(fields)
	commands = CommandList.new()
	commands.visible = false
	commands.commands_changed.connect(_on_commands_changed)
	split.add_child(commands)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_autowrap = true
	confirm_dialog.min_size = Vector2i(480, 0)
	add_child(confirm_dialog)


func set_project(p_project: RefCounted) -> void:
	project = p_project
	fields.project = project
	commands.project = project
	fields.invalidate_names()
	normalising_confirmed = false
	round_trip = project.check_round_trip() if project and project.is_loaded() else {}
	if round_trip.is_empty() or round_trip.get("identical", true):
		warning.visible = false
	else:
		warning.text = "⚠ Saving will not reproduce RPG_RT.ldb byte for byte (%d → %d bytes). %s A backup is made before every save." % [
			round_trip.original_size, round_trip.saved_size, _notes_text()]
		warning.visible = true
	_update_status("")
	sections = project.get_database_sections() if project and project.is_loaded() else []
	section_list.clear()
	for section: Dictionary in sections:
		var label: String = section.label
		if not section.single:
			label += "  (%d)" % section.count
		section_list.add_item(label)
	entry_list.clear()
	fields.clear()
	commands.visible = false
	header.text = "Select a section." if sections else "Open a project in the LCF Project dock."
	if sections:
		section_list.select(0)
		_on_section_selected(0)


func _on_section_selected(index: int) -> void:
	current_section = sections[index].key
	current_entries = project.get_database_entries(current_section)
	filter_edit.text = ""
	_fill_entries()
	if entry_list.item_count > 0:
		entry_list.select(0)
		_on_entry_selected(0)
	else:
		fields.clear()
		commands.visible = false
		header.text = "%s: no entries" % sections[index].label


func _fill_entries() -> void:
	entry_list.clear()
	var filter := filter_edit.text.strip_edges().to_lower()
	for entry: Dictionary in current_entries:
		var label := "%04d: %s" % [entry.id, entry.name]
		if filter == "" or filter in label.to_lower():
			entry_list.add_item(label)
			entry_list.set_item_metadata(entry_list.item_count - 1, entry.index)


func _on_entry_selected(row: int) -> void:
	current_index = entry_list.get_item_metadata(row)
	var xml: String = project.get_database_entry_xml(current_section, current_index)
	var root := FieldTree.parse(xml)
	var is_common := current_section == "commonevents"
	fields.show_node(root, PackedInt32Array(), ["event_commands"] if is_common else [])
	commands.visible = is_common
	if is_common:
		commands.set_commands(project.get_common_event_commands(current_index))
	header.text = entry_list.get_item_text(row)
	if root.is_empty():
		header.text += "  (could not read entry)"


## Parses liblcf XML into { tag, id, text, children } (kept for tests and tools).
func _parse(xml: String) -> Dictionary:
	return FieldTree.parse(xml)


func _on_field_changed(path: PackedInt32Array, tag: String, value: String) -> void:
	if path.size() == 1 and tag == "name":
		_refresh_entry_name(value)
	fields.invalidate_names(current_section)
	_update_status("")


func _on_commands_changed(list: Array, _action: String) -> void:
	if project.set_common_event_commands(current_index, list) != OK:
		_update_status(project.get_last_error(), true)
		return
	commands.set_commands(project.get_common_event_commands(current_index))
	_update_status("")


func _refresh_entry_name(value: String) -> void:
	for entry: Dictionary in current_entries:
		if entry.index == current_index:
			entry.name = value
	var row := entry_list.get_selected_items()
	if not row.is_empty():
		var label := "%04d: %s" % [current_entries.filter(func(e: Dictionary) -> bool: return e.index == current_index)[0].id, value]
		entry_list.set_item_text(row[0], label)
		header.text = label


# --- saving -----------------------------------------------------------------------

func _notes_text() -> String:
	var notes: PackedStringArray = round_trip.get("notes", PackedStringArray())
	if notes.is_empty():
		return "liblcf leaves out fields that hold default values."
	return "liblcf reported: " + "; ".join(notes.slice(0, 3)) + "."


func _backup_dir() -> String:
	var dir: String = project.get_project_dir()
	return "user://backups/%s-%s" % [dir.get_file().validate_filename(), dir.md5_text().substr(0, 8)]


func is_modified() -> bool:
	return project != null and project.is_loaded() and project.is_database_modified()


## Saves without asking when that is safe; used when Godot saves everything.
func save_if_safe() -> void:
	if is_modified() and (round_trip.get("identical", true) or normalising_confirmed):
		_save()


func _on_save_pressed() -> void:
	if round_trip.get("identical", true) or normalising_confirmed:
		_save()
		return
	confirm_dialog.title = "Save database?"
	confirm_dialog.dialog_text = "Saving will not reproduce RPG_RT.ldb byte for byte (%d → %d bytes). %s\n\nThe current file is copied to a backup first. Save anyway?" % [
		round_trip.original_size, round_trip.saved_size, _notes_text()]
	_reconnect(confirm_dialog, func() -> void:
		normalising_confirmed = true
		_save())
	confirm_dialog.popup_centered()


func _save() -> void:
	if project.save_database(_backup_dir()) != OK:
		_update_status("Save failed: " + project.get_last_error(), true)
		return
	_update_status("Saved. Backup: " + project.get_last_backup().get_file())


func _on_revert_pressed() -> void:
	confirm_dialog.title = "Revert database?"
	confirm_dialog.dialog_text = "Discard all unsaved changes to the database?"
	_reconnect(confirm_dialog, func() -> void:
		project.revert_database()
		set_project(project)
		_update_status("Reverted to the saved file."))
	confirm_dialog.popup_centered()


func _reconnect(dialog: ConfirmationDialog, action: Callable) -> void:
	for connection in dialog.confirmed.get_connections():
		dialog.confirmed.disconnect(connection.callable)
	dialog.confirmed.connect(action, CONNECT_ONE_SHOT)


func _update_status(message: String, is_error := false) -> void:
	var modified := is_modified()
	save_button.disabled = not modified
	revert_button.disabled = not modified
	if message == "" and modified:
		message = "● Unsaved changes"
	status.text = message
	status.remove_theme_color_override("font_color")
	if is_error:
		status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	modified_changed.emit(modified)
