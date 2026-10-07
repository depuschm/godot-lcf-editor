@tool
extends RefCounted
## The structure of an event command list, as RPG Maker writes it:
##
##   ◆Conditional Branch      indent i       (head)
##     ◆Show Message          indent i+1     (body)
##     ◆                      indent i+1     END (code 10): ends every body
##   : Else                   indent i       (marker)
##     ◆                      indent i+1
##   : End                    indent i       (marker)
##
## Message and comment lines after the first are continuation commands at the head's
## indent. A "unit" is a head with everything that belongs to it; units are what gets
## deleted, copied and pasted, so blocks never break apart.

const END := 10
## Continuation lines of a message or comment.
const CONTINUATIONS := [20110, 22410]
## Lines at a block's own indent that split or close it (Else, End, choice cases,
## battle/shop/inn branches, End Loop).
const MARKERS := [20140, 20141, 20710, 20711, 20712, 20713, 20720, 20721, 20722,
	20730, 20731, 20732, 22010, 22011, 22210, 23310, 23311]


static func is_follower(command: Dictionary) -> bool:
	return command.code in CONTINUATIONS or command.code in MARKERS


## Index of the head that a continuation or marker line belongs to (itself otherwise).
static func head_of(commands: Array, index: int) -> int:
	if index < 0 or index >= commands.size() or not is_follower(commands[index]):
		return index
	var indent: int = commands[index].indent
	var i := index - 1
	while i >= 0:
		var c: Dictionary = commands[i]
		if c.indent == indent and not is_follower(c):
			return i
		if c.indent < indent:
			break
		i -= 1
	return index  # malformed list: treat the line as its own unit


## One past the last line of the unit starting at `head`.
static func unit_end(commands: Array, head: int) -> int:
	var indent: int = commands[head].indent
	var i := head + 1
	while i < commands.size():
		var c: Dictionary = commands[i]
		if c.indent > indent or (c.indent == indent and is_follower(c)):
			i += 1
		else:
			break
	return i


## The units touched by a selection of rows, as sorted, merged [start, end) pairs.
## END lines are not units of their own (they belong to the block around them).
static func units_for(commands: Array, rows: PackedInt32Array) -> Array:
	var ranges := []
	for row in rows:
		if row < 0 or row >= commands.size() or commands[row].code == END:
			continue
		var head := head_of(commands, row)
		ranges.append([head, unit_end(commands, head)])
	ranges.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var merged := []
	for r: Array in ranges:
		if not merged.is_empty() and r[0] <= merged.back()[1]:
			merged.back()[1] = maxi(merged.back()[1], r[1])
		else:
			merged.append(r)
	return merged


## The list without the given units.
static func remove_units(commands: Array, units: Array) -> Array:
	var out := []
	var u := 0
	for i in commands.size():
		while u < units.size() and i >= units[u][1]:
			u += 1
		if u < units.size() and i >= units[u][0] and i < units[u][1]:
			continue
		out.append(commands[i])
	return out


## Where a new command goes when row `row` is selected, and at which indent:
## { index, indent }. Never inside a message or between a body's END and its marker.
static func insert_point(commands: Array, row: int) -> Dictionary:
	if row < 0 or row >= commands.size():
		return { "index": commands.size(), "indent": 0 }
	var c: Dictionary = commands[row]
	if c.code in CONTINUATIONS:
		var head := head_of(commands, row)
		return { "index": unit_end(commands, head), "indent": commands[head].indent }
	if c.code in MARKERS and row > 0 and commands[row - 1].code == END:
		return { "index": row - 1, "indent": commands[row - 1].indent }
	return { "index": row, "indent": c.indent }


## The commands of the given rows' units, indented so the first starts at 0.
static func copy_units(commands: Array, rows: PackedInt32Array) -> Array:
	var out := []
	for r: Array in units_for(commands, rows):
		for i in range(r[0], r[1]):
			out.append(commands[i].duplicate(true))
	return reindent(out, 0)


## Shifts lines so the first one is at `indent`, keeping their relative indents.
static func reindent(lines: Array, indent: int) -> Array:
	if lines.is_empty():
		return lines
	var delta: int = indent - lines[0].indent
	var out := []
	for line: Dictionary in lines:
		var copy := line.duplicate(true)
		copy.indent = maxi(0, line.indent + delta)
		out.append(copy)
	return out


## The lines for a new command from its schema: head, continuation lines and, for
## blocks, empty bodies with their markers.
static func build(schema: Dictionary, params: PackedInt32Array, text: String, indent: int) -> Array:
	var lines := _head_lines(schema, params, text, indent)
	var block: Dictionary = schema.get("block", {})
	if block.is_empty():
		return lines
	lines.append(_line(END, indent + 1))
	if _wants_else(block, params):
		lines.append(_line(int(block.else.code), indent))
		lines.append(_line(END, indent + 1))
	lines.append(_line(int(block.end), indent))
	return lines


## Replaces the unit at `head` with an edited command, keeping the bodies of a block.
## For a branch whose Else flag changed, the Else part is added (empty) or removed.
static func rebuild(commands: Array, head: int, schema: Dictionary, params: PackedInt32Array, text: String) -> Array:
	var end := unit_end(commands, head)
	var indent: int = commands[head].indent
	var lines := _head_lines(schema, params, text, indent)
	var block: Dictionary = schema.get("block", {})
	# The rest of the old unit after its head and continuation lines.
	var rest_start := head + 1
	while rest_start < end and commands[rest_start].code in CONTINUATIONS and commands[rest_start].indent == indent:
		rest_start += 1
	var rest := commands.slice(rest_start, end)
	if not block.is_empty() and block.has("else") and not rest.is_empty():
		rest = _set_else(rest, indent, int(block.else.code), int(block.end), _wants_else(block, params))
	return commands.slice(0, head) + lines + rest + commands.slice(end)


static func _wants_else(block: Dictionary, params: PackedInt32Array) -> bool:
	if not block.has("else"):
		return false
	var flag := int(block.else.flag)
	return flag < params.size() and params[flag] != 0


# Adds or removes the Else part of a block's remaining lines (body, markers).
static func _set_else(rest: Array, indent: int, else_code: int, end_code: int, wanted: bool) -> Array:
	var else_at := -1
	var end_at := -1
	for i in rest.size():
		if rest[i].indent == indent:
			if rest[i].code == else_code and else_at < 0:
				else_at = i
			elif rest[i].code == end_code:
				end_at = i
	if end_at < 0:
		return rest  # not a well-formed block; leave it alone
	if wanted and else_at < 0:
		return rest.slice(0, end_at) + [_line(else_code, indent), _line(END, indent + 1)] + rest.slice(end_at)
	if not wanted and else_at >= 0:
		return rest.slice(0, else_at) + rest.slice(end_at)
	return rest


static func _head_lines(schema: Dictionary, params: PackedInt32Array, text: String, indent: int) -> Array:
	var text_def: Dictionary = schema.get("text", {})
	var parts := [text]
	if text_def.get("kind", "") == "lines":
		parts = text.split("\n")
	var head := _line(int(schema.code), indent, parts[0], params)
	var lines := [head]
	for i in range(1, parts.size()):
		lines.append(_line(int(text_def.continuation), indent, parts[i]))
	return lines


static func _line(code: int, indent: int, text := "", params := PackedInt32Array()) -> Dictionary:
	return { "code": code, "indent": indent, "string": text, "parameters": params }


## The text of a command for its dialog: for "lines" commands, the head's text and
## its continuation lines joined with newlines.
static func text_of(commands: Array, head: int, schema: Dictionary) -> String:
	var text: String = commands[head].string
	if schema.get("text", {}).get("kind", "") != "lines":
		return text
	var indent: int = commands[head].indent
	var i := head + 1
	while i < commands.size() and commands[i].code == int(schema.text.continuation) and commands[i].indent == indent:
		text += "\n" + commands[i].string
		i += 1
	return text
