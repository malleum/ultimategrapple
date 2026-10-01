extends CharacterBody2D
## Flying disc with simplified 2D aerodynamics.
##
## Forces: lift (perpendicular to relative airflow) + drag (parabolic in AoA)
## + gravity + wind. Attitude (nose pitch) is gyroscopically held, drifts nose
## down as the disc slows ("fade"), and wobbles when spin is low. Spin comes
## from the snap mechanic and drives stability, skip shots and wall kicks.

const ThrowTypes = preload("res://src/disc/throw_types.gd")

signal scored
signal state_changed(new_state: int)
signal impact(kind: String, strength: float)
signal out_of_bounds

enum { HELD, FLIGHT, ROLL, SLIDE, REST, CHAINED, SCORED }

const KL := 0.00135     # lift constant
const KD := 0.00095     # drag constant
const RADIUS := 10.0
const MAX_ALPHA := 0.75
const STALL_ALPHA := 0.42
const FLUTTER_LIFT := 0.8    # lift multiplier at zero snap quality
const FLUTTER_DRAG := 1.3    # drag multiplier at zero snap quality

var state := HELD
var type_idx := 0
var t: Dictionary = ThrowTypes.TYPES[0]
var age := 0.0
var spin := 1.0            # 0..1
var quality := 1.0         # snap quality (aero stability): 1 perfect .. 0.25 none
var spin_dir := 1          # visual + wall kick direction
var phi := 0.0             # attitude (nose up, radians) in forward frame
var wobble := 0.0          # amplitude of attitude noise
var skips := 0
var facing := 1.0          # +1 moving right, -1 left (for attitude frame)
var winds: Array = []      # active wind zone nodes
var level: Node = null
var runner: Node = null
var color := Color(2, 0.5, 1.5)
var noise_t := 0.0
var last_speed := 0.0
var rest_timer := 0.0
var thrower_id := 0
var spin_angle := 0.0
var trail: Line2D
var chain_timer := 0.0
var grounded_frames := 0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	collision_layer = 1 << 2
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	floor_max_angle = deg_to_rad(70)
	floor_snap_length = 6.0
	safe_margin = 0.5
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	cs.shape = shape
	add_child(cs)
	trail = Line2D.new()
	trail.top_level = true
	trail.width = 6.0
	trail.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var grad := Gradient.new()
	grad.set_color(0, Color(color, 0.0))
	grad.set_color(1, Color(color, 0.9))
	trail.gradient = grad
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(trail)
	_rng.randomize()
	visible = false


func set_color(c: Color) -> void:
	color = c
	if trail:
		trail.gradient.set_color(0, Color(c, 0.0))
		trail.gradient.set_color(1, Color(c, 0.9))
	queue_redraw()


# ------------------------------------------------------------------ control

func hold() -> void:
	_set_state(HELD)
	visible = false
	velocity = Vector2.ZERO
	winds.clear()
	trail.clear_points()


func launch(from: Vector2, vel: Vector2, p_type: int, p_spin: float, nose: float, p_wobble: float, p_quality := 1.0) -> void:
	type_idx = p_type
	quality = p_quality
	t = ThrowTypes.get_type(p_type)
	global_position = from
	reset_physics_interpolation()
	velocity = vel
	spin = clampf(p_spin, 0.05, 1.0)
	facing = 1.0 if vel.x >= 0.0 else -1.0
	spin_dir = int(facing) * (1 if t.id in ["backhand", "roller", "scoober"] else -1)
	var gamma := atan2(-vel.y, absf(vel.x))
	phi = gamma + t.trim + nose
	wobble = p_wobble
	age = 0.0
	skips = 0
	rest_timer = 0.0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	visible = true
	trail.clear_points()
	_set_state(FLIGHT)


## Snap pressed just after release: upgrade the throw to exactly what an
## on-time snap would have produced (spin, wobble, stability, and the missing
## speed — including the distance that speed would already have covered).
func apply_late_snap(p_spin: float, add_vel: Vector2, p_wobble: float, p_quality: float) -> void:
	if state != FLIGHT or age > 0.21:
		return
	spin = p_spin
	wobble = p_wobble
	quality = p_quality
	velocity += add_vel
	move_and_collide(add_vel * age)


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	if s == ROLL or s == SLIDE:
		motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
		up_direction = Vector2.UP
	else:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	state_changed.emit(s)


func is_loose() -> bool:
	return state in [FLIGHT, ROLL, SLIDE, REST]


func is_airborne() -> bool:
	return state == FLIGHT


# ------------------------------------------------------------------ physics

func _physics_process(dt: float) -> void:
	if state == HELD or state == SCORED:
		return
	age += dt
	noise_t += dt
	spin_angle += dt * (8.0 + spin * 30.0) * spin_dir
	match state:
		FLIGHT:
			_flight(dt)
		ROLL:
			_roll(dt)
		SLIDE:
			_slide(dt)
		REST:
			velocity = Vector2.ZERO
			_check_support(dt)
		CHAINED:
			_chained(dt)
	if state != HELD and state != SCORED:
		_check_basket()
		_check_gates()
		if level and global_position.y > level.kill_y:
			out_of_bounds.emit()
	last_speed = velocity.length()
	_update_trail()
	queue_redraw()


func _wind_vec() -> Vector2:
	var w := Vector2.ZERO
	for z in winds:
		if is_instance_valid(z):
			w += z.force
	return w


func _flight(dt: float) -> void:
	var wind := _wind_vec()
	var air := velocity - wind * 0.3
	var spd := air.length()
	var acc := Vector2(0, t.grav)
	if spd > 1.0:
		var f := air / spd
		if absf(f.x) > 0.05:
			facing = signf(f.x)
		var gamma := atan2(-air.y, absf(air.x))
		# gyroscopic attitude: fade (nose drop) as the disc slows; wobble at low spin
		var fade_amt := clampf((t.fade_v - spd) / t.fade_v, 0.0, 1.0)
		phi -= t.fade * fade_amt * (1.35 - 0.6 * spin) * dt
		phi += (gamma - phi) * 0.35 * dt  # slow aerodynamic weathervane
		var noise := sin(noise_t * 23.0) * 0.6 + sin(noise_t * 37.0 + 1.3) * 0.4
		phi += noise * wobble * (1.1 - spin) * 2.2 * dt
		var alpha := clampf(phi - gamma, -MAX_ALPHA, MAX_ALPHA)
		var cl: float = t.cl0 + t.cla * alpha
		if absf(alpha) > STALL_ALPHA:
			cl *= clampf(1.0 - (absf(alpha) - STALL_ALPHA) * 2.5, 0.25, 1.0)
		var cd: float = t.cd0 + t.cda * pow(alpha + 0.07, 2)
		# an unspun disc flutters: less lift, more drag
		var lift_mul: float = t.lift
		if quality < 0.999:
			cd *= lerpf(FLUTTER_DRAG, 1.0, quality)
			lift_mul *= lerpf(FLUTTER_LIFT, 1.0, quality)
		if t.flip_t > 0.0:
			lift_mul *= lerpf(1.0, t.flip_lift, smoothstep(t.flip_t * 0.6, t.flip_t * 1.4, age))
		var up := Vector2(f.y, -f.x) * (1.0 if f.x >= 0.0 else -1.0)
		var q := spd * spd
		acc += up * KL * q * cl * lift_mul
		acc -= f * KD * q * cd
	acc += wind * 0.25
	velocity += acc * dt
	spin = maxf(0.05, spin - 0.04 * dt)
	var motion := velocity * dt
	for i in 3:
		var col := move_and_collide(motion)
		if col == null:
			break
		var other := col.get_collider()
		if other and other.has_meta("glass") and velocity.length() > 520.0:
			other.get_parent().shatter(velocity)
			impact.emit("glass", velocity.length())
			velocity *= 0.8
			motion = col.get_remainder()
			continue
		_flight_impact(col.get_normal(), other)
		if state != FLIGHT:
			break
		motion = col.get_remainder().slide(col.get_normal()) * 0.5


func _flight_impact(n: Vector2, other: Object) -> void:
	var v := velocity
	var vn := v.dot(n)
	if vn >= 0.0:
		return
	var vt := v - n * vn
	var spd := v.length()
	var shallow := absf(vn) < 0.4 * spd
	if other and other.has_meta("pad"):
		var pad = other.get_meta("pad")
		velocity = pad.dir * maxf(pad.power * 0.85, spd * 0.9)
		impact.emit("pad", spd)
		return
	if n.y < -0.6:  # floor
		if t.roll and spd > 250.0:
			velocity = vt.normalized() * (vt.length() * 0.92 + absf(vn) * 0.25)
			if velocity.length() < 1.0:
				velocity = Vector2(facing * 200.0, 0)
			_set_state(ROLL)
			impact.emit("roll", spd)
			return
		if shallow and spin > 0.5 and spd > 420.0 and skips < 3:
			skips += 1
			velocity = vt * 0.84 - n * vn * 0.42
			phi *= 0.5
			spin *= 0.85
			impact.emit("skip", spd)
			return
		velocity = vt * 0.5 - n * vn * 0.08
		_set_state(SLIDE)
		impact.emit("land", spd)
	elif n.y > 0.6:  # ceiling
		velocity = vt * 0.85 - n * vn * 0.35
		phi -= 0.2
		impact.emit("ceiling", spd)
	else:  # wall
		var tangent := Vector2(-n.y, n.x)
		velocity = vt * 0.75 - n * vn * 0.42 + tangent * spin_dir * spin * 140.0 * signf(n.x)
		phi = -phi * 0.5
		facing = signf(velocity.x) if absf(velocity.x) > 1.0 else facing
		spin *= 0.8
		impact.emit("wall", spd)


## Floor contact under the disc. is_on_floor() alone misses most frames for a
## rolling/sliding disc (it micro-hops off the floor), which used to skip
## friction and made rollers travel ~2x too far.
func _ground_probe() -> KinematicCollision2D:
	var c := move_and_collide(Vector2(0, 4), true, 0.08)
	if c and c.get_normal().y < -0.5:
		return c
	return null


func _roll(dt: float) -> void:
	velocity.y += t.grav * dt
	move_and_slide()
	var g := _ground_probe()
	if g:
		var n := g.get_normal()
		var tangent := Vector2(-n.y, n.x)
		var along := velocity.dot(tangent)
		along = move_toward(along, 0.0, 420.0 * dt)
		velocity = tangent * along
		if absf(along) < 55.0:
			_set_state(SLIDE)
	if is_on_wall():
		velocity.x = -velocity.x * 0.45
		spin_dir = -spin_dir
		impact.emit("wall", absf(velocity.x))
	spin_angle += velocity.x * dt * 0.08


func _slide(dt: float) -> void:
	velocity.y += 1800.0 * dt
	move_and_slide()
	var g := _ground_probe()
	if g:
		var friction := 1600.0
		if g.get_collider() and g.get_collider().has_meta("ice"):
			friction = 250.0
		velocity.x = move_toward(velocity.x, 0.0, friction * dt)
		if absf(velocity.x) < 20.0:
			velocity = Vector2.ZERO
			_set_state(REST)
			impact.emit("rest", 0)


func _check_support(_dt: float) -> void:
	# fall if the thing we're resting on disappeared (door, mover, glass)
	if not test_move(global_transform, Vector2(0, 3)):
		_set_state(SLIDE)


func _chained(dt: float) -> void:
	chain_timer += dt
	var target: Vector2 = level.basket_pos + Vector2(clampf(global_position.x - level.basket_pos.x, -16, 16), -46)
	velocity = velocity.lerp(Vector2.ZERO, 8.0 * dt)
	global_position = global_position.move_toward(target, 500.0 * dt)
	if chain_timer > 0.35 or global_position.distance_to(target) < 4.0:
		_score()


func _check_basket() -> void:
	if level == null or not level.has_basket:
		return
	var l: Vector2 = global_position - level.basket_pos
	if absf(l.x) > 60.0 or l.y > 10.0 or l.y < -130.0:
		return
	var spd := velocity.length()
	# chains
	if state != CHAINED and absf(l.x) < 26.0 and l.y > -104.0 and l.y < -56.0:
		if spd > 1500.0 and absf(l.x) > 14.0:
			# too hot off the edge of the chains: spit out
			velocity = Vector2(-velocity.x * 0.25, velocity.y * 0.3 - 120.0)
			impact.emit("chain_spit", spd)
			global_position.x = level.basket_pos.x + signf(l.x) * 28.0
			_set_state(FLIGHT)
			return
		_set_state(CHAINED)
		chain_timer = 0.0
		impact.emit("chains", spd)
		return
	# dropping into the tray from above
	if absf(l.x) < 30.0 and l.y > -56.0 and l.y < -38.0 and velocity.y > -50.0 and state != CHAINED:
		_set_state(CHAINED)
		chain_timer = 0.2
		impact.emit("chains", spd)
		return
	# pole
	if absf(l.x) < 4.0 + RADIUS and l.y > -38.0 and l.y < 0.0 and state == FLIGHT:
		velocity.x = -velocity.x * 0.4
		global_position.x = level.basket_pos.x + signf(l.x if l.x != 0 else -velocity.x) * (4.0 + RADIUS + 1.0)
		impact.emit("pole", spd)
	# top band
	if absf(l.x) < 32.0 and l.y > -114.0 and l.y < -104.0 and state == FLIGHT:
		velocity.y = -absf(velocity.y) * 0.4 if l.y < -109.0 else absf(velocity.y) * 0.3
		impact.emit("pole", spd)


func _check_gates() -> void:
	if runner == null:
		return
	for g in runner.gates:
		if not g.triggered and g.ring_pos.distance_to(global_position) < 46.0:
			g.trigger()
			impact.emit("gate", velocity.length())


func _score() -> void:
	global_position = level.basket_pos + Vector2(clampf(global_position.x - level.basket_pos.x, -16, 16), -46)
	velocity = Vector2.ZERO
	_set_state(SCORED)
	scored.emit()


# ------------------------------------------------------------------ triggers (from Area2D zones)

func trigger_enter(kind: String, node: Node) -> void:
	match kind:
		"wind":
			if not winds.has(node):
				winds.append(node)
		"pad":
			if state in [FLIGHT, ROLL, SLIDE, REST]:
				velocity = node.dir * maxf(node.power * 0.85, velocity.length() * 0.9)
				global_position += node.dir * 6.0
				_set_state(FLIGHT)
				impact.emit("pad", velocity.length())


func trigger_exit(kind: String, node: Node) -> void:
	if kind == "wind":
		winds.erase(node)


# ------------------------------------------------------------------ visuals

func _update_trail() -> void:
	if not visible:
		return
	if state == FLIGHT or state == ROLL or state == CHAINED:
		trail.add_point(global_position)
		while trail.get_point_count() > 22:
			trail.remove_point(0)
	elif trail.get_point_count() > 0:
		trail.remove_point(0)


func _draw() -> void:
	var ang := 0.0
	var squash := 0.3
	match state:
		FLIGHT, CHAINED:
			ang = -phi * facing
			if t.flip_t > 0.0 and age > t.flip_t:
				squash = -0.3
		ROLL:
			ang = 0.0
			squash = 1.0
		SLIDE, REST:
			ang = 0.0
			squash = 0.28
		SCORED:
			squash = 0.28
	var pts := PackedVector2Array()
	var rx := 14.0
	var ry := 14.0 * absf(squash)
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry).rotated(ang))
	draw_colored_polygon(pts, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5))
	pts.append(pts[0])
	draw_polyline(pts, color, 2.5, true)
	# rim highlight / spin marker
	var mark := Vector2(cos(spin_angle) * rx * 0.8, sin(spin_angle) * ry * 0.8).rotated(ang)
	draw_circle(mark, 2.2, Color(2, 2, 2))
	if state == REST:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_arc(Vector2.ZERO, 22.0 + pulse * 6.0, 0, TAU, 24, Color(color, 0.6 * (1.0 - pulse)), 2.0)
