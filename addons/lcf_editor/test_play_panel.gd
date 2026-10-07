@tool
extends VBoxContainer
## The "Test Play" bottom panel: Play / Stop, the Player's log, and the settings
## (EasyRPG Player program, title screen, extra options, the game's EasyRPG extensions).

## The user wants to play (the plugin saves and then calls TestPlay.start()).
signal play_requested

const TestPlay := preload("res://addons/lcf_editor/test_play.gd")

var test_play: TestPlay
var project: RefCounted  # LcfProject, for the per-game settings

var play_button: Button
var stop_button: Button
var status: Label
var log_view: TextEdit
var settings: ConfirmationDialog
var _path_edit: LineEdit
var _skip_title: CheckBox
var _options_edit: LineEdit
var _extensions: CheckBox
var _browse: FileDialog


func _init() -> void:
	name = "Test Play"
	custom_minimum_size = Vector2(0, 160)
	var bar := HBoxContainer.new()
	add_child(bar)
	play_button = Button.new()
	play_button.text = "▶ Test Play"
	play_button.tooltip_text = "Save and run the project in EasyRPG Player"
	play_button.pressed.connect(func() -> void: play_requested.emit())
	bar.add_child(play_button)
	stop_button = Button.new()
	stop_button.text = "■ Stop"
	stop_button.disabled = true
	bar.add_child(stop_button)
	var settings_button := Button.new()
	settings_button.text = "Settings…"
	settings_button.pressed.connect(open_settings)
	bar.add_child(settings_button)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	bar.add_child(status)
	var clear := Button.new()
	clear.text = "Clear log"
	clear.flat = true
	clear.pressed.connect(func() -> void: log_view.text = "")
	bar.add_child(clear)

	log_view = TextEdit.new()
	log_view.editable = false
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Monospace", "DejaVu Sans Mono", "Consolas", "Menlo"])
	log_view.add_theme_font_override("font", font)
	add_child(log_view)
	_build_settings()


## Connects the panel to a TestPlay node.
func attach(p_test_play: TestPlay) -> void:
	test_play = p_test_play
	stop_button.pressed.connect(test_play.stop)
	test_play.started.connect(func(pid: int) -> void:
		log_view.text = ""
		_update("Running (process %d). Close the game window or press Stop to end it." % pid))
	test_play.stopped.connect(func() -> void: _update("Stopped."))
	test_play.log_received.connect(_append)
	_update("" if test_play.check_player() == "" else test_play.check_player())


func _append(text: String) -> void:
	log_view.text += text
	log_view.scroll_vertical = log_view.get_line_count()


func show_message(text: String, is_error := false) -> void:
	_update(text)
	status.remove_theme_color_override("font_color")
	if is_error:
		status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))


func _update(text: String) -> void:
	var running := test_play != null and test_play.is_running()
	stop_button.disabled = not running
	status.text = text
	status.remove_theme_color_override("font_color")


# --- settings -----------------------------------------------------------------------

func _build_settings() -> void:
	settings = ConfirmationDialog.new()
	settings.title = "Test Play settings"
	settings.min_size = Vector2i(620, 0)
	settings.confirmed.connect(_apply_settings)
	add_child(settings)
	var box := VBoxContainer.new()
	settings.add_child(box)

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var path_label := Label.new()
	path_label.text = "EasyRPG Player"
	grid.add_child(path_label)
	var path_row := HBoxContainer.new()
	path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "Path of the Player program (Player.exe, easyrpg-player, …)"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path_edit)
	var browse_button := Button.new()
	browse_button.text = "Browse…"
	browse_button.pressed.connect(func() -> void: _browse.popup_centered_ratio(0.6))
	path_row.add_child(browse_button)
	grid.add_child(path_row)
	var options_label := Label.new()
	options_label.text = "Extra options"
	grid.add_child(options_label)
	_options_edit = LineEdit.new()
	_options_edit.placeholder_text = "e.g. --show-fps --scaling integer"
	grid.add_child(_options_edit)

	var link := LinkButton.new()
	link.text = "Download EasyRPG Player (free, for Windows, Linux, macOS, …)"
	link.uri = TestPlay.DOWNLOAD_URL
	box.add_child(link)
	_skip_title = CheckBox.new()
	_skip_title.text = "Skip the title screen (start a new game directly)"
	box.add_child(_skip_title)
	box.add_child(HSeparator.new())
	var game_label := Label.new()
	game_label.text = "This game"
	box.add_child(game_label)
	_extensions = CheckBox.new()
	_extensions.text = "Enable EasyRPG extensions (EasyRPG.ini), so @easyrpg_ comment commands run"
	box.add_child(_extensions)
	var note := Label.new()
	note.text = "Any [Patch] setting in EasyRPG.ini makes the Player skip its patch detection: a game that uses Maniacs or other patches must then list them there too."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(note)

	_browse = FileDialog.new()
	_browse.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_browse.access = FileDialog.ACCESS_FILESYSTEM
	_browse.title = "EasyRPG Player program"
	_browse.file_selected.connect(func(path: String) -> void: _path_edit.text = path)
	add_child(_browse)


func open_settings() -> void:
	if test_play:
		_path_edit.text = test_play.player_path
		var bundled: String = test_play.find_bundled_player()
		_path_edit.placeholder_text = ("Empty: use " + bundled) if bundled != "" else "Empty: use easyrpg-player/ in this Godot project"
		_skip_title.button_pressed = test_play.skip_title
		_options_edit.text = test_play.extra_options
	var has_project: bool = project != null and project.is_loaded()
	_extensions.disabled = not has_project
	_extensions.button_pressed = has_project and TestPlay.get_easyrpg_extensions(project.get_project_dir())
	settings.popup_centered()


func _apply_settings() -> void:
	if test_play:
		test_play.player_path = _path_edit.text.strip_edges()
		test_play.skip_title = _skip_title.button_pressed
		test_play.extra_options = _options_edit.text.strip_edges()
		test_play.save_settings()
		_update(test_play.check_player())
	if project != null and project.is_loaded():
		var dir: String = project.get_project_dir()
		if TestPlay.get_easyrpg_extensions(dir) != _extensions.button_pressed:
			TestPlay.set_easyrpg_extensions(dir, _extensions.button_pressed)
