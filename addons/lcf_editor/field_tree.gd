@tool
extends Tree
## Shows the fields of one liblcf structure (as XML from LcfProject) and lets the user
## edit them: double-click a field to change it. Used for database entries and for
## event pages. The owner decides where edits go by setting `setter`.

## A field was changed successfully.
signal field_changed(path: PackedInt32Array, tag: String, value: String)
## An edit could not be applied (bad input or rejected by liblcf).
signal edit_failed(message: String)

const CommandText := preload("res://addons/lcf_editor/command_text.gd")

## Fields that point into a database section, shown with the target's name.
const REFERENCES := {
	"class_id": "classes", "skill_id": "skills", "item_id": "items", "state_id": "states",
	"animation_id": "animations", "enemy_id": "enemies", "troop_id": "troops",
	"terrain_id": "terrains", "attribute_id": "attributes", "chipset_id": "chipsets",
	"actor_id": "actors", "switch_id": "switches", "variable_id": "variables",
	"switch_a_id": "switches", "switch_b_id": "switches",
	"weapon_id": "items", "shield_id": "items", "armor_id": "items", "helmet_id": "items",
	"accessory_id": "items", "unarmed_animation": "animations",
	"battler_animation": "battleranimations",
}

## Fields with named values, keyed by "Structure/field" (values from liblcf's enums).
const ENUMS := {
	"EventPage/trigger": ["Action Button", "Player Touch", "Event Touch", "Autorun", "Parallel Process"],
	"EventPage/move_type": ["Stay Still", "Random", "Up and Down", "Left and Right", "Toward Hero", "Away from Hero", "Custom Route"],
	"EventPage/layer": ["Below Hero", "Same as Hero", "Above Hero"],
	"EventPage/character_direction": ["Up", "Right", "Down", "Left"],
	"EventPage/character_pattern": ["Left", "Middle", "Right"],
	"EventPage/animation_type": ["Standing Animation", "Walking Animation", "Fixed Direction / Standing", "Fixed Direction / Walking", "Fixed Graphic", "Spin", "Step Frame Fix"],
	"EventPage/move_speed": { 1: "1: 1/8 Speed", 2: "2: 1/4 Speed", 3: "3: 1/2 Speed", 4: "4: Normal", 5: "5: 2x Speed", 6: "6: 4x Speed" },
	"EventPage/move_frequency": { 1: "1 (lowest)", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8 (highest)" },
	"EventPageCondition/compare_operator": ["=  equal to", "≥  at least", "≤  at most", ">  greater than", "<  less than", "≠  not equal to"],
	"CommonEvent/trigger": { 3: "Autorun", 4: "Parallel Process", 5: "Call", 6: "Battle Start (Maniacs)", 7: "Battle Parallel (Maniacs)" },
}
const LONG_LIST := 12

var project: RefCounted  # LcfProject
## Applies an edit: func(path: PackedInt32Array, value: String) -> String (error, or "").
var setter: Callable
var names_cache := {}  # section key -> { id: name }

var _names: LcfCommands.Names
var _edit_dialog: ConfirmationDialog
var _editing_item: TreeItem
var _editor_control: Control


func _init() -> void:
	columns = 2
	column_titles_visible = true
	set_column_title(0, "Field")
	set_column_title(1, "Value")
	set_column_expand_ratio(0, 2)
	set_column_expand_ratio(1, 3)
	hide_root = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_activated.connect(_on_item_activated)
	_edit_dialog = ConfirmationDialog.new()
	_edit_dialog.confirmed.connect(_on_edit_confirmed)
	add_child(_edit_dialog)


## Shows the children of `node` (from parse()). `base_path` is the path of `node` below
## the root element; field paths handed to `setter` are relative to the root.
## Child elements whose tag is in `hidden` are left out.
func show_node(node: Dictionary, base_path := PackedInt32Array(), hidden: Array = []) -> void:
	clear()
	_names = null
	var tree_root := create_item()
	if node.is_empty():
		return
	for i in node.children.size():
		if node.children[i].tag in hidden:
			continue
		_add_node(tree_root, node.children[i], base_path + PackedInt32Array([i]), node.tag)


## Forget cached names of a section (after one of its entries was renamed).
func invalidate_names(section := "") -> void:
	if section == "":
		names_cache.clear()
	else:
		names_cache.erase(section)


# --- XML to nodes: { tag, id, text, children } ----------------------------------

static func parse(xml: String) -> Dictionary:
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


## Child-element indices of a field, following tag names from `node`.
static func path_of(node: Dictionary, tags: Array) -> PackedInt32Array:
	var path := PackedInt32Array()
	for tag in tags:
		var found := false
		for i in node.children.size():
			if node.children[i].tag == tag:
				path.append(i)
				node = node.children[i]
				found = true
				break
		if not found:
			return PackedInt32Array()
	return path


static func node_at(node: Dictionary, path: PackedInt32Array) -> Dictionary:
	for i in path:
		if i < 0 or i >= node.children.size():
			return {}
		node = node.children[i]
	return node


# --- nodes to tree rows -----------------------------------------------------------

func _add_node(parent: TreeItem, node: Dictionary, path: PackedInt32Array, owner_tag: String) -> void:
	var item := create_item(parent)
	var children: Array = node.children
	if children.is_empty():
		item.set_text(0, node.tag)
		item.set_tooltip_text(0, node.tag)
		item.set_metadata(0, { "path": path, "tag": node.tag, "text": node.text, "owner": owner_tag })
		_show_value(item)
		return

	# A field holding exactly one structure (e.g. parameters → Parameters): skip a level.
	if children.size() == 1 and children[0].id == "" and _is_structure(children[0].tag):
		item.set_text(0, node.tag)
		for i in children[0].children.size():
			_add_node(item, children[0].children[i], path + PackedInt32Array([0, i]), children[0].tag)
		item.collapsed = children[0].children.size() > 8
		return

	if node.tag == "event_commands":
		item.set_text(0, "event_commands")
		item.set_text(1, "%d commands" % children.size())
		for command: Dictionary in children:
			_add_command(item, command)
		return

	if _is_structure(node.tag):  # a list element such as <Learning id="0001">
		item.set_text(0, "%s %s" % [node.tag, node.id] if node.id != "" else node.tag)
		item.set_text(1, _summary(node))
	else:
		item.set_text(0, node.tag)
		item.set_text(1, "%d entries" % children.size())
		item.collapsed = children.size() > 1
	for i in children.size():
		_add_node(item, children[i], path + PackedInt32Array([i]), node.tag)


func _is_structure(tag: String) -> bool:
	return tag != "" and tag[0] == tag[0].to_upper()


func _add_command(parent: TreeItem, command: Dictionary) -> void:
	var values := {}
	for f: Dictionary in command.children:
		values[f.tag] = f.text
	var params := PackedInt32Array()
	for part in String(values.get("parameters", "")).split(" ", false):
		params.append(int(part))
	var code := int(values.get("code", "0"))
	var line := CommandText.describe(project, code, values.get("string", ""), params)
	var full := { "code": code, "indent": int(values.get("indent", "0")), "string": values.get("string", ""), "parameters": params }
	var schema := LcfCommands.schema_for(full)
	if not schema.is_empty():
		if _names == null:
			_names = LcfCommands.Names.new(project)
		line.name = schema.name
		line.detail = LcfCommands.summary(schema, full, _names)
	var item := create_item(parent)
	item.set_text(0, "  ".repeat(int(values.get("indent", "0"))) + line.name)
	item.set_tooltip_text(0, line.name)
	item.set_text(1, line.detail)
	item.set_tooltip_text(1, line.detail)


func _summary(node: Dictionary) -> String:
	for child: Dictionary in node.children:
		if child.tag == "name" and child.text != "":
			return child.text
	return ""


func _enum_for(meta: Dictionary) -> Variant:
	return ENUMS.get("%s/%s" % [meta.get("owner", ""), meta.tag])


func _enum_items(choices: Variant) -> Dictionary:
	var out := {}
	if choices is Array:
		for i in choices.size():
			out[i] = choices[i]
	else:
		out = choices
	return out


func _format_value(meta: Dictionary) -> String:
	var tag: String = meta.tag
	var text: String = meta.text
	if text == "T":
		return "Yes"
	if text == "F":
		return "No"
	if text == "":
		return "—"
	var choices: Variant = _enum_for(meta)
	if choices != null and text.is_valid_int():
		var label: String = _enum_items(choices).get(int(text), "")
		if label != "":
			return label
	if " " in text and text.replace(" ", "").replace("-", "").is_valid_int():
		var numbers := text.split(" ")
		if numbers.size() > LONG_LIST:
			return "%d values: %s, …" % [numbers.size(), ", ".join(numbers.slice(0, 8))]
		return ", ".join(numbers)
	if text.is_valid_int() and REFERENCES.has(tag) and int(text) > 0 and project:
		var target := name_of(REFERENCES[tag], int(text))
		if target != "":
			return "%s · %s" % [text, target]
	return text


## Name of entry `id` of a database section, e.g. name_of("switches", 3).
func name_of(section: String, id: int) -> String:
	if not names_cache.has(section):
		var names := {}
		for entry: Dictionary in project.get_database_entries(section):
			names[entry.id] = entry.name
		names_cache[section] = names
	return names_cache[section].get(id, "")


# --- editing ----------------------------------------------------------------------

func _show_value(item: TreeItem) -> void:
	var meta: Dictionary = item.get_metadata(0)
	item.set_text(1, _format_value(meta))
	item.set_tooltip_text(1, meta.text + "\n(double-click to edit)")


func _kind(text: String) -> String:
	if text == "T" or text == "F":
		return "bool"
	if text.is_valid_int():
		return "int"
	if " " in text and text.replace(" ", "").replace("-", "").is_valid_int():
		return "list"
	return "text"


func _on_item_activated() -> void:
	var item := get_selected()
	if item == null or not (item.get_metadata(0) is Dictionary) or not setter.is_valid():
		return
	_editing_item = item
	var meta: Dictionary = item.get_metadata(0)
	if _editor_control:
		_editor_control.queue_free()
	var choices: Variant = _enum_for(meta)
	if choices != null and meta.text.is_valid_int():
		var option := OptionButton.new()
		var items := _enum_items(choices)
		for value: int in items:
			option.add_item(items[value], value)
		if option.get_item_index(int(meta.text)) < 0:
			option.add_item("%s (unknown)" % meta.text, int(meta.text))
		option.select(option.get_item_index(int(meta.text)))
		_editor_control = option
	else:
		match _kind(meta.text):
			"bool":
				var box := CheckBox.new()
				box.text = "Yes"
				box.button_pressed = meta.text == "T"
				_editor_control = box
			"int":
				var spin := SpinBox.new()
				spin.allow_greater = true
				spin.allow_lesser = true
				spin.rounded = true
				spin.value = int(meta.text)
				_editor_control = spin
			_:
				if "\n" in meta.text:
					var area := TextEdit.new()
					area.text = meta.text
					area.custom_minimum_size = Vector2(420, 120)
					_editor_control = area
				else:
					var line := LineEdit.new()
					line.text = meta.text
					line.custom_minimum_size = Vector2(320, 0)
					line.text_submitted.connect(func(_t: String) -> void:
						_edit_dialog.hide()
						_on_edit_confirmed())
					_editor_control = line
	_edit_dialog.title = "Edit %s" % meta.tag
	_edit_dialog.add_child(_editor_control)
	_edit_dialog.popup_centered()
	if _editor_control is LineEdit:
		_editor_control.grab_focus()
		_editor_control.select_all()


func _on_edit_confirmed() -> void:
	if _editing_item == null or _editor_control == null:
		return
	var meta: Dictionary = _editing_item.get_metadata(0)
	var value: String
	if _editor_control is OptionButton:
		value = str(_editor_control.get_selected_id())
	elif _editor_control is CheckBox:
		value = "T" if _editor_control.button_pressed else "F"
	elif _editor_control is SpinBox:
		value = str(int(_editor_control.value))
	else:
		value = _editor_control.text
		if _kind(meta.text) == "list":
			var parts := PackedStringArray()
			for part in value.replace(",", " ").split(" ", false):
				if not part.is_valid_int():
					edit_failed.emit("“%s” is not a whole number" % part)
					return
				parts.append(str(int(part)))
			value = " ".join(parts)
	if value == meta.text:
		return
	var error: String = setter.call(meta.path, value)
	if error != "":
		edit_failed.emit("Could not set %s: %s" % [meta.tag, error])
		return
	meta.text = value
	_editing_item.set_metadata(0, meta)
	_show_value(_editing_item)
	field_changed.emit(meta.path, meta.tag, value)
