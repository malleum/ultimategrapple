extends CharacterBody2D
## Local player: momentum platformer + rope/zip grapple + disc throwing.
## Origin is at the feet.

const ThrowTypes = preload("res://src/disc/throw_types.gd")
const PlayerVisual = preload("res://src/player/player_visual.gd")
const Disc = preload("res://src/disc/disc.gd")
const PlayerInput = preload("res://src/core/player_input.gd")

signal died
signal fx(kind: String, pos: Vector2, data: Variant)
signal threw(info: Dictionary)
signal caught(midair: bool)
signal recalled

enum { NORMAL, SWING, ZIP, PIVOT, DEAD }

# --- movement tuning (px, px/s, px/s^2)
const RUN_SPEED := 440.0
const GROUND_ACCEL := 4400.0
const GROUND_DECEL := 5200.0
const OVERSPEED_FRICTION := 650.0
const AIR_ACCEL := 2600.0
const GRAVITY := 2300.0
const FALL_GRAVITY := 2750.0
const MAX_FALL := 1400.0
const FAST_FALL := 1950.0
const JUMP_V := 830.0
const JUMP_CUT := 0.45
const COYOTE := 0.09
const JUMP_BUFFER := 0.12
const WALL_SLIDE_MAX := 260.0
const WALL_JUMP_X := 540.0
const WALL_JUMP_Y := 790.0
const WALL_LOCK := 0.13
const DASH_SPEED := 920.0
const DASH_TIME := 0.13
const DASH_COOLDOWN := 0.28
const SLIDE_MIN_SPEED := 190.0
const SLIDE_BOOST := 150.0
const SLIDE_FRICTION := 300.0
const CROUCH_SPEED := 170.0
const CARRY_SPEED_MULT := 0.9     # carrying the disc is marginally slower
const CARRY_JUMP_MULT := 0.97
const MAX_SPEED := 2600.0

# --- grapple
const GRAPPLE_RANGE := 520.0
const ROPE_MIN := 36.0
const ROPE_MAX := 660.0
const REEL_SPEED := 540.0
const SWING_PUMP := 900.0
const ZIP_ACCEL := 4800.0
const ZIP_MAX := 1250.0
const TARGET_CONE := 0.42

# --- disc
const CATCH_RADIUS := 46.0
const PICKUP_RADIUS := 40.0
const CHARGE_TIME := 0.5
const OVERCHARGE_START := 1.1
const SNAP_PERFECT_MS := 35
const SNAP_GOOD_MS := 90
const NOSE_STEP := deg_to_rad(3.0)
const NOSE_MAX := deg_to_rad(15.0)
const PIVOT_MAX := 1.5
const AIR_PIVOT_MAX := 0.35
const PIVOT_LAUNCH_WINDOW := 0.3

const STAND := Vector2(20, 44)
const LOW := Vector2(20, 22)

var level: Node = null     # shared world (kill_y, basket)
var runner: Node = null    # per-player context (grapple points, gates, hud)
var inp: PlayerInput = PlayerInput.new()
var disc: Node = null
var visual: Node2D
var shape_node: CollisionShape2D
var rect_shape: RectangleShape2D

var state := NORMAL
var facing := 1.0
var input_x := 0.0
var on_floor := false
var coyote_t := 0.0
var buffer_t := 0.0
var jump_held_cut := false
var wall_dir := 0
var wall_lock_t := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var has_air_dash := true
var sliding := false
var crouched := false
var slide_boost_cd := 0.0
var winds: Array = []
var booster_dir := 0
var pad_lock_t := 0.0
var floor_ice := false
var air_time := 0.0

# grapple state
var anchors: Array = []       # Array[Vector2]; [0] original, rest are wrap corners
var wrap_signs: Array = []
var rope_len := 0.0
var grapple_node: Node = null  # grapple point node (null for grip surfaces)
var target: Dictionary = {}    # current aim target {pos, node}
var grapple_cd := 0.0

# throw state
var has_disc := true
var charging := false
var charge_t := 0.0
var sway_t := 0.0
var throw_type := 0
var nose := 0.0
var last_snap_ms := -100000
var last_release_ms := -100000
var pending_late_snap := false
var pivot_t := 0.0
var pivot_air := false
var pivot_stored := Vector2.ZERO
var air_pivot_ready := true
var pivot_threw_t := -1.0
var throws := 0
var aim_dir := Vector2.RIGHT
var move_factor := 0.0
var last_snap_quality := ""

# interpolation helpers for visuals drawn in world space
var prev_pos := Vector2.ZERO
var cur_pos := Vector2.ZERO
var anim_t := 0.0
var input_enabled := true
var color := Color(0.2, 1.0, 0.9)
var aim_override = null   # world position; used by tests/bots instead of the mouse

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	collision_layer = 1 << 1
	collision_mask = 1
	floor_max_angle = deg_to_rad(52)
	floor_snap_length = 10.0
	floor_constant_speed = false
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	safe_margin = 0.2
	shape_node = CollisionShape2D.new()
	rect_shape = RectangleShape2D.new()
	rect_shape.size = STAND
	shape_node.shape = rect_shape
	shape_node.position = Vector2(0, -STAND.y * 0.5)
	add_child(shape_node)
	visual = PlayerVisual.new()
	add_child(visual)
	_rng.randomize()


func _ready() -> void:
	prev_pos = global_position
	cur_pos = global_position
	visual.color = color


func mouse_world() -> Vector2:
	if aim_override != null:
		return aim_override
	if not inp.mouse_world_fn.is_valid():
		inp.mouse_world_fn = get_global_mouse_position
	return inp.aim_point(center())


func center() -> Vector2:
	return global_position + Vector2(0, -rect_shape.size.y * 0.5)


func hand() -> Vector2:
	return global_position + Vector2(0, -rect_shape.size.y * 0.72)


func interp_pos() -> Vector2:
	return prev_pos.lerp(cur_pos, Engine.get_physics_interpolation_fraction())


# ================================================================== main loop

func _physics_process(dt: float) -> void:
	prev_pos = cur_pos
	anim_t += dt
	if input_enabled:
		inp.poll()
	else:
		inp.clear()
	if state == DEAD:
		cur_pos = global_position
		return
	_timers(dt)
	_read_input()
	_handle_disc_input(dt)
	_handle_grapple_input()
	match state:
		NORMAL:
			_normal(dt)
		SWING:
			_swing(dt)
		ZIP:
			_zip(dt)
		PIVOT:
			_pivot(dt)
	_catch_disc()
	if level and global_position.y > level.kill_y:
		die("fall")
	cur_pos = global_position
	visual.update_from_player(self)


func _timers(dt: float) -> void:
	coyote_t -= dt
	buffer_t -= dt
	wall_lock_t -= dt
	dash_cd -= dt
	slide_boost_cd -= dt
	pad_lock_t -= dt
	grapple_cd -= dt
	if pivot_threw_t >= 0.0:
		pivot_threw_t += dt


func _read_input() -> void:
	if not input_enabled:
		input_x = 0.0
		return
	input_x = inp.move.x
	if inp.just_pressed("jump"):
		buffer_t = JUMP_BUFFER
	if inp.just_pressed("throw_next"):
		set_throw_type(throw_type + 1)
	if inp.just_pressed("throw_prev"):
		set_throw_type(throw_type - 1)
	for i in 6:
		if inp.just_pressed("throw_%d" % (i + 1)):
			set_throw_type(i)
	if inp.just_pressed("nose_up"):
		adjust_nose(1)
	if inp.just_pressed("nose_down"):
		adjust_nose(-1)
	if inp.just_pressed("recall"):
		recall()
	var aim := mouse_world() - hand()
	if aim.length() > 4.0:
		aim_dir = aim.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not inp.uses_kbm():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_nose(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_nose(-1)


func set_throw_type(i: int) -> void:
	throw_type = posmod(i, ThrowTypes.count())
	fx.emit("ui_tick", global_position, throw_type)


func adjust_nose(dir: int) -> void:
	nose = clampf(nose + dir * NOSE_STEP, -NOSE_MAX, NOSE_MAX)
	fx.emit("ui_tick", global_position, nose)


func carry_mult() -> float:
	return CARRY_SPEED_MULT if has_disc else 1.0


# ================================================================== NORMAL state

func _normal(dt: float) -> void:
	var max_speed := RUN_SPEED * carry_mult()
	var jump_mult := CARRY_JUMP_MULT if has_disc else 1.0
	var down := inp.pressed("move_down") and input_enabled

	if on_floor:
		coyote_t = COYOTE
		has_air_dash = true
		air_pivot_ready = true
		air_time = 0.0
	else:
		air_time += dt

	# ---- dash
	if input_enabled and inp.just_pressed("dash") and dash_cd <= 0.0 and (on_floor or has_air_dash):
		var dv := Vector2(input_x, inp.move.y)
		if dv.length() < 0.1:
			dv = Vector2(facing, 0)
		dash_dir = dv.normalized()
		dash_t = DASH_TIME
		dash_cd = DASH_COOLDOWN
		if not on_floor:
			has_air_dash = false
		velocity = dash_dir * maxf(DASH_SPEED, velocity.dot(dash_dir))
		_set_low(false)
		sliding = false
		fx.emit("dash", center(), dash_dir)

	if dash_t > 0.0:
		dash_t -= dt
		velocity = dash_dir * maxf(DASH_SPEED, velocity.dot(dash_dir))
		if dash_t <= 0.0:
			var spd := velocity.length()
			if dash_dir.y < -0.3:
				velocity *= 0.55
			elif spd > RUN_SPEED:
				velocity = velocity.normalized() * maxf(RUN_SPEED * 1.05, spd * 0.72)
		_move(dt)
		return

	# ---- jump (before friction so bunny hops keep speed)
	var jumped := false
	if buffer_t > 0.0 and state == NORMAL:
		if on_floor or coyote_t > 0.0:
			var can_stand := not crouched or _can_stand()
			velocity.y = -JUMP_V * jump_mult
			if sliding:
				velocity.x *= 1.04
			buffer_t = 0.0
			coyote_t = 0.0
			jumped = true
			jump_held_cut = false
			on_floor = false
			if can_stand:
				_set_low(false)
				sliding = false
			fx.emit("jump", global_position, sliding)
		elif wall_dir != 0:
			velocity.x = -wall_dir * WALL_JUMP_X
			velocity.y = -WALL_JUMP_Y * jump_mult
			facing = -wall_dir
			wall_lock_t = WALL_LOCK
			buffer_t = 0.0
			jump_held_cut = false
			fx.emit("walljump", global_position, wall_dir)
	if not jump_held_cut and velocity.y < 0.0 and not inp.pressed("jump") and pad_lock_t <= 0.0:
		velocity.y *= JUMP_CUT
		jump_held_cut = true

	# ---- slide / crouch
	if on_floor and not jumped:
		if down and not sliding and absf(velocity.x) > SLIDE_MIN_SPEED:
			sliding = true
			_set_low(true)
			if slide_boost_cd <= 0.0:
				velocity.x += signf(velocity.x) * SLIDE_BOOST
				slide_boost_cd = 0.7
			fx.emit("slide", global_position, velocity.x)
		elif down and not sliding:
			crouched = true
			_set_low(true)
		elif not down and (sliding or crouched) and _can_stand():
			sliding = false
			crouched = false
			_set_low(false)
		if sliding and absf(velocity.x) < 70.0:
			sliding = false
			crouched = true
	elif not on_floor and (sliding or crouched) and not down and _can_stand():
		sliding = false
		crouched = false
		_set_low(false)

	# ---- horizontal
	if input_x != 0.0:
		facing = signf(input_x)
	var ice_mult := 0.3 if floor_ice else 1.0
	if on_floor and not jumped:
		if sliding:
			var n := get_floor_normal()
			var tangent := Vector2(-n.y, n.x)
			velocity += tangent * tangent.dot(Vector2(0, GRAVITY)) * dt * 0.9
			velocity.x = move_toward(velocity.x, 0.0, SLIDE_FRICTION * (0.4 if floor_ice else 1.0) * dt)
		elif crouched:
			velocity.x = move_toward(velocity.x, input_x * CROUCH_SPEED, GROUND_DECEL * ice_mult * dt)
		elif booster_dir != 0:
			velocity.x = booster_dir * maxf(absf(velocity.x) if signf(velocity.x) == booster_dir else 0.0, 950.0)
		elif input_x != 0.0:
			var target_v := input_x * max_speed
			if signf(input_x) == signf(velocity.x) and absf(velocity.x) > max_speed:
				velocity.x = move_toward(velocity.x, target_v, OVERSPEED_FRICTION * ice_mult * dt)
			else:
				velocity.x = move_toward(velocity.x, target_v, GROUND_ACCEL * ice_mult * dt)
		else:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_DECEL * (0.08 if floor_ice else 1.0) * dt)
	else:
		if input_x != 0.0 and wall_lock_t <= 0.0 and pad_lock_t <= 0.0:
			var target_v := input_x * max_speed
			if absf(velocity.x) < max_speed or signf(velocity.x) != signf(input_x):
				velocity.x = move_toward(velocity.x, target_v, AIR_ACCEL * dt)

	# ---- vertical
	if not on_floor or jumped:
		var g := GRAVITY if velocity.y < 0.0 else FALL_GRAVITY
		var max_fall := MAX_FALL
		if down and velocity.y > -100.0:
			g *= 1.4
			max_fall = FAST_FALL
		velocity.y = minf(velocity.y + g * dt, max_fall)
		# wall slide
		if wall_dir != 0 and signf(input_x) == wall_dir and velocity.y > WALL_SLIDE_MAX:
			velocity.y = move_toward(velocity.y, WALL_SLIDE_MAX, 6000.0 * dt)
	for w in winds:
		if is_instance_valid(w):
			velocity += w.force * dt
			velocity.y = maxf(velocity.y, -950.0)
	_move(dt)


func _move(_dt: float) -> void:
	if velocity.length() > MAX_SPEED:
		velocity = velocity.limit_length(MAX_SPEED)
	var pre_vel := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o and o.has_meta("glass") and (dash_t > 0.0 or pre_vel.length() > 700.0):
			o.get_parent().shatter(pre_vel)
			velocity = pre_vel * 0.9
	var was_floor := on_floor
	on_floor = is_on_floor()
	floor_ice = false
	if on_floor:
		var fc := get_last_slide_collision()
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			if c.get_normal().y < -0.5 and c.get_collider() and c.get_collider().has_meta("ice"):
				floor_ice = true
		if not was_floor and pre_vel.y > 300.0:
			fx.emit("land", global_position, pre_vel.y)
	wall_dir = 0
	if not on_floor:
		if test_move(global_transform, Vector2(3, 0)):
			wall_dir = 1
		elif test_move(global_transform, Vector2(-3, 0)):
			wall_dir = -1


func _set_low(low: bool) -> void:
	var size := LOW if low else STAND
	if rect_shape.size == size:
		return
	rect_shape.size = size
	shape_node.position = Vector2(0, -size.y * 0.5)


func _can_stand() -> bool:
	if rect_shape.size == STAND:
		return true
	return not test_move(global_transform, Vector2(0, -(STAND.y - LOW.y)))


# ================================================================== grapple

func _handle_grapple_input() -> void:
	target = _find_target() if state != SWING and state != ZIP else {}
	if not input_enabled:
		return
	if state == NORMAL or state == PIVOT:
		if grapple_cd <= 0.0 and not target.is_empty():
			if inp.just_pressed("grapple"):
				_attach(target, SWING)
			elif inp.just_pressed("zip"):
				_attach(target, ZIP)
	elif state == SWING:
		if not inp.pressed("grapple"):
			_detach(false)
		elif inp.just_pressed("jump"):
			buffer_t = 0.0
			_detach(true)
		elif inp.just_pressed("dash") and has_air_dash:
			_detach(false)
			_normal(0.0)
	elif state == ZIP:
		if not inp.pressed("zip"):
			_detach(false)
		elif inp.just_pressed("jump"):
			buffer_t = 0.0
			_detach(true)


func _find_target() -> Dictionary:
	if level == null:
		return {}
	var c := center()
	var aim := mouse_world() - c
	if aim.length() < 1.0:
		aim = Vector2(facing, -1)
	var best := {}
	var best_score := INF
	var space := get_world_2d().direct_space_state
	var cone := TARGET_CONE * (1.5 if inp.is_pad_aim() else 1.0)
	for gp in runner.grapple_points:
		if not gp.active:
			continue
		var p: Vector2 = gp.global_position
		var d := p - c
		var dist := d.length()
		if dist > GRAPPLE_RANGE or dist < 20.0:
			continue
		var ang := absf(aim.angle_to(d))
		if ang > cone:
			continue
		var score := ang + dist / GRAPPLE_RANGE * 0.35
		if score >= best_score:
			continue
		var q := PhysicsRayQueryParameters2D.create(c, p, collision_mask, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			continue
		best_score = score
		best = {"pos": p, "node": gp}
	if not best.is_empty():
		return best
	# grip surfaces: grapple anywhere on them
	var q2 := PhysicsRayQueryParameters2D.create(c, c + aim.normalized() * GRAPPLE_RANGE, collision_mask, [get_rid()])
	var hit2 := space.intersect_ray(q2)
	if not hit2.is_empty() and hit2.collider and hit2.collider.has_meta("grip"):
		return {"pos": hit2.position + hit2.normal * 2.0, "node": null}
	return {}


func _attach(t: Dictionary, mode: int) -> void:
	anchors = [t.pos]
	wrap_signs = []
	grapple_node = t.node
	rope_len = clampf(center().distance_to(t.pos), ROPE_MIN, ROPE_MAX)
	state = mode
	has_air_dash = true
	dash_t = 0.0
	sliding = false
	if grapple_node:
		grapple_node.on_attach(self)
	fx.emit("grapple_attach", t.pos, mode)


func _detach(jump: bool) -> void:
	if state != SWING and state != ZIP:
		return
	if grapple_node and is_instance_valid(grapple_node):
		if grapple_node.kind == "boost":
			velocity += velocity.normalized() * 380.0
			fx.emit("boost", center(), velocity)
		grapple_node.on_release(self)
	if jump:
		velocity.y = minf(velocity.y - 260.0, -380.0)
		jump_held_cut = true
	state = NORMAL
	anchors.clear()
	wrap_signs.clear()
	grapple_node = null
	grapple_cd = 0.08
	fx.emit("grapple_release", center(), jump)


## Called by fragile grapple points when they shatter.
func force_release(node: Node) -> void:
	if grapple_node == node:
		_detach(false)


func _swing(dt: float) -> void:
	if grapple_node and is_instance_valid(grapple_node):
		if not grapple_node.active:
			_detach(false)
			return
		anchors[0] = grapple_node.global_position
	var a: Vector2 = anchors[-1]
	var c := center()
	var r := c - a
	var dist := r.length()
	var n := r / maxf(dist, 0.001)
	var taut := dist >= rope_len - 2.0

	velocity.y += GRAVITY * dt
	for w in winds:
		if is_instance_valid(w):
			velocity += w.force * dt * 0.6
	if taut and input_x != 0.0:
		var tangent := Vector2(-n.y, n.x)
		if signf(tangent.x) != signf(input_x):
			tangent = -tangent
		velocity += tangent * SWING_PUMP * absf(input_x) * dt
	elif input_x != 0.0:
		velocity.x = move_toward(velocity.x, input_x * RUN_SPEED, AIR_ACCEL * 0.5 * dt)

	# reel in/out (reel-in conserves angular momentum -> speeds up the swing)
	if input_enabled:
		var reel := inp.move.y
		if reel != 0.0:
			var old := rope_len
			rope_len = clampf(rope_len + reel * REEL_SPEED * dt, ROPE_MIN, ROPE_MAX)
			if reel < 0.0 and taut and rope_len < old:
				var vr := n * velocity.dot(n)
				var vt := velocity - vr
				velocity = vr + vt * minf(old / rope_len, 1.04)

	_move(dt)

	# rope constraint (inelastic)
	c = center()
	a = anchors[-1]
	r = c - a
	dist = r.length()
	if dist > rope_len:
		n = r / dist
		var corr := a + n * rope_len - c
		move_and_collide(corr)
		var vn := velocity.dot(n)
		if vn > 0.0:
			velocity -= n * vn
	_update_wraps()
	if on_floor and velocity.length() < 30.0 and dist < rope_len * 0.6:
		pass


func _zip(dt: float) -> void:
	if grapple_node and is_instance_valid(grapple_node):
		if not grapple_node.active:
			_detach(false)
			return
		anchors[0] = grapple_node.global_position
	var a: Vector2 = anchors[0]
	var c := center()
	var to := a - c
	var dist := to.length()
	if dist < 42.0:
		_detach(false)
		return
	var dir := to / dist
	velocity += dir * ZIP_ACCEL * dt
	velocity.y += GRAVITY * 0.2 * dt
	# kill sideways drift so the zip is snappy
	var along := velocity.dot(dir)
	var side := velocity - dir * along
	velocity = dir * minf(along, ZIP_MAX) + side * pow(0.02, dt)
	_move(dt)
	var q := PhysicsRayQueryParameters2D.create(center(), a, collision_mask, [get_rid()])
	if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
		_detach(false)


func _update_wraps() -> void:
	var c := center()
	# unwrap: we swung back across the line through the last two anchors
	if anchors.size() > 1:
		var last: Vector2 = anchors[-1]
		var prev: Vector2 = anchors[-2]
		var side := signf((last - prev).cross(c - last))
		if side != 0.0 and side != wrap_signs[-1]:
			rope_len = minf(rope_len + last.distance_to(prev), ROPE_MAX * 1.5)
			anchors.pop_back()
			wrap_signs.pop_back()
			return
	var a: Vector2 = anchors[-1]
	var q := PhysicsRayQueryParameters2D.create(c, a, collision_mask, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.position.distance_to(a) < 4.0:
		return
	var corner = _find_corner(hit.collider, c, a)
	if corner == null:
		return
	var seg: float = a.distance_to(corner)
	if seg < 4.0 or anchors.size() > 12:
		return
	rope_len = maxf(ROPE_MIN, rope_len - seg)
	anchors.append(corner)
	wrap_signs.append(signf((corner - a).cross(c - corner)))
	fx.emit("rope_wrap", corner, null)


func _find_corner(col: Object, c: Vector2, a: Vector2):
	var verts := PackedVector2Array()
	var mid := Vector2.ZERO
	if col and col.has_meta("rect"):
		var r: Rect2 = col.get_meta("rect")
		verts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		mid = r.get_center()
	elif col and col.has_meta("poly"):
		verts = col.get_meta("poly")
		for v in verts:
			mid += v
		mid /= maxf(1.0, verts.size())
	else:
		return null
	var best = null
	var best_d := INF
	for v in verts:
		# only corners that are inside the swept triangle-ish region: closest to the rope line
		var d := Geometry2D.get_closest_point_to_segment(v, c, a).distance_to(v)
		if d < best_d:
			best_d = d
			best = v
	if best == null:
		return null
	return best + (best - mid).normalized() * 2.0


# ================================================================== pivot

func _pivot(dt: float) -> void:
	pivot_t += dt
	velocity = Vector2.ZERO
	var limit := AIR_PIVOT_MAX if pivot_air else PIVOT_MAX
	var released := not inp.pressed("pivot") or not input_enabled
	if released or pivot_t > limit or (not has_disc and pivot_threw_t < 0.0):
		_end_pivot(released)
		return
	if buffer_t > 0.0 and not pivot_air:
		_end_pivot(false)
		_normal(dt)
		return
	_move(dt)
	if not pivot_air and not on_floor:
		_end_pivot(false)


func _start_pivot() -> void:
	pivot_stored = velocity
	pivot_t = 0.0
	pivot_air = not on_floor
	if pivot_air:
		air_pivot_ready = false
	pivot_threw_t = -1.0
	state = PIVOT
	sliding = false
	velocity = Vector2.ZERO
	fx.emit("pivot", global_position, pivot_air)


func _end_pivot(released: bool) -> void:
	state = NORMAL
	if released and pivot_threw_t >= 0.0 and pivot_threw_t <= PIVOT_LAUNCH_WINDOW:
		velocity = pivot_stored * 1.08
		if pivot_air:
			velocity.y = minf(velocity.y, 0.0)
		fx.emit("pivot_launch", center(), velocity)
	pivot_threw_t = -1.0


# ================================================================== disc

func _handle_disc_input(dt: float) -> void:
	if not input_enabled:
		charging = false
		return
	var now := Time.get_ticks_msec()
	if inp.just_pressed("snap"):
		last_snap_ms = now
		if pending_late_snap and now - last_release_ms <= SNAP_GOOD_MS and disc:
			var dtm := now - last_release_ms
			var perfect := dtm <= SNAP_PERFECT_MS
			disc.late_snap(1.0 if perfect else 0.8, 1.09 if perfect else 1.04, 0.15 if perfect else 0.5)
			pending_late_snap = false
			_snap_feedback("PERFECT" if perfect else "GOOD")
	if pending_late_snap and now - last_release_ms > SNAP_GOOD_MS:
		pending_late_snap = false
		_snap_feedback("NO SNAP")

	if inp.just_pressed("pivot") and has_disc and (state == NORMAL) and (on_floor or air_pivot_ready):
		_start_pivot()

	if not has_disc:
		charging = false
		return
	if inp.just_pressed("throw"):
		charging = true
		charge_t = 0.0
		sway_t = _rng.randf() * 10.0
		fx.emit("charge", hand(), null)
	if charging:
		charge_t += dt
		sway_t += dt
		move_factor = _move_factor()
		if not inp.pressed("throw"):
			_throw()


func _move_factor() -> float:
	if state == PIVOT:
		return 0.0
	var t: Dictionary = ThrowTypes.get_type(throw_type)
	var m := clampf(velocity.length() / RUN_SPEED, 0.0, 1.4)
	if not on_floor and state != PIVOT:
		m += 0.2
	return m * t.move_pen


func charge_power() -> float:
	var c := clampf(charge_t / CHARGE_TIME, 0.0, 1.0)
	return lerpf(0.3, 1.0, pow(c, 0.8))


func overcharge() -> float:
	return clampf((charge_t - OVERCHARGE_START) / 1.0, 0.0, 1.0)


## Current aim sway angle (radians); grows with movement and overcharge.
func sway_angle() -> float:
	var amp := 0.13 * move_factor + 0.1 * overcharge()
	return (sin(sway_t * 7.3) * 0.6 + sin(sway_t * 11.7 + 0.7) * 0.4) * amp


func _throw() -> void:
	charging = false
	var ty: Dictionary = ThrowTypes.get_type(throw_type)
	var now := Time.get_ticks_msec()
	last_release_ms = now
	var mf := _move_factor()
	var oc := overcharge()
	var snap_dt := now - last_snap_ms
	var spin: float = 0.45
	var speed_mult := 1.0
	var wob_mult := 1.0
	var quality := ""
	if snap_dt >= 0 and snap_dt <= SNAP_PERFECT_MS:
		spin = 1.0; speed_mult = 1.09; wob_mult = 0.15; quality = "PERFECT"
	elif snap_dt >= 0 and snap_dt <= SNAP_GOOD_MS:
		spin = 0.8; speed_mult = 1.04; wob_mult = 0.5; quality = "GOOD"
	else:
		pending_late_snap = true
	spin *= ty.spin * (1.0 - 0.3 * minf(mf, 1.0))
	var ang := aim_dir.angle() + sway_angle() + _rng.randfn(0.0, 0.035 * mf + 0.04 * oc)
	var dir := Vector2.RIGHT.rotated(ang)
	var power := charge_power()
	var spd: float = ty.speed * power * speed_mult * (1.0 - 0.22 * minf(mf, 1.0)) * (1.0 - 0.1 * oc)
	var vel := dir * spd + velocity * 0.2
	var wobble := (0.25 + mf * 0.9 + oc * 0.8) * wob_mult
	var from := hand() + dir * 16.0
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(center(), from, collision_mask, [get_rid()])
	if not space.intersect_ray(q).is_empty():
		from = center()
	has_disc = false
	throws += 1
	disc.launch(from, vel, throw_type, spin, nose * facing_sign_for(dir), wobble)
	disc.thrower_id = 1
	if state == PIVOT:
		pivot_threw_t = 0.0
	if quality != "":
		_snap_feedback(quality)
	var info := {"type": ty.id, "power": power, "quality": quality, "move": mf, "overcharge": oc}
	threw.emit(info)
	fx.emit("throw", from, info)


func facing_sign_for(_dir: Vector2) -> float:
	return 1.0


func _snap_feedback(q: String) -> void:
	last_snap_quality = q
	fx.emit("snap", hand(), q)


func _catch_disc() -> void:
	if has_disc or disc == null or state == DEAD:
		return
	var c := center()
	var d: float = disc.global_position.distance_to(c)
	if disc.state == Disc.FLIGHT and disc.age > 0.2 and d < CATCH_RADIUS:
		_take_disc(not on_floor)
	elif disc.state in [Disc.ROLL, Disc.SLIDE, Disc.REST] and d < PICKUP_RADIUS + 8.0:
		_take_disc(false)


func _take_disc(midair: bool) -> void:
	has_disc = true
	disc.hold()
	pending_late_snap = false
	if midair:
		has_air_dash = true
		air_pivot_ready = true
		dash_cd = 0.0
	caught.emit(midair)
	fx.emit("catch", center(), midair)


func recall() -> void:
	if has_disc or disc == null:
		return
	if disc.state == Disc.SCORED:
		return
	has_disc = true
	disc.hold()
	recalled.emit()
	fx.emit("recall", center(), null)


# ================================================================== triggers

func trigger_enter(kind: String, node: Node) -> void:
	match kind:
		"hazard", "kill":
			die(kind)
		"wind":
			if not winds.has(node):
				winds.append(node)
		"booster":
			booster_dir = int(node.dir)
			fx.emit("booster", global_position, booster_dir)
		"pad":
			if state == SWING or state == ZIP:
				_detach(false)
			if state == PIVOT:
				state = NORMAL
			velocity = node.dir * node.power
			pad_lock_t = 0.18
			jump_held_cut = true
			has_air_dash = true
			air_pivot_ready = true
			on_floor = false
			dash_t = 0.0
			fx.emit("pad", global_position, node.dir)


func trigger_exit(kind: String, node: Node) -> void:
	match kind:
		"wind":
			winds.erase(node)
		"booster":
			booster_dir = 0


func die(reason: String) -> void:
	if state == DEAD:
		return
	if state == SWING or state == ZIP:
		_detach(false)
	state = DEAD
	velocity = Vector2.ZERO
	charging = false
	fx.emit("death", center(), reason)
	died.emit()


func respawn(pos: Vector2) -> void:
	global_position = pos
	reset_physics_interpolation()
	prev_pos = pos
	cur_pos = pos
	velocity = Vector2.ZERO
	state = NORMAL
	anchors.clear()
	wrap_signs.clear()
	grapple_node = null
	winds.clear()
	booster_dir = 0
	sliding = false
	crouched = false
	_set_low(false)
	has_air_dash = true
	air_pivot_ready = true
	dash_t = 0.0
	charging = false
	on_floor = false


## Compact state for network ghosts / replays.
func snapshot() -> Array:
	var flags := 0
	if on_floor: flags |= 1
	if sliding or crouched: flags |= 2
	if state == SWING or state == ZIP: flags |= 4
	if has_disc: flags |= 8
	if charging: flags |= 16
	if state == DEAD: flags |= 32
	var anchor := Vector2.ZERO
	if not anchors.is_empty():
		anchor = anchors[-1]
	return [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1),
		snappedf(velocity.x, 1), snappedf(velocity.y, 1), int(facing), flags,
		snappedf(anchor.x, 0.1), snappedf(anchor.y, 0.1)]
