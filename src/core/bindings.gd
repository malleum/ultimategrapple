extends RefCounted
## Rebindable controls. Bindings are stored as short strings so they survive
## JSON round-trips in settings.json:
##   keyboard + mouse:  "k:<physical keycode>"   "m:<mouse button index>"
##   controller:        "b:<joy button index>"    "a:<joy axis>" (trigger, pulled)
## Mouse wheel and side buttons (MOUSE 4 / MOUSE 5) bind like any other button.
## Wheel notches can't be "held", so they act as one-tick taps (see PlayerInput).
## Fixed, not rebindable: ESC / START pause, TAB scoreboard, sticks move/aim.

## [action, label] in menu order.
const KBM_ACTIONS := [
	["move_left", "Run left"], ["move_right", "Run right"],
	["move_up", "Up · reel in"], ["move_down", "Slide · crouch · reel out"],
	["jump", "Jump · double jump"], ["grapple", "Grapple swing (hold)"], ["zip", "Zip (hold)"],
	["throw", "Charge + throw"], ["snap", "Snap"], ["pivot", "Pivot (hold)"],
	["throw_next", "Next throw"], ["throw_prev", "Previous throw"],
	["throw_1", "Backhand"], ["throw_2", "Forehand"], ["throw_3", "Hammer"],
	["throw_4", "Roller"], ["throw_5", "Scoober"], ["throw_6", "Thumber"],
	["nose_up", "Nose up"], ["nose_down", "Nose down"],
	["recall", "Recall disc"], ["restart", "Restart"], ["pin", "Pin course"], ["next_level", "Next course"],
]
const PAD_ACTIONS := [
	["jump", "Jump · double jump"], ["grapple", "Grapple swing (hold)"], ["zip", "Zip (hold)"],
	["throw", "Charge + throw"], ["snap", "Snap"], ["pivot", "Pivot (hold)"],
	["throw_next", "Next throw"], ["throw_prev", "Previous throw"],
	["nose_up", "Nose up"], ["nose_down", "Nose down"],
	["recall", "Recall disc"], ["restart", "Restart"],
]
const KBM_SLOTS := 2
const PAD_SLOTS := 2

## Always-on extras that are not in the rebind lists.
const FIXED_KBM := {"pause": [KEY_ESCAPE], "scoreboard": [KEY_TAB]}

const MOUSE_NAMES := {1: "LMB", 2: "RMB", 3: "MMB", 4: "WHEEL UP", 5: "WHEEL DOWN", 6: "WHEEL LEFT",
	7: "WHEEL RIGHT", 8: "MOUSE 4", 9: "MOUSE 5"}
const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "BACK", 5: "GUIDE", 6: "START", 7: "LS", 8: "RS",
	9: "LB", 10: "RB", 11: "D-UP", 12: "D-DOWN", 13: "D-LEFT", 14: "D-RIGHT", 15: "SHARE",
	16: "PADDLE 1", 17: "PADDLE 2", 18: "PADDLE 3", 19: "PADDLE 4", 20: "TOUCHPAD"}
const AXIS_NAMES := {4: "LT", 5: "RT"}

static var kbm: Dictionary = {}
static var pad: Dictionary = {}
## mouse wheel button index -> [actions]; these never enter the InputMap
static var wheel: Dictionary = {}


static func default_kbm() -> Dictionary:
	return {
		"move_left": [_k(KEY_A), _k(KEY_LEFT)],
		"move_right": [_k(KEY_D), _k(KEY_RIGHT)],
		"move_up": [_k(KEY_W), _k(KEY_UP)],
		"move_down": [_k(KEY_S), _k(KEY_DOWN)],
		"jump": [_k(KEY_SPACE)],
		"grapple": [_m(MOUSE_BUTTON_RIGHT)],
		"zip": [_k(KEY_E), _m(MOUSE_BUTTON_XBUTTON2)],
		"throw": [_m(MOUSE_BUTTON_LEFT)],
		"snap": [_k(KEY_F), _m(MOUSE_BUTTON_XBUTTON1)],
		"pivot": [_k(KEY_CTRL)],
		"throw_next": [_k(KEY_Q)],
		"throw_prev": [],
		"throw_1": [_k(KEY_1)], "throw_2": [_k(KEY_2)], "throw_3": [_k(KEY_3)],
		"throw_4": [_k(KEY_4)], "throw_5": [_k(KEY_5)], "throw_6": [_k(KEY_6)],
		"nose_up": [_k(KEY_X), _m(MOUSE_BUTTON_WHEEL_UP)],
		"nose_down": [_k(KEY_Z), _m(MOUSE_BUTTON_WHEEL_DOWN)],
		"recall": [_k(KEY_T)],
		"restart": [_k(KEY_R)],
		"pin": [_k(KEY_P)],
		"next_level": [_k(KEY_N)],
	}


static func default_pad() -> Dictionary:
	return {
		"jump": [_b(JOY_BUTTON_A)],
		"grapple": [_a(JOY_AXIS_TRIGGER_LEFT)],
		"zip": [_b(JOY_BUTTON_LEFT_SHOULDER)],
		"throw": [_a(JOY_AXIS_TRIGGER_RIGHT)],
		"snap": [_b(JOY_BUTTON_RIGHT_SHOULDER)],
		"pivot": [_b(JOY_BUTTON_B)],
		"throw_next": [_b(JOY_BUTTON_DPAD_RIGHT)],
		"throw_prev": [_b(JOY_BUTTON_DPAD_LEFT)],
		"nose_up": [_b(JOY_BUTTON_DPAD_UP)],
		"nose_down": [_b(JOY_BUTTON_DPAD_DOWN)],
		"recall": [_b(JOY_BUTTON_Y)],
		"restart": [_b(JOY_BUTTON_BACK)],
	}


static func _k(code: int) -> String: return "k:%d" % code
static func _m(idx: int) -> String: return "m:%d" % idx
static func _b(idx: int) -> String: return "b:%d" % idx
static func _a(axis: int) -> String: return "a:%d" % axis


## Load from the saved settings blob ({"kbm": {...}, "pad": {...}}), falling
## back to defaults per action, then push into the InputMap.
static func load_from(saved) -> void:
	kbm = _merge(default_kbm(), saved.get("kbm", {}) if saved is Dictionary else {}, ["k:", "m:"])
	pad = _merge(default_pad(), saved.get("pad", {}) if saved is Dictionary else {}, ["b:", "a:"])
	apply()


static func _merge(defaults: Dictionary, saved, prefixes: Array) -> Dictionary:
	var out := defaults
	if not saved is Dictionary:
		return out
	for a in saved:
		if not out.has(a) or not saved[a] is Array:
			continue
		var codes: Array = []
		for c in saved[a]:
			var sc := str(c)
			if sc.substr(0, 2) in prefixes and sc.substr(2).is_valid_int():
				codes.append(sc)
		out[a] = codes
	return out


static func to_dict() -> Dictionary:
	return {"kbm": kbm.duplicate(true), "pad": pad.duplicate(true)}


static func reset(device: String) -> void:
	if device == "pad":
		pad = default_pad()
	else:
		kbm = default_kbm()
	apply()


## Rebuild InputMap actions for keyboard + mouse.
static func apply() -> void:
	wheel = {}
	var all := {}
	for a in kbm:
		all[a] = true
	for a in FIXED_KBM:
		all[a] = true
	for a in all:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a, 0.2)
	for a in FIXED_KBM:
		for code in FIXED_KBM[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(a, ev)
	for a in kbm:
		for c in kbm[a]:
			var idx := int(str(c).substr(2))
			if str(c).begins_with("k:"):
				var ev := InputEventKey.new()
				ev.physical_keycode = idx
				InputMap.action_add_event(a, ev)
			elif is_wheel(idx):
				if not wheel.has(idx):
					wheel[idx] = []
				wheel[idx].append(a)
			else:
				var mev := InputEventMouseButton.new()
				mev.button_index = idx
				InputMap.action_add_event(a, mev)


static func is_wheel(mouse_idx: int) -> bool:
	return mouse_idx >= MOUSE_BUTTON_WHEEL_UP and mouse_idx <= MOUSE_BUTTON_WHEEL_RIGHT


## Set slot `slot` of `action` to `code`, unbinding it from any other action on
## the same device. Returns the action it was taken from ("" if none).
static func bind(device: String, action: String, slot: int, code: String) -> String:
	var map: Dictionary = pad if device == "pad" else kbm
	var taken := ""
	for a in map:
		if a != action and map[a].has(code):
			map[a].erase(code)
			taken = a
	var arr: Array = map.get(action, [])
	arr.erase(code)
	if slot < arr.size():
		arr[slot] = code
	else:
		arr.append(code)
	map[action] = arr
	apply()
	return taken


static func unbind(device: String, action: String, slot: int) -> void:
	var map: Dictionary = pad if device == "pad" else kbm
	var arr: Array = map.get(action, [])
	if slot < arr.size():
		arr.remove_at(slot)
	apply()


## Binding string for an input event captured in the rebind menu, or "".
static func code_for_event(ev: InputEvent) -> String:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var pc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return _k(pc) if pc != 0 else ""
	if ev is InputEventMouseButton and ev.pressed:
		return _m(ev.button_index)
	if ev is InputEventJoypadButton and ev.pressed:
		return _b(ev.button_index)
	if ev is InputEventJoypadMotion and ev.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and ev.axis_value > 0.6:
		return _a(ev.axis)
	return ""


static func code_label(code: String) -> String:
	var idx := int(code.substr(2))
	match code.substr(0, 2):
		"k:":
			var s := OS.get_keycode_string(idx)
			return s.to_upper() if s != "" else "KEY %d" % idx
		"m:":
			return MOUSE_NAMES.get(idx, "MOUSE %d" % idx)
		"b:":
			return PAD_NAMES.get(idx, "BUTTON %d" % idx)
		"a:":
			return AXIS_NAMES.get(idx, "AXIS %d" % idx)
	return "?"


## First binding of an action as a short keycap label ("" when unbound).
static func label(action: String, use_pad := false) -> String:
	if use_pad:
		if action == "pause":
			return "START"
		var p: Array = pad.get(action, [])
		return code_label(p[0]) if not p.is_empty() else ""
	if FIXED_KBM.has(action):
		return OS.get_keycode_string(FIXED_KBM[action][0]).to_upper()
	var k: Array = kbm.get(action, [])
	return code_label(k[0]) if not k.is_empty() else ""


## Keycap labels for the replay keystroke overlay, frozen at record time
## so friends see the keys you actually used.
static func snapshot_labels() -> Dictionary:
	var out := {"kbm": {}, "pad": {}}
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "grapple", "zip", "throw", "snap", "pivot", "recall"]:
		out.kbm[a] = label(a)
		out.pad[a] = label(a, true)
	out.pad["move_left"] = "LS ←"
	out.pad["move_right"] = "LS →"
	out.pad["move_up"] = "LS ↑"
	out.pad["move_down"] = "LS ↓"
	return out


## All bindings of an action joined for help text, e.g. "F / MOUSE 4".
static func labels(action: String, use_pad := false) -> String:
	var arr: Array = (pad if use_pad else kbm).get(action, [])
	var parts := []
	for c in arr:
		parts.append(code_label(c))
	return " / ".join(parts) if not parts.is_empty() else "unbound"
