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

const GROUPS := ["Message", "Game Progress", "Party", "Map", "Flow", "Sound", "Screen", "Other"]
const REFERENCES := {
	"switch": "switches", "variable": "variables", "item": "items", "actor": "actors",
	"skill": "skills", "state": "states", "common_event": "commonevents", "troop": "troops",
	"enemy": "enemies", "animation": "animations",
}
## Special event IDs RPG Maker uses in commands that target a character.
const SPECIAL_EVENTS := { 10001: "Hero", 10002: "Boat", 10003: "Ship", 10004: "Airship", 10005: "This event" }

static var _schemas := {}
static var _loaded := false


## Adds or replaces the schema for its code. Returns false if it is malformed.
static func register(schema: Dictionary) -> bool:
	_ensure()
	if int(schema.get("code", 0)) <= 0 or String(schema.get("name", "")) == "":
		push_error("LcfCommands.register: a schema needs a positive code and a name")
		return false
	for def: Dictionary in schema.get("params", []):
		if not def.has("index") or not def.has("type"):
			push_error("LcfCommands.register: every parameter needs an index and a type (%s)" % schema.name)
			return false
	_schemas[int(schema.code)] = schema
	return true


## Removes a schema (e.g. when a plugin is disabled). Built-in schemas come back with
## reset_builtins().
static func unregister(code: int) -> void:
	_ensure()
	_schemas.erase(code)


static func reset_builtins() -> void:
	clear()
	_ensure()


## Drops every schema, built-in ones included (they load again on next use). The
## editor plugin calls this when it exits.
static func clear() -> void:
	_schemas.clear()
	_loaded = false


static func get_schema(code: int) -> Dictionary:
	_ensure()
	return _schemas.get(code, {})


## All schemas, by group (in GROUPS order, unknown groups last) and name.
static func get_schemas() -> Array:
	_ensure()
	var list := _schemas.values()
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
		_schemas[int(schema.code)] = schema


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
		if int(def.index) < size and is_visible(def, params, engine) and def.has("default"):
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
static func summary(schema: Dictionary, command: Dictionary, names: Names) -> String:
	var custom: Variant = schema.get("summary")
	if custom is Callable and custom.is_valid():
		return custom.call(command, names)
	var parts := PackedStringArray()
	var text: Dictionary = schema.get("text", {})
	if not text.is_empty() and command.string != "":
		parts.append(command.string)
	for def: Dictionary in visible_params(schema, command.parameters, names.engine if names else ""):
		if int(def.index) < command.parameters.size():
			parts.append("%s %s" % [def.get("label", "?"), format_value(def, command.parameters[int(def.index)], names)])
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
