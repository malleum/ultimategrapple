extends Node2D
## Procedural neon runner. Drawn in the parent's local space (origin = feet).
## Fed either by the local player or by network/replay ghost state.

const Perf = preload("res://src/core/perf.gd")

var color := Color(0.2, 1.0, 0.9)
var alpha := 1.0
var vel := Vector2.ZERO
var on_floor := true
var low := false
var swinging := false
var has_disc := true
var charging := false
var dead := false
var facing := 1.0
var aim_dir := Vector2.RIGHT
var anchor_local := Vector2.ZERO
var snapshot_rope := false   # puppets / ghosts draw their own rope (live runners get the overlay's)
var disc_color := Color(2, 0.5, 1.5)
const BODY_HDR := 1.15     # runner line brightness (glow kicks in just above 1.0)
var run_phase := 0.0
## Scarf: world-space verlet chain (gravity + air drag), so it hangs down when
## you stand still and streams back when you move. scarf holds the points
## relative to the feet at the last physics step, for drawing.
const SCARF_N := 7
const SCARF_SEG := 5.0
const SCARF_GRAVITY := 1500.0
const SCARF_DRAG := 5.0          # 1/s air drag on the cloth
var scarf: Array = []
var _sw: Array = []              # world positions
var _sw_prev: Array = []
var _flutter_t := 0.0
var name_tag := ""
var stunned := false      # versus: tackled (dizzy stars)
var frozen := 0.0         # versus: penalty freeze seconds left (ice shell + countdown)
var knocked := false      # versus: knocked down by a disc to the head (lying flat)
var knock_side := 1.0
var charge := 0.0


func _init() -> void:
	for i in SCARF_N:
		scarf.append(Vector2(0, -38.0 + i * SCARF_SEG))


func update_from_player(p) -> void:
	vel = p.velocity
	on_floor = p.on_floor
	low = p.sliding or p.crouched
	swinging = p.state == 1 or p.state == 2
	has_disc = p.has_disc
	charging = p.charging
	dead = p.state == 4
	stunned = p.stun_t > 0.0
	frozen = maxf(p.frozen_t, 0.0)
	_set_knocked(p.down_t > 0.0)
	facing = p.facing
	aim_dir = p.aim_dir
	charge = p.charge_power() if p.charging else 0.0
	if swinging and not p.anchors.is_empty():
		anchor_local = p.anchors[-1] - p.global_position
	if p.disc:
		disc_color = p.disc.color
	_step(1.0 / Engine.physics_ticks_per_second)


## For ghosts: flags bitfield matches player.snapshot()
func update_from_snapshot(s: Array, pos: Vector2, dt: float) -> void:
	vel = Vector2(s[2], s[3])
	facing = s[4]
	var flags: int = s[5]
	on_floor = flags & 1 != 0
	low = flags & 2 != 0
	swinging = flags & 4 != 0
	has_disc = flags & 8 != 0
	charging = flags & 16 != 0
	dead = flags & 32 != 0
	stunned = flags & 128 != 0
	frozen = 1.0 if flags & 256 != 0 else 0.0
	_set_knocked(flags & 512 != 0)
	anchor_local = Vector2(s[6], s[7]) - pos
	snapshot_rope = true
	aim_dir = Vector2(facing, -0.3).normalized()
	_step(dt)


func _step(dt: float) -> void:
	if on_floor and not low:
		run_phase += absf(vel.x) * dt * 0.035
	elif not on_floor:
		run_phase += dt * 4.0
	_step_scarf(dt)
	queue_redraw()


## Forget the cloth's world positions (after a teleport), so it re-hangs.
func reset_scarf() -> void:
	_sw.clear()
	_sw_prev.clear()


func _scarf_anchor() -> Vector2:
	if low:
		return Vector2(facing * 9.0, -17.0)
	var lean := clampf(vel.x / 1400.0, -0.45, 0.45)
	return Vector2(lean * 20.0 - facing * 2.0, -37.0)


func _step_scarf(dt: float) -> void:
	var origin := global_position
	var anchor := origin + _scarf_anchor()
	if _sw.size() != SCARF_N or (_sw[0] as Vector2).distance_to(anchor) > 160.0:
		_sw.clear()
		_sw_prev.clear()
		for i in SCARF_N:
			_sw.append(anchor + Vector2(-facing * 1.5 * i, i * SCARF_SEG))
			_sw_prev.append(_sw[i])
	_flutter_t += dt * (6.0 + vel.length() * 0.02)
	var keep := exp(-SCARF_DRAG * dt)
	_sw[0] = anchor
	_sw_prev[0] = anchor
	for i in range(1, SCARF_N):
		var cur: Vector2 = _sw[i]
		var step: Vector2 = (cur - (_sw_prev[i] as Vector2)) * keep
		# a little flutter when the air is moving past it
		var flutter := Vector2(0, sin(_flutter_t + i * 0.9) * minf(vel.length(), 900.0) * 0.9 * i)
		_sw_prev[i] = cur
		_sw[i] = cur + step + (Vector2(0, SCARF_GRAVITY) + flutter) * dt * dt
	for _k in 3:
		for i in range(1, SCARF_N):
			var a: Vector2 = _sw[i - 1]
			var b: Vector2 = _sw[i]
			var d := b - a
			var l := d.length()
			if l > 0.001:
				_sw[i] = a + d / l * SCARF_SEG
	for i in SCARF_N:
		scarf[i] = (_sw[i] as Vector2) - origin


func _set_knocked(k: bool) -> void:
	if k and not knocked:
		knock_side = signf(vel.x) if absf(vel.x) > 10.0 else -facing
	knocked = k


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("runner_visual.draw", _pt)


func _draw_timed() -> void:
	if dead:
		return
	# just over the glow threshold: a soft halo, not a bloomed-out blob
	var c := Color(color.r * BODY_HDR, color.g * BODY_HDR, color.b * BODY_HDR, alpha)
	var body_c := Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, alpha)
	var accent := Color(1.45, 0.4, 1.0, alpha) if color.g > 0.8 else Color(0.35, 1.35, 1.45, alpha)
	var w := 3.6
	var lean := clampf(vel.x / 1400.0, -0.45, 0.45)
	if knocked:
		# flat on the back, head away from the hit
		draw_set_transform(Vector2(-knock_side * 22.0, -3.0), knock_side * PI * 0.5)
		lean = 0.0
	var lo := low and not knocked

	# scarf
	var sp := PackedVector2Array()
	for p in scarf:
		sp.append(p)
	draw_polyline(sp, accent, 3.0, true)
	draw_circle(sp[sp.size() - 1], 1.6, accent)

	var hip: Vector2
	var neck: Vector2
	var head: Vector2
	if lo:
		hip = Vector2(-facing * 6, -8)
		neck = Vector2(facing * 12, -16)
		head = neck + Vector2(facing * 7, -4)
	else:
		hip = Vector2(0, -20)
		neck = hip + Vector2(lean * 20.0, -18)
		head = neck + Vector2(lean * 8.0, -9)

	# legs
	var l1: Vector2
	var l2: Vector2
	var k1: Vector2
	var k2: Vector2
	if lo:
		l1 = Vector2(-facing * 20, -2)
		l2 = Vector2(-facing * 14, 0)
		k1 = (hip + l1) * 0.5 + Vector2(0, -3)
		k2 = (hip + l2) * 0.5 + Vector2(0, 2)
	elif not on_floor:
		var tuck := clampf(-vel.y / 800.0, -0.5, 1.0)
		l1 = hip + Vector2(facing * 8, 18 - tuck * 6)
		l2 = hip + Vector2(-facing * 6, 20 - tuck * 2)
		k1 = hip + Vector2(facing * 12, 8 - tuck * 4)
		k2 = hip + Vector2(-facing * 2, 12)
	else:
		var s := sin(run_phase)
		var s2 := sin(run_phase + PI)
		var amp := clampf(absf(vel.x) / 440.0, 0.0, 1.2)
		l1 = hip + Vector2(s * 12 * amp, 20)
		l2 = hip + Vector2(s2 * 12 * amp, 20)
		k1 = hip + Vector2(s * 6 * amp + facing * 4 * amp, 10 - maxf(0, cos(run_phase)) * 3 * amp)
		k2 = hip + Vector2(s2 * 6 * amp + facing * 4 * amp, 10 - maxf(0, cos(run_phase + PI)) * 3 * amp)
	# dark under-stroke keeps the runner readable on bright themes
	var ol := Color(0.02, 0.0, 0.06, 0.75 * alpha)
	draw_polyline(PackedVector2Array([hip, k1, l1]), ol, w + 3.5, true)
	draw_polyline(PackedVector2Array([hip, k2, l2]), ol, w + 3.5, true)
	draw_line(hip, neck, ol, w + 4.5, true)
	draw_circle(head, 9.5, ol)
	draw_polyline(PackedVector2Array([hip, k1, l1]), c, w, true)
	draw_polyline(PackedVector2Array([hip, k2, l2]), c, w, true)

	# torso + head
	draw_line(hip, neck, c, w + 1.0, true)
	draw_circle(head, 7.5, body_c)
	draw_arc(head, 7.5, 0, TAU, 20, c, 2.0, true)
	# visor
	draw_line(head + Vector2(facing * 2, -1), head + Vector2(facing * 7, -1), accent, 2.0, true)

	# arms
	var shoulder := neck + Vector2(0, 3)
	var hand_a: Vector2
	var hand_b: Vector2
	if swinging:
		var dir := (anchor_local - shoulder).normalized()
		hand_a = shoulder + dir * 20.0
		hand_b = shoulder + dir.rotated(0.35 * facing) * 17.0
	elif charging:
		var back := -aim_dir
		hand_a = shoulder + (back * (10.0 + charge * 10.0)) + Vector2(0, 4)
		hand_b = shoulder + aim_dir * 14.0
	else:
		var swing_a := sin(run_phase + PI) * 0.8 if on_floor else -0.9
		hand_a = shoulder + Vector2(facing * 6 + swing_a * 8, 12)
		hand_b = shoulder + Vector2(-facing * 4 - swing_a * 8, 13)
	if swinging and snapshot_rope and anchor_local.length() > 24.0:
		draw_line(hand_a, anchor_local, Color(0.02, 0.0, 0.06, 0.5 * alpha), 5.0, true)
		draw_line(hand_a, anchor_local, Color(0.95, 0.85, 0.55, 0.9 * alpha), 2.5, true)
		draw_circle(anchor_local, 4.0, Color(1.0, 0.9, 0.5, alpha))
	draw_line(shoulder, hand_a, ol, w + 3.5, true)
	draw_line(shoulder, hand_b, ol, w + 3.5, true)
	draw_line(shoulder, hand_a, c, w, true)
	draw_line(shoulder, hand_b, c, w, true)
	if has_disc:
		var dp := hand_a
		var pts := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			pts.append(dp + Vector2(cos(a) * 9.0, sin(a) * 3.0))
		draw_colored_polygon(pts, Color(disc_color, alpha))
	draw_set_transform(Vector2.ZERO)
	if stunned:
		# dizzy stars circling the head
		var hc := Vector2(0, -56)
		for k in 3:
			var sa := Time.get_ticks_msec() * 0.008 + k * TAU / 3.0
			draw_circle(hc + Vector2(cos(sa) * 14.0, sin(sa) * 4.0), 3.0, Color(2.2, 1.9, 0.5, alpha))
	if frozen > 0.0:
		# penalty freeze: an ice shell with the seconds left
		var box := Rect2(-17, -54, 34, 58)
		draw_rect(box, Color(0.55, 0.85, 1.0, 0.28 * alpha))
		draw_rect(box, Color(0.8, 1.5, 2.2, 0.85 * alpha), false, 2.0)
		draw_line(box.position + Vector2(5, 8), box.position + Vector2(12, 1), Color(1.8, 2.0, 2.2, 0.7 * alpha), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(-30, -62), "%.1f" % frozen, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color(0.8, 1.6, 2.2, alpha))
	if name_tag != "":
		draw_string(ThemeDB.fallback_font, Vector2(-40, -62), name_tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(c, 0.8 * alpha))
