@tool
extends VBoxContainer
## An event command list as RPG Maker shows it ("◆Show Message: …"), with insert, edit
## and delete. Every command can be edited raw (code, indent, text, parameters), so no
## command is ever out of reach. The owner applies changes: it listens to
## `commands_changed`, writes the list through LcfProject and calls set_commands().

## The user changed the list; `action` names the change for undo ("Delete command").
signal commands_changed(commands: Array, action: String)

const CommandText := preload("res://addons/lcf_editor/command_text.gd")

var project: RefCounted  # LcfProject
var commands: Array = []
var read_only := false

var list: ItemList
var insert_button: Button
var edit_button: Button
var delete_button: Button

var _dialog: ConfirmationDialog
var _filter: LineEdit
var _catalog: ItemList
var _code: SpinBox
var _code_name: Label
var _indent: SpinBox
var _text: LineEdit
var _params: LineEdit
var _error: Label
var _editing := -1     # index of the command being edited, or -1 when inserting
var _insert_at := 0


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	var title := Label.new()
	title.text = "Commands"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	insert_button = _button(bar, "Insert…", func() -> void: _open_insert())
	edit_button = _button(bar, "Edit…", func() -> void: _open_edit())
	delete_button = _button(bar, "Delete", func() -> void: _delete_selected())

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_MULTI
	list.add_theme_font_override("font", _mono_font())
	list.multi_selected.connect(func(_i: int, _s: bool) -> void: _update_buttons())
	list.item_activated.connect(func(index: int) -> void:
		if index < commands.size():
			_open_edit()
		else:
			_open_insert())
	list.gui_input.connect(_on_list_input)
	add_child(list)
	_build_dialog()
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
	list.clear()
	for command: Dictionary in commands:
		list.add_item(CommandText.line(project, command))
		list.set_item_tooltip(list.item_count - 1, "%s (%d)" % [project.get_event_command_name(command.code) if project else "", command.code])
	list.add_item("◆")  # end of the list: select it to insert at the end
	list.set_item_tooltip(list.item_count - 1, "End of the list")
	if not keep.is_empty():
		list.select(mini(keep[0], list.item_count - 1))
	_update_buttons()


func _selected() -> PackedInt32Array:
	return list.get_selected_items()


func _update_buttons() -> void:
	var selected := _selected()
	var has_command := not selected.is_empty() and selected[0] < commands.size()
	insert_button.disabled = read_only
	edit_button.disabled = read_only or not has_command or selected.size() != 1
	delete_button.disabled = read_only or not has_command


func _on_list_input(event: InputEvent) -> void:
	if read_only or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_DELETE:
			_delete_selected()
			list.accept_event()
		KEY_INSERT, KEY_SPACE:
			_open_insert()
			list.accept_event()


func _delete_selected() -> void:
	var selected := _selected()
	var keep: Array = []
	for i in commands.size():
		if not i in selected:
			keep.append(commands[i])
	if keep.size() == commands.size():
		return
	var removed := commands.size() - keep.size()
	commands_changed.emit(keep, "Delete event command" if removed == 1 else "Delete %d event commands" % removed)


# --- raw command dialog ----------------------------------------------------------

func _build_dialog() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.min_size = Vector2i(560, 0)
	_dialog.confirmed.connect(_on_dialog_confirmed)
	_dialog.get_ok_button().text = "Apply"
	add_child(_dialog)
	var box := VBoxContainer.new()
	_dialog.add_child(box)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Search commands…"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _fill_catalog())
	box.add_child(_filter)
	_catalog = ItemList.new()
	_catalog.custom_minimum_size = Vector2(0, 180)
	_catalog.item_selected.connect(func(index: int) -> void: _code.value = _catalog.get_item_metadata(index))
	box.add_child(_catalog)

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_code = SpinBox.new()
	_code.max_value = 99999
	_code.value_changed.connect(func(_v: float) -> void: _show_code_name())
	_code_name = Label.new()
	var code_row := HBoxContainer.new()
	code_row.add_child(_code)
	code_row.add_child(_code_name)
	_row(grid, "Code", code_row)
	_indent = SpinBox.new()
	_indent.max_value = 999
	_row(grid, "Indent", _indent)
	_text = LineEdit.new()
	_text.custom_minimum_size = Vector2(380, 0)
	_row(grid, "Text", _text)
	_params = LineEdit.new()
	_params.placeholder_text = "numbers, separated by spaces or commas"
	_row(grid, "Parameters", _params)
	_error = Label.new()
	_error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	box.add_child(_error)
	var note := Label.new()
	note.text = "Raw editing: parameters are stored exactly as entered. Dialogs per command follow."
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(note)


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	grid.add_child(control)


func _fill_catalog() -> void:
	_catalog.clear()
	var filter := _filter.text.strip_edges().to_lower()
	if project == null:
		return
	for code: int in project.get_event_command_codes():
		if code == 10:
			continue
		var label := "%s  (%d)" % [CommandText.command_name(project, code), code]
		if filter == "" or filter in label.to_lower():
			_catalog.add_item(label)
			_catalog.set_item_metadata(_catalog.item_count - 1, code)


func _show_code_name() -> void:
	var code := int(_code.value)
	_code_name.text = CommandText.command_name(project, code) if code > 0 else "(choose a command)"


func _open_insert() -> void:
	if read_only:
		return
	var selected := _selected()
	_insert_at = selected[0] if not selected.is_empty() else commands.size()
	_editing = -1
	var indent: int = commands[_insert_at].indent if _insert_at < commands.size() else 0
	_open_dialog("Insert command", 0, indent, "", PackedInt32Array())


func _open_edit() -> void:
	var selected := _selected()
	if read_only or selected.size() != 1 or selected[0] >= commands.size():
		return
	_editing = selected[0]
	var command: Dictionary = commands[_editing]
	_open_dialog("Edit command %d" % (_editing + 1), command.code, command.indent, command.string, command.parameters)


func _open_dialog(title: String, code: int, indent: int, text: String, params: PackedInt32Array) -> void:
	_dialog.title = title
	_filter.text = ""
	_fill_catalog()
	_code.value = code
	_show_code_name()
	_indent.value = indent
	_text.text = text
	var numbers := PackedStringArray()
	for p in params:
		numbers.append(str(p))
	_params.text = " ".join(numbers)
	_error.text = ""
	_dialog.popup_centered()
	if code == 0:
		_filter.grab_focus()


func _on_dialog_confirmed() -> void:
	var params := PackedInt32Array()
	for part in _params.text.replace(",", " ").split(" ", false):
		if not part.is_valid_int():
			_error.text = "“%s” is not a whole number." % part
			_dialog.popup_centered.call_deferred()
			return
		params.append(int(part))
	if int(_code.value) <= 0:
		_error.text = "Choose a command."
		_dialog.popup_centered.call_deferred()
		return
	var command := { "code": int(_code.value), "indent": int(_indent.value), "string": _text.text, "parameters": params }
	var result := commands.duplicate(true)
	if _editing >= 0:
		result[_editing] = command
		commands_changed.emit(result, "Edit event command")
	else:
		result.insert(_insert_at, command)
		commands_changed.emit(result, "Insert event command")
