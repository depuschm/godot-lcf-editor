@tool
extends LcfMapTool
## The "Notes" map tool: click a cell to add or edit its note, right-click to delete
## it. Notes are drawn as pins on every map; their text shows while the tool is selected.

## Asks the plugin to edit a note: (map_id, cell, current text).
signal edit_requested(map_id: int, cell: Vector2i, text: String)
## Asks the plugin to change a note with undo: (map_id, cell, new text; "" deletes).
signal change_requested(map_id: int, cell: Vector2i, text: String)

const PIN := Color(1.0, 0.78, 0.2)

var notes: RefCounted  # notes.gd
var hover := Vector2i(-1, -1)


func _init(p_notes: RefCounted = null) -> void:
	notes = p_notes
	name = "Notes"
	tooltip = "Pin notes to map cells (example plugin)"
	help = "Notes: click a cell to add or edit its note · right-click to delete it"


func _map_input(event: InputEvent, cell: Vector2i) -> bool:
	if event is InputEventMouseMotion:
		if cell != hover:
			hover = cell
			redraw()
		return false
	if not (event is InputEventMouseButton) or not event.pressed or not is_on_map(cell):
		return false
	var text: String = notes.get_note(get_map_id(), cell)
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			edit_requested.emit(get_map_id(), cell, text)
			return true
		MOUSE_BUTTON_RIGHT:
			if text != "":
				change_requested.emit(get_map_id(), cell, "")
			return true
	return false


func _deactivated() -> void:
	hover = Vector2i(-1, -1)


func _draw_map(canvas: CanvasItem, active: bool) -> void:
	var map_notes: Dictionary = notes.notes_of(get_map_id())
	var font := ThemeDB.fallback_font
	var zoom := get_zoom()
	for cell: Vector2i in map_notes:
		var r := cell_rect(cell)
		var corner := r.position + Vector2(TILE, 0)
		canvas.draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(-7, 0), corner + Vector2(0, 7)]), PIN)
		if active:
			canvas.draw_rect(r, PIN, false, 1.0)
			# The label is drawn at screen size, so it stays sharp at any zoom.
			var text: String = map_notes[cell]
			var size := 13
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			canvas.draw_set_transform(r.position + Vector2(TILE + 2, TILE / 2.0), 0.0, Vector2.ONE / zoom)
			canvas.draw_rect(Rect2(Vector2(-3, -size + 2), Vector2(width + 6, size + 4)), Color(0, 0, 0, 0.75))
			canvas.draw_string(font, Vector2(0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if active and is_on_map(hover):
		canvas.draw_rect(cell_rect(hover), Color(1, 1, 1, 0.8), false, 1.0)
