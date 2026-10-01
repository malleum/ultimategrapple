extends Node2D
## Procedural neon runner. Drawn in the parent's local space (origin = feet).
## Fed either by the local player or by network/replay ghost state.

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
var disc_color := Color(2, 0.5, 1.5)
var run_phase := 0.0
var scarf: Array = []
var name_tag := ""
var charge := 0.0


func _init() -> void:
	for i in 7:
		scarf.append(Vector2(-i * 5.0, -38.0))


func update_from_player(p) -> void:
	vel = p.velocity
	on_floor = p.on_floor
	low = p.sliding or p.crouched
	swinging = p.state == 1 or p.state == 2
	has_disc = p.has_disc
	charging = p.charging
	dead = p.state == 4
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
	anchor_local = Vector2(s[6], s[7]) - pos
	aim_dir = Vector2(facing, -0.3).normalized()
	_step(dt)


func _step(dt: float) -> void:
	if on_floor and not low:
		run_phase += absf(vel.x) * dt * 0.035
	elif not on_floor:
		run_phase += dt * 4.0
	# scarf: verlet-ish trailing chain
	var neck := Vector2(0, -38 if not low else -18)
	scarf[0] = neck
	for i in range(1, scarf.size()):
		var target: Vector2 = scarf[i - 1] + Vector2(-facing * 5.0, 1.5) - vel * 0.006
		scarf[i] = (scarf[i] as Vector2).lerp(target, 0.35)
		var dv: Vector2 = scarf[i] - scarf[i - 1]
		if dv.length() > 6.0:
			scarf[i] = scarf[i - 1] + dv.normalized() * 6.0
	queue_redraw()


func _draw() -> void:
	if dead:
		return
	var c := Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, alpha)
	var body_c := Color(color.r * 0.25, color.g * 0.25, color.b * 0.25, alpha)
	var accent := Color(2.2, 0.5, 1.4, alpha) if color.g > 0.8 else Color(0.4, 2.0, 2.2, alpha)
	var w := 3.6
	var lean := clampf(vel.x / 1400.0, -0.45, 0.45)

	# scarf
	var sp := PackedVector2Array()
	for p in scarf:
		sp.append(p)
	draw_polyline(sp, accent, 3.0, true)

	var hip: Vector2
	var neck: Vector2
	var head: Vector2
	if low:
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
	if low:
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
	if name_tag != "":
		draw_string(ThemeDB.fallback_font, Vector2(-40, -62), name_tag, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(c, 0.8 * alpha))
