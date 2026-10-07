@tool
extends VBoxContainer
## Main-screen view of one RPG Maker map: lower and upper layer as TileMapLayers,
## events as markers. Wheel zooms, middle or right mouse button pans.

const TILE := 16
const ZOOM_STEPS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0, 6.0]

var project: RefCounted  # LcfProject
var map: Dictionary
var chipset: RefCounted  # LcfChipset

var title_label: Label
var zoom_label: Label
var status_label: Label
var events_toggle: CheckButton
var grid_toggle: CheckButton
var viewport_area: Control
var canvas: Node2D
var lower_layer: TileMapLayer
var upper_layer: TileMapLayer
var overlay: Node2D
var message: Label

var zoom_index := 2
var panning := false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	add_child(bar)
	title_label = Label.new()
	title_label.text = "No map open. Select one in the LCF Project dock."
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title_label)
	events_toggle = _toggle(bar, "Events", true)
	grid_toggle = _toggle(bar, "Grid", false)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "−" if step < 0 else "+"
		button.flat = true
		button.pressed.connect(_zoom_by.bind(step, Vector2.ZERO))
		bar.add_child(button)
	zoom_label = Label.new()
	bar.add_child(zoom_label)

	viewport_area = Control.new()
	viewport_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_area.clip_contents = true
	viewport_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport_area.gui_input.connect(_on_gui_input)
	add_child(viewport_area)

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

	status_label = Label.new()
	status_label.text = " "
	add_child(status_label)
	_update_zoom_label()


func _toggle(parent: Control, text: String, on: bool) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = on
	toggle.toggled.connect(func(_on: bool) -> void: overlay.queue_redraw())
	parent.add_child(toggle)
	return toggle


func show_map(p_project: RefCounted, map_id: int, map_name: String) -> void:
	project = p_project
	map = project.get_map(map_id)
	lower_layer.clear()
	upper_layer.clear()
	message.text = ""
	if map.is_empty():
		title_label.text = map_name
		message.text = "Could not load map:\n" + project.get_last_error()
		overlay.queue_redraw()
		return

	var info: Dictionary = project.get_chipset(map.chipset_id)
	title_label.text = "%s · Map%04d · %d×%d · chipset “%s”" % [
		map_name, map_id, map.width, map.height, info.get("name", "?")]

	chipset = ClassDB.instantiate("LcfChipset")
	var file: String = project.find_image("ChipSet", info.get("file", ""))
	if file == "" or chipset.load(file) != OK:
		message.text = "Chipset image “%s” not found in the project's ChipSet folder.\nRTP graphics are not supported yet." % info.get("file", "")
	else:
		_fill_layers()
	_fit_view()
	overlay.queue_redraw()


func _fill_layers() -> void:
	var ids := PackedInt32Array()
	ids.append_array(map.lower)
	ids.append_array(map.upper)
	var atlas: Dictionary = chipset.build_atlas(ids)
	var coords: Dictionary = atlas.coords

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

	var w: int = map.width
	for i in map.lower.size():
		var pos := Vector2i(i % w, i / w)
		lower_layer.set_cell(pos, 0, coords[map.lower[i]])
		upper_layer.set_cell(pos, 0, coords[map.upper[i]])


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


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(-1, event.position)
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			panning = event.pressed
	elif event is InputEventMouseMotion:
		if panning:
			canvas.position += event.relative
		_update_status(event.position)


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


func _update_status(mouse: Vector2) -> void:
	if map.is_empty():
		return
	var cell := Vector2i(((mouse - canvas.position) / canvas.scale.x / TILE).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= map.width or cell.y >= map.height:
		status_label.text = " "
		return
	var i: int = cell.y * map.width + cell.x
	var text := "(%d, %d)   lower %d   upper %d" % [cell.x, cell.y, map.lower[i], map.upper[i]]
	for event: Dictionary in map.events:
		if event.x == cell.x and event.y == cell.y:
			text += "   event %d “%s”" % [event.id, event.name]
	status_label.text = text
