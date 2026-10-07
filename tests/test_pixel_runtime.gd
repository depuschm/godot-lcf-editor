extends SceneTree
## Runtime test for the pixel movement prototype (runtime/easyrpg-player): plays
## scripted input in a patched EasyRPG Player and checks where the hero ends up.
## Run (needs a display, e.g. xvfb-run):
##   godot --headless --path . --script res://tests/test_pixel_runtime.gd -- /path/to/patched/easyrpg-player
##
## Each scenario copies the demo, writes lcf-plugins/pixel_movement.json, adds a
## parallel event that logs the hero's screen X and tile (Control Variables + the
## @easyrpg_output comment command), and replays key presses (--replay-input).

const TestPlay := preload("res://addons/lcf_editor/test_play.gd")

var _failures := 0
var _player := ""


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("Usage: ... -- /path/to/patched/easyrpg-player")
		quit(2)
		return
	_player = args[0]

	# Walking left along the path into the map's edge.
	var tile := await _scenario("edge-tile", false, Vector2i(2, 17), [[120, 170, "LEFT"]])
	var pixel := await _scenario("edge-pixel", true, Vector2i(2, 17), [[120, 170, "LEFT"]])
	_check(tile.get("x") == 0 and tile.get("sx") == 8, "tile movement stops on the edge tile: %s" % [_brief(tile)])
	_check(pixel.get("x") == 0 and pixel.get("sx") == 6, "pixel movement stops with the hitbox (2 px in) at the edge: sprite 2 px further left: %s" % [_brief(pixel)])

	# Walking right into the lake (water blocks): the hitbox's right edge stops at the shore.
	tile = await _scenario("lake-tile", false, Vector2i(1, 10), [[120, 170, "RIGHT"]])
	pixel = await _scenario("lake-pixel", true, Vector2i(1, 10), [[120, 170, "RIGHT"]])
	_check(tile.get("x") == 3 and tile.get("sx") == 56, "tile movement stops on the last land tile: %s" % [_brief(tile)])
	_check(pixel.get("x") == 3 and pixel.get("sx") == 58, "pixel movement walks on until the hitbox touches the water (2 px further): %s" % [_brief(pixel)])

	# Diagonal input: pixel movement moves on both axes, tile movement on one.
	tile = await _scenario("diagonal-tile", false, Vector2i(20, 20), [[120, 160, "RIGHT,DOWN"]])
	pixel = await _scenario("diagonal-pixel", true, Vector2i(20, 20), [[120, 160, "RIGHT,DOWN"]])
	_check(tile.get("x", 20) == 20 or tile.get("y", 20) == 20, "tile movement goes one way only: %s" % [_brief(tile)])
	_check(pixel.get("x", 20) > 20 and pixel.get("y", 20) > 20, "pixel movement goes diagonally: %s" % [_brief(pixel)])

	# Short taps: pixel movement stops between tiles.
	# Short taps near the left edge (where the camera stands still, so screen X shows
	# the hero's position): pixel movement stops between tiles.
	tile = await _scenario("tap-tile", false, Vector2i(2, 17), [[120, 123, "RIGHT"]])
	pixel = await _scenario("tap-pixel", true, Vector2i(2, 17), [[120, 123, "RIGHT"]])
	_check(tile.get("x") == 3 and tile.get("sx") == 56, "a tap moves a whole tile in tile movement: %s" % [_brief(tile)])
	_check(pixel.get("x") == 2 and pixel.get("sx") == 46, "and 3 frames × 2 px in pixel movement: %s" % [_brief(pixel)])

	# Events: a blocking event (whole tile), one with a thin hitbox, and Player Touch.
	var post := { "x": 5, "y": 17, "layer": 1, "trigger": 0, "commands": [] }
	tile = await _scenario("event-tile", false, Vector2i(2, 17), [[120, 170, "RIGHT"]], [post])
	pixel = await _scenario("event-pixel", true, Vector2i(2, 17), [[120, 170, "RIGHT"]], [post])
	_check(tile.get("x") == 4 and tile.get("sx") == 72, "tile movement stops in front of an event: %s" % [_brief(tile)])
	_check(pixel.get("x") == 4 and pixel.get("sx") == 74, "pixel movement stops where the hitboxes touch: %s" % [_brief(pixel)])
	var thin := post.duplicate()
	thin.commands = [_cmd(12410, "@pixel_hitbox 6, 0, 4, 16", [])]
	pixel = await _scenario("hitbox-pixel", true, Vector2i(2, 17), [[120, 170, "RIGHT"]], [thin])
	_check(pixel.get("sx") == 80, "an @pixel_hitbox comment makes the event's hitbox thinner (6 px closer): %s" % [_brief(pixel)])
	var touch := post.duplicate()
	touch.trigger = 1
	touch.commands = [_cmd(12410, '@easyrpg_output "info", "touched by the hero"', [])]
	pixel = await _scenario("touch-pixel", true, Vector2i(2, 17), [[120, 170, "RIGHT"]], [touch])
	_check("touched by the hero" in pixel.get("log", ""), "bumping into a Player Touch event starts it")

	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


## Runs one scenario and returns the hero's last logged { sx, x, y }.
func _scenario(name: String, pixel: bool, start: Vector2i, keys: Array, events: Array = []) -> Dictionary:
	var game := ProjectSettings.globalize_path("user://pixel_runtime/" + name)
	_copy_demo(game)
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	project.load(game)
	# A parallel process event that logs the hero's screen X and tile.
	var id: int = project.add_map_event(1, 39, 0)
	var xml: String = project.get_map_event_xml(1, id)
	project.set_map_event_xml(1, id, xml.replace("<trigger>0</trigger>", "<trigger>4</trigger>"))
	var output := LcfCommands.get_comment_schema("easyrpg_output")
	project.set_map_event_commands(1, id, 0, [
		_cmd(10220, "", [0, 1, 1, 0, 6, 10001, 4, 0]),  # V1 = hero screen X
		_cmd(10220, "", [0, 2, 2, 0, 6, 10001, 1, 0]),  # V2 = hero X
		_cmd(10220, "", [0, 3, 3, 0, 6, 10001, 2, 0]),  # V3 = hero Y
		_cmd(12410, '@easyrpg_output "info", "hero $1 $2 $3", V1, V2, V3', []),
		_cmd(11410, "", [1]),
	])
	for spec: Dictionary in events:
		var ev: int = project.add_map_event(1, spec.x, spec.y)
		var ev_xml: String = project.get_map_event_xml(1, ev)
		ev_xml = ev_xml.replace("<trigger>0</trigger>", "<trigger>%d</trigger>" % spec.trigger)
		ev_xml = ev_xml.replace("<layer>1</layer>", "<layer>%d</layer>" % spec.layer)
		project.set_map_event_xml(1, ev, ev_xml)
		project.set_map_event_commands(1, ev, 0, spec.commands)
	_check(project.save_map(1, "") == OK, "%s: test game prepared" % name)
	TestPlay.set_easyrpg_extensions(game, true)
	if pixel:
		DirAccess.make_dir_recursive_absolute(game.path_join("lcf-plugins"))
		var f := FileAccess.open(game.path_join("lcf-plugins/pixel_movement.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({ "enabled": true, "hero": { "x": 2, "y": 4, "width": 12, "height": 12 } }))
		f.close()

	var replay := "H EasyRPG Player Recording\nV 2 test\n"
	for k: Array in keys:
		for frame in range(k[0], k[1]):
			replay += "F %d,%s\n" % [frame, k[2]]
	replay += "F 200,N0\n"  # the map takes about a second to fade in; the replay ends here
	var replay_path := game.path_join("input.log")
	var rf := FileAccess.open(replay_path, FileAccess.WRITE)
	rf.store_string(replay)
	rf.close()

	var log_path := game.path_join("player.log")
	var output_lines := []
	var exit_code := OS.execute(_player, ["--project-path", game, "--window", "--no-audio", "--seed", "1",
		"--new-game", "--start-map-id", "1", "--start-position", str(start.x), str(start.y),
		"--replay-input", replay_path, "--log-file", log_path], output_lines, true)
	var log_text := FileAccess.get_file_as_string(log_path)
	var result := {}
	for line in log_text.split("\n"):
		var at := line.find("hero ")
		if at >= 0:
			var parts := line.substr(at + 5).split(" ")
			if parts.size() >= 3:
				result = { "sx": int(parts[0]), "x": int(parts[1]), "y": int(parts[2]) }
	result["log"] = log_text
	if not result.has("x"):
		print("        (exit %d) %s" % [exit_code, log_text.right(400)])
	return result


func _brief(result: Dictionary) -> String:
	return "screen x %s, tile (%s, %s)" % [result.get("sx"), result.get("x"), result.get("y")]


func _cmd(code: int, text: String, params: Array) -> Dictionary:
	return { "code": code, "indent": 0, "string": text, "parameters": PackedInt32Array(params) }


func _copy_demo(game: String) -> void:
	var demo := ProjectSettings.globalize_path("res://demo")
	DirAccess.make_dir_recursive_absolute(game.path_join("ChipSet"))
	for f in DirAccess.get_files_at(game):
		DirAccess.remove_absolute(game.path_join(f))
	var plugins := game.path_join("lcf-plugins")
	if DirAccess.dir_exists_absolute(plugins):
		for f in DirAccess.get_files_at(plugins):
			DirAccess.remove_absolute(plugins.path_join(f))
	for f in DirAccess.get_files_at(demo):
		DirAccess.copy_absolute(demo.path_join(f), game.path_join(f))
	for folder in DirAccess.get_directories_at(demo):
		DirAccess.make_dir_recursive_absolute(game.path_join(folder))
		for f in DirAccess.get_files_at(demo.path_join(folder)):
			DirAccess.copy_absolute(demo.path_join(folder).path_join(f), game.path_join(folder).path_join(f))
