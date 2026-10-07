extends SceneTree
## Runtime test for the screen shader prototype (runtime/easyrpg-player): runs the
## demo in a patched EasyRPG Player with shaders chosen per map and by comment
## commands, and checks the colours of the shaded frames. Needs a display with
## OpenGL (e.g. xvfb-run with Mesa):
##   godot --headless --path . --script res://tests/test_shader_runtime.gd -- /path/to/patched/easyrpg-player
##
## The patched Player writes the shaded frame of game frame
## $EASYRPG_SHADER_CAPTURE_FRAME to $EASYRPG_SHADER_CAPTURE (a BMP); no file means
## that frame was drawn without a shader.

const TestPlay := preload("res://addons/lcf_editor/test_play.gd")
const EXAMPLES := "res://addons/lcf_shaders/examples"

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

	var plain := _scenario("identity", { "maps": { "1": { "shader": "identity" } } })
	_check(plain.ok and plain.green > 0.3, "a pass-through shader shows the map as it is (green grass): %s" % _brief(plain))

	var sepia := _scenario("sepia", { "maps": { "1": { "shader": "sepia" } } })
	_check(sepia.ok and sepia.not_sepia < 0.01 and sepia.green == 0.0, "the map's shader (sepia) colours the whole frame: %s" % _brief(sepia))

	var night := _scenario("night-default", { "default": { "shader": "night" }, "maps": {} })
	_check(night.ok and night.mean.b > night.mean.r and night.mean.v < plain.mean.v * 0.75, "the default shader applies to maps without their own (night: darker and bluer): %s" % _brief(night))

	var params := _scenario("params", { "maps": { "1": { "shader": "sepia", "params": { "amount": 0.0 } } } })
	_check(params.ok and params.green > 0.3, "parameters from the settings reach the shader (sepia amount 0): %s" % _brief(params))

	var none := _scenario("none", { "default": { "shader": "sepia" }, "maps": { "1": { "shader": "none" } } })
	_check(not none.ok, "\"none\" turns the default off for a map (nothing shaded, no capture)")

	var switched := _scenario("command", { "maps": { "1": { "shader": "identity" } } }, ['@shader "sepia"'])
	_check(switched.ok and switched.not_sepia < 0.01, "@shader switches the shader in the game: %s" % _brief(switched))

	var cleared := _scenario("clear-command", { "maps": { "1": { "shader": "identity" } } }, ['@shader "sepia"', '@shader ""'])
	_check(cleared.ok and cleared.green > 0.3, "@shader \"\" goes back to the map's shader: %s" % _brief(cleared))

	var param_cmd := _scenario("param-command", { "maps": { "1": { "shader": "sepia" } } }, ['@shader_param "amount", 0, 100'])
	_check(param_cmd.ok and param_cmd.green > 0.3, "@shader_param changes a parameter (amount 0/100): %s" % _brief(param_cmd))

	var broken := _scenario("broken", { "maps": { "1": { "shader": "broken" } } })
	_check(not broken.ok and "does not compile" in broken.log and broken.exit == 0, "a shader with errors is reported and the game runs without it (exit %d)" % broken.exit)

	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


## Runs the demo on map 1 with these shader settings (and comment commands in a
## parallel event) and returns statistics of the captured frame.
func _scenario(name: String, settings: Dictionary, commands: Array = []) -> Dictionary:
	var game := ProjectSettings.globalize_path("user://shader_runtime/" + name)
	_copy_demo(game)
	DirAccess.make_dir_recursive_absolute(game.path_join("Shader"))
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(EXAMPLES)):
		if file.ends_with(".glsl"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(EXAMPLES).path_join(file), game.path_join("Shader").path_join(file))
	_write(game.path_join("Shader/identity.glsl"), "vec4 effect(vec2 uv) {\n\treturn pixel(uv);\n}\n")
	_write(game.path_join("Shader/broken.glsl"), "vec4 effect(vec2 uv) {\n\treturn pixel(uv) * undefined_thing;\n}\n")
	DirAccess.make_dir_recursive_absolute(game.path_join("lcf-plugins"))
	_write(game.path_join("lcf-plugins/shaders.json"), JSON.stringify(settings))
	TestPlay.set_easyrpg_extensions(game, true)
	if not commands.is_empty():
		var project: RefCounted = ClassDB.instantiate("LcfProject")
		project.load(game)
		var id: int = project.add_map_event(1, 39, 0)
		var xml: String = project.get_map_event_xml(1, id)
		project.set_map_event_xml(1, id, xml.replace("<trigger>0</trigger>", "<trigger>4</trigger>"))
		var list := []
		for text: String in commands:
			list.append({ "code": 12410, "indent": 0, "string": text, "parameters": PackedInt32Array() })
		project.set_map_event_commands(1, id, 0, list)
		_check(project.save_map(1, "") == OK, "%s: test game prepared" % name)

	var replay_path := game.path_join("input.log")
	_write(replay_path, "H EasyRPG Player Recording\nV 2 test\nF 300,N0\n")
	var capture := game.path_join("capture.bmp")
	var log_path := game.path_join("player.log")
	OS.set_environment("EASYRPG_SHADER_CAPTURE", capture)
	OS.set_environment("EASYRPG_SHADER_CAPTURE_FRAME", "200")  # the map has faded in; the replay ends at 300
	var output := []
	var exit_code := OS.execute(_player, ["--project-path", game, "--window", "--no-audio", "--seed", "1",
		"--new-game", "--start-map-id", "1", "--start-position", "20", "17",
		"--replay-input", replay_path, "--log-file", log_path], output, true)
	OS.unset_environment("EASYRPG_SHADER_CAPTURE")
	OS.unset_environment("EASYRPG_SHADER_CAPTURE_FRAME")
	var result := { "ok": false, "exit": exit_code, "log": FileAccess.get_file_as_string(log_path) + "\n".join(output) }
	if not FileAccess.file_exists(capture):
		return result
	var image := Image.new()
	if image.load_bmp_from_buffer(FileAccess.get_file_as_bytes(capture)) != OK:
		return result
	result.merge(_stats(image), true)
	result.ok = true
	return result


## Share of green pixels (green clearly above red and blue), share of pixels that are
## not sepia toned (red >= green >= blue), and the mean colour.
func _stats(image: Image) -> Dictionary:
	var green := 0
	var not_sepia := 0
	var sum := Vector3()
	var count := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			var r := c.r8
			var g := c.g8
			var b := c.b8
			if g > r + 12 and g > b + 12:
				green += 1
			if r + 2 < g or g + 2 < b:
				not_sepia += 1
			sum += Vector3(r, g, b)
			count += 1
	var mean := sum / maxi(1, count)
	return { "green": float(green) / count, "not_sepia": float(not_sepia) / count,
		"mean": { "r": mean.x, "g": mean.y, "b": mean.z, "v": (mean.x + mean.y + mean.z) / 3.0 },
		"size": image.get_size() }


func _brief(result: Dictionary) -> String:
	if not result.get("ok", false):
		return "no frame captured (exit %s) %s" % [result.get("exit"), String(result.get("log", "")).right(300)]
	var m: Dictionary = result.mean
	return "%d%% green, %d%% not sepia, mean rgb %d %d %d" % [roundi(result.green * 100), roundi(result.not_sepia * 100), m.r, m.g, m.b]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _copy_demo(game: String) -> void:
	var demo := ProjectSettings.globalize_path("res://demo")
	DirAccess.make_dir_recursive_absolute(game)
	for sub in ["", "lcf-plugins", "Shader"]:
		var dir := game.path_join(sub)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
	for f in DirAccess.get_files_at(demo):
		DirAccess.copy_absolute(demo.path_join(f), game.path_join(f))
	for folder in DirAccess.get_directories_at(demo):
		DirAccess.make_dir_recursive_absolute(game.path_join(folder))
		for f in DirAccess.get_files_at(demo.path_join(folder)):
			DirAccess.copy_absolute(demo.path_join(folder).path_join(f), game.path_join(folder).path_join(f))
