extends CharacterBody2D
## Flying disc with simplified 2D aerodynamics.
##
## Forces: lift (perpendicular to relative airflow) + drag (parabolic in AoA)
## + gravity + wind. Attitude (nose pitch) is gyroscopically held, drifts nose
## down as the disc slows ("fade"), and wobbles when spin is low. Spin comes
## from the snap mechanic and drives stability, skip shots and wall kicks.

const Perf = preload("res://src/core/perf.gd")

const ThrowTypes = preload("res://src/disc/throw_types.gd")
const Basket = preload("res://src/world/basket.gd")

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
const CLASH_RADIUS := 30.0   # versus: two discs this close in flight collide
const CLASH_E := 0.8         # restitution of a disc-disc hit
const GYRO_FADE_HOLD := 0.9  # share of fade a full-spin gyro throw resists
const GYRO_VANE := 1.4       # weathervane rate (1/s) of an unspun gyro throw
const GYRO_CN := 8.0         # flat-plate normal force coefficient past the stall (KL units)

var state := HELD
var type_idx := 0
var t: Dictionary = ThrowTypes.TYPES[0]
var age := 0.0
var spin := 1.0            # 0..1
var quality := 1.0         # snap quality (aero stability): 1 perfect .. 0.25 none
var spin_dir := 1          # visual + wall kick direction
var phi := 0.0             # attitude (nose up, radians) in forward frame; world frame (att_s) for gyro throws
var att_s := 1.0           # gyro throws: launch direction the attitude is measured against
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
var clash_cd := 0.0
var hit_cd := 0.0          # versus: after hitting a runner (or being fumbled), no more runner hits

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


func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value


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
	att_s = facing
	wobble = p_wobble
	age = 0.0
	skips = 0
	rest_timer = 0.0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	visible = true
	trail.clear_points()
	hit_cd = 0.0
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


## Versus: this disc (in flight) hits another disc at `op` moving at `ov`.
## Equal-mass bounce along the line between them, and the hit knocks spin
## and stability out of it, so a clean hit ruins the throw. Each disc applies
## its own half, from the other's pre-hit state.
func clash(op: Vector2, ov: Vector2) -> bool:
	if state != FLIGHT or clash_cd > 0.0:
		return false
	var n := global_position - op
	var dist := n.length()
	if dist > CLASH_RADIUS:
		return false
	n = n / dist if dist > 0.001 else Vector2.UP
	global_position += n * (CLASH_RADIUS - dist) * 0.5
	return clash_hit(n, ov)


## Apply a hit along `n` (pointing from the other disc to this one) from a
## disc moving at `ov`. Used directly for hits another client saw: by the time
## the report arrives our disc has moved on, so their contact normal is used.
func clash_hit(n: Vector2, ov: Vector2) -> bool:
	if state != FLIGHT or clash_cd > 0.0:
		return false
	var vn := (velocity - ov).dot(n)
	if vn < 0.0:
		velocity -= n * vn * (1.0 + CLASH_E) * 0.5
	else:
		velocity += n * 120.0   # already separating: still a knock
	spin *= 0.55
	quality = minf(quality, 0.5)
	wobble += 0.6
	phi += _rng.randf_range(-0.35, 0.35)
	clash_cd = 0.3
	impact.emit("clash", absf(vn))
	return true


## Versus: this disc in flight (or a roller along the ground) can hit another
## runner (not right after release).
func can_hit_runner() -> bool:
	return (state == FLIGHT or state == ROLL) and hit_cd <= 0.0 and age > 0.08


## Versus: hit a runner whose body centre is at `body`: bounce off it,
## losing most of the speed and some spin.
func bounce_off_runner(body: Vector2) -> void:
	var spd := velocity.length()
	var n := global_position - body
	n = n.normalized() if n.length() > 0.001 else -velocity.normalized()
	var vn := velocity.dot(n)
	if vn < 0.0:
		velocity -= n * vn * 1.35
	velocity *= 0.45
	spin *= 0.7
	wobble += 0.4
	hit_cd = 0.6
	impact.emit("runner", spd)


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
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("disc.physics", _pt)


func _physics_process_timed(dt: float) -> void:
	if state == HELD or state == SCORED:
		return
	age += dt
	noise_t += dt
	clash_cd -= dt
	hit_cd -= dt
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
		var cl: float
		var cd: float
		var up: Vector2
		if t.get("gyro", false):
			var g := _gyro_aero(f, spd, dt)
			cl = g.cl
			cd = g.cd
			up = g.up
		else:
			var gamma := atan2(-air.y, absf(air.x))
			# attitude in the travel frame: fade (nose drop) as the disc slows,
			# slow weathervane into the flight path, wobble at low spin
			var fade_amt := clampf((t.fade_v - spd) / t.fade_v, 0.0, 1.0)
			phi -= t.fade * fade_amt * (1.35 - 0.6 * spin) * dt
			phi += (gamma - phi) * 0.35 * dt
			phi += _wobble_noise() * wobble * (1.1 - spin) * 2.2 * dt
			var alpha := clampf(phi - gamma, -MAX_ALPHA, MAX_ALPHA)
			cl = t.cl0 + t.cla * alpha
			if absf(alpha) > STALL_ALPHA:
				cl *= clampf(1.0 - (absf(alpha) - STALL_ALPHA) * 2.5, 0.25, 1.0)
			cd = t.cd0 + t.cda * pow(alpha + 0.07, 2)
			up = Vector2(f.y, -f.x) * (1.0 if f.x >= 0.0 else -1.0)
		# an unspun disc flutters: less lift, more drag
		var lift_mul: float = t.lift
		if quality < 0.999:
			cd *= lerpf(FLUTTER_DRAG, 1.0, quality)
			lift_mul *= lerpf(FLUTTER_LIFT, 1.0, quality)
		if t.flip_t > 0.0:
			lift_mul *= lerpf(1.0, t.flip_lift, smoothstep(t.flip_t * 0.6, t.flip_t * 1.4, age))
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


func _wobble_noise() -> float:
	return sin(noise_t * 23.0) * 0.6 + sin(noise_t * 37.0 + 1.3) * 0.4


## Backhand / forehand: the disc plane is gyroscopically fixed in the world
## (phi measured against the launch direction att_s), not in the travel frame.
## Thrown steep with the nose up it stays nose-up through the apex; on the way
## down the air hits its underside from below-behind, lift points back along
## the tilted plane and the disc glides back toward the thrower. Spin is what
## holds the attitude: a weak snap lets it weathervane/fade nose-down instead.
## Angle of attack is measured against whichever edge faces the airflow, so
## the same lift/drag curves work flying forwards or backwards.
func _gyro_aero(f: Vector2, spd: float, dt: float) -> Dictionary:
	# plane direction and top-surface normal in screen space (y down)
	var p := Vector2(att_s * cos(phi), -sin(phi))
	var n := Vector2(-att_s * sin(phi), -cos(phi))
	var vp := f.dot(p)
	var alpha_raw := atan2(-f.dot(n), absf(vp))   # + = air on the underside
	var stab := clampf(spin, 0.0, 1.0)
	var edge := signf(vp) if absf(vp) > 0.02 else 0.0   # +1 nose leads, -1 tail leads
	# fade: the leading edge drops as the disc slows (much less with real spin)
	var fade_amt := clampf((t.fade_v - spd) / t.fade_v, 0.0, 1.0)
	phi -= t.fade * fade_amt * (1.0 - GYRO_FADE_HOLD * stab) * maxf(edge, 0.0) * dt
	# weak spin: the disc weathervanes into the airflow and loses its attitude
	phi -= alpha_raw * edge * GYRO_VANE * pow(1.0 - stab, 2.0) * dt
	phi += _wobble_noise() * wobble * (1.1 - spin) * 2.2 * dt
	var alpha := clampf(alpha_raw, -MAX_ALPHA, MAX_ALPHA)
	var cl: float = t.cl0 + t.cla * alpha
	if absf(alpha) > STALL_ALPHA:
		cl *= clampf(1.0 - (absf(alpha) - STALL_ALPHA) * 2.5, 0.25, 1.0)
	var cd: float = t.cd0 + t.cda * pow(alpha + 0.07, 2)
	# past the stall the disc behaves like a flat plate: the air pushes on its
	# face (normal force ~ sin a). Split into lift/drag along the airflow. This
	# is what stops a steep nose-up disc at the apex and slides it back down.
	var w := smoothstep(STALL_ALPHA, MAX_ALPHA, absf(alpha_raw))
	if w > 0.0:
		var sa := sin(alpha_raw)
		var cl_plate := GYRO_CN * sa * cos(alpha_raw)
		var cd_plate: float = t.cd0 + GYRO_CN * sa * sa * KL / KD
		cl = lerpf(cl, cl_plate, w)
		cd = lerpf(cd, cd_plate, w)
	# lift is perpendicular to the airflow, on the disc's top side
	var up := Vector2(-f.y, f.x)
	if up.dot(n) < 0.0:
		up = -up
	return {"cl": cl, "cd": cd, "up": up}


## Screen-space angle of the disc plane (what _draw uses).
func plane_angle() -> float:
	if state == FLIGHT and t.get("gyro", false):
		return -phi * att_s
	return -phi * facing


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
		if t.get("gyro", false):
			phi *= 0.5  # attitude is world-fixed: the knock just flattens it
		else:
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


## Rolling resistance (px/s^2) and the extra pull a slope gives a rolling
## disc on top of its flight gravity: a wheel runs downhill, so a roller
## speeds up down a slope and keeps going instead of stalling on it.
const ROLL_FRICTION := 420.0
const ROLL_SLOPE_G := 1500.0
const ROLL_MAX := 2600.0


func _roll(dt: float) -> void:
	velocity.y += t.grav * dt
	var pre := velocity
	move_and_slide()
	var g := _ground_probe()
	if g:
		var n := g.get_normal()
		var tangent := Vector2(-n.y, n.x)
		# the contact normal wobbles ~0.1 even on flat ground; the slope comes
		# from the surface under the disc
		var fn := _floor_normal()
		var slope := absf(fn.x) > 0.02
		# on a slope, speed along the ground from before the move:
		# move_and_slide bleeds ~10% a tick off a body running down one
		var along := (pre if slope else velocity).dot(tangent)
		if slope:
			var down_slope := Vector2.DOWN - fn * fn.dot(Vector2.DOWN)   # gravity along the surface
			along += ROLL_SLOPE_G * down_slope.dot(tangent) * dt
		along = clampf(move_toward(along, 0.0, ROLL_FRICTION * dt), -ROLL_MAX, ROLL_MAX)
		velocity = tangent * along
		if absf(along) < 55.0 and not _downhill(fn):
			_set_state(SLIDE)
	if is_on_wall():
		velocity.x = -velocity.x * 0.45
		spin_dir = -spin_dir
		impact.emit("wall", absf(velocity.x))
	spin_angle += velocity.x * dt * 0.08


## Surface normal straight below the disc (UP when there's nothing there).
func _floor_normal() -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 48), collision_mask, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.normal if not hit.is_empty() else Vector2.UP


## Steep enough that gravity beats rolling resistance.
func _downhill(n: Vector2) -> bool:
	return (t.grav + ROLL_SLOPE_G) * absf(n.x) > ROLL_FRICTION * 1.2


func _slide(dt: float) -> void:
	velocity.y += 1800.0 * dt
	move_and_slide()
	var g := _ground_probe()
	if g and t.roll and _downhill(_floor_normal()):
		_set_state(ROLL)   # a roller set down on a slope sets off down it
		return
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
	var target: Vector2 = level.basket_pos + Vector2(clampf(global_position.x - level.basket_pos.x, -24, 24), Basket.CATCH_Y)
	velocity = velocity.lerp(Vector2.ZERO, 8.0 * dt)
	global_position = global_position.move_toward(target, 500.0 * dt)
	if chain_timer > 0.35 or global_position.distance_to(target) < 4.0:
		_score()


func _check_basket() -> void:
	if level == null or not level.has_basket:
		return
	var l: Vector2 = global_position - level.basket_pos
	if absf(l.x) > Basket.HALF_W + 40.0 or l.y > 10.0 or l.y < Basket.BAND_TOP - 20.0:
		return
	var spd := velocity.length()
	# chains
	if state != CHAINED and absf(l.x) < Basket.CHAIN_HALF and l.y > Basket.CHAIN_TOP and l.y < Basket.CHAIN_BOT:
		if spd > 1500.0 and absf(l.x) > Basket.SPIT_X:
			# too hot off the edge of the chains: spit out
			velocity = Vector2(-velocity.x * 0.25, velocity.y * 0.3 - 120.0)
			impact.emit("chain_spit", spd)
			global_position.x = level.basket_pos.x + signf(l.x) * (Basket.CHAIN_HALF + 3.0)
			_set_state(FLIGHT)
			return
		_set_state(CHAINED)
		chain_timer = 0.0
		impact.emit("chains", spd)
		return
	# dropping into the tray from above
	if absf(l.x) < Basket.TRAY_HALF and l.y > Basket.TRAY_TOP and l.y < Basket.TRAY_BOT and velocity.y > -50.0 and state != CHAINED:
		_set_state(CHAINED)
		chain_timer = 0.2
		impact.emit("chains", spd)
		return
	# pole
	if absf(l.x) < Basket.POLE_HALF + RADIUS and l.y > Basket.TRAY_BOT and l.y < 0.0 and state == FLIGHT:
		velocity.x = -velocity.x * 0.4
		global_position.x = level.basket_pos.x + signf(l.x if l.x != 0 else -velocity.x) * (Basket.POLE_HALF + RADIUS + 1.0)
		impact.emit("pole", spd)
	# top band
	if absf(l.x) < Basket.HALF_W and l.y > Basket.BAND_TOP - 2.0 and l.y < Basket.BAND_BOT and state == FLIGHT:
		var mid := (Basket.BAND_TOP + Basket.BAND_BOT) * 0.5
		velocity.y = -absf(velocity.y) * 0.4 if l.y < mid else absf(velocity.y) * 0.3
		impact.emit("pole", spd)


func _check_gates() -> void:
	if runner == null:
		return
	for g in runner.gates:
		if not g.triggered and g.hit_by(global_position, state == ROLL):
			g.trigger()
			impact.emit("gate", velocity.length())


func _score() -> void:
	global_position = level.basket_pos + Vector2(clampf(global_position.x - level.basket_pos.x, -24, 24), Basket.CATCH_Y)
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


## How the disc is drawn right now: x = screen rotation, y = vertical squash
## (1 = seen edge-on rolling, ~0.3 = flat, negative = upside down).
func pose() -> Vector2:
	match state:
		FLIGHT, CHAINED:
			var sq := 0.3
			if t.get("inverted", false):
				sq = -0.3   # scoober: leaves the hand upside down
			elif t.flip_t > 0.0:
				# turns over through edge-on, over the same window its lift changes
				sq = lerpf(0.3, -0.3, smoothstep(t.flip_t * 0.6, t.flip_t * 1.4, age))
			return Vector2(plane_angle(), sq)
		ROLL:
			return Vector2(0.0, 1.0)
	return Vector2(0.0, 0.28)


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("disc.draw", _pt)


func _draw_timed() -> void:
	var pz := pose()
	var ang := pz.x
	var squash := pz.y
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
