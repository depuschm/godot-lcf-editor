@tool
extends VBoxContainer
## An event command list as RPG Maker shows it ("◆Show Message: …"). Commands with a
## schema (command_registry.gd) get a generated dialog; every command can also be
## edited raw (code, indent, text, parameters), so nothing is out of reach.
##
## Editing follows the list's structure (command_blocks.gd): deleting, copying and
## pasting work on whole units (a branch with its bodies, a message with its lines),
## and new commands are inserted where RPG Maker would put them.
##
## The owner applies changes: it listens to `commands_changed`, writes the list
## through LcfProject and calls set_commands().

## The user changed the list; `action` names the change for undo ("Delete command").
signal commands_changed(commands: Array, action: String)

const CommandText := preload("res://addons/lcf_editor/command_text.gd")
const Blocks := preload("res://addons/lcf_editor/command_blocks.gd")
const CommandDialog := preload("res://addons/lcf_editor/command_dialog.gd")

enum Menu { INSERT, EDIT, EDIT_RAW, COPY, CUT, PASTE, DELETE }

## Copied commands, shared by all lists (indented from 0).
static var clipboard: Array = []

var project: RefCounted  # LcfProject
var map_id := 0          # map of the event, for event names (0 for common events)
var commands: Array = []
var read_only := false
var names: LcfCommands.Names

var list: ItemList
var insert_button: Button
var edit_button: Button
var delete_button: Button
var menu: PopupMenu
var picker: ConfirmationDialog
var dialog: CommandDialog

var _picker_filter: LineEdit
var _picker_tree: Tree
var _raw: ConfirmationDialog
var _raw_code: SpinBox
var _raw_code_name: Label
var _raw_indent: SpinBox
var _raw_text: LineEdit
var _raw_params: LineEdit
var _raw_error: Label

var _insert := {}       # { index, indent } for the command being inserted
var _editing := -1      # head of the command being edited, or -1 when inserting
var _select_after := -1


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	var title := Label.new()
	title.text = "Commands"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	insert_button = _button(bar, "Insert…", func() -> void: open_insert())
	edit_button = _button(bar, "Edit…", func() -> void: open_edit())
	delete_button = _button(bar, "Delete", func() -> void: delete_selected())

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_MULTI
	list.allow_rmb_select = true
	list.add_theme_font_override("font", _mono_font())
	list.multi_selected.connect(func(_i: int, _s: bool) -> void: _update_buttons())
	list.item_activated.connect(func(_index: int) -> void: open_edit())
	list.item_clicked.connect(_on_item_clicked)
	list.gui_input.connect(_on_list_input)
	add_child(list)

	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu)
	add_child(menu)
	dialog = CommandDialog.new()
	dialog.applied.connect(_on_dialog_applied)
	dialog.raw_requested.connect(func() -> void:
		if _editing >= 0:
			_open_raw_edit(_editing)
		else:
			_open_raw_insert(int(dialog.schema.code)))
	add_child(dialog)
	_build_picker()
	_build_raw()
	_update_buttons()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Monospace", "DejaVu Sans Mono", "Consolas", "Menlo"])
	return font


## Shows a command list ([{ code, indent, string, parameters }]), keeping the selection.
func set_commands(p_commands: Array) -> void:
	var keep := list.get_selected_items()
	commands = p_commands.duplicate(true)
	names = LcfCommands.Names.new(project, map_id)
	list.clear()
	for command: Dictionary in commands:
		list.add_item(CommandText.line(project, command, names))
		list.set_item_tooltip(list.item_count - 1, "%s (%d)" % [CommandText.command_name(project, command.code), command.code])
	list.add_item("◆")  # end of the list: select it to insert at the end
	list.set_item_tooltip(list.item_count - 1, "End of the list")
	if _select_after >= 0:
		list.select(mini(_select_after, list.item_count - 1))
		list.ensure_current_is_visible()
		_select_after = -1
	elif not keep.is_empty():
		list.select(mini(keep[0], list.item_count - 1))
	_update_buttons()


func _selected() -> PackedInt32Array:
	return list.get_selected_items()


func _row() -> int:
	var selected := _selected()
	return selected[0] if not selected.is_empty() else commands.size()


func _has_units() -> bool:
	return not Blocks.units_for(commands, _selected()).is_empty()


func _update_buttons() -> void:
	insert_button.disabled = read_only
	edit_button.disabled = read_only or not _has_units()
	delete_button.disabled = read_only or not _has_units()


func _emit(result: Array, action: String, select := -1) -> void:
	_select_after = select
	commands_changed.emit(result, action)


# --- actions -----------------------------------------------------------------------

func delete_selected() -> void:
	var units := Blocks.units_for(commands, _selected())
	if read_only or units.is_empty():
		return
	var count := 0
	for u: Array in units:
		count += 1
	_emit(Blocks.remove_units(commands, units), "Delete event command" if count == 1 else "Delete %d event commands" % count, units[0][0])


func copy_selected() -> void:
	var copied := Blocks.copy_units(commands, _selected())
	if not copied.is_empty():
		clipboard = copied


func cut_selected() -> void:
	copy_selected()
	delete_selected()


func paste() -> void:
	if read_only or clipboard.is_empty():
		return
	var at := Blocks.insert_point(commands, _row())
	var lines := Blocks.reindent(clipboard, at.indent)
	_emit(commands.slice(0, at.index) + lines + commands.slice(at.index), "Paste event commands", at.index)


## Opens the command picker to insert at the selected row.
func open_insert() -> void:
	if read_only:
		return
	_insert = Blocks.insert_point(commands, _row())
	_editing = -1
	_picker_filter.text = ""
	_fill_picker()
	picker.popup_centered(Vector2i(460, 520))
	_picker_filter.grab_focus()


## Opens the dialog of the selected command (its head, for block lines). On an END
## line or the end of the list, inserts instead, like RPG Maker.
func open_edit() -> void:
	if read_only:
		return
	var row := _row()
	if row >= commands.size() or commands[row].code == Blocks.END:
		open_insert()
		return
	var head := Blocks.head_of(commands, row)
	var schema := LcfCommands.get_schema(commands[head].code)
	if schema.is_empty():
		_open_raw_edit(head)
		return
	_editing = head
	dialog.open(schema, commands[head].parameters, Blocks.text_of(commands, head, schema), names)


func _on_dialog_applied(params: PackedInt32Array, text: String) -> void:
	var schema := dialog.schema
	if _editing >= 0:
		_emit(Blocks.rebuild(commands, _editing, schema, params, text), "Edit %s" % schema.name, _editing)
	else:
		var lines := Blocks.build(schema, params, text, _insert.indent)
		_emit(commands.slice(0, _insert.index) + lines + commands.slice(_insert.index), "Insert %s" % schema.name, _insert.index)


func _on_item_clicked(index: int, at: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or read_only:
		return
	if not index in _selected():
		list.deselect_all()
		list.select(index)
		_update_buttons()
	var has_units := _has_units()
	menu.clear()
	menu.add_item("Insert…", Menu.INSERT)
	menu.add_item("Edit…", Menu.EDIT)
	menu.add_item("Edit raw…", Menu.EDIT_RAW)
	menu.add_separator()
	menu.add_item("Copy", Menu.COPY)
	menu.add_item("Cut", Menu.CUT)
	menu.add_item("Paste", Menu.PASTE)
	menu.add_separator()
	menu.add_item("Delete", Menu.DELETE)
	for id in [Menu.EDIT, Menu.EDIT_RAW, Menu.COPY, Menu.CUT, Menu.DELETE]:
		menu.set_item_disabled(menu.get_item_index(id), not has_units)
	menu.set_item_disabled(menu.get_item_index(Menu.PASTE), clipboard.is_empty())
	menu.position = Vector2i(list.get_screen_position() + at)
	menu.reset_size()
	menu.popup()


func _on_menu(id: int) -> void:
	match id:
		Menu.INSERT: open_insert()
		Menu.EDIT: open_edit()
		Menu.EDIT_RAW:
			var row := _row()
			if row < commands.size():
				_open_raw_edit(row)
		Menu.COPY: copy_selected()
		Menu.CUT: cut_selected()
		Menu.PASTE: paste()
		Menu.DELETE: delete_selected()


func _on_list_input(event: InputEvent) -> void:
	if read_only or not (event is InputEventKey) or not event.pressed:
		return
	var handled := true
	if event.is_command_or_control_pressed():
		match event.keycode:
			KEY_C: copy_selected()
			KEY_X: cut_selected()
			KEY_V: paste()
			_: handled = false
	else:
		match event.keycode:
			KEY_DELETE: delete_selected()
			KEY_INSERT, KEY_SPACE: open_insert()
			_: handled = false
	if handled:
		list.accept_event()


# --- command picker ------------------------------------------------------------------

func _build_picker() -> void:
	picker = ConfirmationDialog.new()
	picker.title = "Insert command"
	picker.get_ok_button().text = "Next…"
	picker.confirmed.connect(_on_picked)
	add_child(picker)
	var box := VBoxContainer.new()
	picker.add_child(box)
	_picker_filter = LineEdit.new()
	_picker_filter.placeholder_text = "Search commands…"
	_picker_filter.clear_button_enabled = true
	_picker_filter.text_changed.connect(func(_t: String) -> void: _fill_picker())
	_picker_filter.text_submitted.connect(func(_t: String) -> void:
		picker.hide()
		_on_picked())
	box.add_child(_picker_filter)
	_picker_tree = Tree.new()
	_picker_tree.hide_root = true
	_picker_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_tree.custom_minimum_size = Vector2(0, 380)
	_picker_tree.item_activated.connect(func() -> void:
		picker.hide()
		_on_picked())
	box.add_child(_picker_tree)


func _fill_picker() -> void:
	_picker_tree.clear()
	var root := _picker_tree.create_item()
	var filter := _picker_filter.text.strip_edges().to_lower()
	var groups := {}
	var first: TreeItem
	for schema: Dictionary in LcfCommands.get_schemas():
		if filter != "" and not filter in String(schema.name).to_lower():
			continue
		var group: String = schema.get("group", "Other")
		if not groups.has(group):
			groups[group] = _picker_tree.create_item(root)
			groups[group].set_text(0, group)
			groups[group].set_selectable(0, false)
		var item := _picker_tree.create_item(groups[group])
		item.set_text(0, schema.name)
		item.set_metadata(0, int(schema.code))
		if first == null:
			first = item
	# Every other command liblcf knows, edited raw.
	if project:
		var raw := _picker_tree.create_item(root)
		raw.set_text(0, "All other commands (raw)")
		raw.set_selectable(0, false)
		raw.collapsed = filter == ""
		for code: int in project.get_event_command_codes():
			if code == Blocks.END or code in Blocks.MARKERS or code in Blocks.CONTINUATIONS or not LcfCommands.get_schema(code).is_empty():
				continue
			var label := "%s  (%d)" % [CommandText.command_name(project, code), code]
			if filter != "" and not filter in label.to_lower():
				continue
			var item := _picker_tree.create_item(raw)
			item.set_text(0, label)
			item.set_metadata(0, -code)
			if first == null:
				first = item
		if raw.get_child_count() == 0:
			raw.free()
	if first and filter != "":
		first.select(0)


func _on_picked() -> void:
	var item := _picker_tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var code: int = item.get_metadata(0)
	if code < 0:
		_open_raw_insert(-code)
		return
	var schema := LcfCommands.get_schema(code)
	dialog.open(schema, LcfCommands.default_params(schema, names.engine if names else ""), "", names, "Insert %s" % schema.name, true)


# --- raw command dialog ----------------------------------------------------------

func _build_raw() -> void:
	_raw = ConfirmationDialog.new()
	_raw.min_size = Vector2i(560, 0)
	_raw.confirmed.connect(_on_raw_confirmed)
	_raw.get_ok_button().text = "Apply"
	add_child(_raw)
	var box := VBoxContainer.new()
	_raw.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_raw_code = SpinBox.new()
	_raw_code.max_value = 99999
	_raw_code.value_changed.connect(func(v: float) -> void: _raw_code_name.text = CommandText.command_name(project, int(v)))
	_raw_code_name = Label.new()
	var code_row := HBoxContainer.new()
	code_row.add_child(_raw_code)
	code_row.add_child(_raw_code_name)
	_row_pair(grid, "Code", code_row)
	_raw_indent = SpinBox.new()
	_raw_indent.max_value = 999
	_row_pair(grid, "Indent", _raw_indent)
	_raw_text = LineEdit.new()
	_raw_text.custom_minimum_size = Vector2(380, 0)
	_row_pair(grid, "Text", _raw_text)
	_raw_params = LineEdit.new()
	_raw_params.placeholder_text = "numbers, separated by spaces or commas"
	_row_pair(grid, "Parameters", _raw_params)
	_raw_error = Label.new()
	_raw_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	box.add_child(_raw_error)
	var note := Label.new()
	note.text = "Raw editing changes this one line exactly as entered."
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(note)


func _row_pair(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	grid.add_child(control)


func _open_raw_insert(code: int) -> void:
	_editing = -1
	_show_raw("Insert command", code, _insert.get("indent", 0), "", PackedInt32Array())


func _open_raw_edit(row: int) -> void:
	_editing = row
	var c: Dictionary = commands[row]
	_show_raw("Edit line %d (raw)" % (row + 1), c.code, c.indent, c.string, c.parameters)


func _show_raw(title: String, code: int, indent: int, text: String, params: PackedInt32Array) -> void:
	_raw.title = title
	_raw_code.value = code
	_raw_code_name.text = CommandText.command_name(project, code)
	_raw_indent.value = indent
	_raw_text.text = text
	_raw_params.text = " ".join(Array(params).map(func(p: int) -> String: return str(p)))
	_raw_error.text = ""
	_raw.popup_centered()


func _on_raw_confirmed() -> void:
	var params := PackedInt32Array()
	for part in _raw_params.text.replace(",", " ").split(" ", false):
		if not part.is_valid_int():
			_raw_error.text = "“%s” is not a whole number." % part
			_raw.popup_centered.call_deferred()
			return
		params.append(int(part))
	if int(_raw_code.value) <= 0:
		_raw_error.text = "Choose a command code."
		_raw.popup_centered.call_deferred()
		return
	var command := { "code": int(_raw_code.value), "indent": int(_raw_indent.value), "string": _raw_text.text, "parameters": params }
	var result := commands.duplicate(true)
	if _editing >= 0:
		result[_editing] = command
		_emit(result, "Edit event command (raw)", _editing)
	else:
		result.insert(_insert.index, command)
		_emit(result, "Insert event command", _insert.index)
