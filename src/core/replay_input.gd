extends "res://src/core/player_input.gd"
## Plays a recorded run back through the normal input interface: one
## recorded tick per poll(), bit-exact (moves, aim, snap timing). Real
## keyboard / mouse / pad input is ignored.

const BASE_US := 1000000000   # recorded times are relative; keep them positive

var data: Dictionary = {}
var tick := 0
var mouse_now := Vector2.ZERO
var pad_aim := false


func _init(p_rec: Dictionary = {}) -> void:
	device = REPLAY
	data = p_rec


func label() -> String:
	return "Replay"


func uses_kbm() -> bool:
	return false


func rewind() -> void:
	tick = 0
	clear()


func ticks() -> int:
	return data.get("bits", PackedInt32Array()).size()


func finished() -> bool:
	return tick >= ticks()


func _abs(rel: int) -> int:
	return rel + BASE_US if rel >= 0 else -1


func poll() -> void:
	_prev = _cur
	_cur = {}
	if finished():
		move = Vector2.ZERO
		_now_us = _abs(int(data.now[-1]) + (tick - ticks() + 1) * 8333) if ticks() > 0 else BASE_US
		tick += 1
		return
	var bits: int = data.bits[tick]
	for i in ACTIONS.size():
		if bits & (1 << i):
			_cur[ACTIONS[i]] = true
	pad_aim = bits & (1 << 30) != 0
	using_pad = pad_aim
	_has_mouse = bits & (1 << 29) == 0
	move = data.move[tick]
	mouse_now = data.mouse[tick]
	_mouse = mouse_now
	stick_aim = data.stick[tick]
	stick_active = pad_aim
	_now_us = _abs(int(data.now[tick]))
	snap_us = _abs(int(data.snap[tick]))
	throw_release_us = _abs(int(data.rel[tick]))
	tick += 1


func handle_event(_ev: InputEvent) -> void:
	pass


func aim_point(origin: Vector2) -> Vector2:
	if pad_aim or not _has_mouse:
		return origin + stick_aim * 320.0
	return mouse_now


func aim_point_draw(origin: Vector2) -> Vector2:
	return aim_point(origin)


func is_pad_aim() -> bool:
	return pad_aim
