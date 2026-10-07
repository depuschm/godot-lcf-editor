@tool
extends Control
## Tile palette: a grid of chipset tiles to paint with, six per row like RPG Maker.

signal tile_selected(tile_id: int)

const COLUMNS := 6
const TILE := 16
const SCALE := 2

var ids: Array[int] = []
var selected := -1
var texture: ImageTexture


func set_tiles(chipset: RefCounted, tile_ids: Array[int]) -> void:
	ids = tile_ids
	var rows := ceili(ids.size() / float(COLUMNS))
	var image := Image.create_empty(COLUMNS * TILE, maxi(rows, 1) * TILE, false, Image.FORMAT_RGBA8)
	if chipset:
		for i in ids.size():
			var tile: Image = chipset.render_tile(ids[i])
			image.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(i % COLUMNS, i / COLUMNS) * TILE)
	texture = ImageTexture.create_from_image(image)
	custom_minimum_size = Vector2(COLUMNS * TILE, maxi(rows, 1) * TILE) * SCALE
	if selected >= ids.size():
		selected = -1
	queue_redraw()


func select_tile(tile_id: int) -> void:
	selected = ids.find(tile_id)
	if selected < 0:
		selected = ids.find(_palette_entry_for(tile_id))
	queue_redraw()


func selected_tile() -> int:
	return ids[selected] if selected >= 0 else -1


# Autotiles appear once in the palette; any variant maps back to that entry.
func _palette_entry_for(tile_id: int) -> int:
	if tile_id >= 0 and tile_id < 3000:
		return (tile_id / 1000) * 1000
	if tile_id >= 3000 and tile_id < 4000:
		return 3000 + ((tile_id - 3000) / 50) * 50
	if tile_id >= 4000 and tile_id < 4600:
		return 4000 + ((tile_id - 4000) / 50) * 50 + 49
	return tile_id


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12))
	if texture:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, texture.get_size() * SCALE), false)
	if selected >= 0:
		var cell := Vector2(selected % COLUMNS, selected / COLUMNS) * TILE * SCALE
		draw_rect(Rect2(cell, Vector2.ONE * TILE * SCALE), Color.WHITE, false, 2.0)
		draw_rect(Rect2(cell + Vector2(2, 2), Vector2.ONE * (TILE * SCALE - 4)), Color.BLACK, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := Vector2i(event.position / (TILE * SCALE))
		var index := cell.y * COLUMNS + cell.x
		if cell.x >= 0 and cell.x < COLUMNS and index >= 0 and index < ids.size():
			selected = index
			queue_redraw()
			tile_selected.emit(ids[index])
			accept_event()
