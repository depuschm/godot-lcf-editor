@tool
extends AcceptDialog
## Editor for one map event: its name, its pages (conditions, graphic, movement,
## trigger) and each page's command list. Every change goes straight into the project
## and is reported through `event_changed`, so the map view can record it for undo.
## Plugins add panels next to the command list (LcfEditorAPI.add_event_panel()).

## The event changed; `before` and `after` are the whole event as XML.
signal event_changed(action: String, event_id: int, before: String, after: String)

const FieldTree := preload("res://addons/lcf_editor/field_tree.gd")
const CommandList := preload("res://addons/lcf_editor/command_list.gd")

var project: RefCounted  # LcfProject
var map_id := 0
var event_id := 0
var page := 0
var xml := ""
var root: Dictionary

var name_edit: LineEdit
var position_label: Label
var tabs: TabBar
var fields: FieldTree
var commands: CommandList
var status: Label
var delete_page_button: Button
## Tabs on the right: the command list, then plugin panels.
var side: TabContainer
## Plugin panels: [{ title, factory }], shared with LcfEditorAPI.
var panels: Array = []
var _panel_controls: Array[Control] = []


func _init() -> void:
	title = "Event"
	min_size = Vector2i(860, 540)
	get_ok_button().text = "Close"
	exclusive = false
	var box := VBoxContainer.new()
	add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := Label.new()
	name_label.text = "Name"
	top.add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.text_submitted.connect(func(_t: String) -> void: _apply_name())
	name_edit.focus_exited.connect(_apply_name)
	top.add_child(name_edit)
	position_label = Label.new()
	top.add_child(position_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_button(top, "New page", func() -> void: _insert_page(-1))
	_button(top, "Copy page", func() -> void: _insert_page(page))
	delete_page_button = _button(top, "Delete page", _delete_page)

	tabs = TabBar.new()
	tabs.tab_changed.connect(func(index: int) -> void: _show_page(index))
	box.add_child(tabs)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	fields = FieldTree.new()
	fields.custom_minimum_size = Vector2(380, 0)
	fields.setter = _set_page_field
	fields.edit_failed.connect(func(message: String) -> void: _status(message, true))
	split.add_child(fields)
	side = TabContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(side)
	commands = CommandList.new()
	commands.name = "Commands"
	commands.commands_changed.connect(_on_commands_changed)
	side.add_child(commands)

	status = Label.new()
	status.text = "Changes apply immediately; undo them with Ctrl+Z in the map."
	box.add_child(status)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Opens the editor on an event; `p_page` selects a page.
func edit(p_project: RefCounted, p_map_id: int, p_event_id: int, p_page := 0) -> void:
	project = p_project
	map_id = p_map_id
	event_id = p_event_id
	fields.project = project
	commands.project = project
	fields.invalidate_names()
	reload(p_page)
	if not visible:
		popup_centered()


## Reads the event again (after undo/redo or outside changes). Closes if it is gone.
func reload(p_page := -1) -> void:
	xml = project.get_map_event_xml(map_id, event_id)
	if xml == "":
		hide()
		return
	root = FieldTree.parse(xml)
	var pages := _pages()
	var target := clampi(page if p_page < 0 else p_page, 0, maxi(pages.size() - 1, 0))
	title = "Event %04d · Map%04d" % [event_id, map_id]
	name_edit.text = _text_of(root, "name")
	position_label.text = "  at (%s, %s)" % [_text_of(root, "x"), _text_of(root, "y")]
	tabs.set_block_signals(true)  # adding tabs would select page 1 on the way
	tabs.clear_tabs()
	for i in pages.size():
		tabs.add_tab("Page %d" % (i + 1))
	if pages.size() > 0:
		tabs.current_tab = target
	tabs.set_block_signals(false)
	delete_page_button.disabled = pages.size() <= 1
	_show_page(target)


func _pages() -> Array:
	var path := FieldTree.path_of(root, ["pages"])
	return FieldTree.node_at(root, path).children if not path.is_empty() else []


func _text_of(node: Dictionary, tag: String) -> String:
	for child: Dictionary in node.children:
		if child.tag == tag:
			return child.text
	return ""


func _show_page(index: int) -> void:
	page = index
	var pages_path := FieldTree.path_of(root, ["pages"])
	var pages := _pages()
	if index < 0 or index >= pages.size():
		fields.clear()
		commands.set_commands([])
		return
	fields.show_node(pages[index], pages_path + PackedInt32Array([index]), ["event_commands"])
	commands.map_id = map_id
	commands.set_commands(project.get_map_event_commands(map_id, event_id, index))
	refresh_panels()


## Builds the plugin panels again for the current event and page. Each panel's factory
## gets { project, map_id, event_id, page, editor } and returns a Control (or null).
func refresh_panels() -> void:
	var current := side.get_tab_title(side.current_tab) if side.get_tab_count() > 0 else ""
	for control in _panel_controls:
		side.remove_child(control)
		control.queue_free()
	_panel_controls.clear()
	if project == null or xml == "":
		return
	var context := { "project": project, "map_id": map_id, "event_id": event_id, "page": page, "editor": self }
	for panel: Dictionary in panels:
		var factory: Callable = panel.factory
		if not factory.is_valid():
			continue
		var control: Variant = factory.call(context)
		if control is Control:
			control.name = String(panel.title).validate_node_name()
			side.add_child(control)
			side.set_tab_title(side.get_tab_idx_from_control(control), panel.title)
			_panel_controls.append(control)
	for i in side.get_tab_count():
		if side.get_tab_title(i) == current:
			side.current_tab = i


## Shows a tab on the right by its title ("Commands" or a plugin panel's title).
func show_panel(panel_title: String) -> void:
	for i in side.get_tab_count():
		if side.get_tab_title(i) == panel_title:
			side.current_tab = i


# --- changes ----------------------------------------------------------------------

func _changed(action: String, before: String) -> void:
	xml = project.get_map_event_xml(map_id, event_id)
	root = FieldTree.parse(xml)
	event_changed.emit(action, event_id, before, xml)
	_status("")


func _apply_name() -> void:
	if project == null or xml == "" or name_edit.text == _text_of(root, "name"):
		return
	var before := xml
	if project.set_map_event_field(map_id, event_id, FieldTree.path_of(root, ["name"]), name_edit.text) != OK:
		_status("Could not rename: " + project.get_last_error(), true)
		return
	_changed("Rename event", before)


func _set_page_field(path: PackedInt32Array, value: String) -> String:
	var before := xml
	if project.set_map_event_field(map_id, event_id, path, value) != OK:
		return project.get_last_error()
	_changed("Change event page", before)
	return ""


func _on_commands_changed(list: Array, action: String) -> void:
	set_page_commands(list, action)


## Replaces the shown page's command list (with undo); for plugin panels, e.g. to
## keep a settings comment at the top of the page. Returns OK or an error.
func set_page_commands(list: Array, action: String) -> Error:
	var before := xml
	if project.set_map_event_commands(map_id, event_id, page, list) != OK:
		_status(project.get_last_error(), true)
		return ERR_INVALID_PARAMETER
	_changed(action, before)
	commands.set_commands(project.get_map_event_commands(map_id, event_id, page))
	return OK


func _insert_page(copy_from: int) -> void:
	var before := xml
	var at := page + 1 if copy_from >= 0 else _pages().size()
	if project.insert_map_event_page(map_id, event_id, at, copy_from) != OK:
		_status(project.get_last_error(), true)
		return
	_changed("Copy event page" if copy_from >= 0 else "New event page", before)
	reload(at)


func _delete_page() -> void:
	var before := xml
	if project.remove_map_event_page(map_id, event_id, page) != OK:
		_status(project.get_last_error(), true)
		return
	_changed("Delete event page", before)
	reload(maxi(page - 1, 0))


func _status(message: String, is_error := false) -> void:
	status.text = message if message != "" else "Changes apply immediately; undo them with Ctrl+Z in the map."
	status.remove_theme_color_override("font_color")
	if is_error:
		status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
