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

## Air animation (all derived from what the visual already gets, so ghosts,
## replays and online runners animate the same): takeoff stretch, tuck going
## up, spread at the apex, legs reaching down and arms flailing as you fall,
## a front flip on a double jump, a snag-and-pull on a sky catch, a squash
## on landing. Joints ease towards each pose's targets (_j), so nothing snaps.
const TAKEOFF_T := 0.16
const FLIP_T := 0.4
const CATCH_T := 0.34
const LAND_T := 0.16
var air_t := 0.0          # time since leaving the ground
var flip_t := -1.0        # double jump flip progress (s), -1 = none
var catch_t := -1.0       # sky catch, -1 = none
var land_t := -1.0        # landing squash, -1 = none
var land_k := 0.0         # how hard that landing was (0..1)
var _was_floor := true
var _was_swing := false
var _had_disc := true
var _prev_vy := 0.0
var _fall_vy := 0.0       # last airborne vertical speed (for the landing)
var _t := 0.0
var _j := {}              # current joints, feet-relative (hip, neck, k1, l1, k2, l2, ha, hb)


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
	_step_air(dt)
	_step_scarf(dt)
	queue_redraw()


## Events from state changes (works on snapshots too), then ease the joints.
func _step_air(dt: float) -> void:
	_t += dt
	var air := not on_floor and not swinging and not dead and not knocked
	if not on_floor:
		air_t += dt
		_fall_vy = vel.y
	if _was_floor and not on_floor:
		air_t = 0.0
	if not _was_floor and on_floor and _fall_vy > 250.0:
		land_t = 0.0
		land_k = clampf((_fall_vy - 250.0) / 1100.0, 0.25, 1.0)
	# a sudden kick upwards in the air: double jump (also wall jumps, pads)
	# (not the hop of letting go of a grapple)
	if air and not _was_swing and air_t > 0.06 and dt > 0.0 and (vel.y - _prev_vy) / dt < -9000.0 and vel.y < -300.0:
		flip_t = 0.0
	if has_disc and not _had_disc and not on_floor and not swinging:
		catch_t = 0.0
	_was_floor = on_floor
	_was_swing = swinging
	_had_disc = has_disc
	_prev_vy = vel.y
	if flip_t >= 0.0:
		flip_t += dt
		if flip_t > FLIP_T or not air:
			flip_t = -1.0
	if catch_t >= 0.0:
		catch_t += dt
		if catch_t > CATCH_T:
			catch_t = -1.0
	if land_t >= 0.0:
		land_t += dt
		if land_t > LAND_T or not on_floor:
			land_t = -1.0
	var tgt := _targets()
	if _j.is_empty() or dt <= 0.0:
		_j = tgt
		return
	# fast enough to keep up with a run cycle, slow enough to blend poses
	var rate := 30.0 if on_floor or swinging else 18.0
	var k := 1.0 - exp(-rate * dt)
	for key in tgt:
		_j[key] = (_j.get(key, tgt[key]) as Vector2).lerp(tgt[key], k)


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Where every joint wants to be right now (feet-relative; hands relative to
## the shoulder).
func _targets() -> Dictionary:
	var f := facing
	var lean := clampf(vel.x / 1400.0, -0.45, 0.45)
	var hip := Vector2(0, -20)
	var neck := hip + Vector2(lean * 20.0, -18)
	var k1: Vector2
	var l1: Vector2
	var k2: Vector2
	var l2: Vector2
	var ha: Vector2
	var hb: Vector2
	var lo := low and not knocked
	if lo:
		hip = Vector2(-f * 6, -8)
		neck = Vector2(f * 12, -16)
		l1 = Vector2(-f * 20, -2)
		l2 = Vector2(-f * 14, 0)
		k1 = (hip + l1) * 0.5 + Vector2(0, -3)
		k2 = (hip + l2) * 0.5 + Vector2(0, 2)
		ha = Vector2(f * 6, 10)
		hb = Vector2(-f * 4, 11)
	elif on_floor or swinging or knocked:
		var s := sin(run_phase)
		var s2 := sin(run_phase + PI)
		var amp := clampf(absf(vel.x) / 440.0, 0.0, 1.2) if on_floor else 0.3
		l1 = hip + Vector2(s * 12 * amp, 20)
		l2 = hip + Vector2(s2 * 12 * amp, 20)
		k1 = hip + Vector2(s * 6 * amp + f * 4 * amp, 10 - maxf(0, cos(run_phase)) * 3 * amp)
		k2 = hip + Vector2(s2 * 6 * amp + f * 4 * amp, 10 - maxf(0, cos(run_phase + PI)) * 3 * amp)
		var swing_a := sin(run_phase + PI) * 0.8
		ha = Vector2(f * 6 + swing_a * 8, 12)
		hb = Vector2(-f * 4 - swing_a * 8, 13)
		if swinging and not on_floor:
			# hanging: legs trail the swing a little
			var trail := clampf(-vel.x / 900.0, -1.0, 1.0)
			l1 = hip + Vector2(trail * 10.0 + f * 3, 19)
			l2 = hip + Vector2(trail * 14.0 - f * 3, 18)
			k1 = hip + Vector2(trail * 5.0 + f * 5, 10)
			k2 = hip + Vector2(trail * 7.0, 10)
		if land_t >= 0.0:
			# landing squash: hips drop, knees bend forward, arms go out
			var q := land_k * sin(PI * clampf(land_t / LAND_T, 0.0, 1.0))
			hip.y += 7.0 * q
			neck += Vector2(f * 4.0 * q, 9.0 * q)
			k1 += Vector2(f * 6.0 * q, 3.0 * q)
			k2 += Vector2(f * 3.0 * q, 3.0 * q)
			ha += Vector2(f * 8.0 * q, -3.0 * q)
			hb += Vector2(-f * 8.0 * q, -3.0 * q)
	else:
		var vy := vel.y
		var up := _smooth(-vy / 700.0)              # 1 = rising fast
		var top := 1.0 - _smooth(absf(vy) / 380.0)  # 1 = at the apex
		var fall := _smooth((vy - 150.0) / 900.0)   # 1 = falling fast
		var flail := sin(_t * 15.0) * 3.0 * fall
		# rising: knees up, arms forward and up
		k1 = hip + Vector2(f * 11, 6)
		l1 = hip + Vector2(f * 4, 15)
		k2 = hip + Vector2(f * 2, 10)
		l2 = hip + Vector2(-f * 6, 18)
		ha = Vector2(f * 13, -6)
		hb = Vector2(-f * 8, 2)
		# apex: tighter tuck, arms out for balance
		k1 = k1.lerp(hip + Vector2(f * 10, 2), top)
		l1 = l1.lerp(hip + Vector2(f * 3, 12), top)
		k2 = k2.lerp(hip + Vector2(f * 6, 4), top)
		l2 = l2.lerp(hip + Vector2(-f * 2, 13), top)
		ha = ha.lerp(Vector2(f * 15, 2), top)
		hb = hb.lerp(Vector2(-f * 14, 0), top)
		# falling: legs reach for the ground, arms up and flailing, lean back
		k1 = k1.lerp(hip + Vector2(f * 6, 10), fall)
		l1 = l1.lerp(hip + Vector2(f * 4, 21), fall)
		k2 = k2.lerp(hip + Vector2(-f * 4, 9), fall)
		l2 = l2.lerp(hip + Vector2(-f * 10, 15), fall)
		ha = ha.lerp(Vector2(f * 9, -15 + flail), fall)
		hb = hb.lerp(Vector2(-f * 12, -12 - flail), fall)
		neck += Vector2(-f * 3.0 * fall, 0)
		# takeoff: stretched out, arms thrown up, back leg pushing off
		if air_t < TAKEOFF_T and up > 0.3:
			var tk := 1.0 - _smooth(air_t / TAKEOFF_T)
			hip.y -= 2.0 * tk
			neck = neck.lerp(hip + Vector2(f * 3 + lean * 20.0, -19), tk)
			k1 = k1.lerp(hip + Vector2(f * 9, 6), tk)
			l1 = l1.lerp(hip + Vector2(f * 6, 15), tk)
			k2 = k2.lerp(hip + Vector2(-f * 5, 11), tk)
			l2 = l2.lerp(hip + Vector2(-f * 8, 21), tk)
			ha = ha.lerp(Vector2(f * 6, -17), tk)
			hb = hb.lerp(Vector2(-f * 4, -15), tk)
		# double jump: tucked into a ball for the flip
		if flip_t >= 0.0:
			var b := sin(PI * clampf(flip_t / FLIP_T, 0.0, 1.0))
			k1 = k1.lerp(hip + Vector2(f * 9, -2), b)
			l1 = l1.lerp(hip + Vector2(f * 2, 6), b)
			k2 = k2.lerp(hip + Vector2(f * 7, 2), b)
			l2 = l2.lerp(hip + Vector2(f * 1, 9), b)
			neck = neck.lerp(hip + Vector2(f * 8, -15), b)
			ha = ha.lerp(Vector2(f * 2, 18), b)
			hb = hb.lerp(Vector2(-f * 1, 17), b)
	# sky catch: the throwing hand snags forward-up, then pulls the disc in
	if catch_t >= 0.0 and not lo:
		var c := clampf(catch_t / CATCH_T, 0.0, 1.0)
		var reach := sin(PI * minf(c * 1.6, 1.0))
		var e := 1.0 - _smooth(c)
		ha = ha.lerp(Vector2(f * 20, -14), reach * e)
		hb = hb.lerp(Vector2(-f * 14, -4), e)
		if not on_floor:
			k1 = k1.lerp(hip + Vector2(f * 12, 4), e)
			l1 = l1.lerp(hip + Vector2(f * 16, 12), e)
			k2 = k2.lerp(hip + Vector2(-f * 8, 8), e)
			l2 = l2.lerp(hip + Vector2(-f * 15, 15), e)
	return {"hip": hip, "neck": neck, "k1": k1, "l1": l1, "k2": k2, "l2": l2, "ha": ha, "hb": hb}


## Front flip angle for the double jump (0 when not flipping).
func flip_angle() -> float:
	if flip_t < 0.0:
		return 0.0
	return facing * TAU * _smooth(flip_t / FLIP_T)


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

	if _j.is_empty():
		_j = _targets()
	var hip: Vector2 = _j.hip
	var neck: Vector2 = _j.neck
	var head: Vector2
	if lo:
		head = neck + Vector2(facing * 7, -4)
	else:
		var nd := (neck - hip).normalized()
		head = neck + nd * 9.0 + Vector2(lean * 8.0, 0)
	var k1: Vector2 = _j.k1
	var l1: Vector2 = _j.l1
	var k2: Vector2 = _j.k2
	var l2: Vector2 = _j.l2
	# double jump: the whole body turns a front flip around the hips
	var fa := flip_angle()
	if fa != 0.0 and not knocked:
		draw_set_transform(hip - hip.rotated(fa), fa)
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
	var hand_a: Vector2 = shoulder + (_j.ha as Vector2)
	var hand_b: Vector2 = shoulder + (_j.hb as Vector2)
	if swinging:
		# exact, not eased: the rope leaves from this hand
		var dir := (anchor_local - shoulder).normalized()
		hand_a = shoulder + dir * 20.0
		hand_b = shoulder + dir.rotated(0.35 * facing) * 17.0
	elif charging:
		var back := -aim_dir
		hand_a = shoulder + (back * (10.0 + charge * 10.0)) + Vector2(0, 4)
		hand_b = shoulder + aim_dir * 14.0
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
