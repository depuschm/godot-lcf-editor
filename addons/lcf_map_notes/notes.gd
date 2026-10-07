@tool
extends RefCounted
## The notes of a project: on map cells { map_id: { Vector2i(x, y): text } } and on
## events { map_id: { event_id: text } }, stored through the LCF Editor's plugin data
## as lcf-plugins/map_notes.json in the RPG Maker project.

signal changed

const PLUGIN_ID := "map_notes"

var api: LcfEditorAPI
var _notes := {}
var _event_notes := {}


func load_from_project() -> void:
	_notes.clear()
	_event_notes.clear()
	var data: Variant = api.get_plugin_data(PLUGIN_ID, {}) if api else {}
	if data is Dictionary:
		for map_key: String in data.get("maps", {}):
			for note: Dictionary in data.maps[map_key]:
				_on_map(int(map_key))[Vector2i(int(note.x), int(note.y))] = String(note.text)
		for map_key: String in data.get("events", {}):
			for event_key: String in data.events[map_key]:
				_events_on(int(map_key))[int(event_key)] = String(data.events[map_key][event_key])
	changed.emit()


func get_note(map_id: int, cell: Vector2i) -> String:
	return _notes.get(map_id, {}).get(cell, "")


## Notes of one map: { Vector2i: text }.
func notes_of(map_id: int) -> Dictionary:
	return _notes.get(map_id, {})


## All notes, sorted by map: [{ map_id, cell, text }] for cells, then
## [{ map_id, event_id, text }] for events.
func all_notes() -> Array:
	var out := []
	var maps := _notes.keys() + _event_notes.keys().filter(func(id: int) -> bool: return not _notes.has(id))
	maps.sort()
	for map_id: int in maps:
		var cells: Array = _notes.get(map_id, {}).keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for cell: Vector2i in cells:
			out.append({ "map_id": map_id, "cell": cell, "text": _notes[map_id][cell] })
		var events: Array = _event_notes.get(map_id, {}).keys()
		events.sort()
		for event_id: int in events:
			out.append({ "map_id": map_id, "event_id": event_id, "text": _event_notes[map_id][event_id] })
	return out


## Sets a note ("" deletes it) and saves. Used directly by undo/redo.
func set_note(map_id: int, cell: Vector2i, text: String) -> void:
	if text == "":
		_on_map(map_id).erase(cell)
		if _notes[map_id].is_empty():
			_notes.erase(map_id)
	else:
		_on_map(map_id)[cell] = text
	_save()
	changed.emit()


func get_event_note(map_id: int, event_id: int) -> String:
	return _event_notes.get(map_id, {}).get(event_id, "")


## Sets an event's note ("" deletes it) and saves. Used directly by undo/redo.
func set_event_note(map_id: int, event_id: int, text: String) -> void:
	if text == "":
		_events_on(map_id).erase(event_id)
		if _event_notes[map_id].is_empty():
			_event_notes.erase(map_id)
	else:
		_events_on(map_id)[event_id] = text
	_save()
	changed.emit()


func _events_on(map_id: int) -> Dictionary:
	if not _event_notes.has(map_id):
		_event_notes[map_id] = {}
	return _event_notes[map_id]


func _on_map(map_id: int) -> Dictionary:
	if not _notes.has(map_id):
		_notes[map_id] = {}
	return _notes[map_id]


func _save() -> void:
	if api == null or api.get_project() == null:
		return
	var maps := {}
	for map_id: int in _notes:
		var list := []
		for cell: Vector2i in _notes[map_id]:
			list.append({ "x": cell.x, "y": cell.y, "text": _notes[map_id][cell] })
		maps[str(map_id)] = list
	var events := {}
	for map_id: int in _event_notes:
		var by_id := {}
		for event_id: int in _event_notes[map_id]:
			by_id[str(event_id)] = _event_notes[map_id][event_id]
		events[str(map_id)] = by_id
	var err := api.set_plugin_data(PLUGIN_ID, { "version": 1, "maps": maps, "events": events })
	if err != OK:
		push_error("Map Notes: could not save notes (%s)" % error_string(err))
