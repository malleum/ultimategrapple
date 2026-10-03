extends SceneTree
## Rebinding checks: side mouse buttons, wheel taps, key moves, controller
## buttons/triggers, conflicts, snap timing hooks, save/load round-trip and
## which pads rumble.
## godot --headless -s tools/test_bindings.gd

const Bindings = preload("res://src/core/bindings.gd")
const PlayerInput = preload("res://src/core/player_input.gd")

var fails := 0
var started := false


func _check(what: String, ok: bool) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func _mouse(idx: int, down: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	return ev


func _key(code: int, down: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	return ev


func _process(_dt: float) -> bool:
	if started:
		return false
	started = true
	var saved: Dictionary = Bindings.to_dict()
	Bindings.reset("kbm")
	Bindings.reset("pad")
	var inp := PlayerInput.new(PlayerInput.KBM)

	# defaults: throw LMB, snap RMB, side buttons drive grapple (MOUSE 4) and
	# zip (MOUSE 5), nothing on F
	_mouse(MOUSE_BUTTON_XBUTTON1, true)
	inp.poll()
	_check("default MOUSE 4 -> grapple", inp.pressed("grapple"))
	_mouse(MOUSE_BUTTON_XBUTTON1, false)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	inp.poll()
	_check("default RMB -> snap", inp.pressed("snap") and not inp.pressed("grapple"))
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_check("default LMB -> throw", Bindings.kbm.throw == ["m:%d" % MOUSE_BUTTON_LEFT])
	var on_f: Array = []
	for a in Bindings.kbm:
		if Bindings.kbm[a].has("k:%d" % KEY_F):
			on_f.append(a)
	_check("nothing on F %s" % [on_f], on_f.is_empty())
	# saves from before the new defaults are dropped; current ones load back
	Bindings.load_from({"kbm": {"snap": ["k:%d" % KEY_F]}})
	_check("old save reset", not Bindings.kbm.snap.has("k:%d" % KEY_F))
	Bindings.bind("kbm", "recall", 1, "k:%d" % KEY_H)
	Bindings.load_from(Bindings.to_dict())
	_check("current save kept", Bindings.kbm.recall.has("k:%d" % KEY_H))
	Bindings.reset("kbm")
	inp.poll()

	# rebind jump to MOUSE 5: it leaves zip, and both side buttons work
	var taken := Bindings.bind("kbm", "jump", 0, "m:%d" % MOUSE_BUTTON_XBUTTON2)
	_check("conflict reported (zip)", taken == "zip")
	_check("zip lost MOUSE 5", not Bindings.kbm.zip.has("m:%d" % MOUSE_BUTTON_XBUTTON2))
	inp.poll()
	_mouse(MOUSE_BUTTON_XBUTTON2, true)
	inp.poll()
	_check("MOUSE 5 -> jump just_pressed", inp.just_pressed("jump"))
	_check("MOUSE 5 no longer zip", not inp.pressed("zip"))
	_mouse(MOUSE_BUTTON_XBUTTON2, false)
	inp.poll()
	_check("MOUSE 5 release", not inp.pressed("jump"))
	_check("SPACE kept as 2nd? (slot 0 replaced)", not Bindings.kbm.jump.has("k:%d" % KEY_SPACE))

	# throw on a side button, snap on a key: event timestamps still recorded
	Bindings.bind("kbm", "throw", 0, "m:%d" % MOUSE_BUTTON_XBUTTON1)
	Bindings.bind("kbm", "snap", 0, "k:%d" % KEY_G)
	inp.handle_event(_key(KEY_G, true))
	_check("snap timestamp from rebound key", inp.snap_us > 0)
	_mouse(MOUSE_BUTTON_XBUTTON1, true)
	inp.handle_event(_mouse(MOUSE_BUTTON_XBUTTON1, false))
	_check("throw release timestamp from side button", inp.throw_release_us > 0)
	_key(KEY_G, false)

	# wheel bound to an action = one-tick tap
	Bindings.bind("kbm", "recall", 0, "m:%d" % MOUSE_BUTTON_WHEEL_UP)
	_check("wheel up left nose_up", not Bindings.kbm.nose_up.has("m:%d" % MOUSE_BUTTON_WHEEL_UP))
	inp.poll()
	var wev := InputEventMouseButton.new()
	wev.button_index = MOUSE_BUTTON_WHEEL_UP
	wev.pressed = true
	inp.handle_event(wev)
	inp.poll()
	_check("wheel tap -> recall just_pressed", inp.just_pressed("recall"))
	inp.poll()
	_check("wheel tap lasts one tick", not inp.pressed("recall"))

	# unbind
	Bindings.unbind("kbm", "pivot", 0)
	_check("pivot unbound", Bindings.kbm.pivot.is_empty() and Bindings.label("pivot") == "")

	# controller: button + trigger, snap/throw edges
	Bindings.bind("pad", "snap", 0, "a:%d" % JOY_AXIS_TRIGGER_LEFT)
	_check("LT left grapple", not Bindings.pad.grapple.has("a:%d" % JOY_AXIS_TRIGGER_LEFT))
	Bindings.bind("pad", "throw", 0, "b:%d" % JOY_BUTTON_RIGHT_SHOULDER)
	var pin := PlayerInput.new(0)
	var m := InputEventJoypadMotion.new()
	m.device = 0
	m.axis = JOY_AXIS_TRIGGER_LEFT
	m.axis_value = 0.9
	pin.handle_event(m)
	_check("trigger snap timestamp", pin.snap_us > 0)
	var b := InputEventJoypadButton.new()
	b.device = 0
	b.button_index = JOY_BUTTON_RIGHT_SHOULDER
	b.pressed = false
	pin.handle_event(b)
	_check("button throw release timestamp", pin.throw_release_us > 0)
	_check("pad labels", Bindings.label("snap", true) == "LT" and Bindings.label("throw", true) == "RB")

	# capture helper
	var cap := InputEventMouseButton.new()
	cap.button_index = MOUSE_BUTTON_XBUTTON2
	cap.pressed = true
	_check("capture side button", Bindings.code_for_event(cap) == "m:9" and Bindings.code_label("m:9") == "MOUSE 5")

	# save/load round trip through JSON, with junk entries ignored
	var blob = JSON.parse_string(JSON.stringify(Bindings.to_dict()))
	blob.kbm["jump"].append("zz:1")
	blob.kbm["not_an_action"] = ["k:65"]
	var before: Dictionary = Bindings.to_dict()
	Bindings.reset("kbm")
	Bindings.reset("pad")
	Bindings.load_from(blob)
	_check("round trip kbm", JSON.stringify(Bindings.kbm) == JSON.stringify(before.kbm))
	_check("round trip pad", JSON.stringify(Bindings.pad) == JSON.stringify(before.pad))
	_check("InputMap rebuilt", InputMap.action_get_events("jump").size() == 1 and InputMap.action_get_events("pause").size() == 1)

	# rumble: only pads this input reads, and in solo only while a pad is in use
	var Rumble = load("res://src/core/rumble.gd")
	_check("rumble kbm: no pads", Rumble.pads_for(PlayerInput.new(PlayerInput.KBM)).is_empty())
	var any_in := PlayerInput.new(PlayerInput.ANY)
	any_in.using_pad = false
	_check("rumble solo on keyboard: no pads", Rumble.pads_for(any_in).is_empty())
	_check("rumble unplugged pad: nothing", Rumble.pads_for(PlayerInput.new(5)).is_empty())
	for nm in Rumble.PATTERNS:
		_check("rumble pattern %s" % nm, (Rumble.PATTERNS[nm] as Array).size() == 3)

	Bindings.load_from(saved)
	print("bindings: %d failures" % fails)
	quit(0 if fails == 0 else 1)
	return false
