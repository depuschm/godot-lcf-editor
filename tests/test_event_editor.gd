extends SceneTree
## Drives the editor's map view, event editor and database view headlessly on a copy
## of the demo project: creating, editing, moving, copying and deleting events, page
## and command edits, undo states, and common event commands.
## Run: godot --headless --path . --script res://tests/test_event_editor.gd

const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")
const FieldTree := preload("res://addons/lcf_editor/field_tree.gd")
const CommandText := preload("res://addons/lcf_editor/command_text.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var work := ProjectSettings.globalize_path("user://event_editor_test")
	DirAccess.make_dir_recursive_absolute(work.path_join("ChipSet"))
	for file in DirAccess.get_files_at(work):
		DirAccess.remove_absolute(work.path_join(file))
	var source := ProjectSettings.globalize_path("res://demo")
	for file in DirAccess.get_files_at(source):
		DirAccess.copy_absolute(source.path_join(file), work.path_join(file))
	for file in DirAccess.get_files_at(source.path_join("ChipSet")):
		DirAccess.copy_absolute(source.path_join("ChipSet").path_join(file), work.path_join("ChipSet").path_join(file))

	var project: RefCounted = ClassDB.instantiate("LcfProject")
	_check(project.load(work) == OK, "demo copy loads")
	print("Event editor UI on ", work)

	# Readable command names.
	_check(CommandText.command_name(project, 10110) == "Show Message", "10110 reads “Show Message”")
	_check(CommandText.command_name(project, 10460) == "Change HP", "10460 reads “Change HP”")
	_check(CommandText.command_name(project, 3001) == "Get Save Info (Maniacs)", "Maniacs commands are marked")
	_check(CommandText.line(project, { "code": 20110, "indent": 1, "string": "more", "parameters": PackedInt32Array() }) == "      : more", "message continuation lines read “: text”")
	_check(project.get_event_command_codes().size() > 150, "%d command codes known" % project.get_event_command_codes().size())

	var view: Control = MapView.new()
	view.size = Vector2(1200, 800)
	root.add_child(view)
	await process_frame
	var map_id := 1
	view.show_map(project, map_id, "World")
	view._set_layer(MapView.Layer.EVENTS)
	_check(not view.palette_scroll.visible and view.tool_buttons[0].disabled, "Events layer hides the palette and paint tools")

	var free_cell := _free_cell(view)
	var events_before: int = view.map.events.size()
	view._new_event(free_cell)
	var id: int = view.selected_event
	_check(id > 0 and view.map.events.size() == events_before + 1, "new event %d created at %s" % [id, free_cell])
	var editor: AcceptDialog = view.event_editor
	_check(editor.visible and editor.event_id == id, "event editor opens on the new event")
	var created_xml: String = project.get_map_event_xml(map_id, id)
	_check("<move_type>0</move_type>" in created_xml and "<layer>1</layer>" in created_xml, "new page stands still on the hero's layer, like RPG Maker's")

	# Name, page settings, commands, pages.
	editor.name_edit.text = "Signpost"
	editor._apply_name()
	_check(view._event_by_id(id).get("name") == "Signpost", "rename reaches the map view")
	var row := _find_row(editor.fields.get_root(), "trigger")
	_check(row != null and row.get_text(1) == "Action Button", "page trigger shows as “Action Button”")
	if row:
		row.select(0)
		editor.fields._on_item_activated()
		var choice: Control = editor.fields._editor_control
		_check(choice is OptionButton and choice.item_count == 5, "trigger is edited with a list of the five triggers")
		choice.select(choice.get_item_index(3))
		editor.fields._on_edit_confirmed()
		editor.fields._edit_dialog.hide()
		_check(row.get_text(1) == "Autorun", "trigger now shows as “Autorun”")
	_check("<trigger>3</trigger>" in project.get_map_event_xml(map_id, id), "trigger is in the event")
	var lines := [
		{ "code": 10110, "indent": 0, "string": "Welcome to the demo!", "parameters": PackedInt32Array() },
		{ "code": 20110, "indent": 0, "string": "Made with godot-lcf-editor.", "parameters": PackedInt32Array() },
	]
	editor.commands.commands_changed.emit(lines, "Insert event command")
	_check(project.get_map_event_commands(map_id, id, 0).size() == 2, "commands from the list reach the project")
	_check(editor.commands.list.item_count == 3 and editor.commands.list.get_item_text(0) == "◆Show Message: Welcome to the demo!", "command list shows “%s”" % editor.commands.list.get_item_text(0))
	await _test_dialogs(project, editor, map_id, id)
	editor.commands.commands_changed.emit(lines, "Reset")
	editor._insert_page(0)
	_check(editor.tabs.tab_count == 2 and editor.page == 1, "page copied into a second tab (%d tabs, page %d)" % [editor.tabs.tab_count, editor.page])
	_check(project.get_map_event_commands(map_id, id, 1).size() == 2, "copied page has the commands")
	editor._delete_page()
	_check(editor.tabs.tab_count == 1, "page deleted")

	# Moving, copying, deleting, undo states.
	var edited_xml: String = project.get_map_event_xml(map_id, id)
	var target := _free_cell(view)
	view._move_event(id, target)
	var moved: Dictionary = view._event_by_id(id)
	_check(Vector2i(moved.x, moved.y) == target, "event moved to %s" % target)
	view.apply_event(map_id, id, edited_xml)
	moved = view._event_by_id(id)
	_check(Vector2i(moved.x, moved.y) == free_cell, "undoing the move puts it back")
	view.event_clipboard = project.get_map_event_xml(map_id, id)
	var paste_cell := _free_cell(view)
	view._paste_event(paste_cell)
	var copy_id: int = view.selected_event
	_check(copy_id != id and project.get_map_event_commands(map_id, copy_id, 0).size() == 2, "pasted copy %d has the commands" % copy_id)
	var copied: Dictionary = view._event_by_id(copy_id)
	_check(Vector2i(copied.x, copied.y) == paste_cell, "copy sits where it was pasted")
	view._delete_event(copy_id)
	_check(view._event_by_id(copy_id).is_empty(), "copy deleted")
	view.apply_event(map_id, id, "")
	_check(view._event_by_id(id).is_empty() and not editor.visible, "undoing the creation removes the event and closes the editor")
	view.apply_event(map_id, id, edited_xml)
	_check(project.get_map_event_xml(map_id, id) == edited_xml, "redo restores the edited event exactly")
	_check(project.save_map(map_id, "") == OK, "map saves")
	var reloaded: RefCounted = ClassDB.instantiate("LcfProject")
	reloaded.load(work)
	_check(reloaded.get_map_event_commands(map_id, id, 0)[0].string == "Welcome to the demo!", "event is in the saved map")
	_check(created_xml != edited_xml, "edits changed the event")

	# Common events in the database view.
	var db_view: Control = DatabaseView.new()
	root.add_child(db_view)
	await process_frame
	db_view.set_project(project)
	for i in db_view.sections.size():
		if db_view.sections[i].key == "commonevents":
			db_view.section_list.select(i)
			db_view._on_section_selected(i)
	_check(db_view.commands.visible and db_view.commands.commands.size() > 0, "common event shows its %d commands" % db_view.commands.commands.size())
	var list: Array = db_view.commands.commands.duplicate(true)
	list.remove_at(0)
	db_view.commands.commands_changed.emit(list, "Delete event command")
	_check(project.get_common_event_commands(0).size() == list.size() and project.is_database_modified(), "deleting a common event command marks the database modified")

	view.queue_free()
	db_view.queue_free()
	await process_frame
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


# Generated command dialogs, the picker and block-aware editing.
func _test_dialogs(project: RefCounted, editor: AcceptDialog, map_id: int, id: int) -> void:
	var cl: Control = editor.commands
	var count := func() -> int: return project.get_map_event_commands(map_id, id, 0).size()

	# Insert Control Switches through the picker at the end of the list.
	_select(cl, cl.commands.size())
	cl.open_insert()
	_check(cl.picker.visible and _tree_item(cl._picker_tree.get_root(), "Control Switches") != null, "picker lists commands by group")
	cl._picker_filter.text = "switch"
	cl._fill_picker()
	var picked := _tree_item(cl._picker_tree.get_root(), "Control Switches")
	_check(picked != null and picked.is_selected(0), "searching selects the first match")
	cl.picker.hide()
	cl._on_picked()
	var dialog: ConfirmationDialog = cl.dialog
	_check(dialog.visible and dialog.title == "Insert Control Switches", "picking opens the generated dialog")
	_check(_labels(dialog) == ["Target", "Switch", "Set to"], "dialog fields: %s" % [_labels(dialog)])
	dialog._set_param(0, 1)
	await process_frame
	_check(_labels(dialog) == ["Target", "First switch", "Last switch", "Set to"], "choosing a range shows first and last switch")
	dialog._set_param(2, 2)
	dialog._set_param(3, 1)
	dialog.hide()
	dialog._on_confirmed()
	var after: Array = project.get_map_event_commands(map_id, id, 0)
	_check(after.back().code == 10210 and after.back().parameters == PackedInt32Array([1, 1, 2, 1]), "Control Switches inserted: %s" % [after.back().parameters])
	_check(cl.list.get_item_text(after.size() - 1) == "◆Control Switches: [0001..0002] OFF", "its line reads “%s”" % cl.list.get_item_text(after.size() - 1))

	# Editing without changes changes nothing.
	_select(cl, after.size() - 1)
	cl.open_edit()
	dialog.hide()
	dialog._on_confirmed()
	_check(project.get_map_event_commands(map_id, id, 0) == after, "confirming an unchanged dialog changes nothing")

	# A conditional branch with Else, then without.
	_select(cl, cl.commands.size())
	cl.open_insert()
	cl.picker.hide()
	_tree_item(cl._picker_tree.get_root(), "Conditional Branch").select(0)
	cl._on_picked()
	dialog._set_param(5, 1)
	dialog.hide()
	dialog._on_confirmed()
	var codes: Array = project.get_map_event_commands(map_id, id, 0).map(func(c): return c.code)
	_check(codes.slice(-5) == [12010, 10, 22010, 10, 22011], "branch inserted with its bodies and Else")
	var head: int = codes.size() - 5
	_select(cl, head + 2)  # the Else line
	cl.open_edit()
	_check(dialog.schema.code == 12010, "editing the Else line opens its branch")
	dialog._set_param(5, 0)
	dialog.hide()
	dialog._on_confirmed()
	codes = project.get_map_event_commands(map_id, id, 0).map(func(c): return c.code)
	_check(codes.slice(head) == [12010, 10, 22011], "clearing Else removes the Else part")

	# Copy and paste the branch, then delete the copy by its End line.
	_select(cl, head)
	cl.copy_selected()
	_select(cl, cl.commands.size())
	cl.paste()
	codes = project.get_map_event_commands(map_id, id, 0).map(func(c): return c.code)
	_check(codes.slice(head) == [12010, 10, 22011, 12010, 10, 22011], "pasted a copy of the branch")
	_select(cl, head + 5)
	cl.delete_selected()
	codes = project.get_map_event_commands(map_id, id, 0).map(func(c): return c.code)
	_check(codes.slice(head) == [12010, 10, 22011], "deleting at End removes the whole copy")

	# Insert inside the branch body (at its END line) and the message lines.
	_select(cl, head + 1)
	cl.open_insert()
	cl.picker.hide()
	_tree_item(cl._picker_tree.get_root(), "Show Message").select(0)
	cl._on_picked()
	dialog.text = "Inside the branch\nSecond line"
	dialog.hide()
	dialog._on_confirmed()
	var final: Array = project.get_map_event_commands(map_id, id, 0)
	_check(final.slice(head).map(func(c): return "%d@%d" % [c.code, c.indent]) == ["12010@0", "10110@1", "20110@1", "10@1", "22011@0"], "message inserted into the branch body, one command per line")
	_check(count.call() == final.size(), "the list and the project agree")


func _select(cl: Control, row: int) -> void:
	cl.list.deselect_all()
	cl.list.select(row)


func _labels(dialog: ConfirmationDialog) -> Array:
	var out := []
	var cells: Array = dialog._grid.get_children()
	for i in range(0, cells.size(), 2):
		if not cells[i].is_queued_for_deletion():
			out.append(cells[i].text)
	return out


func _tree_item(item: TreeItem, text: String) -> TreeItem:
	while item:
		if item.get_text(0) == text:
			return item
		var found := _tree_item(item.get_first_child(), text)
		if found:
			return found
		item = item.get_next()
	return null


func _free_cell(view: Control) -> Vector2i:
	for y in view.map.height:
		for x in view.map.width:
			if view._event_at(Vector2i(x, y)).is_empty():
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_row(item: TreeItem, label: String) -> TreeItem:
	while item:
		if item.get_text(0) == label:
			return item
		var found := _find_row(item.get_first_child(), label)
		if found:
			return found
		item = item.get_next()
	return null
