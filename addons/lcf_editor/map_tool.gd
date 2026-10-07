@tool
class_name LcfMapTool
extends RefCounted
## Base class for map tools added by plugins (see LcfEditorAPI.add_map_tool()).
##
## A tool gets a button next to Lower layer / Upper layer / Events in the Map tab.
## While it is selected it receives the map's mouse and key input, and every tool can
## draw on top of the map. Override the methods you need:
##
##     class NotesTool extends LcfMapTool:
##         func _init() -> void:
##             name = "Notes"
##             help = "Click: add a note"
##
##         func _map_input(event: InputEvent, cell: Vector2i) -> bool:
##             if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
##                 print("clicked ", cell)
##                 return true
##             return false
##
##         func _draw_map(canvas: CanvasItem, active: bool) -> void:
##             canvas.draw_rect(cell_rect(Vector2i(2, 3)), Color.RED, false)
##
## Zooming and panning (wheel, middle mouse, Space + drag) stay with the map view.

## Size of one map cell in the coordinates _draw_map() draws in.
const TILE := 16

## Button text.
var name := "Tool"
## Button tooltip.
var tooltip := ""
## Status line text while the tool is selected.
var help := ""
## The editor API; set when the tool is added.
var api: Object  # LcfEditorAPI


## The tool was selected.
func _activated() -> void:
	pass


## Another tool or layer was selected.
func _deactivated() -> void:
	pass


## Mouse buttons (except wheel and middle), mouse motion and keys while the tool is
## selected. `cell` is the map cell under the mouse (it may lie outside the map).
## Return true if the tool used the event.
func _map_input(_event: InputEvent, _cell: Vector2i) -> bool:
	return false


## Draws on top of the map, in map pixels (one cell is TILE × TILE). Called for every
## tool whenever the map is redrawn; `active` tells if this tool is selected.
func _draw_map(_canvas: CanvasItem, _active: bool) -> void:
	pass


## A map was opened in the Map tab.
func _map_shown(_map_id: int) -> void:
	pass


# --- helpers -----------------------------------------------------------------------

## Asks the map to redraw (call after your data changed).
func redraw() -> void:
	if api:
		api.redraw_map()


## The ID of the open map (0 if none).
func get_map_id() -> int:
	return api.get_map_id() if api else 0


## True if `cell` is on the open map.
func is_on_map(cell: Vector2i) -> bool:
	var map: Dictionary = api.get_map() if api else {}
	return not map.is_empty() and cell.x >= 0 and cell.y >= 0 and cell.x < map.width and cell.y < map.height


## The map's zoom (1.0 = one map pixel per screen pixel). To draw crisp text, draw it
## with `canvas.draw_set_transform(at, 0.0, Vector2.ONE / get_zoom())` at screen size.
func get_zoom() -> float:
	return api.get_map_zoom() if api else 1.0


## The rectangle of a cell in _draw_map() coordinates.
func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * TILE, Vector2(TILE, TILE))
