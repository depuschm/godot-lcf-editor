extends SceneTree
## Smoke test: loads the demo project through the extension.
## Run: godot --headless --path . --script res://tests/test_load_demo.gd

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
	print("FAILED" if failed else "OK")
	quit(1 if failed else 0)
