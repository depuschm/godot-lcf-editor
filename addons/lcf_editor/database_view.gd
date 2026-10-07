@tool
extends HSplitContainer
## Read-only browser for the RPG Maker database: sections, entries and every field
## of the selected entry. Fields come from liblcf's own description of each entry
## (LcfProject.get_database_entry_xml), so all sections work without special code.

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

var current_section := ""
var current_entries: Array = []


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
	header = Label.new()
	header.text = "Open a project in the LCF Project dock."
	fields_box.add_child(header)
	fields = Tree.new()
	fields.columns = 2
	fields.column_titles_visible = true
	fields.set_column_title(0, "Field")
	fields.set_column_title(1, "Value")
	fields.set_column_expand_ratio(0, 2)
	fields.set_column_expand_ratio(1, 3)
	fields.hide_root = true
	fields.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fields_box.add_child(fields)


func set_project(p_project: RefCounted) -> void:
	project = p_project
	names_cache.clear()
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
	var index: int = entry_list.get_item_metadata(row)
	var xml: String = project.get_database_entry_xml(current_section, index)
	var root := _parse(xml)
	fields.clear()
	var tree_root := fields.create_item()
	header.text = entry_list.get_item_text(row)
	if root.is_empty():
		header.text += "  (could not read entry)"
		return
	for child: Dictionary in root.children:
		_add_node(tree_root, child)


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

func _add_node(parent: TreeItem, node: Dictionary) -> void:
	var item := fields.create_item(parent)
	var children: Array = node.children
	if children.is_empty():
		item.set_text(0, node.tag)
		item.set_tooltip_text(0, node.tag)
		item.set_text(1, _format_value(node.tag, node.text))
		item.set_tooltip_text(1, node.text)
		return

	# A field holding exactly one structure (e.g. parameters → Parameters): skip a level.
	if children.size() == 1 and children[0].id == "" and children[0].tag[0] == children[0].tag[0].to_upper():
		item.set_text(0, node.tag)
		for grandchild: Dictionary in children[0].children:
			_add_node(item, grandchild)
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
	for child: Dictionary in children:
		_add_node(item, child)


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
