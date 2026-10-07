extends SceneTree
## Tests Test Play: the Player's command line, the per-game EasyRPG.ini setting, and
## (on Linux and macOS) starting, logging and stopping a process, with a small shell
## script standing in for EasyRPG Player.
## Run: godot --headless --path . --script res://tests/test_test_play.gd [-- /path/to/Player]
## With a real Player, the demo is test played for a few seconds.

const TestPlay := preload("res://addons/lcf_editor/test_play.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tp: TestPlay = TestPlay.new()
	root.add_child(tp)
	var dir := ProjectSettings.globalize_path("user://test_play_test")
	_clear(dir)
	DirAccess.make_dir_recursive_absolute(dir)

	# Command line.
	var args := tp.build_args("/games/demo")
	_check(args.slice(0, 4) == PackedStringArray(["--project-path", "/games/demo", "--test-play", "--window"]) and "--log-file" in args, "plays in test mode, windowed, with a log file: %s" % [args])
	_check(not "--new-game" in args and not args.has("--patch-easyrpg"), "shows the title and passes no patch options (the Player detects them)")
	tp.skip_title = true
	tp.extra_options = "--show-fps  --scaling integer"
	args = tp.build_args("/games/demo")
	_check("--new-game" in args and args.slice(-3) == PackedStringArray(["--show-fps", "--scaling", "integer"]), "skips the title and appends extra options")
	tp.skip_title = false
	tp.extra_options = ""
	args = tp.build_args("/games/demo", { "map_id": 3, "x": 9, "y": 11 })
	var at := args.find("--start-map-id")
	_check("--new-game" in args and at > 0 and args.slice(at, at + 5) == PackedStringArray(["--start-map-id", "3", "--start-position", "9", "11"]), "“Play from here” starts a new game on that map and cell")
	tp.player_path = ""
	_check(tp.check_player() != "", "without a Player it asks for one")
	tp.player_path = dir.path_join("missing-player")
	_check("not found" in tp.check_player() and tp.start(dir) != OK and not tp.is_running(), "a missing Player is reported, nothing starts")

	# EasyRPG.ini: EasyRPG extensions for comment commands.
	_check(not TestPlay.get_easyrpg_extensions(dir), "no EasyRPG.ini: extensions off")
	_check(TestPlay.set_easyrpg_extensions(dir, true) == OK and TestPlay.get_easyrpg_extensions(dir), "turning them on writes EasyRPG.ini")
	_check(FileAccess.get_file_as_string(dir.path_join("EasyRPG.ini")) == "[Patch]\r\nEasyRPG=1\r\n", "as [Patch] EasyRPG=1")
	var ini := FileAccess.open(dir.path_join("EasyRPG.ini"), FileAccess.WRITE)
	ini.store_string("[Game]\r\nNewGame=1\r\n\r\n[Patch]\r\nMANIAC=1\r\neasyrpg = 0\r\n\r\n[Other]\r\nX=y\r\n")
	ini.close()
	_check(not TestPlay.get_easyrpg_extensions(dir), "reads “easyrpg = 0” as off")
	TestPlay.set_easyrpg_extensions(dir, true)
	var text := FileAccess.get_file_as_string(dir.path_join("EasyRPG.ini"))
	_check(text == "[Game]\r\nNewGame=1\r\n\r\n[Patch]\r\nMANIAC=1\r\nEasyRPG=1\r\n\r\n[Other]\r\nX=y\r\n", "other settings stay as they are: %s" % text.c_escape())
	TestPlay.set_easyrpg_extensions(dir, false)
	_check(not TestPlay.get_easyrpg_extensions(dir) and "MANIAC=1" in FileAccess.get_file_as_string(dir.path_join("EasyRPG.ini")), "turning them off removes only that line")

	# A process standing in for the Player.
	var args_in := OS.get_cmdline_user_args()
	if args_in.size() > 0:
		await _real_player(tp, args_in[0])
	elif OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		await _fake_player(tp, dir)
	else:
		print("  skip  starting a process (needs a shell script; run with a real Player path instead)")

	tp.queue_free()
	await process_frame
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _fake_player(tp: TestPlay, dir: String) -> void:
	var script := dir.path_join("fake-player.sh")
	var file := FileAccess.open(script, FileAccess.WRITE)
	file.store_string("""#!/bin/sh
log=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--log-file" ]; then log="$2"; fi
  args="$args $1"; shift
done
echo "Player started with:$args" >> "$log"
sleep 0.5
echo "Info: easyrpg_output says hello" >> "$log"
sleep 1
echo "Info: live through the pipe" >&2
exec sleep 30
""")
	file.close()
	OS.execute("chmod", ["+x", script])
	tp.player_path = script
	var events := []
	tp.started.connect(func(pid: int) -> void: events.append("started"))
	tp.stopped.connect(func() -> void: events.append("stopped"))
	var log := [""]
	tp.log_received.connect(func(t: String) -> void: log[0] += t)
	_check(tp.start(dir, { "map_id": 2, "x": 4, "y": 5 }) == OK and tp.is_running(), "the Player process starts")
	await _wait_for(func() -> bool: return "hello" in log[0], 5.0)
	_check("--test-play" in log[0] and "--start-map-id 2 --start-position 4 5" in log[0], "it got the command line")
	_check("easyrpg_output says hello" in log[0], "its log file appears in the editor (while the pipe is quiet)")
	await _wait_for(func() -> bool: return "live through the pipe" in log[0], 3.0)
	_check("live through the pipe" in log[0], "and its output, live through a pipe")
	tp.stop()
	await _wait_for(func() -> bool: return not tp.is_running(), 3.0)
	_check(not tp.is_running() and events == ["started", "stopped"], "Stop ends it: %s" % [events])


# End to end with a real EasyRPG Player: a copy of the demo gets an autorun event that
# runs the Log Message comment command; its message must reach the Test Play log.
func _real_player(tp: TestPlay, player: String) -> void:
	var game := ProjectSettings.globalize_path("user://test_play_test/game")
	DirAccess.make_dir_recursive_absolute(game.path_join("ChipSet"))
	var demo := ProjectSettings.globalize_path("res://demo")
	for f in DirAccess.get_files_at(demo):
		DirAccess.copy_absolute(demo.path_join(f), game.path_join(f))
	for f in DirAccess.get_files_at(demo.path_join("ChipSet")):
		DirAccess.copy_absolute(demo.path_join("ChipSet").path_join(f), game.path_join("ChipSet").path_join(f))
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	project.load(game)
	var id: int = project.add_map_event(1, 0, 0)
	var xml: String = project.get_map_event_xml(1, id)
	project.set_map_event_xml(1, id, xml.replace("<trigger>0</trigger>", "<trigger>3</trigger>"))  # Autorun
	var message := "Hello from the LCF Editor"
	var output := LcfCommands.get_comment_schema("easyrpg_output")
	project.set_map_event_commands(1, id, 0, [
		{ "code": 12410, "indent": 0, "string": LcfCommands.encode_comment(output, PackedInt32Array(), { 0: "info", 1: message }), "parameters": PackedInt32Array() },
		{ "code": 12320, "indent": 0, "string": "", "parameters": PackedInt32Array() },  # Erase Event
	])
	var saved: Error = project.save_map(1, "")
	_check(saved == OK and id > 0, "demo copy gets an autorun event with Log Message (%s)" % project.get_last_error())
	TestPlay.set_easyrpg_extensions(game, true)

	tp.player_path = player
	tp.skip_title = true
	var log := [""]
	tp.log_received.connect(func(t: String) -> void: log[0] += t)
	_check(tp.start(game) == OK and tp.is_running(), "EasyRPG Player starts on it")
	await _wait_for(func() -> bool: return message in log[0] or not tp.is_running(), 15.0)
	_check(message in log[0], "the comment command ran in the Player and its message reached the log")
	_check(tp.is_running(), "the game keeps running")
	print("        log: ", log[0].strip_edges().replace("\n", "\n             "))
	if OS.get_environment("LCF_TEST_PLAY_KEEP") != "":
		await create_timer(float(OS.get_environment("LCF_TEST_PLAY_KEEP"))).timeout
	tp.stop()


func _wait_for(condition: Callable, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds and not condition.call():
		await create_timer(0.1).timeout
		waited += 0.1


func _clear(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_clear(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
