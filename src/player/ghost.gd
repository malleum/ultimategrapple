extends Node2D
## Non-colliding ghost runner: plays back a recorded run or mirrors a remote player.
## Frame format: [x, y, vx, vy, facing, flags, ax, ay, disc_x, disc_y, disc_vis, disc_ang, disc_squash]
## (older saved ghosts stop at disc_vis)

const Perf = preload("res://src/core/perf.gd")

const PlayerVisual = preload("res://src/player/player_visual.gd")

const REC_INTERVAL := 4.0 / 120.0   # seconds between recorded frames

var visual: Node2D
var frames: Array = []
var play_t := 0.0
## Optional: returns the playback time (the runner's clock, so penalties line
## up); without it the ghost just plays in real time.
var clock := Callable()
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
## How solid ghosts look: your PB ghost, and other runners (online players,
## raced friends / leaderboard runs). Their discs follow (DISC_ALPHA x this).
const ALPHA_GHOST := 0.32
const ALPHA_OTHER := 0.45
const DISC_ALPHA := 0.9
var history: Array = []     # remote: [[time, frame], ...] for the last HISTORY_S (disc cam)
const HISTORY_S := 12.0
var full: Array = []        # remote: every [time, frame] this round (match recording)
const FULL_MAX := 30 * 60 * 15


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual = PlayerVisual.new()
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual.alpha = ALPHA_GHOST
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
	visual.alpha = ALPHA_OTHER
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
	if frame.size() < 11:
		return
	var now := Time.get_ticks_msec() / 1000.0
	buffer.append([now, frame])
	while buffer.size() > 40:
		buffer.pop_front()
	history.append([now, frame])
	if full.size() < FULL_MAX:
		full.append([now, frame])
	if float(history[0][0]) < now - HISTORY_S - 2.0:
		var keep := 0
		while keep < history.size() and float(history[keep][0]) < now - HISTORY_S:
			keep += 1
		history = history.slice(keep)


## Match recording: the received frames resampled to 30 Hz on the race clock
## (t0 = local time the race started, in seconds).
func match_frames(t0: float) -> Array:
	var out: Array = []
	if full.size() < 2:
		return out
	var step := 1.0 / 30.0
	var tt := t0 + delay
	var i := 0
	var t_end: float = full[-1][0]
	while tt <= t_end:
		while i < full.size() - 2 and float(full[i + 1][0]) < tt:
			i += 1
		var ta: float = full[i][0]
		var tb: float = full[i + 1][0]
		var fa: Array = full[i][1]
		var fb: Array = full[i + 1][1]
		var k := clampf((tt - ta) / maxf(tb - ta, 0.001), 0.0, 1.0)
		var pa := Vector2(fa[0], fa[1])
		var pb := Vector2(fb[0], fb[1])
		if pa.distance_to(pb) > 200.0:
			k = 0.0
		var f: Array = fa.duplicate()
		var p := pa.lerp(pb, k)
		f[0] = p.x
		f[1] = p.y
		if int(fa[10]) != 0 and int(fb[10]) != 0:
			var d := Vector2(fa[8], fa[9]).lerp(Vector2(fb[8], fb[9]), k)
			f[8] = d.x
			f[9] = d.y
		out.append(f)
		tt += step
	return out


## Disc cam clip (see DiscCam) rebuilt at the physics rate from the frames
## received: the last 10 s before `score_t` up to `end_t` (local seconds).
func pov_clip(score_t: float, end_t: float) -> Dictionary:
	var out: Array = []
	var score_at := 0
	if history.size() < 2:
		return {"frames": out, "score_at": 0}
	var step := 1.0 / Engine.physics_ticks_per_second
	var tt := maxf(float(history[0][0]), score_t - 10.0)
	var i := 0
	while tt <= end_t:
		while i < history.size() - 2 and float(history[i + 1][0]) < tt:
			i += 1
		var ta: float = history[i][0]
		var tb: float = history[i + 1][0]
		var fa: Array = history[i][1]
		var fb: Array = history[i + 1][1]
		var k := clampf((tt - ta) / maxf(tb - ta, 0.001), 0.0, 1.0)
		var pa := Vector2(fa[0], fa[1])
		var pb := Vector2(fb[0], fb[1])
		if pa.distance_to(pb) > 200.0:   # respawn: no streak
			k = 0.0
		var p := pa.lerp(pb, k)
		var f: Array = fa.duplicate()
		f[0] = p.x
		f[1] = p.y
		f[5] = int(fa[5]) & ~8
		var dp: Vector2
		var pz := Vector2(0.0, 0.3)
		if int(fa[10]) == 0:
			dp = p + Vector2(0, -(22.0 if int(fa[5]) & 2 else 44.0) * 0.72)
		else:
			dp = Vector2(fa[8], fa[9]).lerp(Vector2(fb[8], fb[9]), k if int(fb[10]) != 0 else 0.0)
			if fa.size() >= 13:
				pz = Vector2(lerp_angle(float(fa[11]), float(fb[11]) if fb.size() >= 13 else float(fa[11]), k), float(fa[12]))
		out.append([f, dp, pz])
		if tt <= score_t:
			score_at = out.size() - 1
		tt += step
	return {"frames": out, "score_at": score_at}


func _process(dt: float) -> void:
	var f: Array = []
	if remote:
		f = _remote_frame()
	elif playing and frames.size() > 1:
		play_t = clock.call() if clock.is_valid() else play_t + dt
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


func is_low() -> bool:
	return not cur.is_empty() and int(cur[5]) & 2 != 0


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
	for j in [0, 1, 2, 3, 8, 9]:
		if j < a.size() and j < b.size():
			out[j] = lerpf(a[j], b[j], k)
	# rope anchor: only slide it while both frames hang on the same point
	# (a moving one); a grab, a release or a wrap onto a new corner jumps.
	# Blending those swept the rope in from (0, 0) / across the screen.
	if a.size() > 7 and b.size() > 7:
		var swing_a := int(a[5]) & 4 != 0
		var swing_b := int(b[5]) & 4 != 0
		var aa := Vector2(a[6], a[7])
		var ab := Vector2(b[6], b[7])
		if swing_a and swing_b and aa.distance_to(ab) < 40.0:
			var m := aa.lerp(ab, k)
			out[6] = m.x
			out[7] = m.y
		elif k >= 0.5 or not swing_a:
			out[5] = (int(a[5]) & ~4) | (int(b[5]) & 4)
			out[6] = b[6]
			out[7] = b[7]
	# a recall / respawn teleports the disc: don't streak it across the map
	if a.size() > 9 and b.size() > 9 and Vector2(a[8], a[9]).distance_to(Vector2(b[8], b[9])) > 300.0:
		out[8] = a[8] if k < 0.5 else b[8]
		out[9] = a[9] if k < 0.5 else b[9]
	return out


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("ghost.draw", _pt)


func _draw_timed() -> void:
	if disc_vis:
		# the disc as it flew: tilted and squashed like the real one (frames
		# carry its pose; older ghosts without it show it flat)
		var lp := disc_pos - position
		var ang := 0.0
		var sq := 0.3
		if cur.size() > 12:
			ang = float(cur[11])
			sq = float(cur[12])
		var a: float = visual.alpha * DISC_ALPHA
		var rx := 14.0
		var ry := maxf(14.0 * absf(sq), 1.5)
		var pts := PackedVector2Array()
		for i in 18:
			var t := TAU * i / 18.0
			pts.append(lp + Vector2(cos(t) * rx, sin(t) * ry).rotated(ang))
		draw_colored_polygon(pts, Color(disc_color.r * 0.5, disc_color.g * 0.5, disc_color.b * 0.5, a * 0.8))
		pts.append(pts[0])
		draw_polyline(pts, Color(disc_color * 1.4, a), 2.0, true)
