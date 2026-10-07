extends SceneTree
## Round-trip test for database editing and saving. Works on a copy of the project.
## Run: godot --headless --path . --script res://tests/test_roundtrip.gd -- [project_dir]
## Default project: res://demo

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var source: String = ProjectSettings.globalize_path(args[0] if args.size() > 0 else "res://demo")
	var work := ProjectSettings.globalize_path("user://roundtrip/project")
	var backups := ProjectSettings.globalize_path("user://roundtrip/backups")
	_clear(work.get_base_dir())
	DirAccess.make_dir_recursive_absolute(work)
	var ldb_name := ""
	for file in DirAccess.get_files_at(source):
		if file.get_extension().to_lower() in ["ldb", "lmt", "ini", "lmu"]:
			DirAccess.copy_absolute(source.path_join(file), work.path_join(file))
			if file.get_extension().to_lower() == "ldb":
				ldb_name = file
	print("Round trip on a copy of ", source)

	var project: RefCounted = ClassDB.instantiate("LcfProject")
	if project.load(work) != OK:
		printerr("FAIL: ", project.get_last_error())
		quit(1)
		return
	var original := FileAccess.get_file_as_bytes(work.path_join(ldb_name))
	var exported := work.get_base_dir().path_join("export.ldb")

	# 1. Untouched database writes back byte for byte (or the check says why not).
	_check(project.export_database(exported) == OK, "export works")
	var baseline := FileAccess.get_file_as_bytes(exported)
	var report: Dictionary = project.check_round_trip()
	_check(report.get("identical") == (baseline == original), "check_round_trip agrees with an actual export")
	if baseline == original:
		_check(true, "untouched database exports byte-identical (%d bytes)" % original.size())
	else:
		print("  note  saving normalises this database: %d -> %d bytes, first difference at byte %d" % [report.original_size, report.saved_size, report.first_difference])
		for note: String in report.notes:
			print("        liblcf: ", note)

	# 2. Every entry survives the XML round trip.
	var entries := 0
	var failed_entries: Array[String] = []
	for section: Dictionary in project.get_database_sections():
		for i in section.count:
			var xml: String = project.get_database_entry_xml(section.key, i)
			if project.set_database_entry_xml(section.key, i, xml) != OK:
				failed_entries.append("%s[%d]: %s" % [section.key, i, project.get_last_error()])
			entries += 1
	_check(failed_entries.is_empty(), "all %d entries parse back from XML %s" % [entries, failed_entries.slice(0, 3)])
	project.export_database(exported)
	_check(FileAccess.get_file_as_bytes(exported) == baseline, "XML round trip of every entry changes no byte")

	# 3. Broken input is rejected and changes nothing.
	project.revert_database()
	_check(project.set_database_entry_xml("actors", 0, "<Skill id=\"0001\"></Skill>") != OK, "wrong entry type is rejected")
	_check(not project.is_database_modified(), "rejected edit leaves the database unmodified")

	# 4. Field edits (top level, nested, special characters) save safely.
	if project.get_database_entries("actors").size() > 0:
		var view: Node = load("res://addons/lcf_editor/database_view.gd").new()
		var actor: Dictionary = view._parse(project.get_database_entry_xml("actors", 0))
		view.free()
		var name_path := _path_of(actor, ["name"])
		var title_path := _path_of(actor, ["title"])
		var weapon_path := _path_of(actor, ["initial_equipment", "Equipment", "weapon_id"])
		var old_name: String = project.get_database_entries("actors")[0].name
		var tricky := "A <b> & \"c\"\r\nnext line"
		var save_count_before := _save_count(project)
		_check(project.set_database_field("actors", 0, name_path, "Round Trip") == OK, "top-level field set: " + project.get_last_error())
		_check(project.set_database_field("actors", 0, title_path, tricky) == OK, "string with special characters set")
		_check(project.set_database_field("actors", 0, weapon_path, "2") == OK, "nested field set: " + project.get_last_error())
		_check(project.set_database_field("actors", 0, PackedInt32Array([9999]), "x") != OK, "unknown field path is rejected")
		_check(project.is_database_modified(), "database is marked modified")
		_check(project.save_database(backups) == OK, "save works: " + project.get_last_error())
		_check(not project.is_database_modified(), "database is clean after saving")
		var backup: String = project.get_last_backup()
		_check(FileAccess.file_exists(backup) and FileAccess.get_file_as_bytes(backup) == original, "backup holds the previous file")
		_check(not FileAccess.file_exists(work.path_join(ldb_name + ".tmp")), "no temporary file left behind")

		var reloaded: RefCounted = ClassDB.instantiate("LcfProject")
		reloaded.load(work)
		var saved: String = reloaded.get_database_entry_xml("actors", 0)
		_check(reloaded.get_database_entries("actors")[0].name == "Round Trip", "name edit is in the saved file (was “%s”)" % old_name)
		_check("<weapon_id>2</weapon_id>" in saved, "nested edit is in the saved file")
		var view2: Node = load("res://addons/lcf_editor/database_view.gd").new()
		var saved_title := _text_at(view2._parse(saved), title_path)
		view2.free()
		_check(saved_title == tricky, "special characters survive exactly")
		_check(_save_count(reloaded) == save_count_before + 1, "save counter went up by one")

	# 5. Maps: untouched maps export byte for byte; painting, undo and saving work.
	var map_ids: Array[int] = []
	for entry: Dictionary in project.get_map_tree():
		if entry.type == "map" and FileAccess.file_exists(work.path_join("Map%04d.lmu" % entry.id)):
			map_ids.append(entry.id)
	var exact := 0
	var normalised: Array[String] = []
	var map_export := work.get_base_dir().path_join("export.lmu")
	for id in map_ids:
		project.export_map(id, map_export)
		var same := FileAccess.get_file_as_bytes(map_export) == FileAccess.get_file_as_bytes(work.path_join("Map%04d.lmu" % id))
		var map_report: Dictionary = project.check_map_round_trip(id)
		if map_report.get("identical") != same:
			_check(false, "check_map_round_trip agrees with an export for map %d" % id)
		if same:
			exact += 1
		else:
			normalised.append("Map%04d" % id)
	_check(exact + normalised.size() == map_ids.size() and map_ids.size() > 0, "%d of %d maps export byte-identical" % [exact, map_ids.size()])
	if not normalised.is_empty():
		print("  note  saving normalises: ", ", ".join(normalised.slice(0, 8)), " …" if normalised.size() > 8 else "")

	if not map_ids.is_empty():
		var id: int = map_ids[0]
		var map: Dictionary = project.get_map(id)
		var w: int = map.width
		var h: int = map.height
		if w >= 7 and h >= 7:
			var path_before := FileAccess.get_file_as_bytes(work.path_join("Map%04d.lmu" % id))
			var cx := w / 2
			var cy := h / 2
			var cells := PackedInt32Array()
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					cells.append((cy + dy) * w + cx + dx)
			var change: Dictionary = project.paint_map_tiles(id, 0, cells, 0)
			var lower: PackedInt32Array = project.get_map(id).lower
			_check(lower[cy * w + cx] == 0, "painted lake: middle tile is open water")
			_check(lower[(cy - 1) * w + cx - 1] % 50 == 34, "painted lake: top-left corner has its shore (pattern 34)")
			_check(lower[(cy + 1) * w + cx] % 50 == 28, "painted lake: bottom edge has its shore (pattern 28)")
			_check(change.cells.size() >= 9, "%d tiles changed (9 painted + neighbours)" % change.cells.size())
			_check(project.is_map_modified(id), "map is marked modified")
			project.set_map_tiles(id, 0, change.cells, change.before)
			project.export_map(id, map_export)
			_check(FileAccess.get_file_as_bytes(map_export) == path_before or not normalised.is_empty(), "undo restores the map exactly")
			project.set_map_tiles(id, 0, change.cells, change.after)
			_check(project.save_map(id, backups) == OK, "map saves: " + project.get_last_error())
			_check(FileAccess.get_file_as_bytes(project.get_last_backup()) == path_before, "map backup holds the previous file")
			var again: RefCounted = ClassDB.instantiate("LcfProject")
			again.load(work)
			_check(again.get_map(id).lower[cy * w + cx] == 0, "painted tiles are in the saved map")

	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


# Child-element indices of a field, following tag names from the entry's root.
func _path_of(node: Dictionary, tags: Array) -> PackedInt32Array:
	var path := PackedInt32Array()
	for tag in tags:
		var children: Array = node.children
		for i in children.size():
			if children[i].tag == tag:
				path.append(i)
				node = children[i]
				break
	return path


func _text_at(node: Dictionary, path: PackedInt32Array) -> String:
	for i in path:
		node = node.children[i]
	return node.text


func _save_count(project: RefCounted) -> int:
	var xml: String = project.get_database_entry_xml("system", 0)
	var start := xml.find("<save_count>") + 12
	return int(xml.substr(start, xml.find("</save_count>") - start))


func _clear(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir in DirAccess.get_directories_at(path):
		_clear(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
