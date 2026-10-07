@tool
extends HSplitContainer
## Browser and editor for the RPG Maker database: sections, entries and every field
## of the selected entry. Fields come from liblcf's own description of each entry
## (LcfProject.get_database_entry_xml), so all sections work without special code.
## Double-click a field to edit it; Save writes RPG_RT.ldb with a backup.

## Emitted when the database gets unsaved changes or is saved/reverted.
signal modified_changed(modified: bool)

## Fields that point into another section, shown with the target's name.
const REFERENCES := {
	"class_id": "classes", "skill_id": "skills", "item_id": "items", "state_id": "states",
	"animation_id": "animations", "enemy_id": "enemies", "troop_id": "troops",
	"terrain_id": "terrains", "attribute_id": "attributes", "chipset_id": "chipsets",
	"actor_id": "actors", "switch_id": "switches", "variable_id": "variables",
	"weapon_id": "items", "shield_id": "items", "armor_id": "items", "helmet_id": "items",
	"accessory_id": "items", "unarmed_animation": "animations",
	"battler_animation": "battleranimations",
}
const LONG_LIST := 12

var project: RefCounted  # LcfProject
var sections: Array = []
var names_cache := {}  # section key -> { id: name }

var section_list: ItemList
var filter_edit: LineEdit
var entry_list: ItemList
var fields: Tree
var header: Label
var status: Label
var warning: Label
var save_button: Button
var revert_button: Button
var edit_dialog: ConfirmationDialog
var confirm_dialog: ConfirmationDialog

var current_section := ""
var current_entries: Array = []
var current_index := -1
var round_trip: Dictionary = {}
var normalising_confirmed := false
var editing_item: TreeItem
var editor_control: Control


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
	fields = Tree.new()
	fields.columns = 2
	fields.column_titles_visible = true
	fields.set_column_title(0, "Field")
	fields.set_column_title(1, "Value")
	fields.set_column_expand_ratio(0, 2)
	fields.set_column_expand_ratio(1, 3)
	fields.hide_root = true
	fields.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields.item_activated.connect(_on_field_activated)
	fields_box.add_child(fields)

	edit_dialog = ConfirmationDialog.new()
	edit_dialog.confirmed.connect(_on_edit_confirmed)
	add_child(edit_dialog)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_autowrap = true
	confirm_dialog.min_size = Vector2i(480, 0)
	add_child(confirm_dialog)


func set_project(p_project: RefCounted) -> void:
	project = p_project
	names_cache.clear()
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
	var root := _parse(xml)
	fields.clear()
	var tree_root := fields.create_item()
	header.text = entry_list.get_item_text(row)
	if root.is_empty():
		header.text += "  (could not read entry)"
		return
	for i in root.children.size():
		_add_node(tree_root, root.children[i], PackedInt32Array([i]))


# --- XML to nodes: { tag, id, text, children } ----------------------------------

func _parse(xml: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return {}
	var stack: Array[Dictionary] = []
	var root := {}
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node := {
					"tag": parser.get_node_name(),
					"id": parser.get_named_attribute_value_safe("id"),
					"text": "",
					"children": [],
				}
				if stack.is_empty():
					root = node
				else:
					stack.back().children.append(node)
				if not parser.is_empty():
					stack.push_back(node)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT:
				if not stack.is_empty():
					var text := parser.get_node_data()
					if text.strip_edges() != "":
						stack.back().text += text.xml_unescape()
	return root


# --- nodes to tree rows -----------------------------------------------------------

func _add_node(parent: TreeItem, node: Dictionary, path: PackedInt32Array) -> void:
	var item := fields.create_item(parent)
	var children: Array = node.children
	if children.is_empty():
		item.set_text(0, node.tag)
		item.set_tooltip_text(0, node.tag)
		item.set_metadata(0, { "path": path, "tag": node.tag, "text": node.text })
		_show_value(item)
		return

	# A field holding exactly one structure (e.g. parameters → Parameters): skip a level.
	if children.size() == 1 and children[0].id == "" and children[0].tag[0] == children[0].tag[0].to_upper():
		item.set_text(0, node.tag)
		for i in children[0].children.size():
			_add_node(item, children[0].children[i], path + PackedInt32Array([0, i]))
		item.collapsed = children[0].children.size() > 8
		return

	if node.tag == "event_commands":
		item.set_text(0, "event_commands")
		item.set_text(1, "%d commands" % children.size())
		for command: Dictionary in children:
			_add_command(item, command)
		return

	if node.tag[0] == node.tag[0].to_upper():  # a list element such as <Learning id="0001">
		item.set_text(0, "%s %s" % [node.tag, node.id] if node.id != "" else node.tag)
		item.set_text(1, _summary(node))
	else:
		item.set_text(0, node.tag)
		item.set_text(1, "%d entries" % children.size())
		item.collapsed = children.size() > 1
	for i in children.size():
		_add_node(item, children[i], path + PackedInt32Array([i]))


func _add_command(parent: TreeItem, command: Dictionary) -> void:
	var values := {}
	for f: Dictionary in command.children:
		values[f.tag] = f.text
	var code := int(values.get("code", "0"))
	var command_name: String = project.get_event_command_name(code)
	if command_name == "":
		command_name = "Command %d" % code
	var item := fields.create_item(parent)
	item.set_text(0, "  ".repeat(int(values.get("indent", "0"))) + command_name)
	item.set_tooltip_text(0, command_name)
	var detail: String = values.get("string", "")
	var params: String = values.get("parameters", "").strip_edges()
	if params != "":
		detail = ("“%s”  " % detail if detail != "" else "") + "[" + params.replace(" ", ", ") + "]"
	elif detail != "":
		detail = "“%s”" % detail
	item.set_text(1, detail)
	item.set_tooltip_text(1, detail)


func _summary(node: Dictionary) -> String:
	for child: Dictionary in node.children:
		if child.tag == "name" and child.text != "":
			return child.text
	return ""


func _format_value(tag: String, text: String) -> String:
	if text == "T":
		return "Yes"
	if text == "F":
		return "No"
	if text == "":
		return "—"
	if " " in text and text.replace(" ", "").replace("-", "").is_valid_int():
		var numbers := text.split(" ")
		if numbers.size() > LONG_LIST:
			return "%d values: %s, …" % [numbers.size(), ", ".join(numbers.slice(0, 8))]
		return ", ".join(numbers)
	if text.is_valid_int() and REFERENCES.has(tag) and int(text) > 0:
		var target := _name_of(REFERENCES[tag], int(text))
		if target != "":
			return "%s · %s" % [text, target]
	return text


func _name_of(section: String, id: int) -> String:
	if not names_cache.has(section):
		var names := {}
		for entry: Dictionary in project.get_database_entries(section):
			names[entry.id] = entry.name
		names_cache[section] = names
	return names_cache[section].get(id, "")


# --- editing ----------------------------------------------------------------------

func _show_value(item: TreeItem) -> void:
	var meta: Dictionary = item.get_metadata(0)
	item.set_text(1, _format_value(meta.tag, meta.text))
	item.set_tooltip_text(1, meta.text + "\n(double-click to edit)")


func _kind(text: String) -> String:
	if text == "T" or text == "F":
		return "bool"
	if text.is_valid_int():
		return "int"
	if " " in text and text.replace(" ", "").replace("-", "").is_valid_int():
		return "list"
	return "text"


func _on_field_activated() -> void:
	var item := fields.get_selected()
	if item == null or not (item.get_metadata(0) is Dictionary):
		return
	editing_item = item
	var meta: Dictionary = item.get_metadata(0)
	if editor_control:
		editor_control.queue_free()
	var kind := _kind(meta.text)
	match kind:
		"bool":
			var box := CheckBox.new()
			box.text = "Yes"
			box.button_pressed = meta.text == "T"
			editor_control = box
		"int":
			var spin := SpinBox.new()
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.rounded = true
			spin.value = int(meta.text)
			editor_control = spin
		_:
			if "\n" in meta.text:
				var area := TextEdit.new()
				area.text = meta.text
				area.custom_minimum_size = Vector2(420, 120)
				editor_control = area
			else:
				var line := LineEdit.new()
				line.text = meta.text
				line.custom_minimum_size = Vector2(320, 0)
				line.text_submitted.connect(func(_t: String) -> void:
					edit_dialog.hide()
					_on_edit_confirmed())
				editor_control = line
	edit_dialog.title = "Edit %s" % meta.tag
	edit_dialog.add_child(editor_control)
	edit_dialog.popup_centered()
	if editor_control is LineEdit:
		editor_control.grab_focus()
		editor_control.select_all()


func _on_edit_confirmed() -> void:
	if editing_item == null or editor_control == null:
		return
	var meta: Dictionary = editing_item.get_metadata(0)
	var value: String
	if editor_control is CheckBox:
		value = "T" if editor_control.button_pressed else "F"
	elif editor_control is SpinBox:
		value = str(int(editor_control.value))
	else:
		value = editor_control.text
		if _kind(meta.text) == "list":
			var parts := PackedStringArray()
			for part in value.replace(",", " ").split(" ", false):
				if not part.is_valid_int():
					_update_status("“%s” is not a whole number" % part, true)
					return
				parts.append(str(int(part)))
			value = " ".join(parts)
	if value == meta.text:
		return
	if project.set_database_field(current_section, current_index, meta.path, value) != OK:
		_update_status("Could not set %s: %s" % [meta.tag, project.get_last_error()], true)
		return
	meta.text = value
	editing_item.set_metadata(0, meta)
	_show_value(editing_item)
	if meta.path.size() == 1 and meta.tag == "name":
		_refresh_entry_name(value)
	names_cache.erase(current_section)
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
