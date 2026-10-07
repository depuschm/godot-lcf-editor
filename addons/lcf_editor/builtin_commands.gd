@tool
extends RefCounted
## Schemas of the RPG Maker 2000/2003 commands the editor has dialogs for. Parameter
## layouts follow what RPG Maker writes (checked against EasyRPG's TestGame) and how
## EasyRPG Player reads them. See command_registry.gd for the schema format.

const OPERATIONS := ["Set", "Add", "Subtract", "Multiply", "Divide", "Modulo"]
const OPERATION_SIGNS := ["=", "+=", "-=", "*=", "/=", "%="]
const COMPARISONS := ["equal to", "at least", "at most", "greater than", "less than", "not equal to"]
const COMPARISON_SIGNS := ["==", ">=", "<=", ">", "<", "!="]
const ACTOR_VALUES := ["Level", "Experience", "HP", "MP", "Max HP", "Max MP", "Attack", "Defense",
	"Intelligence", "Agility", "Weapon ID", "Shield ID", "Armor ID", "Helmet ID", "Accessory ID"]
const EVENT_VALUES := ["Map ID", "X", "Y", "Direction", "Screen X", "Screen Y"]
const OTHER_VALUES := ["Money", "Timer 1 (seconds)", "Party size", "Save count", "Battle count",
	"Victories", "Defeats", "Escapes", "MIDI position (ticks)", "Timer 2 (seconds)"]
const DIRECTIONS := ["Up", "Right", "Down", "Left"]


## `script` is this script (from the registry), so summaries are plain method callables.
static func schemas(script: GDScript) -> Array:
	return [
		{
			"code": 10110, "name": "Show Message", "group": "Message",
			"text": { "label": "Message", "kind": "lines", "continuation": 20110 },
			"summary": Callable(script, "_summary_text"),
		},
		{
			"code": 12410, "name": "Comment", "group": "Other",
			"text": { "label": "Comment", "kind": "lines", "continuation": 22410 },
			"summary": Callable(script, "_summary_text"),
		},
		{
			"code": 10210, "name": "Control Switches", "group": "Game Progress", "length": 4,
			"params": [
				{ "index": 0, "label": "Target", "type": "enum", "choices": ["One switch", "Range of switches", "Switch ID from a variable"] },
				{ "index": 1, "label": "Switch", "type": "switch", "default": 1, "when": { 0: 0 } },
				{ "index": 1, "label": "First switch", "type": "switch", "default": 1, "when": { 0: 1 } },
				{ "index": 2, "label": "Last switch", "type": "switch", "default": 1, "when": { 0: 1 } },
				{ "index": 1, "label": "Variable holding the switch ID", "type": "variable", "default": 1, "when": { 0: 2 } },
				{ "index": 3, "label": "Set to", "type": "enum", "choices": ["ON", "OFF", "Toggle"] },
			],
			"sync": Callable(script, "_single_target"),
			"summary": Callable(script, "_summary_switches"),
		},
		{
			"code": 10220, "name": "Control Variables", "group": "Game Progress", "length": 7,
			"params": [
				{ "index": 0, "label": "Target", "type": "enum", "choices": ["One variable", "Range of variables", "Variable ID from a variable"] },
				{ "index": 1, "label": "Variable", "type": "variable", "default": 1, "when": { 0: 0 } },
				{ "index": 1, "label": "First variable", "type": "variable", "default": 1, "when": { 0: 1 } },
				{ "index": 2, "label": "Last variable", "type": "variable", "default": 1, "when": { 0: 1 } },
				{ "index": 1, "label": "Variable holding the variable ID", "type": "variable", "default": 1, "when": { 0: 2 } },
				{ "index": 3, "label": "Operation", "type": "enum", "choices": OPERATIONS },
				{ "index": 4, "label": "Operand", "type": "enum", "choices": ["Number", "Variable", "Variable ID from a variable", "Random number", "Item", "Actor", "Event", "Other"] },
				{ "index": 5, "label": "Number", "type": "int", "min": -9999999, "max": 9999999, "when": { 4: 0 } },
				{ "index": 5, "label": "Variable", "type": "variable", "default": 1, "when": { 4: 1 } },
				{ "index": 5, "label": "Variable holding the variable ID", "type": "variable", "default": 1, "when": { 4: 2 } },
				{ "index": 5, "label": "From", "type": "int", "min": -9999999, "max": 9999999, "when": { 4: 3 } },
				{ "index": 6, "label": "To", "type": "int", "min": -9999999, "max": 9999999, "when": { 4: 3 } },
				{ "index": 5, "label": "Item", "type": "item", "default": 1, "when": { 4: 4 } },
				{ "index": 6, "label": "Value", "type": "enum", "choices": ["Number held", "Number equipped"], "when": { 4: 4 } },
				{ "index": 5, "label": "Actor", "type": "actor", "default": 1, "when": { 4: 5 } },
				{ "index": 6, "label": "Value", "type": "enum", "choices": ACTOR_VALUES, "when": { 4: 5 } },
				{ "index": 5, "label": "Event", "type": "event", "default": 10001, "when": { 4: 6 } },
				{ "index": 6, "label": "Value", "type": "enum", "choices": EVENT_VALUES, "when": { 4: 6 } },
				{ "index": 5, "label": "Value", "type": "enum", "choices": OTHER_VALUES, "when": { 4: 7 } },
			],
			"sync": Callable(script, "_single_target"),
			"summary": Callable(script, "_summary_variables"),
		},
		{
			"code": 10310, "name": "Change Money", "group": "Party", "length": 3,
			"params": _amount_params(0, ["Increase", "Decrease"], 1, 2, 0, 999999, 0),
			"summary": Callable(script, "_summary_money"),
		},
		{
			"code": 10320, "name": "Change Items", "group": "Party", "length": 5,
			"params": [
				{ "index": 0, "label": "Operation", "type": "enum", "choices": ["Add", "Remove"] },
				{ "index": 1, "label": "Item from", "type": "enum", "choices": ["Item", "Item ID from a variable"] },
				{ "index": 2, "label": "Item", "type": "item", "default": 1, "when": { 1: 0 } },
				{ "index": 2, "label": "Variable holding the item ID", "type": "variable", "default": 1, "when": { 1: 1 } },
			] + _amount_params(-1, [], 3, 4, 0, 99, 1),
			"summary": Callable(script, "_summary_items"),
		},
		{
			"code": 10330, "name": "Change Party Members", "group": "Party", "length": 3,
			"params": [
				{ "index": 0, "label": "Operation", "type": "enum", "choices": ["Add", "Remove"] },
				{ "index": 1, "label": "Actor from", "type": "enum", "choices": ["Actor", "Actor ID from a variable"] },
				{ "index": 2, "label": "Actor", "type": "actor", "default": 1, "when": { 1: 0 } },
				{ "index": 2, "label": "Variable holding the actor ID", "type": "variable", "default": 1, "when": { 1: 1 } },
			],
			"summary": Callable(script, "_summary_party"),
		},
		{
			"code": 10460, "name": "Change HP", "group": "Party", "length": 6,
			"params": _actor_target() + [
				{ "index": 2, "label": "Operation", "type": "enum", "choices": ["Increase", "Decrease"] },
			] + _amount_params(-1, [], 3, 4, 0, 9999, 1) + [
				{ "index": 5, "label": "Can be knocked out", "type": "bool", "when": { 2: 1 } },
			],
			"summary": Callable(script, "_summary_hp"),
		},
		{
			"code": 10490, "name": "Recover All", "group": "Party", "length": 2,
			"params": _actor_target(),
			"summary": Callable(script, "_summary_recover"),
		},
		{
			"code": 10810, "name": "Teleport", "group": "Map", "length": 3,
			"params": [
				{ "index": 0, "label": "Map", "type": "map", "default": 1 },
				{ "index": 1, "label": "X", "type": "int", "min": 0, "max": 499 },
				{ "index": 2, "label": "Y", "type": "int", "min": 0, "max": 499 },
				{ "index": 3, "label": "Facing", "type": "enum", "choices": ["Keep direction", "Up", "Right", "Down", "Left"], "engine": "2003" },
			],
			"summary": Callable(script, "_summary_teleport"),
		},
		{
			"code": 11410, "name": "Wait", "group": "Flow", "length": 1,
			"params": [{ "index": 0, "label": "Duration (tenths of a second)", "type": "int", "min": 0, "max": 9999, "default": 10 }],
			"summary": Callable(script, "_summary_wait"),
		},
		{
			"code": 11550, "name": "Play Sound Effect", "group": "Sound", "length": 3,
			"text": { "label": "Sound", "kind": "file", "folder": "Sound" },
			"params": [
				{ "index": 0, "label": "Volume", "type": "int", "min": 0, "max": 100, "default": 100 },
				{ "index": 1, "label": "Tempo", "type": "int", "min": 50, "max": 150, "default": 100 },
				{ "index": 2, "label": "Balance", "type": "int", "min": 0, "max": 100, "default": 50 },
			],
			"summary": Callable(script, "_summary_sound"),
		},
		{
			"code": 11510, "name": "Play BGM", "group": "Sound", "length": 4,
			"text": { "label": "Music", "kind": "file", "folder": "Music" },
			"params": [
				{ "index": 0, "label": "Fade in (ms)", "type": "int", "min": 0, "max": 10000 },
				{ "index": 1, "label": "Volume", "type": "int", "min": 0, "max": 100, "default": 100 },
				{ "index": 2, "label": "Tempo", "type": "int", "min": 50, "max": 150, "default": 100 },
				{ "index": 3, "label": "Balance", "type": "int", "min": 0, "max": 100, "default": 50 },
			],
			"summary": Callable(script, "_summary_bgm"),
		},
		{
			"code": 12330, "name": "Call Event", "group": "Flow", "length": 3,
			"params": [
				{ "index": 0, "label": "Call", "type": "enum", "choices": ["Common event", "Map event", "Map event (IDs from variables)"] },
				{ "index": 1, "label": "Common event", "type": "common_event", "default": 1, "when": { 0: 0 } },
				{ "index": 1, "label": "Event", "type": "event", "default": 10005, "when": { 0: 1 } },
				{ "index": 2, "label": "Page", "type": "int", "min": 1, "max": 100, "default": 1, "when": { 0: 1 } },
				{ "index": 1, "label": "Variable holding the event ID", "type": "variable", "default": 1, "when": { 0: 2 } },
				{ "index": 2, "label": "Variable holding the page", "type": "variable", "default": 1, "when": { 0: 2 } },
			],
			"summary": Callable(script, "_summary_call_event"),
		},
		{
			"code": 12110, "name": "Label", "group": "Flow", "length": 1,
			"params": [{ "index": 0, "label": "Label number", "type": "int", "min": 1, "max": 9999, "default": 1 }],
			"summary": Callable(script, "_summary_number"),
		},
		{
			"code": 12120, "name": "Jump to Label", "group": "Flow", "length": 1,
			"params": [{ "index": 0, "label": "Label number", "type": "int", "min": 1, "max": 9999, "default": 1 }],
			"summary": Callable(script, "_summary_number"),
		},
		{ "code": 12210, "name": "Loop", "group": "Flow", "block": { "end": 22210 } },
		{ "code": 12220, "name": "Break Loop", "group": "Flow" },
		{ "code": 12310, "name": "Stop Event Processing", "group": "Flow" },
		{ "code": 12320, "name": "Erase Event", "group": "Flow" },
		{ "code": 12420, "name": "Game Over", "group": "Flow" },
		{ "code": 12510, "name": "Return to Title Screen", "group": "Flow" },
		_conditional_branch(script),
	]


static func _conditional_branch(script: GDScript) -> Dictionary:
	var at_least := ["at least", "at most"]
	return {
		"code": 12010, "name": "Conditional Branch", "group": "Flow", "length": 6,
		"block": { "end": 22011, "else": { "code": 22010, "flag": 5 } },
		"text": { "label": "Name", "kind": "line", "when": { 0: 5, 2: 1 } },
		"params": [
			{ "index": 0, "label": "Condition", "type": "enum", "choices": ["Switch", "Variable", "Timer", "Money", "Item", "Actor", "Event facing", "Vehicle in use", "Started with the Action Button", "Music played once", "Timer 2", "Other"] },
			{ "index": 1, "label": "Switch", "type": "switch", "default": 1, "when": { 0: 0 } },
			{ "index": 2, "label": "Is", "type": "enum", "choices": ["ON", "OFF"], "when": { 0: 0 } },
			{ "index": 1, "label": "Variable", "type": "variable", "default": 1, "when": { 0: 1 } },
			{ "index": 4, "label": "Is", "type": "enum", "choices": COMPARISONS, "when": { 0: 1 } },
			{ "index": 2, "label": "Compared with", "type": "enum", "choices": ["Number", "Variable"], "when": { 0: 1 } },
			{ "index": 3, "label": "Number", "type": "int", "min": -9999999, "max": 9999999, "when": { 0: 1, 2: 0 } },
			{ "index": 3, "label": "Variable", "type": "variable", "default": 1, "when": { 0: 1, 2: 1 } },
			{ "index": 1, "label": "Seconds", "type": "int", "min": 0, "max": 5999, "when": { 0: [2, 10] } },
			{ "index": 2, "label": "Is", "type": "enum", "choices": at_least, "when": { 0: [2, 10] } },
			{ "index": 1, "label": "Money", "type": "int", "min": 0, "max": 999999, "when": { 0: 3 } },
			{ "index": 2, "label": "Is", "type": "enum", "choices": at_least, "when": { 0: 3 } },
			{ "index": 1, "label": "Item", "type": "item", "default": 1, "when": { 0: 4 } },
			{ "index": 2, "label": "Is", "type": "enum", "choices": ["Held", "Not held"], "when": { 0: 4 } },
			{ "index": 1, "label": "Actor", "type": "actor", "default": 1, "when": { 0: 5 } },
			{ "index": 2, "label": "Check", "type": "enum", "choices": ["Is in the party", "Name is", "Level is at least", "HP is at least", "Can use skill", "Has item equipped", "Has state"], "when": { 0: 5 } },
			{ "index": 3, "label": "Value", "type": "int", "min": 0, "max": 9999, "when": { 0: 5, 2: [2, 3] } },
			{ "index": 3, "label": "Skill", "type": "skill", "default": 1, "when": { 0: 5, 2: 4 } },
			{ "index": 3, "label": "Item", "type": "item", "default": 1, "when": { 0: 5, 2: 5 } },
			{ "index": 3, "label": "State", "type": "state", "default": 1, "when": { 0: 5, 2: 6 } },
			{ "index": 1, "label": "Event", "type": "event", "default": 10001, "when": { 0: 6 } },
			{ "index": 2, "label": "Facing", "type": "enum", "choices": DIRECTIONS, "when": { 0: 6 } },
			{ "index": 1, "label": "Vehicle", "type": "enum", "choices": ["Boat", "Ship", "Airship"], "when": { 0: 7 } },
			{ "index": 1, "label": "Value", "type": "int", "when": { 0: 11 } },
			{ "index": 5, "label": "Else branch", "type": "bool" },
		],
		"summary": Callable(script, "_summary_branch"),
	}


# --- helpers for schemas ----------------------------------------------------------

static func _p(c: Dictionary, index: int) -> int:
	return c.parameters[index] if index < c.parameters.size() else 0


## "Operation" plus "constant or variable" amount fields, as many commands use them.
static func _amount_params(op_index: int, op_choices: Array, from_index: int, value_index: int, minimum: int, maximum: int, default: int) -> Array:
	var out := []
	if op_index >= 0:
		out.append({ "index": op_index, "label": "Operation", "type": "enum", "choices": op_choices })
	out.append({ "index": from_index, "label": "Amount from", "type": "enum", "choices": ["Number", "Variable"] })
	out.append({ "index": value_index, "label": "Amount", "type": "int", "min": minimum, "max": maximum, "default": default, "when": { from_index: 0 } })
	out.append({ "index": value_index, "label": "Variable", "type": "variable", "default": 1, "when": { from_index: 1 } })
	return out


static func _actor_target() -> Array:
	return [
		{ "index": 0, "label": "Target", "type": "enum", "choices": ["Entire party", "Actor", "Actor ID from a variable"] },
		{ "index": 1, "label": "Actor", "type": "actor", "default": 1, "when": { 0: 1 } },
		{ "index": 1, "label": "Variable holding the actor ID", "type": "variable", "default": 1, "when": { 0: 2 } },
	]


## Single targets store their ID twice (first = last), as RPG Maker does.
static func _single_target(params: PackedInt32Array) -> PackedInt32Array:
	if params.size() > 2 and params[0] != 1:
		params[2] = params[1]
	return params


static func _target(params: PackedInt32Array, n: Variant, section: String) -> String:
	var mode := params[0] if params.size() > 0 else 0
	var first := params[1] if params.size() > 1 else 0
	var last := params[2] if params.size() > 2 else 0
	match mode:
		0: return n.ref(section, first)
		1: return "[%04d..%04d]" % [first, last]
	return "[V%s]" % n.ref("variables", first)


static func _value(c: Dictionary, from_index: int, value_index: int, n: Variant) -> String:
	return str(_p(c, value_index)) if _p(c, from_index) == 0 else "V" + n.ref("variables", _p(c, value_index))


static func _actor(c: Dictionary, n: Variant) -> String:
	match _p(c, 0):
		0: return "Entire party"
		1: return n.ref("actors", _p(c, 1))
	return "V" + n.ref("variables", _p(c, 1))


static func _operand(c: Dictionary, n: Variant) -> String:
	var a := _p(c, 5)
	var b := _p(c, 6)
	match _p(c, 4):
		0: return str(a)
		1: return "V" + n.ref("variables", a)
		2: return "V[V%s]" % n.ref("variables", a)
		3: return "Random %d..%d" % [a, b]
		4: return "%s %s" % [n.ref("items", a), "held" if b == 0 else "equipped"]
		5: return "%s %s" % [n.ref("actors", a), ACTOR_VALUES[b] if b < ACTOR_VALUES.size() else "value %d" % b]
		6: return "%s %s" % [n.event(a), EVENT_VALUES[b] if b < EVENT_VALUES.size() else "value %d" % b]
		7: return OTHER_VALUES[a] if a < OTHER_VALUES.size() else "Other %d" % a
	return "operand %d (%d, %d)" % [_p(c, 4), a, b]


static func _condition(c: Dictionary, n: Variant) -> String:
	var a := _p(c, 1)
	var b := _p(c, 2)
	var text := ""
	match _p(c, 0):
		0: text = "Switch %s is %s" % [n.ref("switches", a), "OFF" if b == 1 else "ON"]
		1:
			var other: String = str(_p(c, 3)) if b == 0 else "V" + n.ref("variables", _p(c, 3))
			var op: String = COMPARISON_SIGNS[_p(c, 4)] if _p(c, 4) < COMPARISON_SIGNS.size() else "?"
			text = "Variable %s %s %s" % [n.ref("variables", a), op, other]
		2: text = "Timer %s %d s" % ["<=" if b == 1 else ">=", a]
		3: text = "Money %s %d" % ["<=" if b == 1 else ">=", a]
		4: text = "%s %s" % [n.ref("items", a), "not held" if b == 1 else "held"]
		5:
			var checks := ["is in the party", "name is “%s”" % c.string, "level >= %d" % _p(c, 3), "HP >= %d" % _p(c, 3),
				"can use %s" % n.ref("skills", _p(c, 3)), "has %s equipped" % n.ref("items", _p(c, 3)), "has state %s" % n.ref("states", _p(c, 3))]
			text = "%s %s" % [n.ref("actors", a), checks[b] if b < checks.size() else "check %d" % b]
		6: text = "%s faces %s" % [n.event(a), DIRECTIONS[b] if b < 4 else "?"]
		7: text = "Using the %s" % (["boat", "ship", "airship"][a] if a < 3 else "vehicle %d" % a)
		8: text = "Started with the Action Button"
		9: text = "Music played once"
		10: text = "Timer 2 %s %d s" % ["<=" if b == 1 else ">=", a]
		_: text = "Condition %d (%d, %d)" % [_p(c, 0), a, b]
	return text + (", with Else" if _p(c, 5) == 1 else "")


# --- summaries (static methods, so the registry holds no lambdas) -----------------

static func _summary_text(c: Dictionary, _n: Variant) -> String:
	return c.string


static func _summary_switches(c: Dictionary, n: Variant) -> String:
	return "%s %s" % [_target(c.parameters, n, "switches"), ["ON", "OFF", "Toggle"][clampi(_p(c, 3), 0, 2)]]


static func _summary_variables(c: Dictionary, n: Variant) -> String:
	var sign: String = OPERATION_SIGNS[_p(c, 3)] if _p(c, 3) < OPERATION_SIGNS.size() else "op %d" % _p(c, 3)
	return "%s %s %s" % [_target(c.parameters, n, "variables"), sign, _operand(c, n)]


static func _summary_money(c: Dictionary, n: Variant) -> String:
	return "%s %s" % ["-" if _p(c, 0) == 1 else "+", _value(c, 1, 2, n)]


static func _summary_items(c: Dictionary, n: Variant) -> String:
	var item: String = n.ref("items", _p(c, 2)) if _p(c, 1) == 0 else "V" + n.ref("variables", _p(c, 2))
	return "%s %s %s" % [item, "-" if _p(c, 0) == 1 else "+", _value(c, 3, 4, n)]


static func _summary_party(c: Dictionary, n: Variant) -> String:
	var actor: String = n.ref("actors", _p(c, 2)) if _p(c, 1) == 0 else "V" + n.ref("variables", _p(c, 2))
	return "%s %s" % [["Add", "Remove"][clampi(_p(c, 0), 0, 1)], actor]


static func _summary_hp(c: Dictionary, n: Variant) -> String:
	return "%s HP %s %s" % [_actor(c, n), "-" if _p(c, 2) == 1 else "+", _value(c, 3, 4, n)]


static func _summary_recover(c: Dictionary, n: Variant) -> String:
	return _actor(c, n)


static func _summary_teleport(c: Dictionary, n: Variant) -> String:
	return "%s (%03d, %03d)" % [n.map(_p(c, 0)), _p(c, 1), _p(c, 2)]


static func _summary_wait(c: Dictionary, _n: Variant) -> String:
	return "%.1f s" % (_p(c, 0) / 10.0)


static func _summary_sound(c: Dictionary, _n: Variant) -> String:
	return "%s (%d, %d, %d)" % [c.string, _p(c, 0), _p(c, 1), _p(c, 2)]


static func _summary_bgm(c: Dictionary, _n: Variant) -> String:
	return "%s (%d, %d, %d)" % [c.string, _p(c, 1), _p(c, 2), _p(c, 3)]


static func _summary_call_event(c: Dictionary, n: Variant) -> String:
	match _p(c, 0):
		0: return n.ref("commonevents", _p(c, 1))
		1: return "%s, page %d" % [n.event(_p(c, 1)), _p(c, 2)]
	return "V%s, page V%s" % [n.ref("variables", _p(c, 1)), n.ref("variables", _p(c, 2))]


static func _summary_number(c: Dictionary, _n: Variant) -> String:
	return str(_p(c, 0))


static func _summary_branch(c: Dictionary, n: Variant) -> String:
	return _condition(c, n)
