extends SceneTree
## Tests the pixel movement plugin's editor half (addons/lcf_pixel_movement) on a copy
## of the demo: hitbox comments, the settings file the runtime reads, the event
## editor's Hitbox panel, the settings tab and the comment commands.
## Run: godot --headless --path . --script res://tests/test_pixel_movement.gd

const MapView := preload("res://addons/lcf_editor/map_view.gd")
const DatabaseView := preload("res://addons/lcf_editor/database_view.gd")
const Logic := preload("res://addons/lcf_pixel_movement/pixel_movement.gd")
const Plugin := preload("res://addons/lcf_pixel_movement/plugin.gd")
const HitboxTool := preload("res://addons/lcf_pixel_movement/hitbox_tool.gd")
const CommandText := preload("res://addons/lcf_editor/command_text.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _c(code: int, text := "", params := []) -> Dictionary:
	return { "code": code, "indent": 0, "string": text, "parameters": PackedInt32Array(params) }


func _run() -> void:
	# Hitbox comments.
	var page := [_c(12410, "Guard"), _c(22410, "stands still"), _c(10110, "Halt!")]
	_check(Logic.hitbox_of(page).is_empty(), "a page without @pixel_hitbox uses the whole tile")
	var boxed := Logic.with_hitbox(page, { "x": 4, "y": 6, "width": 8, "height": 10 })
	_check(boxed[0].string == "@pixel_hitbox 4, 6, 8, 10" and boxed.size() == 4, "a hitbox goes first, as a comment: %s" % boxed[0].string)
	_check(Logic.hitbox_of(boxed) == { "x": 4, "y": 6, "width": 8, "height": 10 }, "and reads back")
	var again := Logic.with_hitbox(boxed, { "x": 0, "y": 8, "width": 16, "height": 8 })
	_check(again.size() == 4 and Logic.hitbox_of(again).y == 8, "changing it replaces the comment")
	_check(Logic.with_hitbox(again, {}) == page, "removing it gives back the page")
	_check(Logic.hitbox_of([_c(10110, "x"), _c(12410, "@pixel_hitbox 1, 1, 1, 1")]).is_empty(), "only comments at the top of the page count (like the runtime)")

	# Comment commands.
	for schema in Plugin.schemas():
		LcfCommands.register(schema)
	var move := LcfCommands.get_comment_schema("pixel_move")
	_check(LcfCommands.encode_comment(move, PackedInt32Array([10001, 4, -2]), {}) == "@pixel_move 10001, 4, -2", "Move by Pixels is stored as @pixel_move")
	_check(CommandText.line(null, boxed[0]) == "◆Pixel Hitbox: X 4, Y 6, Width 8, Height 10", "the hitbox comment reads as a command: %s" % CommandText.line(null, boxed[0]))

	# A project, the API and the views.
	var work := ProjectSettings.globalize_path("user://pixel_movement_test")
	_copy_demo(work)
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	project.load(work)
	var main := TabContainer.new()
	main.size = Vector2(1200, 800)
	var map_view: Control = MapView.new()
	map_view.name = "Map"
	main.add_child(map_view)
	var db_view: Control = DatabaseView.new()
	db_view.name = "Database"
	main.add_child(db_view)
	root.add_child(main)
	await process_frame
	var api := LcfEditorAPI.new(null, main, map_view, db_view)
	api.set_project(project)
	api.open_map(3)  # Town

	# Settings: what the runtime reads.
	var logic: RefCounted = Logic.new()
	logic.api = api
	_check(logic.get_settings() == { "enabled": false, "hero": Logic.DEFAULT_HERO }, "defaults: off, hero hitbox 2, 4, 12 × 12")
	var tab: Control = logic.make_settings_tab()
	api.add_tab(tab, "Pixel Movement")
	var enabled: CheckBox = _find(tab, func(n: Node) -> bool: return n is CheckBox)
	var width: SpinBox = _find(tab, func(n: Node) -> bool: return n is SpinBox and n.name == "width")
	var apply: Button = _find(tab, func(n: Node) -> bool: return n is Button and n.text == "Apply")
	enabled.button_pressed = true
	width.value = 10
	apply.pressed.emit()
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(work.path_join("lcf-plugins/pixel_movement.json")))
	_check(stored is Dictionary and stored.enabled == true and int(stored.hero.width) == 10 and int(stored.hero.x) == 2, "the tab writes lcf-plugins/pixel_movement.json: %s" % [stored])
	var height: SpinBox = _find(tab, func(n: Node) -> bool: return n is SpinBox and n.name == "height")
	height.value = 9
	apply.pressed.emit()
	_check(logic.get_settings().hero == { "x": 2, "y": 4, "width": 10, "height": 9 }, "changing one field keeps the others")

	# The Hitbox panel in the event editor (Door B in the town).
	api.add_event_panel("Hitbox", logic.make_event_panel)
	map_view._edit_event(2)
	var editor: AcceptDialog = map_view.event_editor
	editor.show_panel("Hitbox")
	var panel: Control = editor._panel_controls[0]
	var custom: CheckBox = _find(panel, func(n: Node) -> bool: return n is CheckBox)
	var x_spin: SpinBox = _find(panel, func(n: Node) -> bool: return n is SpinBox and n.name == "x")
	var w_spin: SpinBox = _find(panel, func(n: Node) -> bool: return n is SpinBox and n.name == "width")
	var panel_apply: Button = _find(panel, func(n: Node) -> bool: return n is Button and n.text == "Apply")
	_check(not custom.button_pressed, "Door B has no custom hitbox yet")
	custom.button_pressed = true
	x_spin.value = 3
	w_spin.value = 10
	panel_apply.pressed.emit()
	var commands: Array = project.get_map_event_commands(3, 2, 0)
	_check(commands[0].string == "@pixel_hitbox 3, 0, 10, 16" and commands[1].code == 10110, "Apply puts the hitbox at the top of the page: %s" % commands[0].string)
	_check(editor.commands.list.get_item_text(0).begins_with("◆Pixel Hitbox"), "the command list shows it")
	panel = editor._panel_controls[0]
	custom = _find(panel, func(n: Node) -> bool: return n is CheckBox)
	_check(custom.button_pressed, "the rebuilt panel shows the custom hitbox")
	custom.button_pressed = false
	_find(panel, func(n: Node) -> bool: return n is Button and n.text == "Apply").pressed.emit()
	_check(project.get_map_event_commands(3, 2, 0)[0].code == 10110, "unchecking it removes the comment")
	editor.hide()

	# The map tool.
	project.set_map_event_commands(3, 3, 0, Logic.with_hitbox(project.get_map_event_commands(3, 3, 0), { "x": 4, "y": 2, "width": 8, "height": 14 }))
	var boxes: Array = logic.map_hitboxes(3)
	var villager: Dictionary = boxes.filter(func(b: Dictionary) -> bool: return b.id == 3)[0]
	_check(boxes.size() == 3 and villager.custom and villager.box.width == 8 and villager.blocks, "the map tool sees each event's hitbox: %s" % [villager])
	var tool: LcfMapTool = HitboxTool.new(logic)
	api.add_map_tool(tool)
	map_view._activate_tool(tool)
	await process_frame
	_check(tool._boxes.size() == 3, "activating the tool loads the boxes")

	api.shutdown()
	tab.free()  # shutdown only detaches plugin tabs; their owner frees them
	for schema in Plugin.schemas():
		LcfCommands.unregister_comment(schema.comment)
	api.free()
	main.queue_free()
	await process_frame
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _find(node: Node, test: Callable) -> Node:
	if test.call(node):
		return node
	for child in node.get_children():
		var found := _find(child, test)
		if found:
			return found
	return null


func _copy_demo(work: String) -> void:
	var demo := ProjectSettings.globalize_path("res://demo")
	DirAccess.make_dir_recursive_absolute(work.path_join("ChipSet"))
	for dir in [work, work.path_join("lcf-plugins")]:
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
	for f in DirAccess.get_files_at(demo):
		DirAccess.copy_absolute(demo.path_join(f), work.path_join(f))
	for f in DirAccess.get_files_at(demo.path_join("ChipSet")):
		DirAccess.copy_absolute(demo.path_join("ChipSet").path_join(f), work.path_join("ChipSet").path_join(f))
