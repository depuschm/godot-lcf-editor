extends SceneTree
## Tests the event command schemas, the block structure rules and the command text.
## Run: godot --headless --path . --script res://tests/test_commands.gd -- [project_dir]
## With a project, every command of every event and common event is described and its
## block structure checked; the default is res://demo.

const Blocks := preload("res://addons/lcf_editor/command_blocks.gd")
const CommandText := preload("res://addons/lcf_editor/command_text.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _c(code: int, indent: int, text := "", params := []) -> Dictionary:
	return { "code": code, "indent": indent, "string": text, "parameters": PackedInt32Array(params) }


func _codes(list: Array) -> Array:
	return list.map(func(c: Dictionary) -> String: return "%d@%d" % [c.code, c.indent])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = ProjectSettings.globalize_path(args[0] if args.size() > 0 else "res://demo")
	var project: RefCounted = ClassDB.instantiate("LcfProject")
	_check(project.load(dir) == OK, "project loads: " + dir)
	_test_registry(project)
	_test_blocks()
	_test_comment_commands(project)
	_test_project(project)
	print("FAILED" if _failures > 0 else "OK")
	quit(1 if _failures > 0 else 0)


func _test_registry(project: RefCounted) -> void:
	LcfCommands.reset_builtins()
	var schemas := LcfCommands.get_schemas()
	_check(schemas.size() >= 20, "%d built-in command schemas" % schemas.size())
	var known := {}
	for code: int in project.get_event_command_codes():
		known[code] = true
	var unknown := schemas.filter(func(s: Dictionary) -> bool: return s.has("code") and not known.has(int(s.code)))
	_check(unknown.is_empty(), "every built-in schema is a command liblcf knows %s" % [unknown.map(func(s): return s.code)])
	_check(LcfCommands.get_schemas()[0].group == "Message", "schemas are ordered by group")

	var switches := LcfCommands.get_schema(10210)
	_check(LcfCommands.default_params(switches) == PackedInt32Array([0, 1, 0, 0]), "Control Switches defaults: one switch, #1, ON")
	var shown := LcfCommands.visible_params(switches, PackedInt32Array([1, 2, 5, 0]))
	_check(shown.map(func(d): return d.label) == ["Target", "First switch", "Last switch", "Set to"], "range target shows first and last switch")
	var synced: PackedInt32Array = switches.sync.call(PackedInt32Array([0, 7, 3, 1]))
	_check(synced == PackedInt32Array([0, 7, 7, 1]), "single switch stores its ID twice, as RPG Maker does")
	var teleport := LcfCommands.get_schema(10810)
	_check(LcfCommands.default_params(teleport, "2000").size() == 3 and LcfCommands.default_params(teleport, "2003").size() == 4, "Teleport's facing parameter is 2003-only")
	var branch := LcfCommands.get_schema(12010)
	var variable_vs_number := LcfCommands.visible_params(branch, PackedInt32Array([1, 1, 0, 5, 1, 0])).map(func(d): return d.label)
	_check(variable_vs_number == ["Condition", "Variable", "Is", "Compared with", "Number", "Else branch"], "branch on a variable shows its fields: %s" % [variable_vs_number])

	# A plugin registers its own command.
	var ok := LcfCommands.register({
		"code": 11050, "name": "Shake Screen", "group": "Screen",
		"params": [
			{ "index": 0, "label": "Strength", "type": "int", "min": 1, "max": 9, "default": 3 },
			{ "index": 1, "label": "Speed", "type": "int", "min": 1, "max": 9, "default": 3 },
			{ "index": 2, "label": "Tenths", "type": "int", "default": 10 },
			{ "index": 3, "label": "Wait", "type": "bool" },
		],
	})
	_check(ok and LcfCommands.get_schema(11050).name == "Shake Screen", "a plugin schema registers")
	var names := LcfCommands.Names.new(project)
	_check(CommandText.line(project, _c(11050, 1, "", [3, 5, 20, 1]), names) == "    ◆Shake Screen: Strength 3, Speed 5, Tenths 20, Wait Yes", "plugin command gets a generated line")
	_check(not LcfCommands.register({ "code": 0, "name": "Broken" }), "a schema without a code is rejected")
	LcfCommands.unregister(11050)
	_check(LcfCommands.get_schema(11050).is_empty(), "plugin schema can be removed again")


func _test_blocks() -> void:
	var branch := LcfCommands.get_schema(12010)
	var with_else := Blocks.build(branch, PackedInt32Array([0, 1, 0, 0, 0, 1]), "", 1)
	_check(_codes(with_else) == ["12010@1", "10@2", "22010@1", "10@2", "22011@1"], "new branch with Else: %s" % [_codes(with_else)])
	var message := Blocks.build(LcfCommands.get_schema(10110), PackedInt32Array(), "Hello\nsecond\nthird", 0)
	_check(_codes(message) == ["10110@0", "20110@0", "20110@0"] and message[2].string == "third", "message lines become continuation commands")

	# A list: message, branch (with a message inside and an Else), wait.
	var list := [
		_c(10110, 0, "Hi"), _c(20110, 0, "there"),
		_c(12010, 0, "", [0, 1, 0, 0, 0, 1]),
		_c(10110, 1, "Inside"), _c(10, 1),
		_c(22010, 0), _c(10, 1),
		_c(22011, 0),
		_c(11410, 0, "", [10]),
	]
	_check(Blocks.units_for(list, PackedInt32Array([1])) == [[0, 2]], "a continuation line selects its whole message")
	_check(Blocks.units_for(list, PackedInt32Array([5])) == [[2, 8]], "Else selects the whole branch")
	_check(Blocks.units_for(list, PackedInt32Array([3])) == [[3, 4]], "a command inside a branch is its own unit")
	_check(Blocks.units_for(list, PackedInt32Array([4])) == [], "END lines are not deletable")
	var removed := Blocks.remove_units(list, Blocks.units_for(list, PackedInt32Array([2])))
	_check(_codes(removed) == ["10110@0", "20110@0", "11410@0"], "deleting a branch removes its bodies and markers")
	_check(Blocks.insert_point(list, 1) == { "index": 2, "indent": 0 }, "inserting at a continuation line goes after the message")
	_check(Blocks.insert_point(list, 5) == { "index": 4, "indent": 1 }, "inserting at Else goes into the branch's first body")
	_check(Blocks.insert_point(list, 9) == { "index": 9, "indent": 0 }, "inserting at the end row appends")

	var without_else := Blocks.rebuild(list, 2, branch, PackedInt32Array([0, 1, 0, 0, 0, 0]), "")
	_check(_codes(without_else) == ["10110@0", "20110@0", "12010@0", "10110@1", "10@1", "22011@0", "11410@0"], "clearing Else removes the Else part, keeps the body")
	var back := Blocks.rebuild(without_else, 2, branch, PackedInt32Array([0, 1, 0, 0, 0, 1]), "")
	_check(_codes(back) == _codes(list), "setting Else again adds an empty Else part")
	var edited := Blocks.rebuild(list, 0, LcfCommands.get_schema(10110), PackedInt32Array(), "One line")
	_check(_codes(edited).slice(0, 2) == ["10110@0", "12010@0"] and edited.size() == list.size() - 1, "editing a message replaces its lines")
	_check(Blocks.text_of(list, 0, LcfCommands.get_schema(10110)) == "Hi\nthere", "message text joins its lines")

	var copied := Blocks.copy_units(list, PackedInt32Array([3]))
	_check(_codes(copied) == ["10110@0"], "copied commands start at indent 0")
	_check(_codes(Blocks.reindent(Blocks.copy_units(list, PackedInt32Array([2])), 2))[1] == "10110@3", "pasted blocks keep their inner indents")


# Comment commands: DynRPG syntax, parsed the way EasyRPG Player parses it.
func _test_comment_commands(project: RefCounted) -> void:
	var parsed := LcfCommands.parse_comment('@EasyRPG_Output "info", "Say ""hi"", world"')
	_check(parsed.name == "easyrpg_output" and parsed.args == ["info", 'Say "hi", world'], "strings with quotes and commas parse like the Player: %s" % [parsed])
	parsed = LcfCommands.parse_comment("@easyrpg_add  V12 , 3,,Abc")
	_check(parsed.args == ["v12", "3", "", "abc"], "tokens lose spaces and are lowercased, empty arguments stay: %s" % [parsed.args])
	_check(LcfCommands.parse_comment("A plain comment").name == "" and LcfCommands.parse_comment("@").name == "", "plain comments are not commands")
	_check(LcfCommands.parse_comment('@cmd "a" b').name == "", "a token right after a string is rejected, like the Player does")

	var output := LcfCommands.get_comment_schema("easyrpg_output")
	_check(not output.is_empty() and LcfCommands.is_comment_schema(output), "EasyRPG's Log Message is a built-in comment command")
	var text := LcfCommands.encode_comment(output, PackedInt32Array([0, 0]), { 0: "warning", 1: 'Door "A"\nis open' })
	_check(text == '@easyrpg_output "warning", "Door ""A"" is open"', "encoding quotes strings and drops line breaks: %s" % text)
	var decoded := LcfCommands.decode_comment(output, text)
	_check(decoded.ok and decoded.strings == { 0: "warning", 1: 'Door "A" is open' }, "and decodes back")
	var add := LcfCommands.get_comment_schema("easyrpg_add")
	var sum := LcfCommands.encode_comment(add, PackedInt32Array([5, -3, 10]), {})
	_check(sum == "@easyrpg_add 5, -3, 10" and LcfCommands.decode_comment(add, sum).params == PackedInt32Array([5, -3, 10]), "numbers are written plainly: %s" % sum)
	_check(not LcfCommands.decode_comment(add, "@easyrpg_add 5, V12, 1").ok, "a variable token where a number is expected keeps the comment raw")

	var names := LcfCommands.Names.new(project)
	var comment := _c(12410, 0, text)
	_check(LcfCommands.schema_for(comment) == output, "schema_for() finds the comment command")
	_check(LcfCommands.schema_for(_c(12410, 0, "@unknown_cmd 1")).name == "Comment", "unknown comment commands stay comments")
	_check(CommandText.line(project, comment, names) == '◆Log Message: [Warning] Door "A" is open', "its line reads like a command: %s" % CommandText.line(project, comment, names))
	_check(CommandText.line(project, _c(12410, 0, "@easyrpg_add 1, V2, 3"), names) == "◆Add Numbers: @easyrpg_add 1, V2, 3", "undecodable arguments show the raw comment")

	# A plugin's comment command.
	_check(LcfCommands.register({ "comment": "pixel_move", "name": "Move by Pixels", "group": "Map",
		"params": [{ "index": 0, "label": "Event", "type": "event", "default": 10005 }, { "index": 1, "label": "dx", "type": "int" }, { "index": 2, "label": "dy", "type": "int" }] }),
		"a plugin registers a comment command")
	_check(CommandText.line(project, _c(12410, 1, "@pixel_move 10005, 4, -2"), names) == "    ◆Move by Pixels: Event This event, dx 4, dy -2", "it gets a generated line")
	_check(not LcfCommands.register({ "comment": "Bad Name", "name": "x" }), "comment names must be lowercase identifiers")
	_check(not LcfCommands.register({ "code": 11060, "name": "x", "params": [{ "index": 0, "type": "string" }] }), "string parameters need a comment command")
	LcfCommands.unregister_comment("pixel_move")
	_check(LcfCommands.get_comment_schema("pixel_move").is_empty(), "and unregisters")


func _test_project(project: RefCounted) -> void:
	var lists := []
	for entry: Dictionary in project.get_map_tree():
		if entry.type != "map":
			continue
		var map: Dictionary = project.get_map(entry.id)
		for event: Dictionary in map.get("events", []):
			for page in event.page_count:
				lists.append([entry.id, project.get_map_event_commands(entry.id, event.id, page)])
	for i in project.get_database_entries("commonevents").size():
		lists.append([0, project.get_common_event_commands(i)])
	var lines := 0
	var described := 0
	var broken := []
	var bad_units := []
	var samples := {}
	for item: Array in lists:
		var names := LcfCommands.Names.new(project, item[0])
		var commands: Array = item[1]
		for i in commands.size():
			var text := CommandText.line(project, commands[i], names)
			lines += 1
			if text.strip_edges() == "":
				broken.append(commands[i].code)
			if not LcfCommands.get_schema(commands[i].code).is_empty():
				described += 1
				if not samples.has(commands[i].code):
					samples[commands[i].code] = text.strip_edges()
			# Every unit ends where the next one starts.
			var head := Blocks.head_of(commands, i)
			if Blocks.unit_end(commands, head) <= i and commands[i].code != Blocks.END:
				bad_units.append(i)
	_check(broken.is_empty(), "%d command lines written, %d by schemas %s" % [lines, described, broken.slice(0, 5)])
	_check(bad_units.is_empty(), "every command belongs to a unit")
	var codes := samples.keys()
	codes.sort()
	for code: int in codes:
		print("        ", samples[code])
