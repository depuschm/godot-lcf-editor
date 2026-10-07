@tool
extends RefCounted
## Readable text for event commands, shared by the database view and the event editor.

## Commands that continue the one before them (shown as ":" lines, like RPG Maker).
const CONTINUATIONS := [20110, 22410]  # ShowMessage_2, Comment_2

## Names that read better than the split liblcf tag.
const NAMES := {
	10: "", 20140: "[Choice]", 20141: "End Choice", 22010: "Else", 22011: "End",
	22210: "End Loop", 23310: "Else", 23311: "End", 13260: "Show Battle Animation",
	13310: "Conditional Branch (Battle)", 20710: "[Victory]", 20711: "[Escape]",
	20712: "[Defeat]", 20713: "End Battle", 20720: "[Purchase]", 20721: "[No Purchase]",
	20722: "End Shop", 20730: "[Stay]", 20731: "[Don't Stay]", 20732: "End Inn",
	12510: "Return to Title Screen", 10120: "Message Options", 10220: "Control Variables",
}


## { name, detail } for one command, e.g. { "Show Message", "“Hello”" }.
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
	return words.replace("Vars", "Variables").replace("Returnto", "Return to") + suffix


## One line of a command list as RPG Maker shows it: "◆Show Message: Hello",
## continuation lines as " : second line". `indent` is shown with leading spaces.
static func line(project: RefCounted, command: Dictionary) -> String:
	var code: int = command.code
	var pad := "    ".repeat(command.indent)
	var info := describe(project, code, command.string, command.parameters)
	if code in CONTINUATIONS:
		return pad + "  : " + command.string
	if code == 10:  # END of a block or of the list
		return pad + "◆"
	if info.detail == "":
		return pad + "◆" + info.name
	return pad + "◆" + info.name + ": " + info.detail
