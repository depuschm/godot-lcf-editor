@tool
class_name LcfCommands
extends RefCounted
## Registry of event command schemas: the plugin API for event commands.
##
## A schema describes one command code: its name, its text and its parameters. The
## event editor builds the command's dialog and its line in the command list from it,
## so a plugin adds a command (or a better dialog for an existing one) by registering
## a schema, without writing any UI:
##
##     LcfCommands.register({
##         "code": 11050, "name": "Shake Screen", "group": "Screen",
##         "params": [
##             { "index": 0, "label": "Strength", "type": "int", "min": 1, "max": 9, "default": 3 },
##             { "index": 1, "label": "Speed", "type": "int", "min": 1, "max": 9, "default": 3 },
##             { "index": 2, "label": "Duration (tenths of a second)", "type": "int", "default": 10 },
##             { "index": 3, "label": "Wait until done", "type": "bool" },
##         ],
##     })
##
## Schema keys:
##   code     command code (required)
##   name     display name (required)
##   group    catalog group, e.g. "Message", "Flow" (default "Other")
##   text     the command's text: { label, kind: "line" | "lines" | "file", folder,
##            continuation, when }. "lines" stores line 2+ as `continuation` commands
##            (like Show Message); "file" offers the files of a project folder.
##   params   parameter fields: { index, label, type, default, min, max, choices, when,
##            engine }. Types: int, bool, enum (choices: Array or { value: label }),
##            switch, variable, item, actor, skill, state, common_event, troop, enemy,
##            animation (database references), map, event (an event of this map).
##            `when` shows a field only if other parameters have certain values:
##            { 0: 1 } or { 0: [1, 2], 2: 0 }. `engine` "2000" or "2003" limits a field
##            to one engine. Several fields may share an index with different `when`.
##   length   minimum parameter count for new commands
##   block    for commands that open a block: { end: code, else: { code, flag } }
##   sync     Callable(params: PackedInt32Array) -> PackedInt32Array, applied on save
##   summary  Callable(command: Dictionary, names: LcfCommands.Names) -> String for the
##            command list; without it, the fields are listed.
##
## Use method callables for sync and summary (e.g. `_my_summary` of your plugin), not
## lambdas, and unregister your schemas in your plugin's _exit_tree(): the registry
## outlives scripts, and Godot cannot free a lambda after its script is gone.
##
## Unknown parameters of a command are kept as they are, so a schema only needs to
## describe the parameters it knows.
##
## Comment commands (the runtime extension mechanism): instead of `code`, a schema can
## give `comment`, a command name. The command is then stored as an event comment in
## DynRPG syntax, `@name arg, "text", ...`, which RPG Maker and every tool keep as an
## ordinary comment, and which EasyRPG Player executes: commands starting with
## "easyrpg_" when the game enables EasyRPG extensions, any command in DynRPG mode
## (where a runtime plugin handles it). Parameters are the arguments by position
## (`index`); besides the types above they may be "string" (with optional `choices`
## { value: label }). `runtime` names what executes the command, for the dialog.
##
##     LcfCommands.register({
##         "comment": "easyrpg_output", "name": "Log Message", "group": "Other",
##         "runtime": "EasyRPG Player with EasyRPG extensions",
##         "params": [
##             { "index": 0, "label": "Level", "type": "string", "default": "info",
##               "choices": { "info": "Info", "warning": "Warning" } },
##             { "index": 1, "label": "Message", "type": "string" },
##         ],
##     })

const GROUPS := ["Message", "Game Progress", "Party", "Map", "Flow", "Sound", "Screen", "Other"]
const REFERENCES := {
	"switch": "switches", "variable": "variables", "item": "items", "actor": "actors",
	"skill": "skills", "state": "states", "common_event": "commonevents", "troop": "troops",
	"enemy": "enemies", "animation": "animations",
}
## Special event IDs RPG Maker uses in commands that target a character.
const SPECIAL_EVENTS := { 10001: "Hero", 10002: "Boat", 10003: "Ship", 10004: "Airship", 10005: "This event" }

## Event comments hold comment commands; their continuation lines are joined to them.
const COMMENT := 12410
const COMMENT_2 := 22410

static var _schemas := {}
static var _comment_schemas := {}  # command name -> schema
static var _loaded := false


## Adds or replaces the schema for its code (or comment command name). Returns false
## if it is malformed.
static func register(schema: Dictionary) -> bool:
	_ensure()
	return _add(schema)


static func _add(schema: Dictionary) -> bool:
	var comment := String(schema.get("comment", ""))
	if String(schema.get("name", "")) == "" or (comment == "" and int(schema.get("code", 0)) <= 0):
		push_error("LcfCommands.register: a schema needs a name and a positive code or a comment command name")
		return false
	if comment != "" and not _valid_name(comment):
		push_error("LcfCommands.register: comment command names use lowercase letters, digits and \"_\" (%s)" % comment)
		return false
	for def: Dictionary in schema.get("params", []):
		if not def.has("index") or not def.has("type"):
			push_error("LcfCommands.register: every parameter needs an index and a type (%s)" % schema.name)
			return false
		if def.type == "string" and comment == "":
			push_error("LcfCommands.register: \"string\" parameters only exist in comment commands (%s)" % schema.name)
			return false
	if comment != "":
		_comment_schemas[comment] = schema
	else:
		_schemas[int(schema.code)] = schema
	return true


static func _valid_name(name: String) -> bool:
	for c in name:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "_":
			return false
	return name != ""


## Removes a schema (e.g. when a plugin is disabled). Built-in schemas come back with
## reset_builtins().
static func unregister(code: int) -> void:
	_ensure()
	_schemas.erase(code)


static func unregister_comment(name: String) -> void:
	_ensure()
	_comment_schemas.erase(name)


## The schema of a comment command by name, or {}.
static func get_comment_schema(name: String) -> Dictionary:
	_ensure()
	return _comment_schemas.get(name.to_lower(), {})


## The schema that describes a command: a comment command's schema if the command is
## a comment of one, otherwise the schema of its code (or {}).
static func schema_for(command: Dictionary) -> Dictionary:
	_ensure()
	if int(command.code) == COMMENT and String(command.string).begins_with("@"):
		var found := get_comment_schema(String(parse_comment(command.string).name))
		if not found.is_empty():
			return found
	return _schemas.get(int(command.code), {})


static func is_comment_schema(schema: Dictionary) -> bool:
	return schema.has("comment")


static func reset_builtins() -> void:
	clear()
	_ensure()


## Drops every schema, built-in ones included (they load again on next use). The
## editor plugin calls this when it exits.
static func clear() -> void:
	_schemas.clear()
	_comment_schemas.clear()
	_loaded = false


static func get_schema(code: int) -> Dictionary:
	_ensure()
	return _schemas.get(code, {})


## All schemas, by group (in GROUPS order, unknown groups last) and name.
static func get_schemas() -> Array:
	_ensure()
	var list := _schemas.values() + _comment_schemas.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ga := _group_rank(a)
		var gb := _group_rank(b)
		return ga < gb if ga != gb else String(a.name) < String(b.name))
	return list


static func _group_rank(schema: Dictionary) -> int:
	var rank := GROUPS.find(schema.get("group", "Other"))
	return rank if rank >= 0 else GROUPS.size()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var builtins: GDScript = load("res://addons/lcf_editor/builtin_commands.gd")
	for schema: Dictionary in builtins.schemas(builtins):
		_add(schema)


# --- comment commands (DynRPG syntax) ----------------------------------------------

## Parses "@name a, "b", 3" like EasyRPG Player does: { name, args: Array[String] }.
## Strings are in quotes ("" is a quote); other arguments are tokens with spaces
## removed and lowercased. Not a command: { name: "", args: [] }.
static func parse_comment(text: String) -> Dictionary:
	var none := { "name": "", "args": [] }
	if not text.begins_with("@"):
		return none
	var args: Array[String] = []
	var name := ""
	var token := ""
	var mode := "function"  # function, wait_arg, token, string, wait_comma
	var i := 1
	while i <= text.length():
		if i == text.length():
			match mode:
				"function":
					name = token.to_lower()
				"wait_arg":
					if not args.is_empty():
						args.append("")
				"string":
					args.append(token)
				"token":
					args.append(token.to_lower())
			break
		var c := text[i]
		if c == " ":
			match mode:
				"function":
					name = token.to_lower()
					token = ""
					mode = "wait_arg"
				"string":
					token += c
		elif c == ",":
			match mode:
				"function":
					name = token.to_lower()
					token = ""
					args.append("")
					mode = "wait_arg"
				"wait_comma":
					mode = "wait_arg"
				"wait_arg":
					args.append("")
				"string":
					token += c
				"token":
					args.append(token.to_lower())
					token = ""
					mode = "wait_arg"
		else:
			match mode:
				"function", "token":
					token += c
				"wait_comma":
					return none
				"wait_arg":
					if c == "\"":
						mode = "string"
					else:
						mode = "token"
						token += c
				"string":
					if c == "\"":
						if i + 1 < text.length() and text[i + 1] == "\"":
							token += "\""
							i += 1
						else:
							args.append(token)
							token = ""
							mode = "wait_comma"
					else:
						token += c
		i += 1
	if name == "":
		return none
	return { "name": name, "args": args }


## The comment text for a comment command: "@name 3, "text"". Strings are quoted (with
## "" for a quote; line breaks become spaces), everything else is written as a number.
static func encode_comment(schema: Dictionary, params: PackedInt32Array, strings: Dictionary) -> String:
	var count := 0
	for def: Dictionary in schema.get("params", []):
		count = maxi(count, int(def.index) + 1)
	var args := PackedStringArray()
	for index in count:
		var def := _def_at(schema, index, params)
		if not def.is_empty() and def.type == "string":
			var text := String(strings.get(index, "")).replace("\r", "").replace("\n", " ")
			args.append("\"" + text.replace("\"", "\"\"") + "\"")
		else:
			args.append(str(params[index] if index < params.size() else 0))
	return "@" + String(schema.comment) + (" " + ", ".join(args) if not args.is_empty() else "")


## Splits a comment command's text into the schema's values: { ok, params, strings }.
## `ok` is false when an argument does not fit (e.g. a variable token like V12 where a
## number is expected); the editor then shows the comment as it is.
static func decode_comment(schema: Dictionary, text: String) -> Dictionary:
	var parsed := parse_comment(text)
	var params := PackedInt32Array()
	var strings := {}
	var count := 0
	for def: Dictionary in schema.get("params", []):
		count = maxi(count, int(def.index) + 1)
	params.resize(count)
	params.fill(0)
	var ok: bool = parsed.name == String(schema.get("comment", "")) and parsed.args.size() <= count
	for index in parsed.args.size():
		if not ok:
			break
		var arg: String = parsed.args[index]
		var def := _def_at(schema, index, params)
		if not def.is_empty() and def.type == "string":
			strings[index] = arg
		elif arg.is_valid_int():
			params[index] = int(arg)
		elif arg == "":
			params[index] = 0
		else:
			ok = false
	return { "ok": ok, "params": params, "strings": strings }


## The field for an argument position that applies to the given values.
static func _def_at(schema: Dictionary, index: int, params: PackedInt32Array) -> Dictionary:
	for def: Dictionary in schema.get("params", []):
		if int(def.index) == index and is_visible(def, params):
			return def
	return {}


## Default string values of a comment command's string fields: { index: text }.
static func default_strings(schema: Dictionary) -> Dictionary:
	var out := {}
	for def: Dictionary in schema.get("params", []):
		if def.type == "string":
			out[int(def.index)] = String(def.get("default", ""))
	return out


# --- working with schemas --------------------------------------------------------

## True if a field applies to the given parameters (its `when` holds) and engine.
static func is_visible(def: Dictionary, params: PackedInt32Array, engine := "") -> bool:
	if def.has("engine") and engine != "" and def.engine != engine:
		return false
	var when: Dictionary = def.get("when", {})
	for index: int in when:
		var value := params[index] if index < params.size() else 0
		var wanted: Variant = when[index]
		if wanted is Array:
			if not value in wanted:
				return false
		elif value != int(wanted):
			return false
	return true


## The fields that apply, in schema order.
static func visible_params(schema: Dictionary, params: PackedInt32Array, engine := "") -> Array:
	var out := []
	for def: Dictionary in schema.get("params", []):
		if is_visible(def, params, engine):
			out.append(def)
	return out


## Parameters for a new command: every field's default, at least `length` long.
static func default_params(schema: Dictionary, engine := "") -> PackedInt32Array:
	var size := int(schema.get("length", 0))
	for def: Dictionary in schema.get("params", []):
		if not def.has("engine") or engine == "" or def.engine == engine:
			size = maxi(size, int(def.index) + 1)
	var params := PackedInt32Array()
	params.resize(size)
	params.fill(0)
	# Defaults of the fields shown for the defaults chosen so far, in order.
	for def: Dictionary in schema.get("params", []):
		if int(def.index) < size and is_visible(def, params, engine) and def.has("default") and def.type != "string":
			params[int(def.index)] = int(def.default)
	return params


static func enum_items(choices: Variant) -> Dictionary:
	var out := {}
	if choices is Array:
		for i in choices.size():
			out[i] = choices[i]
	elif choices is Dictionary:
		out = choices
	return out


## A parameter value as text, e.g. "ON", "[0003: Door open]", "House".
static func format_value(def: Dictionary, value: int, names: Names) -> String:
	match String(def.type):
		"bool":
			return "Yes" if value != 0 else "No"
		"enum":
			return String(enum_items(def.get("choices", [])).get(value, str(value)))
		"map":
			return names.map(value) if names else str(value)
		"event":
			return names.event(value) if names else str(value)
	if REFERENCES.has(def.type) and names:
		return names.ref(REFERENCES[def.type], value)
	return str(value)


## The text after "◆Name: " in the command list.
## For comment commands, summary callables get the decoded arguments: `parameters`
## (numbers) and `strings` ({ index: text }).
static func summary(schema: Dictionary, command: Dictionary, names: Names) -> String:
	var strings := {}
	if is_comment_schema(schema):
		var decoded := decode_comment(schema, command.string)
		if not decoded.ok:
			return command.string
		command = command.duplicate()
		command.parameters = decoded.params
		command.strings = decoded.strings
		strings = decoded.strings
	var custom: Variant = schema.get("summary")
	if custom is Callable and custom.is_valid():
		return custom.call(command, names)
	var parts := PackedStringArray()
	var text: Dictionary = schema.get("text", {})
	if not text.is_empty() and command.string != "":
		parts.append(command.string)
	for def: Dictionary in visible_params(schema, command.parameters, names.engine if names else ""):
		var index := int(def.index)
		if def.type == "string":
			var value := String(strings.get(index, ""))
			var label: String = def.get("choices", {}).get(value, "“%s”" % value)
			parts.append("%s %s" % [def.get("label", "?"), label])
		elif index < command.parameters.size():
			parts.append("%s %s" % [def.get("label", "?"), format_value(def, command.parameters[index], names)])
	return ", ".join(parts)


## Names of database entries, maps and events for command text and dialogs. Build
## one per list you show; it reads names lazily and caches them.
class Names:
	extends RefCounted
	var project: RefCounted
	var map_id := 0
	var engine := ""
	var _cache := {}

	func _init(p_project: RefCounted = null, p_map_id := 0) -> void:
		project = p_project
		map_id = p_map_id
		engine = project.get_engine() if project and project.is_loaded() else ""

	## { id: name } for a database section ("switches", ...).
	func entries(section: String) -> Dictionary:
		if not _cache.has(section):
			var names := {}
			if project and project.is_loaded():
				for entry: Dictionary in project.get_database_entries(section):
					names[entry.id] = entry.name
			_cache[section] = names
		return _cache[section]

	func name_of(section: String, id: int) -> String:
		return entries(section).get(id, "")

	## "[0003: Door open]" as RPG Maker writes references.
	func ref(section: String, id: int) -> String:
		var name := name_of(section, id)
		return "[%04d: %s]" % [id, name] if name != "" else "[%04d]" % id

	func maps() -> Dictionary:
		if not _cache.has("@maps"):
			var out := {}
			if project and project.is_loaded():
				for entry: Dictionary in project.get_map_tree():
					if entry.type == "map":
						out[entry.id] = entry.name
			_cache["@maps"] = out
		return _cache["@maps"]

	func map(id: int) -> String:
		var name: String = maps().get(id, "")
		return "%04d: %s" % [id, name] if name != "" else "Map%04d" % id

	func events() -> Dictionary:
		if not _cache.has("@events"):
			var out := {}
			if project and project.is_loaded() and map_id > 0:
				for event: Dictionary in project.get_map(map_id).get("events", []):
					out[event.id] = event.name
			_cache["@events"] = out
		return _cache["@events"]

	func event(id: int) -> String:
		if SPECIAL_EVENTS.has(id):
			return SPECIAL_EVENTS[id]
		var name: String = events().get(id, "")
		return "%04d: %s" % [id, name] if name != "" else "Event %d" % id
