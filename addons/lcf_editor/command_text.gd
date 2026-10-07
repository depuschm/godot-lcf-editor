@tool
extends RefCounted
## Readable text for event commands, shared by the database view and the event editor.
## Commands with a schema (see command_registry.gd) are described by it; others show
## their raw text and parameters.

const Blocks := preload("res://addons/lcf_editor/command_blocks.gd")

## Names of lines that are part of a block rather than commands of their own.
const MARKER_NAMES := {
	20140: "When", 20141: "End", 20710: "Victory", 20711: "Escape", 20712: "Defeat",
	20713: "End", 20720: "Purchase", 20721: "No Purchase", 20722: "End", 20730: "Stay",
	20731: "Don't Stay", 20732: "End", 22010: "Else", 22011: "End", 22210: "End Loop",
	23310: "Else", 23311: "End",
}
## Names that read better than the split liblcf tag, for commands without a schema.
const NAMES := {
	10220: "Control Variables", 10120: "Message Options", 13260: "Show Battle Animation",
	13310: "Conditional Branch (Battle)", 12510: "Return to Title Screen",
}


## { name, detail } for one command without looking at schemas (raw view).
static func describe(project: RefCounted, code: int, text: String, params: PackedInt32Array) -> Dictionary:
	var detail := "“%s”" % text if text != "" else ""
	if not params.is_empty():
		var numbers := PackedStringArray()
		for p in params:
			numbers.append(str(p))
		detail = (detail + "  " if detail != "" else "") + "[" + ", ".join(numbers) + "]"
	return { "name": command_name(project, code), "detail": detail }


## Human-readable name of a command code: "Show Message", "Get Save Info (Maniacs)".
static func command_name(project: RefCounted, code: int) -> String:
	var schema := LcfCommands.get_schema(code)
	if not schema.is_empty():
		return schema.name
	if MARKER_NAMES.has(code):
		return MARKER_NAMES[code]
	if NAMES.has(code):
		return NAMES[code]
	var tag: String = project.get_event_command_name(code) if project else ""
	if tag == "":
		return "Command %d" % code
	var suffix := ""
	if tag.begins_with("Maniac_"):
		tag = tag.trim_prefix("Maniac_")
		suffix = " (Maniacs)"
	elif tag.begins_with("EasyRpg_"):
		tag = tag.trim_prefix("EasyRpg_")
		suffix = " (EasyRPG)"
	tag = tag.trim_suffix("_B").trim_suffix("_2")
	var words := ""
	for i in tag.length():
		var c := tag[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower() and tag[i - 1] == tag[i - 1].to_lower():
			words += " "
		words += c
	return words.replace("Returnto", "Return to") + suffix


## One line of a command list as RPG Maker shows it: "◆Show Message: Hello",
## continuation lines as " : second line", block markers as ": Else".
static func line(project: RefCounted, command: Dictionary, names: LcfCommands.Names = null) -> String:
	var code: int = command.code
	var pad := "    ".repeat(command.indent)
	if code in Blocks.CONTINUATIONS:
		return pad + "  : " + command.string
	if code == Blocks.END:
		return pad + "◆"
	if MARKER_NAMES.has(code):
		var marker: String = pad + ": " + MARKER_NAMES[code]
		return marker + (" [%s]" % command.string if command.string != "" else "")
	var schema := LcfCommands.get_schema(code)
	if not schema.is_empty():
		if names == null:
			names = LcfCommands.Names.new(project)
		var text := LcfCommands.summary(schema, command, names)
		return pad + "◆" + schema.name + (": " + text if text != "" else "")
	var info := describe(project, code, command.string, command.parameters)
	if info.detail == "":
		return pad + "◆" + info.name
	return pad + "◆" + info.name + ": " + info.detail
