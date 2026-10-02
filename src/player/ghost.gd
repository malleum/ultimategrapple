extends Node2D
## Non-colliding ghost runner: plays back a recorded run or mirrors a remote player.
## Frame format: [x, y, vx, vy, facing, flags, ax, ay, disc_x, disc_y, disc_vis]

const PlayerVisual = preload("res://src/player/player_visual.gd")

const REC_INTERVAL := 4.0 / 120.0   # seconds between recorded frames

var visual: Node2D
var frames: Array = []
var play_t := 0.0
var playing := false
var remote := false
var buffer: Array = []      # remote: [[time, frame], ...]
var delay := 0.1
var disc_pos := Vector2.ZERO
var disc_vis := false
var disc_color := Color(1, 1, 1)
var disc_flying := false
var disc_vel := Vector2.ZERO
var _prev_disc := Vector2.ZERO
var _prev_disc_ok := false
var cur: Array = []


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual = PlayerVisual.new()
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual.alpha = 0.45
	add_child(visual)
	z_index = -1
	visible = false   # until it has something to show


func setup_replay(p_frames: Array, color: Color) -> void:
	frames = p_frames
	visual.color = color
	disc_color = color
	visible = not frames.is_empty()


func setup_remote(p_name: String, color: Color) -> void:
	remote = true
	visible = true
	visual.color = color
	visual.alpha = 0.6
	visual.name_tag = p_name
	disc_color = color


func start() -> void:
	play_t = 0.0
	playing = true


func stop() -> void:
	playing = false


## Back to the first recorded frame and wait there (restart).
func rewind() -> void:
	playing = false
	play_t = 0.0
	if frames.is_empty():
		return
	_apply(frames[0], 0.0)
	# the scarf and pose would otherwise keep their old world positions
	visual.reset_scarf()
	reset_physics_interpolation()


func push_state(frame: Array) -> void:
	buffer.append([Time.get_ticks_msec() / 1000.0, frame])
	while buffer.size() > 40:
		buffer.pop_front()


func _process(dt: float) -> void:
	var f: Array = []
	if remote:
		f = _remote_frame()
	elif playing and frames.size() > 1:
		play_t += dt
		var idx := play_t / REC_INTERVAL
		var i := int(idx)
		if i >= frames.size() - 1:
			f = frames[-1]
		else:
			f = _lerp_frame(frames[i], frames[i + 1], idx - i)
	if f.is_empty():
		return
	_apply(f, dt)


func _apply(f: Array, dt: float) -> void:
	cur = f
	position = Vector2(f[0], f[1])
	visual.update_from_snapshot(f, position, dt)
	disc_vis = f.size() > 10 and f[10] > 0.5
	disc_flying = disc_vis and (int(f[5]) & 64) != 0
	if disc_vis:
		disc_pos = Vector2(f[8], f[9])
		if _prev_disc_ok and dt > 0.0:
			disc_vel = disc_vel.lerp((disc_pos - _prev_disc) / dt, 0.5)
		_prev_disc = disc_pos
		_prev_disc_ok = true
	else:
		_prev_disc_ok = false
		disc_vel = Vector2.ZERO
	queue_redraw()


func is_stunned() -> bool:
	return not cur.is_empty() and (int(cur[5]) & (128 | 256)) != 0


func _remote_frame() -> Array:
	if buffer.is_empty():
		return []
	var now := Time.get_ticks_msec() / 1000.0 - delay
	if buffer.size() == 1 or now <= buffer[0][0]:
		return buffer[0][1]
	for i in range(buffer.size() - 1):
		var a: Array = buffer[i]
		var b: Array = buffer[i + 1]
		if now >= a[0] and now <= b[0]:
			var k: float = (now - a[0]) / maxf(0.0001, b[0] - a[0])
			return _lerp_frame(a[1], b[1], k)
	return buffer[-1][1]


func _lerp_frame(a: Array, b: Array, k: float) -> Array:
	var out := a.duplicate()
	for j in [0, 1, 2, 3, 6, 7, 8, 9]:
		if j < a.size() and j < b.size():
			out[j] = lerpf(a[j], b[j], k)
	return out


func _draw() -> void:
	if disc_vis:
		var lp := disc_pos - position
		draw_circle(lp, 8.0, Color(disc_color, 0.35))
		draw_arc(lp, 10.0, 0, TAU, 16, Color(disc_color * 1.5, 0.6), 2.0)
