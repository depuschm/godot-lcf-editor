@tool
extends ConfirmationDialog
## A command's dialog, generated from its schema (see command_registry.gd): one field
## per parameter that applies, choices with names (switches, maps, events, ...), and the
## command's text. Fields that other fields depend on rebuild the form when changed.

## The user confirmed: the command's new parameters and text.
signal applied(params: PackedInt32Array, text: String)
## The user wants to edit the command as raw data instead.
signal raw_requested

## References with more entries than this get a number box instead of a list.
const MAX_LIST := 1000

var schema: Dictionary
var params := PackedInt32Array()
var text := ""
var names: LcfCommands.Names
var project: RefCounted
## True when the dialog creates a new command (it then applies even unchanged).
var inserting := false

var _grid: GridContainer
var _hint: Label
var _depends := {}  # parameter index -> true if some field's `when` uses it
var _initial := PackedInt32Array()
var _initial_text := ""


func _init() -> void:
	min_size = Vector2i(520, 0)
	get_ok_button().text = "Apply"
	add_button("Raw…", true, "raw")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"raw":
			hide()
			raw_requested.emit())
	confirmed.connect(_on_confirmed)
	var box := VBoxContainer.new()
	add_child(box)
	_grid = GridContainer.new()
	_grid.columns = 2
	box.add_child(_grid)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


## Opens the dialog for a command. `p_params` may be shorter than the schema needs;
## missing parameters are added as 0 (unknown extra ones are kept).
func open(p_schema: Dictionary, p_params: PackedInt32Array, p_text: String, p_names: LcfCommands.Names, p_title := "", p_inserting := false) -> void:
	schema = p_schema
	inserting = p_inserting
	names = p_names
	project = names.project if names else null
	params = p_params.duplicate()
	var needed := int(schema.get("length", 0))
	for def: Dictionary in schema.get("params", []):
		needed = maxi(needed, int(def.index) + 1)
	while params.size() < needed:
		params.append(0)
	text = p_text
	_initial = params.duplicate()
	_initial_text = text
	_depends.clear()
	for def: Dictionary in schema.get("params", []) + [schema.get("text", {})]:
		for index: int in def.get("when", {}):
			_depends[index] = true
	title = p_title if p_title != "" else schema.name
	_build()
	reset_size()
	popup_centered()


func _engine() -> String:
	return names.engine if names else ""


func _build() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var text_def: Dictionary = schema.get("text", {})
	if not text_def.is_empty() and LcfCommands.is_visible(text_def, params, _engine()):
		_add_row(text_def.get("label", "Text"), _text_control(text_def))
	for def: Dictionary in LcfCommands.visible_params(schema, params, _engine()):
		_add_row(def.get("label", "Parameter %d" % def.index), _param_control(def))
	_hint.text = _hint_text(text_def)
	_hint.visible = _hint.text != ""
	if _grid.get_child_count() == 0:
		var none := Label.new()
		none.text = "This command has no settings."
		_grid.add_child(none)


func _hint_text(text_def: Dictionary) -> String:
	if text_def.get("kind", "") == "lines":
		return "Each line of the text is stored as one line of the command (a message box shows four)."
	return ""


func _add_row(label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	_grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(control)


# --- controls ------------------------------------------------------------------------

func _text_control(def: Dictionary) -> Control:
	match String(def.get("kind", "line")):
		"lines":
			var area := TextEdit.new()
			area.text = text
			area.custom_minimum_size = Vector2(420, 96)
			area.text_changed.connect(func() -> void: text = area.text)
			return area
		"file":
			var row := HBoxContainer.new()
			var line := LineEdit.new()
			line.text = text
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.text_changed.connect(func(t: String) -> void: text = t)
			row.add_child(line)
			var files := _files(String(def.get("folder", "")))
			if not files.is_empty():
				var menu := MenuButton.new()
				menu.text = "▾"
				menu.flat = false
				for file in files:
					menu.get_popup().add_item(file)
				menu.get_popup().index_pressed.connect(func(i: int) -> void:
					line.text = files[i]
					text = files[i])
				row.add_child(menu)
			return row
	var edit := LineEdit.new()
	edit.text = text
	edit.custom_minimum_size = Vector2(320, 0)
	edit.text_changed.connect(func(t: String) -> void: text = t)
	return edit


## File names (without extension) in a project folder such as "Sound".
func _files(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if project == null or folder == "":
		return out
	var base: String = project.get_project_dir()
	for dir in DirAccess.get_directories_at(base):
		if dir.to_lower() == folder.to_lower():
			for file in DirAccess.get_files_at(base.path_join(dir)):
				var name := file.get_basename()
				if not name in out:
					out.append(name)
	out.sort()
	return out


func _param_control(def: Dictionary) -> Control:
	var index := int(def.index)
	var value := params[index]
	var type := String(def.type)
	match type:
		"bool":
			var box := CheckBox.new()
			box.text = "Yes"
			box.button_pressed = value != 0
			box.toggled.connect(func(on: bool) -> void: _set_param(index, 1 if on else 0))
			return box
		"enum":
			return _option(index, LcfCommands.enum_items(def.get("choices", [])), value)
		"map":
			var maps := {}
			for id: int in names.maps():
				maps[id] = names.map(id)
			return _option(index, maps, value)
		"event":
			var events := {}
			for id: int in LcfCommands.SPECIAL_EVENTS:
				events[id] = LcfCommands.SPECIAL_EVENTS[id]
			for id: int in names.events():
				events[id] = names.event(id)
			return _option(index, events, value)
	if LcfCommands.REFERENCES.has(type) and names:
		var section: String = LcfCommands.REFERENCES[type]
		var entries := names.entries(section)
		if entries.size() <= MAX_LIST:
			var items := {}
			for id: int in entries:
				items[id] = "%04d: %s" % [id, entries[id]]
			return _option(index, items, value)
		return _number(index, def, value, section)
	return _number(index, def, value, "")


func _option(index: int, items: Dictionary, value: int) -> OptionButton:
	var option := OptionButton.new()
	for id: int in items:
		option.add_item(String(items[id]), id)
	if option.get_item_index(value) < 0:
		option.add_item("%d (not in the list)" % value, value)
	option.select(option.get_item_index(value))
	option.item_selected.connect(func(i: int) -> void: _set_param(index, option.get_item_id(i)))
	return option


func _number(index: int, def: Dictionary, value: int, section: String) -> Control:
	var spin := SpinBox.new()
	spin.min_value = def.get("min", -9999999)
	spin.max_value = def.get("max", 9999999)
	spin.rounded = true
	spin.value = value
	if section == "":
		spin.value_changed.connect(func(v: float) -> void: _set_param(index, int(v)))
		return spin
	var row := HBoxContainer.new()
	row.add_child(spin)
	var label := Label.new()
	label.text = names.name_of(section, value)
	row.add_child(label)
	spin.value_changed.connect(func(v: float) -> void:
		label.text = names.name_of(section, int(v))
		_set_param(index, int(v)))
	return row


func _set_param(index: int, value: int) -> void:
	if params[index] == value:
		return
	params[index] = value
	if _depends.has(index):
		# Fields that appear now start from their defaults, as in a new command.
		for def: Dictionary in schema.get("params", []):
			if LcfCommands.is_visible(def, params, _engine()) and def.get("when", {}).has(index) and def.has("default"):
				params[int(def.index)] = int(def.default)
		_build.call_deferred()
		reset_size.call_deferred()


## True if the user changed something since open().
func is_changed() -> bool:
	return params != _initial or text != _initial_text


func _on_confirmed() -> void:
	if not inserting and not is_changed():
		return
	var result := params.duplicate()
	var sync: Variant = schema.get("sync")
	if sync is Callable and sync.is_valid():
		result = sync.call(result)
	applied.emit(result, text)
