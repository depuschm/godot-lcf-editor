@tool
extends LcfMapTool
## The "Hitboxes" map tool: shows the hitboxes of the map's events (blocking ones in
## blue, others grey; custom ones filled) and, under the mouse, the hero's hitbox.

var logic: RefCounted  # pixel_movement.gd
var hover := Vector2i(-1, -1)
var _boxes: Array = []


func _init(p_logic: RefCounted = null) -> void:
	logic = p_logic
	name = "Hitboxes"
	tooltip = "Show pixel movement hitboxes (showcase plugin)"
	help = "Hitboxes: blue blocks the hero, grey does not; edit an event's hitbox in its Hitbox panel, the hero's in the Pixel Movement tab"


func refresh() -> void:
	_boxes = logic.map_hitboxes(get_map_id()) if logic and get_map_id() > 0 else []
	redraw()


func _activated() -> void:
	refresh()


func _map_shown(_map_id: int) -> void:
	refresh()


func _map_input(event: InputEvent, cell: Vector2i) -> bool:
	if event is InputEventMouseMotion and cell != hover:
		hover = cell
		redraw()
	return false


func _draw_map(canvas: CanvasItem, active: bool) -> void:
	if not active:
		return
	for entry: Dictionary in _boxes:
		var b: Dictionary = entry.box
		var r := Rect2(Vector2(entry.x * TILE + b.x, entry.y * TILE + b.y), Vector2(b.width, b.height))
		var color := Color(0.3, 0.8, 1.0) if entry.blocks else Color(0.75, 0.75, 0.75)
		canvas.draw_rect(r, Color(color, 0.35 if entry.custom else 0.12))
		canvas.draw_rect(r, color, false, 1.0)
	if is_on_map(hover):
		var hero: Dictionary = logic.get_settings().hero
		var r := Rect2(Vector2(hover * TILE) + Vector2(hero.x, hero.y), Vector2(hero.width, hero.height))
		canvas.draw_rect(r, Color(1.0, 0.85, 0.2, 0.3))
		canvas.draw_rect(r, Color(1.0, 0.85, 0.2), false, 1.0)
