@tool
extends RefCounted
## Pixel movement's editor logic, separate from the EditorPlugin so it can be tested:
## the game's settings (lcf-plugins/pixel_movement.json), event hitboxes (an
## "@pixel_hitbox x, y, w, h" comment at the top of an event page), the settings tab
## and the event editor's "Hitbox" panel.
##
## The runtime half (runtime/easyrpg-player in this repository) reads exactly these:
## the JSON file for the hero, the comment for events.

## The settings changed (enabled, hero hitbox).
signal settings_changed

const PLUGIN_ID := "pixel_movement"
const TILE := 16
const COMMENT := 12410
const COMMENT_2 := 22410
const DEFAULT_HERO := { "x": 2, "y": 4, "width": 12, "height": 12 }
const RUNTIME := "EasyRPG Player with the pixel movement patch (runtime/easyrpg-player)"

var api: Object  # LcfEditorAPI
## EditorUndoRedoManager for settings changes (null: no undo, e.g. in tests).
var undo_redo: Object


# --- settings ---------------------------------------------------------------------------

## { enabled: bool, hero: { x, y, width, height } } (defaults if nothing is stored).
func get_settings() -> Dictionary:
	var stored: Variant = api.get_plugin_data(PLUGIN_ID, {}) if api else {}
	var out := { "enabled": false, "hero": DEFAULT_HERO.duplicate() }
	if stored is Dictionary:
		out.enabled = bool(stored.get("enabled", false))
		var hero: Variant = stored.get("hero", {})
		if hero is Dictionary:
			for key in DEFAULT_HERO:
				out.hero[key] = int(hero.get(key, DEFAULT_HERO[key]))
	return out


## Stores the settings (with undo when an undo manager is set).
func change_settings(settings: Dictionary) -> void:
	var before := get_settings()
	if before == settings:
		return
	if undo_redo:
		undo_redo.create_action("Pixel movement settings")
		undo_redo.add_do_method(self, "apply_settings", settings)
		undo_redo.add_undo_method(self, "apply_settings", before)
		undo_redo.commit_action()
	else:
		apply_settings(settings)


func apply_settings(settings: Dictionary) -> void:
	if api and api.set_plugin_data(PLUGIN_ID, settings) != OK:
		push_error("Pixel movement: could not store the settings")
	settings_changed.emit()


# --- event hitboxes -----------------------------------------------------------------------

## The hitbox of an event page from its commands: { x, y, width, height } in pixels, or
## {} when the page has none (the whole tile).
static func hitbox_of(commands: Array) -> Dictionary:
	for command: Dictionary in commands:
		if command.code != COMMENT and command.code != COMMENT_2:
			break
		var parsed := LcfCommands.parse_comment(command.string)
		if parsed.name == "pixel_hitbox" and parsed.args.size() >= 4:
			var a: Array = parsed.args
			if a[0].is_valid_int() and a[1].is_valid_int() and a[2].is_valid_int() and a[3].is_valid_int():
				return { "x": int(a[0]), "y": int(a[1]), "width": maxi(1, int(a[2])), "height": maxi(1, int(a[3])) }
	return {}


## The commands with the page's hitbox comment replaced (or removed with an empty box).
static func with_hitbox(commands: Array, box: Dictionary) -> Array:
	var out := commands.duplicate(true)
	# Remove an existing @pixel_hitbox among the leading comments (with its continuation lines).
	var i := 0
	while i < out.size() and (out[i].code == COMMENT or out[i].code == COMMENT_2):
		if out[i].code == COMMENT and LcfCommands.parse_comment(out[i].string).name == "pixel_hitbox":
			out.remove_at(i)
			while i < out.size() and out[i].code == COMMENT_2:
				out.remove_at(i)
			break
		i += 1
	if not box.is_empty():
		var text := "@pixel_hitbox %d, %d, %d, %d" % [box.x, box.y, box.width, box.height]
		out.insert(0, { "code": COMMENT, "indent": 0, "string": text, "parameters": PackedInt32Array() })
	return out


## Hitboxes of a map's events for drawing: [{ id, x, y, box, blocks }], using each
## event's first page (the editor cannot know which page will be active in the game).
func map_hitboxes(map_id: int) -> Array:
	var project: RefCounted = api.get_project() if api else null
	if project == null:
		return []
	var out := []
	for event: Dictionary in project.get_map(map_id).get("events", []):
		var box := hitbox_of(project.get_map_event_commands(map_id, event.id, 0))
		var xml: String = project.get_map_event_xml(map_id, event.id)
		var layer_at := xml.find("<layer>")
		var layer := int(xml.substr(layer_at + 7, 1)) if layer_at >= 0 else 1
		out.append({
			"id": event.id, "x": event.x, "y": event.y,
			"box": box if not box.is_empty() else { "x": 0, "y": 0, "width": TILE, "height": TILE },
			"custom": not box.is_empty(),
			"blocks": layer == 1,  # same layer as the hero
		})
	return out


# --- event editor panel ---------------------------------------------------------------------

## The event editor's "Hitbox" panel (see LcfEditorAPI.add_event_panel()).
func make_event_panel(context: Dictionary) -> Control:
	var editor: Object = context.editor
	var project: RefCounted = context.project
	var commands: Array = project.get_map_event_commands(context.map_id, context.event_id, context.page)
	var box := hitbox_of(commands)

	var panel := VBoxContainer.new()
	var info := Label.new()
	info.text = "With pixel movement, this page collides with the hero through this hitbox (pixels within its tile). Without one, the whole tile counts."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	panel.add_child(info)
	var custom := CheckBox.new()
	custom.text = "Custom hitbox for page %d" % (context.page + 1)
	custom.button_pressed = not box.is_empty()
	panel.add_child(custom)
	# Lambdas capture locals by value, so the edited box lives in a shared dictionary.
	var state := { "box": box if not box.is_empty() else { "x": 0, "y": 0, "width": TILE, "height": TILE } }
	var preview := HitboxPreview.new()
	preview.box = state.box
	var fields := _box_fields(state.box, func(changed: Dictionary) -> void:
		state.box = changed
		preview.box = changed
		preview.queue_redraw())
	panel.add_child(fields)
	panel.add_child(preview)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(func() -> void:
		var current: Array = project.get_map_event_commands(context.map_id, context.event_id, context.page)
		var target: Dictionary = state.box if custom.button_pressed else {}
		if hitbox_of(current) != target:
			editor.set_page_commands(with_hitbox(current, target), "Set event hitbox" if custom.button_pressed else "Remove event hitbox"))
	panel.add_child(apply)
	var sync := func(on: bool) -> void:
		fields.modulate.a = 1.0 if on else 0.4
		preview.custom = on
		preview.queue_redraw()
	custom.toggled.connect(sync)
	sync.call(custom.button_pressed)
	return panel


# --- settings tab ---------------------------------------------------------------------------

## The "Pixel Movement" tab of the LCF Editor screen.
func make_settings_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Pixel Movement"
	var title := Label.new()
	title.text = "Pixel movement (showcase plugin)"
	title.add_theme_font_size_override("font_size", 18)
	tab.add_child(title)
	var info := Label.new()
	info.text = "The hero walks in pixel steps instead of whole tiles and collides through a hitbox. Game logic stays tile based: the hero's tile is the one under the middle of its hitbox, so events, terrain and encounters work as before.\nThe game needs %s; other Players ignore these settings and play with tiles." % RUNTIME
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(480, 0)
	tab.add_child(info)
	var enabled := CheckBox.new()
	enabled.text = "Use pixel movement in this game"
	tab.add_child(enabled)
	var hero_label := Label.new()
	hero_label.text = "Hero hitbox (pixels within the hero's 16 × 16 tile):"
	tab.add_child(hero_label)
	var row := HBoxContainer.new()
	tab.add_child(row)
	var preview := HitboxPreview.new()
	preview.custom = true
	var state := { "hero": DEFAULT_HERO.duplicate() }  # shared with the lambdas below
	var fields := _box_fields(DEFAULT_HERO, func(changed: Dictionary) -> void:
		state.hero = changed
		preview.box = changed
		preview.queue_redraw())
	row.add_child(fields)
	row.add_child(preview)
	var apply := Button.new()
	apply.text = "Apply"
	apply.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab.add_child(apply)
	var status := Label.new()
	tab.add_child(status)

	var load_values := func() -> void:
		var s := get_settings()
		enabled.button_pressed = s.enabled
		state.hero = s.hero
		_set_box_fields(fields, s.hero)
		preview.box = s.hero
		preview.queue_redraw()
		status.text = "Stored in lcf-plugins/pixel_movement.json in the game folder." if api and api.get_project() else "Open a project first."
	apply.pressed.connect(func() -> void:
		change_settings({ "enabled": enabled.button_pressed, "hero": state.hero.duplicate() }))
	settings_changed.connect(load_values)
	tab.tree_exiting.connect(func() -> void:
		if settings_changed.is_connected(load_values):
			settings_changed.disconnect(load_values))
	tab.set_meta("reload", load_values)
	load_values.call()
	return tab


func _box_fields(box: Dictionary, on_change: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	var values := box.duplicate()
	grid.set_meta("values", values)  # kept in step by _set_box_fields()
	for key in ["x", "y", "width", "height"]:
		var label := Label.new()
		label.text = key.capitalize()
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.name = key
		spin.min_value = 1 if key in ["width", "height"] else -16
		spin.max_value = 32 if key in ["width", "height"] else 16
		spin.value = box[key]
		spin.value_changed.connect(func(v: float) -> void:
			values[key] = int(v)
			on_change.call(values.duplicate()))
		grid.add_child(spin)
	on_change.call(values.duplicate())
	return grid


func _set_box_fields(grid: GridContainer, box: Dictionary) -> void:
	var values: Dictionary = grid.get_meta("values")
	for key in ["x", "y", "width", "height"]:
		var spin: SpinBox = grid.get_node(key)
		spin.set_value_no_signal(box[key])
		values[key] = int(box[key])


## A tile at 8× with a hitbox in it.
class HitboxPreview:
	extends Control
	var box: Dictionary = { "x": 0, "y": 0, "width": 16, "height": 16 }
	var custom := true
	const SCALE := 6

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16) * SCALE + Vector2(2, 2)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ONE, Vector2(16, 16) * SCALE), Color(0.25, 0.45, 0.25))
		for i in range(1, 16):
			var c := Color(1, 1, 1, 0.08 if i % 4 else 0.2)
			draw_line(Vector2(1 + i * SCALE, 1), Vector2(1 + i * SCALE, 1 + 16 * SCALE), c)
			draw_line(Vector2(1, 1 + i * SCALE), Vector2(1 + 16 * SCALE, 1 + i * SCALE), c)
		var r := Rect2(Vector2(box.x, box.y) * SCALE + Vector2.ONE, Vector2(box.width, box.height) * SCALE)
		var color := Color(0.3, 0.85, 1.0) if custom else Color(1, 1, 1, 0.4)
		draw_rect(r, Color(color, 0.3))
		draw_rect(r, color, false, 2.0)
		draw_rect(Rect2(Vector2.ONE, Vector2(16, 16) * SCALE), Color(1, 1, 1, 0.6), false, 1.0)
