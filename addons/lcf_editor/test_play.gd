@tool
extends Node
## Runs a project in EasyRPG Player (Test Play): builds the command line, starts and
## stops the Player process, and follows the Player's log file.
##
## The Player gets --test-play (debug mode: F9 debug menu, walk through walls with
## Ctrl) and --window. Its output is read live through a pipe; it also writes a log
## file (--log-file, in Godot's user folder), which is shown instead when the pipe stays
## empty (the Player writes that file in larger steps). Patch options are not passed: the
## Player detects the game's patches itself (any patch option would turn that off);
## games enable extra features in their EasyRPG.ini (see set_easyrpg_extensions()).

## The Player was started (process ID).
signal started(pid: int)
## The Player process ended (or was stopped).
signal stopped
## New lines in the Player's log.
signal log_received(text: String)

const DOWNLOAD_URL := "https://easyrpg.org/player/downloads/"
const SETTING_PATH := "lcf_editor/test_play/player_path"
const SETTING_SKIP_TITLE := "lcf_editor/test_play/skip_title"
const SETTING_OPTIONS := "lcf_editor/test_play/extra_options"

## Path of the EasyRPG Player executable.
var player_path := ""
## Start a new game directly instead of showing the title screen.
var skip_title := false
## More command line options, separated by spaces (e.g. "--show-fps").
var extra_options := ""
## Where the Player writes its log.
var log_path := ""

var pid := -1
var _log_offset := 0
var _poll := 0.0
var _pipes: Array[FileAccess] = []  # stdout and stderr of the Player
var _from_pipe := false             # the pipe delivered output: ignore the log file
var _ansi := RegEx.create_from_string("\u001b\\[[0-9;]*m")


func _init() -> void:
	log_path = ProjectSettings.globalize_path("user://test_play/player.log")


## Reads the settings from Godot's editor settings (in the editor only).
func load_settings() -> void:
	var settings := _editor_settings()
	if settings == null:
		return
	player_path = settings.get_setting(SETTING_PATH) if settings.has_setting(SETTING_PATH) else ""
	skip_title = settings.get_setting(SETTING_SKIP_TITLE) if settings.has_setting(SETTING_SKIP_TITLE) else false
	extra_options = settings.get_setting(SETTING_OPTIONS) if settings.has_setting(SETTING_OPTIONS) else ""


func save_settings() -> void:
	var settings := _editor_settings()
	if settings == null:
		return
	settings.set_setting(SETTING_PATH, player_path)
	settings.set_setting(SETTING_SKIP_TITLE, skip_title)
	settings.set_setting(SETTING_OPTIONS, extra_options)


func _editor_settings() -> Object:
	if not Engine.is_editor_hint() or not ClassDB.class_exists("EditorInterface"):
		return null
	return EditorInterface.get_editor_settings()


## The Player's command line for a project. `start` may hold { map_id, x, y } to
## start a new game there ("Play from here").
func build_args(project_dir: String, start := {}) -> PackedStringArray:
	var args := PackedStringArray(["--project-path", project_dir, "--test-play", "--window", "--no-log-color"])
	if not start.is_empty():
		args.append_array(["--new-game", "--start-map-id", str(start.map_id), "--start-position", str(start.x), str(start.y)])
	elif skip_title:
		args.append("--new-game")
	if log_path != "":
		args.append_array(["--log-file", log_path])
	for option in extra_options.split(" ", false):
		args.append(option)
	return args


## Why the Player cannot be started, or "" if it can.
func check_player() -> String:
	if player_path == "":
		return "Choose the EasyRPG Player program in the Test Play settings."
	if not FileAccess.file_exists(player_path):
		return "EasyRPG Player was not found at %s." % player_path
	return ""


func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


## Starts the Player on a project (stopping a running one first).
func start(project_dir: String, start_at := {}) -> Error:
	var problem := check_player()
	if problem != "":
		push_warning(problem)
		return ERR_FILE_NOT_FOUND
	stop()
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var log_file := FileAccess.open(log_path, FileAccess.WRITE)  # start with an empty log
	if log_file:
		log_file.close()
	_log_offset = 0
	_from_pipe = false
	_pipes.clear()
	var process := OS.execute_with_pipe(player_path, build_args(project_dir, start_at), false)
	pid = int(process.get("pid", -1))
	if pid <= 0:
		pid = -1
		return ERR_CANT_FORK
	for key in ["stdio", "stderr"]:
		if process.get(key) is FileAccess:
			_pipes.append(process[key])
	started.emit(pid)
	return OK


func stop() -> void:
	if is_running():
		OS.kill(pid)
	if pid > 0:
		pid = -1
		_read_output()
		_pipes.clear()
		stopped.emit()


func _process(delta: float) -> void:
	if pid <= 0:
		return
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	_read_output()
	if not OS.is_process_running(pid):
		pid = -1
		_read_output()
		_pipes.clear()
		stopped.emit()


func _read_output() -> void:
	var text := ""
	for pipe in _pipes:
		while true:
			var chunk := pipe.get_buffer(4096)
			if chunk.is_empty():
				break
			text += chunk.get_string_from_utf8()
	if text != "":
		_from_pipe = true
		log_received.emit(_ansi.sub(text, "", true))
	elif not _from_pipe:
		_read_log()


func _read_log() -> void:
	if not FileAccess.file_exists(log_path):
		return
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	if length < _log_offset:
		_log_offset = 0  # the file was started again
	if length == _log_offset:
		return
	file.seek(_log_offset)
	var text := file.get_buffer(length - _log_offset).get_string_from_utf8()
	_log_offset = length
	log_received.emit(_ansi.sub(text, "", true))


# --- EasyRPG.ini ------------------------------------------------------------------

## True if the game enables EasyRPG extensions ([Patch] EasyRPG=1 in EasyRPG.ini), which
## lets comment commands starting with @easyrpg_ run.
static func get_easyrpg_extensions(project_dir: String) -> bool:
	var path := _ini_path(project_dir)
	if path == "":
		return false
	var section := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var t := line.strip_edges()
		if t.begins_with("["):
			section = t.to_lower()
		elif section == "[patch]" and t.to_lower().replace(" ", "").begins_with("easyrpg="):
			return t.split("=", true, 1)[1].strip_edges() in ["1", "true", "True"]
	return false


## Turns EasyRPG extensions on or off in the game's EasyRPG.ini, keeping everything
## else in the file. Note that any [Patch] setting makes the Player skip its patch
## detection, so games using other patches (e.g. Maniacs) must list them there too.
static func set_easyrpg_extensions(project_dir: String, on: bool) -> Error:
	var path := _ini_path(project_dir)
	if path == "":
		path = project_dir.path_join("EasyRPG.ini")
	var lines := PackedStringArray()
	if FileAccess.file_exists(path):
		lines = FileAccess.get_file_as_string(path).replace("\r\n", "\n").split("\n")
		if not lines.is_empty() and lines[lines.size() - 1] == "":
			lines.remove_at(lines.size() - 1)
	var out := PackedStringArray()
	var section := ""
	var patch_found := false
	var written := false
	for line in lines:
		var t := line.strip_edges()
		if t.begins_with("["):
			if section == "[patch]" and on and not written:
				out.append("EasyRPG=1")
				written = true
			section = t.to_lower()
			patch_found = patch_found or section == "[patch]"
		elif section == "[patch]" and t.to_lower().replace(" ", "").begins_with("easyrpg="):
			if on and not written:
				out.append("EasyRPG=1")
				written = true
			continue
		out.append(line)
	if on and not written:
		if not patch_found:
			if not out.is_empty() and out[out.size() - 1].strip_edges() != "":
				out.append("")
			out.append("[Patch]")
		out.append("EasyRPG=1")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\r\n".join(out) + "\r\n")
	return OK


static func _ini_path(project_dir: String) -> String:
	for file in DirAccess.get_files_at(project_dir):
		if file.to_lower() == "easyrpg.ini":
			return project_dir.path_join(file)
	return ""
