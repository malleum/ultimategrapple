extends RefCounted
## Per-player input source. Every local runner owns one, so split-screen can
## give each player their own device.
##   device = KBM  : keyboard + mouse (InputMap actions)
##   device = ANY  : keyboard + mouse + every gamepad (solo convenience)
##   device >= 0   : one specific gamepad
## Call poll() once per physics tick; then query pressed()/just_pressed().

const KBM := -1
const ANY := -2

const ACTIONS := ["jump", "dash", "grapple", "zip", "throw", "snap", "pivot", "throw_next", "throw_prev",
	"nose_up", "nose_down", "recall", "restart", "pause", "move_down", "move_up", "throw_1", "throw_2",
	"throw_3", "throw_4", "throw_5", "throw_6"]

const DEADZONE := 0.25
const TRIGGER := 0.45

# Xbox-style layout
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"dash": [JOY_BUTTON_X],
	"pivot": [JOY_BUTTON_B],
	"recall": [JOY_BUTTON_Y],
	"snap": [JOY_BUTTON_RIGHT_SHOULDER],
	"zip": [JOY_BUTTON_LEFT_SHOULDER],
	"throw_next": [JOY_BUTTON_DPAD_RIGHT],
	"throw_prev": [JOY_BUTTON_DPAD_LEFT],
	"nose_up": [JOY_BUTTON_DPAD_UP],
	"nose_down": [JOY_BUTTON_DPAD_DOWN],
	"restart": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}

var device := ANY
var _prev := {}
var _cur := {}
var move := Vector2.ZERO
var stick_aim := Vector2.RIGHT   # last non-neutral right-stick direction
var stick_active := false        # right stick currently deflected
var using_pad := false           # last input came from a pad (ANY mode)
var mouse_world_fn: Callable     # returns the mouse position in world space for this view
## Event-time stamps (µs) for the snap mechanic, taken when the input event
## arrives rather than when a physics tick happens to poll it.
var snap_us := -1
var throw_release_us := -1
var _trig_r := 0.0


func _init(p_device := ANY) -> void:
	device = p_device


func uses_kbm() -> bool:
	return device == KBM or device == ANY


func uses_pad(id: int) -> bool:
	return device == id or (device == ANY)


func label() -> String:
	if device == KBM:
		return "Keyboard + Mouse"
	if device == ANY:
		return "Any"
	return Input.get_joy_name(device) if Input.get_joy_name(device) != "" else "Pad %d" % device


func poll() -> void:
	_prev = _cur
	_cur = {}
	for a in ACTIONS:
		_cur[a] = _raw(a)
	# movement
	var m := Vector2.ZERO
	if uses_kbm():
		m.x = Input.get_axis("move_left", "move_right")
		m.y = Input.get_axis("move_up", "move_down")
	var pm := Vector2.ZERO
	var ra := Vector2.ZERO
	for id in _pads():
		var v := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		if v.length() < DEADZONE:
			v = Vector2.ZERO
		if v.length() > pm.length():
			pm = v
		var r := Vector2(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		if r.length() > ra.length():
			ra = r
	if pm != Vector2.ZERO:
		using_pad = true
		m = pm
	elif m != Vector2.ZERO:
		using_pad = false
	move = m
	stick_active = ra.length() > 0.35
	if stick_active:
		stick_aim = ra.normalized()
		using_pad = true
	elif device >= 0 and m.length() > 0.5:
		# no right stick: aim follows the movement direction
		stick_aim = stick_aim.lerp(m.normalized(), 0.15).normalized()


func _pads() -> Array:
	if device >= 0:
		return [device]
	if device == ANY:
		return Input.get_connected_joypads()
	return []


func _raw(a: String) -> bool:
	if uses_kbm() and InputMap.has_action(a) and Input.is_action_pressed(a):
		return true
	for id in _pads():
		match a:
			"throw":
				if Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER:
					return true
			"grapple":
				if Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT) > TRIGGER:
					return true
			"move_down":
				if Input.get_joy_axis(id, JOY_AXIS_LEFT_Y) > 0.6:
					return true
			"move_up":
				if Input.get_joy_axis(id, JOY_AXIS_LEFT_Y) < -0.6:
					return true
			_:
				for b in PAD_BUTTONS.get(a, []):
					if Input.is_joy_button_pressed(id, b):
						return true
	return false


func _pad_ok(id: int) -> bool:
	return device == id or device == ANY


func handle_event(ev: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if ev is InputEventKey or ev is InputEventMouseButton:
		if not uses_kbm():
			return
		if ev.is_action_pressed("snap"):
			snap_us = now
		elif ev.is_action_released("throw"):
			throw_release_us = now
	elif ev is InputEventJoypadButton:
		if _pad_ok(ev.device) and ev.pressed and PAD_BUTTONS.snap.has(ev.button_index):
			snap_us = now
	elif ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_TRIGGER_RIGHT and _pad_ok(ev.device):
		if _trig_r > TRIGGER and ev.axis_value <= TRIGGER:
			throw_release_us = now
		_trig_r = ev.axis_value


## Timestamp of a press/release that the poll just reported: the event time if
## we saw the event recently, otherwise now (scripted/test input has no events).
static func stamp(event_us: int, now_us: int) -> int:
	if event_us > 0 and now_us - event_us < 80000:
		return event_us
	return now_us


func pressed(a: String) -> bool:
	return _cur.get(a, false)


func just_pressed(a: String) -> bool:
	return _cur.get(a, false) and not _prev.get(a, false)


func just_released(a: String) -> bool:
	return not _cur.get(a, false) and _prev.get(a, false)


## Aim target in world space. Mouse for KBM; stick direction projected from `origin` for pads.
func aim_point(origin: Vector2) -> Vector2:
	if uses_kbm() and not (device == ANY and using_pad) and mouse_world_fn.is_valid():
		return mouse_world_fn.call()
	return origin + stick_aim * 320.0


func is_pad_aim() -> bool:
	return device >= 0 or (device == ANY and using_pad)


## Release everything (e.g. when input gets disabled mid-hold).
func clear() -> void:
	_prev = {}
	_cur = {}
	move = Vector2.ZERO
