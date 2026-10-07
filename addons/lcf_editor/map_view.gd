@tool
extends VBoxContainer
## Main-screen view and editor of one RPG Maker map: lower and upper layer as
## TileMapLayers, events as markers, a tile palette and painting tools.
##
## Left mouse paints with the current tool, right click picks the tile under the
## cursor, middle mouse (or Space + left mouse) pans, the wheel zooms. Holding Shift
## places the exact tile without autotiling. On the Events layer, clicks select, create,
## move and open events instead.

const TILE := 16
const ZOOM_STEPS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0, 6.0]
const TilePalette := preload("res://addons/lcf_editor/tile_palette.gd")
const EventEditor := preload("res://addons/lcf_editor/event_editor.gd")
const FieldTree := preload("res://addons/lcf_editor/field_tree.gd")
const PAINT_HELP := "Left: paint · Right: pick tile · Middle or Space+drag: pan · Wheel: zoom · Shift: exact tile (no autotiling)"
const EVENT_HELP := "Click: select event · Double-click: edit, or create on an empty cell · Drag: move · Right-click: menu · Del: delete · Ctrl+C / Ctrl+V: copy / paste"

enum Tool { PENCIL, RECTANGLE, FILL, PICK }
enum Layer { LOWER, UPPER, EVENTS }

var project: RefCounted  # LcfProject
var chipset: RefCounted  # LcfChipset
var undo_redo: Object    # EditorUndoRedoManager, set by the plugin
var map: Dictionary
var map_id := 0
var map_name := ""
var lower: PackedInt32Array
var upper: PackedInt32Array
var coords := {}  # tile id -> atlas cell
var round_trip_ok := true
var confirmed_maps := {}  # map id -> true once the user accepted a normalising save

var title_label: Label
var zoom_label: Label
var status_label: Label
var map_status: Label
var save_button: Button
var revert_button: Button
var events_toggle: CheckButton
var grid_toggle: CheckButton
var layer_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []
var viewport_area: Control
var canvas: Node2D
var lower_layer: TileMapLayer
var upper_layer: TileMapLayer
var overlay: Node2D
var message: Label
var palette: Control
var palette_scroll: ScrollContainer
var confirm_dialog: ConfirmationDialog
var event_editor: EventEditor
var event_menu: PopupMenu

var zoom_index := 2
var panning := false
var tool := Tool.PENCIL
var layer := Layer.LOWER
var selected_tile := {Layer.LOWER: 4049, Layer.UPPER: 10001}

# Current stroke
var painting := false
var last_cell := Vector2i(-1, -1)
var rect_start := Vector2i(-1, -1)
var rect_end := Vector2i(-1, -1)
var stroke_before := {}
var stroke_after := {}

# Events layer
var selected_event := -1      # event ID
var dragging_event := false
var drag_cell := Vector2i(-1, -1)
var menu_cell := Vector2i(-1, -1)
var event_clipboard := ""     # event XML


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	add_child(bar)
	title_label = Label.new()
	title_label.text = "No map open. Select one in the LCF Project dock."
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	bar.add_child(title_label)
	events_toggle = _toggle(bar, "Show events", true)
	grid_toggle = _toggle(bar, "Grid", false)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "−" if step < 0 else "+"
		button.flat = true
		button.pressed.connect(_zoom_by.bind(step, Vector2.ZERO))
		bar.add_child(button)
	zoom_label = Label.new()
	bar.add_child(zoom_label)

	var tools := HBoxContainer.new()
	add_child(tools)
	var layer_group := ButtonGroup.new()
	for entry in [["Lower layer", Layer.LOWER], ["Upper layer", Layer.UPPER], ["Events", Layer.EVENTS]]:
		layer_buttons.append(_choice(tools, entry[0], layer_group, _set_layer.bind(entry[1])))
	tools.add_child(VSeparator.new())
	var tool_group := ButtonGroup.new()
	for entry in [["Pencil", Tool.PENCIL], ["Rectangle", Tool.RECTANGLE], ["Fill", Tool.FILL], ["Pick", Tool.PICK]]:
		tool_buttons.append(_choice(tools, entry[0], tool_group, func() -> void: tool = entry[1]))
	layer_buttons[0].button_pressed = true
	tool_buttons[0].button_pressed = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	map_status = Label.new()
	tools.add_child(map_status)
	save_button = Button.new()
	save_button.text = "Save map"
	save_button.disabled = true
	save_button.pressed.connect(_on_save_pressed)
	tools.add_child(save_button)
	revert_button = Button.new()
	revert_button.text = "Revert"
	revert_button.disabled = true
	revert_button.pressed.connect(_on_revert_pressed)
	tools.add_child(revert_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	viewport_area = Control.new()
	viewport_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_area.clip_contents = true
	viewport_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport_area.focus_mode = Control.FOCUS_CLICK
	viewport_area.gui_input.connect(_on_gui_input)
	split.add_child(viewport_area)

	var background := ColorRect.new()
	background.color = Color(0.08, 0.08, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_area.add_child(background)

	canvas = Node2D.new()
	viewport_area.add_child(canvas)
	lower_layer = TileMapLayer.new()
	upper_layer = TileMapLayer.new()
	canvas.add_child(lower_layer)
	canvas.add_child(upper_layer)
	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	canvas.add_child(overlay)

	message = Label.new()
	message.set_anchors_preset(Control.PRESET_CENTER)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	viewport_area.add_child(message)

	palette_scroll = ScrollContainer.new()
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_scroll.custom_minimum_size = Vector2(TilePalette.COLUMNS * 16 * TilePalette.SCALE + 16, 0)
	palette_scroll.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	split.add_child(palette_scroll)
	palette = TilePalette.new()
	palette.tile_selected.connect(func(id: int) -> void: selected_tile[layer] = id)
	palette_scroll.add_child(palette)

	status_label = Label.new()
	status_label.text = PAINT_HELP
	status_label.clip_text = true
	add_child(status_label)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_autowrap = true
	confirm_dialog.min_size = Vector2i(480, 0)
	add_child(confirm_dialog)

	event_editor = EventEditor.new()
	event_editor.event_changed.connect(_on_event_edited)
	add_child(event_editor)
	event_menu = PopupMenu.new()
	event_menu.id_pressed.connect(_on_event_menu)
	add_child(event_menu)
	_update_zoom_label()


func _toggle(parent: Control, text: String, on: bool) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = on
	toggle.toggled.connect(func(_on: bool) -> void: overlay.queue_redraw())
	parent.add_child(toggle)
	return toggle


func _choice(parent: Control, text: String, group: ButtonGroup, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(action)
	parent.add_child(button)
	return button


# --- loading ----------------------------------------------------------------------

func show_map(p_project: RefCounted, p_map_id: int, p_map_name: String) -> void:
	project = p_project
	map_id = p_map_id
	map_name = p_map_name
	map = project.get_map(map_id)
	lower_layer.clear()
	upper_layer.clear()
	message.text = ""
	if map.is_empty():
		title_label.text = map_name
		message.text = "Could not load map:\n" + project.get_last_error()
		overlay.queue_redraw()
		_update_map_status()
		return
	lower = map.lower
	upper = map.upper
	selected_event = -1
	if event_editor.visible and event_editor.map_id != map_id:
		event_editor.hide()
	round_trip_ok = project.check_map_round_trip(map_id).get("identical", true)

	var info: Dictionary = project.get_chipset(map.chipset_id)
	title_label.text = "%s · Map%04d · %d×%d · chipset “%s”" % [
		map_name, map_id, map.width, map.height, info.get("name", "?")]

	chipset = ClassDB.instantiate("LcfChipset")
	var file: String = project.find_image("ChipSet", info.get("file", ""))
	if file == "" or chipset.load(file) != OK:
		chipset = null
		message.text = "Chipset image “%s” not found in the project's ChipSet folder.\nRTP graphics are not supported yet." % info.get("file", "")
	else:
		_build_tileset()
		_fill_layers()
	_set_layer(layer)
	_fit_view()
	overlay.queue_redraw()
	_update_map_status()


# Every tile ID the editor can produce, so atlas cells never have to move.
func _all_tile_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for type in 3:
		for deep in 16:
			for shore in 47:
				ids.append(type * 1000 + deep * 50 + shore)
	for animated in 3:
		ids.append(3000 + animated * 50)
	for block in 12:
		for pattern in 50:
			ids.append(4000 + block * 50 + pattern)
	for n in 144:
		ids.append(5000 + n)
		ids.append(10000 + n)
	ids.append_array(lower)
	ids.append_array(upper)
	return ids


func _build_tileset() -> void:
	var atlas: Dictionary = chipset.build_atlas(_all_tile_ids(), 0, 0, 64)
	coords = atlas.coords
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas.image)
	source.texture_region_size = Vector2i(TILE, TILE)
	for cell: Vector2i in coords.values():
		source.create_tile(cell)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	lower_layer.tile_set = tile_set
	upper_layer.tile_set = tile_set


func _fill_layers() -> void:
	var w: int = map.width
	for i in lower.size():
		var pos := Vector2i(i % w, i / w)
		lower_layer.set_cell(pos, 0, coords.get(lower[i], Vector2i.ZERO))
		upper_layer.set_cell(pos, 0, coords.get(upper[i], Vector2i.ZERO))


func _set_layer(value: Layer) -> void:
	layer = value
	var events_mode := layer == Layer.EVENTS
	palette_scroll.visible = not events_mode
	for button in tool_buttons:
		button.disabled = events_mode
	status_label.text = EVENT_HELP if events_mode else PAINT_HELP
	if events_mode:
		events_toggle.button_pressed = true
		upper_layer.modulate.a = 1.0
		overlay.queue_redraw()
		return
	if not chipset:
		palette.set_tiles(null, [])
		return
	var ids: Array[int] = []
	if layer == Layer.LOWER:
		ids.append_array([0, 1000, 2000, 3000, 3050, 3100])
		for block in 12:
			ids.append(4000 + block * 50 + 49)
		for n in 144:
			ids.append(5000 + n)
	else:
		for n in 144:
			ids.append(10000 + n)
	palette.set_tiles(chipset, ids)
	palette.select_tile(selected_tile[layer])
	upper_layer.modulate.a = 1.0 if layer == Layer.UPPER else 0.6


# --- painting ---------------------------------------------------------------------

func _cell_at(mouse: Vector2) -> Vector2i:
	return Vector2i(((mouse - canvas.position) / canvas.scale.x / TILE).floor())


func _inside(cell: Vector2i) -> bool:
	return not map.is_empty() and cell.x >= 0 and cell.y >= 0 and cell.x < map.width and cell.y < map.height


func _paint(cells: PackedInt32Array, exact: bool) -> void:
	if cells.is_empty() or not chipset or layer == Layer.EVENTS:
		return
	var change: Dictionary = project.paint_map_tiles(map_id, layer, cells, selected_tile[layer], not exact)
	var changed: PackedInt32Array = change.get("cells", PackedInt32Array())
	for i in changed.size():
		var cell: int = changed[i]
		if not stroke_before.has(cell):
			stroke_before[cell] = change.before[i]
		stroke_after[cell] = change.after[i]
	_show_tiles(layer, changed, change.get("after", PackedInt32Array()))


func _show_tiles(which: int, cells: PackedInt32Array, ids: PackedInt32Array) -> void:
	var w: int = map.width
	var target := lower_layer if which == Layer.LOWER else upper_layer
	for i in cells.size():
		var id: int = ids[i]
		if which == Layer.LOWER:
			lower[cells[i]] = id
		else:
			upper[cells[i]] = id
		target.set_cell(Vector2i(cells[i] % w, cells[i] / w), 0, coords.get(id, Vector2i.ZERO))


func _line(a: Vector2i, b: Vector2i) -> PackedInt32Array:
	var cells := PackedInt32Array()
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var t := 0.0 if steps == 0 else float(i) / steps
		var p := Vector2i(Vector2(a).lerp(Vector2(b), t).round())
		if _inside(p):
			cells.append(p.y * map.width + p.x)
	return cells


func _rect_cells(a: Vector2i, b: Vector2i) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			if _inside(Vector2i(x, y)):
				cells.append(y * map.width + x)
	return cells


# Autotiles count as one region per terrain (all water, or one ground autotile).
func _kind(id: int) -> int:
	if id >= 0 and id < 3000:
		return -1
	if id >= 4000 and id < 4600:
		return -2 - (id - 4000) / 50
	return id


func _fill_cells(start: Vector2i) -> PackedInt32Array:
	var tiles := lower if layer == Layer.LOWER else upper
	var w: int = map.width
	var target := _kind(tiles[start.y * w + start.x])
	var seen := {}
	var queue: Array[Vector2i] = [start]
	var cells := PackedInt32Array()
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if not _inside(p) or seen.has(p):
			continue
		seen[p] = true
		if _kind(tiles[p.y * w + p.x]) != target:
			continue
		cells.append(p.y * w + p.x)
		queue.append_array([p + Vector2i.LEFT, p + Vector2i.RIGHT, p + Vector2i.UP, p + Vector2i.DOWN])
	return cells


func _pick(cell: Vector2i) -> void:
	var id: int = (lower if layer == Layer.LOWER else upper)[cell.y * map.width + cell.x]
	selected_tile[layer] = id
	palette.select_tile(id)


func _begin_stroke() -> void:
	painting = true
	stroke_before.clear()
	stroke_after.clear()


func _end_stroke() -> void:
	painting = false
	rect_start = Vector2i(-1, -1)
	overlay.queue_redraw()
	if stroke_after.is_empty():
		return
	var cells := PackedInt32Array(stroke_after.keys())
	var before := PackedInt32Array()
	var after := PackedInt32Array()
	for cell in cells:
		before.append(stroke_before[cell])
		after.append(stroke_after[cell])
	if undo_redo:
		undo_redo.create_action("Paint map tiles")
		undo_redo.add_do_method(self, "apply_tiles", map_id, layer, cells, after)
		undo_redo.add_undo_method(self, "apply_tiles", map_id, layer, cells, before)
		undo_redo.commit_action(false)
	_update_map_status()


## Sets exact tiles (used by undo/redo).
func apply_tiles(p_map_id: int, which: int, cells: PackedInt32Array, ids: PackedInt32Array) -> void:
	project.set_map_tiles(p_map_id, which, cells, ids)
	if p_map_id == map_id and not map.is_empty():
		_show_tiles(which, cells, ids)
	_update_map_status()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var cell := _cell_at(event.position)
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(1, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(-1, event.position)
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
			MOUSE_BUTTON_RIGHT:
				if event.pressed and _inside(cell):
					if layer == Layer.EVENTS:
						_open_event_menu(cell, event.global_position)
					else:
						_pick(cell)
			MOUSE_BUTTON_LEFT:
				if Input.is_key_pressed(KEY_SPACE):
					panning = event.pressed
				elif layer == Layer.EVENTS:
					_on_event_click(cell, event)
				elif event.pressed and _inside(cell):
					_on_left_pressed(cell, event.shift_pressed)
				elif not event.pressed and painting:
					if tool == Tool.RECTANGLE and rect_start.x >= 0:
						_paint(_rect_cells(rect_start, rect_end), event.shift_pressed)
					_end_stroke()
		viewport_area.accept_event()
	elif event is InputEventMouseMotion:
		if panning:
			canvas.position += event.relative
		var cell := _cell_at(event.position)
		if dragging_event and _inside(cell) and cell != drag_cell:
			drag_cell = cell
			overlay.queue_redraw()
		if painting and cell != last_cell:
			if tool == Tool.PENCIL:
				_paint(_line(last_cell, cell), event.shift_pressed)
			elif tool == Tool.RECTANGLE:
				rect_end = Vector2i(clampi(cell.x, 0, map.width - 1), clampi(cell.y, 0, map.height - 1))
				overlay.queue_redraw()
			last_cell = cell
		_update_status(cell)
	elif event is InputEventKey and event.pressed and layer == Layer.EVENTS and selected_event > 0:
		if event.keycode == KEY_DELETE:
			_delete_event(selected_event)
			viewport_area.accept_event()
		elif event.keycode == KEY_C and event.is_command_or_control_pressed():
			event_clipboard = project.get_map_event_xml(map_id, selected_event)
			viewport_area.accept_event()
		elif event.keycode == KEY_ENTER:
			_edit_event(selected_event)
			viewport_area.accept_event()
	elif event is InputEventKey and event.pressed and layer == Layer.EVENTS and event.keycode == KEY_V and event.is_command_or_control_pressed():
		var cell := _cell_at(viewport_area.get_local_mouse_position())
		if _inside(cell):
			_paste_event(cell)
		viewport_area.accept_event()


func _on_left_pressed(cell: Vector2i, exact: bool) -> void:
	match tool:
		Tool.PICK:
			_pick(cell)
		Tool.PENCIL:
			_begin_stroke()
			last_cell = cell
			_paint(PackedInt32Array([cell.y * map.width + cell.x]), exact)
		Tool.RECTANGLE:
			_begin_stroke()
			rect_start = cell
			rect_end = cell
			last_cell = cell
			overlay.queue_redraw()
		Tool.FILL:
			_begin_stroke()
			_paint(_fill_cells(cell), exact)
			_end_stroke()


# --- events -----------------------------------------------------------------------

func _event_at(cell: Vector2i) -> Dictionary:
	for event: Dictionary in map.get("events", []):
		if event.x == cell.x and event.y == cell.y:
			return event
	return {}


func _on_event_click(cell: Vector2i, event: InputEventMouseButton) -> void:
	if event.pressed:
		var target := _event_at(cell) if _inside(cell) else {}
		if event.double_click:
			if target.is_empty():
				if _inside(cell):
					_new_event(cell)
			else:
				_edit_event(target.id)
			return
		selected_event = target.get("id", -1)
		dragging_event = selected_event > 0
		drag_cell = cell
		viewport_area.grab_focus()
		overlay.queue_redraw()
		_update_status(cell)
	elif dragging_event:
		dragging_event = false
		var moving := _event_by_id(selected_event)
		if not moving.is_empty() and _inside(drag_cell) and Vector2i(moving.x, moving.y) != drag_cell:
			if not _event_at(drag_cell).is_empty():
				_update_map_status("Another event is already there.", true)
			else:
				_move_event(selected_event, drag_cell)
		overlay.queue_redraw()


func _event_by_id(id: int) -> Dictionary:
	for event: Dictionary in map.get("events", []):
		if event.id == id:
			return event
	return {}


func _open_event_menu(cell: Vector2i, at: Vector2) -> void:
	menu_cell = cell
	var target := _event_at(cell)
	selected_event = target.get("id", -1)
	overlay.queue_redraw()
	event_menu.clear()
	if target.is_empty():
		event_menu.add_item("New event", 0)
		event_menu.add_item("Paste event", 3)
		event_menu.set_item_disabled(1, event_clipboard == "")
	else:
		event_menu.add_item("Edit event…", 1)
		event_menu.add_item("Copy event", 2)
		event_menu.add_separator()
		event_menu.add_item("Delete event", 4)
	event_menu.position = Vector2i(at)
	event_menu.reset_size()
	event_menu.popup()


func _on_event_menu(id: int) -> void:
	match id:
		0: _new_event(menu_cell)
		1: _edit_event(selected_event)
		2: event_clipboard = project.get_map_event_xml(map_id, selected_event)
		3: _paste_event(menu_cell)
		4: _delete_event(selected_event)


func _new_event(cell: Vector2i) -> void:
	var id: int = project.add_map_event(map_id, cell.x, cell.y)
	if id < 0:
		_update_map_status("Could not create event: " + project.get_last_error(), true)
		return
	_record_event("New event", id, "", project.get_map_event_xml(map_id, id))
	selected_event = id
	_edit_event(id)


func _paste_event(cell: Vector2i) -> void:
	if event_clipboard == "" or not _event_at(cell).is_empty():
		return
	var id: int = project.insert_map_event_xml(map_id, event_clipboard)
	if id < 0:
		_update_map_status("Could not paste event: " + project.get_last_error(), true)
		return
	var tree := FieldTree.parse(project.get_map_event_xml(map_id, id))
	project.set_map_event_field(map_id, id, FieldTree.path_of(tree, ["x"]), str(cell.x))
	project.set_map_event_field(map_id, id, FieldTree.path_of(tree, ["y"]), str(cell.y))
	_record_event("Paste event", id, "", project.get_map_event_xml(map_id, id))
	selected_event = id


func _move_event(id: int, cell: Vector2i) -> void:
	var before: String = project.get_map_event_xml(map_id, id)
	var tree := FieldTree.parse(before)
	project.set_map_event_field(map_id, id, FieldTree.path_of(tree, ["x"]), str(cell.x))
	project.set_map_event_field(map_id, id, FieldTree.path_of(tree, ["y"]), str(cell.y))
	_record_event("Move event", id, before, project.get_map_event_xml(map_id, id))


func _delete_event(id: int) -> void:
	var before: String = project.get_map_event_xml(map_id, id)
	if before == "" or project.delete_map_event(map_id, id) != OK:
		return
	_record_event("Delete event", id, before, "")
	selected_event = -1


func _edit_event(id: int) -> void:
	if id > 0:
		event_editor.edit(project, map_id, id)


func _on_event_edited(action: String, id: int, before: String, after: String) -> void:
	_record_event(action, id, before, after, false)


## Registers an event change that already happened, for undo/redo.
func _record_event(action: String, id: int, before: String, after: String, reload_editor := true) -> void:
	if undo_redo:
		undo_redo.create_action(action)
		undo_redo.add_do_method(self, "apply_event", map_id, id, after)
		undo_redo.add_undo_method(self, "apply_event", map_id, id, before)
		undo_redo.commit_action(false)
	_refresh_events(reload_editor)


## Puts an event into the given state: its XML, or "" for deleted (used by undo/redo).
func apply_event(p_map_id: int, id: int, xml: String) -> void:
	var exists: bool = project.get_map_event_xml(p_map_id, id) != ""
	if xml == "":
		if exists:
			project.delete_map_event(p_map_id, id)
	elif exists:
		project.set_map_event_xml(p_map_id, id, xml)
	else:
		project.insert_map_event_xml(p_map_id, xml)
	if p_map_id == map_id:
		_refresh_events(true)
	_update_map_status()


func _refresh_events(reload_editor: bool) -> void:
	if map.is_empty():
		return
	map.events = project.get_map(map_id).events
	if _event_by_id(selected_event).is_empty():
		selected_event = -1
	if reload_editor and event_editor.visible and event_editor.map_id == map_id:
		event_editor.reload()
	overlay.queue_redraw()
	_update_map_status()


# --- saving -----------------------------------------------------------------------

func _backup_dir() -> String:
	var dir: String = project.get_project_dir()
	return "user://backups/%s-%s" % [dir.get_file().validate_filename(), dir.md5_text().substr(0, 8)]


func _update_map_status(note := "", is_error := false) -> void:
	var modified: bool = project != null and map_id > 0 and project.is_map_modified(map_id)
	save_button.disabled = not modified
	revert_button.disabled = not modified
	map_status.text = note if note != "" else ("● Unsaved changes" if modified else "")
	map_status.remove_theme_color_override("font_color")
	if is_error:
		map_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))


func has_unsaved_maps() -> bool:
	return project != null and project.is_loaded() and not project.get_modified_maps().is_empty()


## Saves modified maps that save byte-identically or were confirmed; used when Godot saves everything.
func save_if_safe() -> void:
	if not has_unsaved_maps():
		return
	for id: int in project.get_modified_maps():
		if project.check_map_round_trip(id).get("identical", true) or confirmed_maps.has(id):
			project.save_map(id, _backup_dir())
	_update_map_status()


func _on_save_pressed() -> void:
	if round_trip_ok or confirmed_maps.has(map_id):
		_save()
		return
	confirm_dialog.title = "Save map?"
	confirm_dialog.dialog_text = "Saving will not reproduce Map%04d.lmu byte for byte: liblcf leaves out a few fields that hold default values. The current file is copied to a backup first. Save anyway?" % map_id
	_reconnect(func() -> void:
		confirmed_maps[map_id] = true
		_save())
	confirm_dialog.popup_centered()


func _save() -> void:
	if project.save_map(map_id, _backup_dir()) != OK:
		_update_map_status("Save failed: " + project.get_last_error(), true)
		return
	_update_map_status("Saved. Backup: " + project.get_last_backup().get_file())


func _on_revert_pressed() -> void:
	confirm_dialog.title = "Revert map?"
	confirm_dialog.dialog_text = "Discard all unsaved changes to this map?"
	_reconnect(func() -> void:
		project.revert_map(map_id)
		event_editor.hide()
		if undo_redo:
			undo_redo.clear_history()
		show_map(project, map_id, map_name)
		_update_map_status("Reverted to the saved file."))
	confirm_dialog.popup_centered()


func _reconnect(action: Callable) -> void:
	for connection in confirm_dialog.confirmed.get_connections():
		confirm_dialog.confirmed.disconnect(connection.callable)
	confirm_dialog.confirmed.connect(action, CONNECT_ONE_SHOT)


# --- view -------------------------------------------------------------------------

func _draw_overlay() -> void:
	if map.is_empty():
		return
	var map_px := Vector2(map.width, map.height) * TILE
	if grid_toggle.button_pressed:
		var line := Color(1, 1, 1, 0.15)
		for x in range(map.width + 1):
			overlay.draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, map_px.y), line)
		for y in range(map.height + 1):
			overlay.draw_line(Vector2(0, y * TILE), Vector2(map_px.x, y * TILE), line)
	overlay.draw_rect(Rect2(Vector2.ZERO, map_px), Color(1, 1, 1, 0.3), false)
	if events_toggle.button_pressed:
		for event: Dictionary in map.events:
			var r := Rect2(Vector2(event.x, event.y) * TILE + Vector2(1, 1), Vector2(TILE - 2, TILE - 2))
			overlay.draw_rect(r, Color(1, 1, 1, 0.25))
			overlay.draw_rect(r, Color(1, 1, 1, 0.9), false)
		var chosen := _event_by_id(selected_event)
		if layer == Layer.EVENTS and not chosen.is_empty():
			var r := Rect2(Vector2(chosen.x, chosen.y) * TILE, Vector2(TILE, TILE))
			overlay.draw_rect(r, Color(1.0, 0.85, 0.2, 0.35))
			overlay.draw_rect(r, Color(1.0, 0.85, 0.2), false, 2.0)
			if dragging_event and drag_cell != Vector2i(chosen.x, chosen.y):
				overlay.draw_rect(Rect2(Vector2(drag_cell) * TILE, Vector2(TILE, TILE)), Color(1.0, 0.85, 0.2), false, 1.0)
	if painting and tool == Tool.RECTANGLE and rect_start.x >= 0:
		var a := Vector2(mini(rect_start.x, rect_end.x), mini(rect_start.y, rect_end.y)) * TILE
		var b := Vector2(maxi(rect_start.x, rect_end.x) + 1, maxi(rect_start.y, rect_end.y) + 1) * TILE
		overlay.draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.2))
		overlay.draw_rect(Rect2(a, b - a), Color.WHITE, false, 1.0)


func _zoom_by(step: int, anchor: Vector2) -> void:
	if anchor == Vector2.ZERO:
		anchor = viewport_area.size / 2
	var new_index := clampi(zoom_index + step, 0, ZOOM_STEPS.size() - 1)
	if new_index == zoom_index:
		return
	var world := (anchor - canvas.position) / canvas.scale.x
	zoom_index = new_index
	canvas.scale = Vector2.ONE * ZOOM_STEPS[zoom_index]
	canvas.position = anchor - world * canvas.scale.x
	_update_zoom_label()


func _fit_view() -> void:
	if map.is_empty():
		return
	var map_size := Vector2(map.width, map.height) * TILE
	var area := viewport_area.size if viewport_area.size.x > 0 else Vector2(800, 600)
	zoom_index = 0
	for i in ZOOM_STEPS.size():
		if map_size.x * ZOOM_STEPS[i] <= area.x and map_size.y * ZOOM_STEPS[i] <= area.y:
			zoom_index = i
	canvas.scale = Vector2.ONE * ZOOM_STEPS[zoom_index]
	canvas.position = ((area - map_size * canvas.scale.x) / 2).floor()
	_update_zoom_label()


func _update_zoom_label() -> void:
	zoom_label.text = "%d%%" % int(ZOOM_STEPS[zoom_index] * 100)


func _update_status(cell: Vector2i) -> void:
	if not _inside(cell):
		return
	var i: int = cell.y * map.width + cell.x
	var text := "(%d, %d)   lower %d   upper %d" % [cell.x, cell.y, lower[i], upper[i]]
	for event: Dictionary in map.events:
		if event.x == cell.x and event.y == cell.y:
			text += "   event %d “%s”" % [event.id, event.name]
	status_label.text = text
