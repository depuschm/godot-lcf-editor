extends SceneTree
## Smoke test: loads the demo project through the extension.
## Run: godot --headless --path . --script res://tests/test_load_demo.gd

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		printerr("FAIL: ", what)
		_failures += 1


func _init() -> void:
	var failed := false
	if not ClassDB.class_exists("LcfProject"):
		printerr("FAIL: LcfProject class missing - is the extension built?")
		quit(1)
		return

	var project: RefCounted = ClassDB.instantiate("LcfProject")
	if project.load("res://demo") != OK:
		printerr("FAIL: ", project.get_last_error())
		quit(1)
		return

	print("Title:    ", project.get_game_title())
	print("Engine:   RPG Maker ", project.get_engine())
	print("Encoding: ", project.get_encoding())
	print("Database: ", project.get_database_summary())
	for entry: Dictionary in project.get_map_tree():
		var line := "  ".repeat(entry.indentation) + "- %s [%s #%d]" % [entry.name, entry.type, entry.id]
		if entry.type == "map":
			var info: Dictionary = project.get_map_info(entry.id)
			if info.is_empty():
				printerr("FAIL: ", project.get_last_error())
				failed = true
			else:
				line += "  %dx%d, %d events" % [info.width, info.height, info.event_count]
		print(line)

	if project.get_game_title() != "LCF Editor Demo":
		printerr("FAIL: unexpected game title")
		failed = true

	# Map layers and events
	var map: Dictionary = project.get_map(1)
	var lower: PackedInt32Array = map.get("lower", PackedInt32Array())
	_check(map.get("width") == 40 and map.get("height") == 30, "map 1 is 40x30")
	_check(lower.size() == 40 * 30, "lower layer has one tile per cell")
	_check(Array(lower).any(func(id: int) -> bool: return id < 1000), "map 1 contains water")
	_check(Array(lower).any(func(id: int) -> bool: return id >= 4050 and id < 4100), "map 1 contains the dirt path autotile")
	_check(map.get("events", []).size() == 1 and map.events[0].name == "Sign", "map 1 has the sign event")

	# Chipset loading and tile composition
	var info: Dictionary = project.get_chipset(map.get("chipset_id", 0))
	var file: String = project.find_image("ChipSet", info.get("file", ""))
	_check(file.ends_with("Demo.png"), "chipset image is found")
	var chipset: RefCounted = ClassDB.instantiate("LcfChipset")
	_check(chipset.load(file) == OK, "chipset loads")
	if chipset.get_image():
		_check(chipset.get_image().get_size() == Vector2i(480, 256), "chipset is 480x256")
		_check(chipset.render_tile(10000).get_pixel(8, 8).a == 0.0, "upper tile 0 is transparent")
		_check(chipset.render_tile(5000).get_pixel(8, 8).a == 1.0, "lower tile 0 is opaque")
		var atlas: Dictionary = chipset.build_atlas(lower)
		_check(Array(lower).all(func(id: int) -> bool: return atlas.coords.has(id)), "atlas covers every tile of the map")

	# Database browser data
	var sections: Array = project.get_database_sections()
	_check(sections.size() == 19, "database has 19 sections")
	var actors: Array = project.get_database_entries("actors")
	_check(actors.size() == 2 and actors[0].name == "Hero", "actors are listed by name")
	var actor_xml: String = project.get_database_entry_xml("actors", 0)
	_check("<name>Hero</name>" in actor_xml, "actor XML names its fields")
	_check(project.get_event_command_name(10110) == "ShowMessage", "event command names resolve")
	var view: Node = load("res://addons/lcf_editor/database_view.gd").new()
	var parsed: Dictionary = view._parse(project.get_database_entry_xml("commonevents", 0))
	_check(parsed.get("tag") == "CommonEvent", "entry XML parses into a tree")
	var commands: Array = []
	for child: Dictionary in parsed.get("children", []):
		if child.tag == "event_commands":
			commands = child.children
	_check(commands.size() == 12, "common event has its 12 commands")
	view.free()

	failed = failed or _failures > 0
	print("FAILED" if failed else "OK")
	quit(1 if failed else 0)
