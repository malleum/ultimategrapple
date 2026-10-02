extends RefCounted
## Per-player input source. Every local runner owns one, so split-screen can
## give each player their own device.
##   device = KBM  : keyboard + mouse (InputMap actions)
##   device = ANY  : keyboard + mouse + every gamepad (solo convenience)
##   device >= 0   : one specific gamepad
## Call poll() once per physics tick; then query pressed()/just_pressed().

const KBM := -1
const ANY := -2
const REPLAY := -3

const ACTIONS := ["jump", "grapple", "zip", "throw", "snap", "pivot", "throw_next", "throw_prev",
	"nose_up", "nose_down", "recall", "restart", "pause", "move_down", "move_up", "throw_1", "throw_2",
	"throw_3", "throw_4", "throw_5", "throw_6"]

const DEADZONE := 0.25
const TRIGGER := 0.45

const Bindings = preload("res://src/core/bindings.gd")

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
## Per-tick snapshots, so the simulation reads one consistent value per tick
## (and a replay can feed back exactly the same numbers).
var _now_us := 0
var _mouse := Vector2.ZERO
var _has_mouse := false
## Recording (solo runs, for replays): one entry per poll().
var recording := false
var rec: Dictionary = {}
var _rec_t0 := 0
var _axes := {}                  # joy axis -> last value (for trigger press/release edges)
var _taps := {}                  # actions pulsed by mouse wheel notches since the last poll


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
	_now_us = Time.get_ticks_usec()
	_prev = _cur
	_cur = {}
	for a in ACTIONS:
		_cur[a] = _raw(a) or _taps.has(a)
	_taps.clear()
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
	_has_mouse = uses_kbm() and mouse_world_fn.is_valid()
	if _has_mouse:
		_mouse = mouse_world_fn.call()
	if recording:
		_record_tick()


## Start a fresh recording (called on restart).
func start_recording() -> void:
	recording = true
	_rec_t0 = Time.get_ticks_usec()
	rec = {"bits": PackedInt32Array(), "move": PackedVector2Array(), "mouse": PackedVector2Array(),
		"stick": PackedVector2Array(), "now": PackedInt64Array(), "snap": PackedInt64Array(), "rel": PackedInt64Array()}


func stop_recording() -> void:
	recording = false


func _rel(us: int) -> int:
	return us - _rec_t0 if us > 0 else -1


func _record_tick() -> void:
	var bits := 0
	for i in ACTIONS.size():
		if _cur.get(ACTIONS[i], false):
			bits |= 1 << i
	if is_pad_aim():
		bits |= 1 << 30
	if not _has_mouse:
		bits |= 1 << 29
	rec.bits.append(bits)
	rec.move.append(move)
	rec.mouse.append(_mouse)
	rec.stick.append(stick_aim)
	rec.now.append(_rel(_now_us))
	rec.snap.append(_rel(snap_us))
	rec.rel.append(_rel(throw_release_us))


## Clock for gameplay timing (snap judging): the time this tick was polled.
func now_us() -> int:
	return _now_us if _now_us > 0 else Time.get_ticks_usec()


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
			"move_down":
				if Input.get_joy_axis(id, JOY_AXIS_LEFT_Y) > 0.6:
					return true
			"move_up":
				if Input.get_joy_axis(id, JOY_AXIS_LEFT_Y) < -0.6:
					return true
			"pause":
				if Input.is_joy_button_pressed(id, JOY_BUTTON_START):
					return true
		for c in Bindings.pad.get(a, []):
			var idx := int(str(c).substr(2))
			if str(c).begins_with("b:"):
				if Input.is_joy_button_pressed(id, idx):
					return true
			elif Input.get_joy_axis(id, idx) > TRIGGER:
				return true
	return false


func _pad_ok(id: int) -> bool:
	return device == id or device == ANY


func handle_event(ev: InputEvent) -> void:
	var now := Time.get_ticks_usec()
	if ev is InputEventKey or ev is InputEventMouseButton:
		if not uses_kbm():
			return
		if ev is InputEventMouseButton and ev.pressed and Bindings.wheel.has(ev.button_index):
			for a in Bindings.wheel[ev.button_index]:
				_taps[a] = true
				if a == "snap":
					snap_us = now
			return
		if ev.is_action_pressed("snap"):
			snap_us = now
		elif ev.is_action_released("throw"):
			throw_release_us = now
	elif ev is InputEventJoypadButton:
		if not _pad_ok(ev.device):
			return
		var code := "b:%d" % ev.button_index
		if ev.pressed and Bindings.pad.get("snap", []).has(code):
			snap_us = now
		elif not ev.pressed and Bindings.pad.get("throw", []).has(code):
			throw_release_us = now
	elif ev is InputEventJoypadMotion and _pad_ok(ev.device):
		var key: int = ev.device * 64 + ev.axis
		var was: float = _axes.get(key, 0.0)
		_axes[key] = ev.axis_value
		var code := "a:%d" % ev.axis
		if was <= TRIGGER and ev.axis_value > TRIGGER and Bindings.pad.get("snap", []).has(code):
			snap_us = now
		elif was > TRIGGER and ev.axis_value <= TRIGGER and Bindings.pad.get("throw", []).has(code):
			throw_release_us = now


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
		return _mouse if _has_mouse else mouse_world_fn.call()
	return origin + stick_aim * 320.0


## Same, but live every frame: for drawing the reticle smoothly.
func aim_point_draw(origin: Vector2) -> Vector2:
	if uses_kbm() and not (device == ANY and using_pad) and mouse_world_fn.is_valid():
		return mouse_world_fn.call()
	return origin + stick_aim * 320.0


## Is this action held right now (for the keystroke overlay)?
func held(a: String) -> bool:
	return _cur.get(a, false)


func is_pad_aim() -> bool:
	return device >= 0 or (device == ANY and using_pad)


## Release everything (e.g. when input gets disabled mid-hold).
func clear() -> void:
	_prev = {}
	_cur = {}
	_taps = {}
	move = Vector2.ZERO
