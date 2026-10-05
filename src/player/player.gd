extends CharacterBody2D
## Local player: momentum platformer + rope/zip grapple + disc throwing.
## Origin is at the feet.

const Perf = preload("res://src/core/perf.gd")

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
const RUN_SPEED := 858.0         # empty-handed
const GROUND_ACCEL := 6600.0
const GROUND_DECEL := 7200.0
const OVERSPEED_FRICTION := 650.0
const AIR_ACCEL := 4200.0
const GRAVITY := 2300.0
const FALL_GRAVITY := 2750.0
const MAX_FALL := 1400.0
const FAST_FALL := 1950.0
const JUMP_V := 830.0
const RELEASE_GRAVITY := 2.6     # gravity x while rising after letting go of jump (short hops)
const APEX_GRAVITY := 0.55       # gravity x near the top of a held jump (a little hang)
const APEX_BAND := 130.0         # |vy| below this counts as "near the top"
const TURN_ACCEL_MULT := 1.8     # extra grip when reversing direction on the ground
const MANTLE_UP := 48.0          # walls whose top is within this above your feet get climbed
const CORNER_NUDGE := 12.0
const TACKLE_KNOCK := Vector2(620.0, 460.0)   # versus: a slide into another runner
const TACKLE_STUN := 0.7
const TACKLE_REACH := Vector2(26.0, 40.0)    # |dx|, |dy| between feet that counts as contact       # head clips a ceiling corner by up to this: slide past it
const DISC_HIT_MIN := 260.0      # versus: a disc slower than this just bounces off a runner
const DISC_HIT_FULL := 1100.0    # ... and this fast gives the full effect
const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const WALL_SLIDE_MAX := 260.0
const WALL_JUMP_X := 540.0
const WALL_JUMP_Y := 790.0
const WALL_LOCK := 0.13
const AIR_JUMP_V := 760.0          # double jump
const SLIDE_MIN_SPEED := 190.0
const SLIDE_BOOST := 150.0
const SLIDE_FRICTION := 300.0
const CROUCH_SPEED := 170.0
const CARRY_SPEED_MULT := 0.56    # carrying the disc: ~480
const CARRY_JUMP_MULT := 0.97
const MAX_SPEED := 2600.0
const THROW_MOVE_REF := 593.0     # speed that counts as "full run" for moving-throw sway

# --- grapple
const GRAPPLE_RANGE := 680.0
const ROPE_MIN := 36.0
const ROPE_MAX := 860.0
const REEL_SPEED := 540.0
const SWING_PUMP := 900.0
const ZIP_ACCEL := 3200.0
const ZIP_MAX := 830.0
const TARGET_CONE := 0.7          # aim cone (rad) for picking a grapple point
const CURSOR_SNAP := 160.0        # a point this close to the cursor is picked regardless of cone
const GRAPPLE_BUFFER := 0.15      # a grapple/zip press waits this long for a target / cooldown
const ZIP_STUCK_T := 0.4          # zip gives up after this long without getting closer

# --- disc
const CATCH_RADIUS := 46.0
const PICKUP_RADIUS := 40.0
const CHARGE_TIME := 0.5
const OVERCHARGE_START := 1.1
const NOSE_STEP := deg_to_rad(3.0)
const NOSE_MAX := deg_to_rad(15.0)
const PIVOT_MAX := 1.5
const AIR_PIVOT_MAX := 1.05
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
var frozen_t := 0.0        # versus: penalty freeze (recall / out of bounds), held in place
var stun_t := 0.0          # versus: tackled, no control while the knockback plays out
var tackle_cd := 0.0
var down_t := 0.0          # versus: knocked down by a disc to the head (lying, no control)
var stumble_t := 0.0       # versus: disc to the legs, forced into a slide
var mantle_t := 0.0         # climbing onto a ledge (no wall jump / jump cut meanwhile)
var has_air_jump := true    # double jump: refreshed by ground, grapple, pads, sky catch
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
var rope_ghosts: Array = []   # RIDs the rope was thrown straight through (see _rope_hit)
var rope_len := 0.0
var grapple_node: Node = null  # grapple point node (null for grip surfaces)
var target: Dictionary = {}    # current aim target {pos, node}
var grapple_cd := 0.0
var grapple_buf := 0.0
var zip_buf := 0.0
var zip_best := INF
var zip_stuck_t := 0.0

# throw state
var has_disc := true
var charging := false
var charge_t := 0.0
var sway_t := 0.0
var throw_type := 0
var nose := 0.0
var last_snap_us := -100000000
var last_release_us := -100000000
var pending_late_snap := false
var _pending := {}   # launch info kept for a late snap
var pivot_t := 0.0
var pivot_air := false
var pivot_stored := Vector2.ZERO
var air_pivot_ready := true
var pivot_threw_t := -1.0
var throws := 0
var aim_dir := Vector2.RIGHT
var move_factor := 0.0
var last_snap_quality := ""
var last_snap_score := 0.0

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
	if not inp.mouse_world_fn.is_valid():
		inp.mouse_world_fn = get_global_mouse_position


## Everything a fresh run starts from, so a restarted run and a freshly loaded
## one behave identically (replays depend on it). Throw type and nose angle
## are the player's choice and carry over.
func reset_run_state(seed_value: int) -> void:
	_rng.seed = seed_value
	coyote_t = 0.0
	buffer_t = 0.0
	mantle_t = 0.0
	jump_held_cut = false
	wall_dir = 0
	wall_lock_t = 0.0
	slide_boost_cd = 0.0
	pad_lock_t = 0.0
	floor_ice = false
	air_time = 0.0
	rope_len = 0.0
	rope_ghosts.clear()
	target = {}
	grapple_cd = 0.0
	grapple_buf = 0.0
	zip_buf = 0.0
	charge_t = 0.0
	sway_t = 0.0
	last_snap_us = -100000000
	last_release_us = -100000000
	pending_late_snap = false
	_pending = {}
	pivot_t = 0.0
	pivot_air = false
	pivot_stored = Vector2.ZERO
	pivot_threw_t = -1.0
	aim_dir = Vector2.RIGHT
	move_factor = 0.0
	input_x = 0.0
	anim_t = 0.0


## Aim point for drawing the reticle: live mouse every frame.
func mouse_world_draw() -> Vector2:
	if aim_override != null:
		return aim_override
	return inp.aim_point_draw(center())


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
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("player.physics", _pt)


func _physics_process_timed(dt: float) -> void:
	prev_pos = cur_pos
	anim_t += dt
	tackle_cd -= dt
	down_t -= dt
	stumble_t -= dt
	if frozen_t > 0.0:
		# penalty freeze: held in place, timer still running
		frozen_t -= dt
		inp.clear()
		velocity = Vector2.ZERO
		cur_pos = global_position
		visual.update_from_player(self)
		return
	if stun_t > 0.0:
		stun_t -= dt
		inp.clear()
	elif input_enabled:
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
	mantle_t -= dt
	buffer_t -= dt
	wall_lock_t -= dt
	slide_boost_cd -= dt
	pad_lock_t -= dt
	grapple_cd -= dt
	grapple_buf -= dt
	zip_buf -= dt
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


func _input(event: InputEvent) -> void:
	inp.handle_event(event)


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
	var down := (inp.pressed("move_down") and input_enabled) or stumble_t > 0.0 or down_t > 0.0

	if on_floor:
		coyote_t = COYOTE
		has_air_jump = true
		air_pivot_ready = true
		air_time = 0.0
	else:
		air_time += dt

	# ---- jump (before friction so bunny hops keep speed)
	var jumped := false
	if buffer_t > 0.0 and state == NORMAL:
		if (on_floor or coyote_t > 0.0) and rect_shape.size == LOW and _spikes_overhead():
			pass  # no jumping into tunnel spikes; the buffered jump fires once clear
		elif on_floor or coyote_t > 0.0:
			var can_stand := not (crouched or sliding) or _can_stand()
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
		elif wall_dir != 0 and _try_mantle(wall_dir):
			buffer_t = 0.0   # jumped at a wall you can reach the top of: climb it
		elif wall_dir != 0:
			velocity.x = -wall_dir * WALL_JUMP_X
			velocity.y = -WALL_JUMP_Y * jump_mult
			facing = -wall_dir
			wall_lock_t = WALL_LOCK
			buffer_t = 0.0
			jump_held_cut = false
			fx.emit("walljump", global_position, wall_dir)
		elif has_air_jump and inp.just_pressed("jump") and not _floor_close():
			# double jump: a fresh press in the air. Pressed just before landing
			# it stays buffered as a normal jump instead of burning this.
			has_air_jump = false
			# falling: a full jump; still rising: adds on top, capped at 1.15x
			var up := AIR_JUMP_V * jump_mult
			if velocity.y > -up:
				velocity.y = maxf(minf(velocity.y, 0.0) - up, -up * 1.15)
			if input_x != 0.0 and signf(input_x) != signf(velocity.x):
				velocity.x = input_x * maxf(absf(velocity.x) * 0.5, RUN_SPEED * carry_mult() * 0.6)
			buffer_t = 0.0
			jumped = true
			jump_held_cut = false
			fx.emit("airjump", center(), null)
	# a jump stays "variable" until its apex: letting go early adds gravity
	# (smooth short hop) instead of chopping the upward speed in one frame
	if not jump_held_cut and velocity.y >= 0.0:
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
				var turning := absf(velocity.x) > 1.0 and signf(velocity.x) != signf(input_x)
				velocity.x = move_toward(velocity.x, target_v, GROUND_ACCEL * ice_mult * (TURN_ACCEL_MULT if turning else 1.0) * dt)
		else:
			velocity.x = move_toward(velocity.x, 0.0, GROUND_DECEL * (0.08 if floor_ice else 1.0) * dt)
	else:
		if input_x != 0.0 and pad_lock_t <= 0.0:
			# after a wall jump, steering fades back in rather than snapping on
			var grip := 1.0 - clampf(wall_lock_t / WALL_LOCK, 0.0, 1.0) * 0.85
			var target_v := input_x * max_speed
			if absf(velocity.x) < max_speed or signf(velocity.x) != signf(input_x):
				velocity.x = move_toward(velocity.x, target_v, AIR_ACCEL * grip * dt)
		# jumped / fell into a wall near its top while pushing at it: climb on
		if mantle_t <= 0.0 and velocity.y > -320.0 and state == NORMAL:
			var push := int(signf(input_x)) if input_x != 0.0 else 0
			if push != 0 and test_move(global_transform, Vector2(push * 4.0, 0)):
				_try_mantle(push)

	# ---- vertical
	if not on_floor or jumped:
		var g := GRAVITY if velocity.y < 0.0 else FALL_GRAVITY
		if not jump_held_cut and mantle_t <= 0.0:
			if velocity.y < 0.0 and not inp.pressed("jump") and pad_lock_t <= 0.0:
				g *= RELEASE_GRAVITY
			elif absf(velocity.y) < APEX_BAND and inp.pressed("jump"):
				g *= APEX_GRAVITY
		var max_fall := MAX_FALL
		if down and velocity.y > -100.0:
			g *= 1.4
			max_fall = FAST_FALL
		velocity.y = minf(velocity.y + g * dt, max_fall)
		# wall slide
		if wall_dir != 0 and signf(input_x) == wall_dir and velocity.y > WALL_SLIDE_MAX and mantle_t <= 0.0:
			velocity.y = move_toward(velocity.y, WALL_SLIDE_MAX, 6000.0 * dt)
	for w in winds:
		if is_instance_valid(w):
			velocity += w.force * dt
			velocity.y = maxf(velocity.y, -950.0)
	if velocity.y < 0.0:
		_corner_correct(dt)
	_move(dt)


## How far up the body must rise to step `dir`-ward onto the top of the wall
## it is touching; -1 if that wall's top is out of reach (or a ceiling's in
## the way).
func _ledge_lift(dir: int) -> float:
	var xf := global_transform
	if dir == 0 or not test_move(xf, Vector2(dir * 6.0, 0)):
		return -1.0
	var h := 4.0
	while h <= MANTLE_UP:
		if test_move(xf, Vector2(0, -h)):
			return -1.0
		if not test_move(xf.translated(Vector2(0, -h)), Vector2(dir * 14.0, 0)):
			return h
		h += 4.0
	return -1.0


## Pop up onto a ledge: just enough upward speed to clear its lip, carrying
## on toward it. Feels like sliding up the last bit of wall, not bonking.
func _try_mantle(dir: int) -> bool:
	var h := _ledge_lift(dir)
	if h < 0.0:
		return false
	velocity.y = minf(velocity.y, -sqrt(2.0 * GRAVITY * (h + 10.0)))
	velocity.x = dir * maxf(absf(velocity.x), 260.0)
	mantle_t = 0.3
	jump_held_cut = true
	wall_lock_t = 0.0
	facing = dir
	fx.emit("mantle", global_position + Vector2(dir * 10.0, -h), dir)
	return true


## Rising into a ceiling corner by a few pixels: slide sideways past it
## instead of stopping dead.
func _corner_correct(dt: float) -> void:
	var xf := global_transform
	var rise := Vector2(0, minf(velocity.y * dt, -1.0))
	if not test_move(xf, rise):
		return
	for off in [4.0, 8.0, CORNER_NUDGE]:
		for sgn in [1.0, -1.0]:
			var side := Vector2(off * sgn, 0)
			if not test_move(xf, side) and not test_move(xf.translated(side), rise):
				global_position.x += off * sgn
				return


## Ground just below while falling: a jump press now should wait for landing.
func _floor_close() -> bool:
	if velocity.y <= 0.0:
		return false
	return test_move(global_transform, Vector2(0, clampf(velocity.y * JUMP_BUFFER, 6.0, 70.0)))


func _move(_dt: float) -> void:
	if velocity.length() > MAX_SPEED:
		velocity = velocity.limit_length(MAX_SPEED)
	var pre_vel := velocity
	move_and_slide()
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
		if _grippy_wall(1):
			wall_dir = 1
		elif _grippy_wall(-1):
			wall_dir = -1


## A wall right beside us that can be wall-jumped (slick walls can't).
func _grippy_wall(dir: int) -> bool:
	var c := move_and_collide(Vector2(dir * 3.0, 0), true, 0.08)   # same test as test_move()
	if c == null:
		return false
	var o := c.get_collider()
	return not (o and o.has_meta("slick"))


func _set_low(low: bool) -> void:
	var size := LOW if low else STAND
	if rect_shape.size == size:
		return
	rect_shape.size = size
	shape_node.position = Vector2(0, -size.y * 0.5)


func _can_stand() -> bool:
	if rect_shape.size == STAND:
		return true
	if test_move(global_transform, Vector2(0, -(STAND.y - LOW.y))):
		return false
	return not _spikes_overhead()


## Standing up here would put the head into a spike strip (slide tunnels):
## stay low instead of dying for letting go of down.
func _spikes_overhead() -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var sh := RectangleShape2D.new()
	sh.size = STAND + Vector2(4, 0)
	q.shape = sh
	q.transform = Transform2D(0.0, global_position + Vector2(0, -STAND.y * 0.5))
	q.collision_mask = 1 << 3
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 8):
		var z: Object = hit.collider
		if z and z.get("kind") == "hazard":
			return true
	return false


# ================================================================== grapple

func _handle_grapple_input() -> void:
	target = _find_target() if state != SWING and state != ZIP else {}
	if not input_enabled:
		return
	# presses are buffered briefly: a click during the release cooldown or a
	# frame before a point comes into range still grabs
	if inp.just_pressed("grapple"):
		grapple_buf = GRAPPLE_BUFFER
	if inp.just_pressed("zip"):
		zip_buf = GRAPPLE_BUFFER
	if state == NORMAL or state == PIVOT:
		if grapple_cd <= 0.0 and not target.is_empty():
			if zip_buf > 0.0 and inp.pressed("zip"):
				_attach(target, ZIP)
			elif grapple_buf > 0.0 and inp.pressed("grapple"):
				_attach(target, SWING)
	elif state == SWING:
		if inp.just_pressed("zip"):
			# swinging + tap zip: reel straight in along the rope
			_begin_zip()
		elif not inp.pressed("grapple"):
			_detach(false)
		elif inp.just_pressed("jump"):
			buffer_t = 0.0
			_detach(true)
	elif state == ZIP:
		if not inp.pressed("zip") and not inp.pressed("grapple"):
			_detach(false)
		elif inp.just_pressed("jump"):
			buffer_t = 0.0
			_detach(true)


func _find_target() -> Dictionary:
	if level == null:
		return {}
	var c := center()
	var m := mouse_world()
	var aim := m - c
	if aim.length() < 1.0:
		aim = Vector2(facing, -1)
	var pad := inp.is_pad_aim()
	var cone := TARGET_CONE * (1.3 if pad else 1.0)
	var best := {}
	var best_score := INF
	var space := get_world_2d().direct_space_state
	for gp in runner.grapple_points:
		if not gp.active:
			continue
		var p: Vector2 = gp.global_position
		var d := p - c
		var dist := d.length()
		if dist > GRAPPLE_RANGE or dist < 20.0:
			continue
		var ang := absf(aim.angle_to(d))
		var cursor_d := m.distance_to(p)
		var near_cursor := not pad and cursor_d < CURSOR_SNAP
		if ang > cone and not near_cursor:
			continue
		var score := ang + dist / GRAPPLE_RANGE * 0.25
		if near_cursor:
			# the point you're pointing at wins
			score = minf(score, cursor_d / CURSOR_SNAP * 0.3)
		if score >= best_score:
			continue
		# a wall in the way rules a point out; platforms don't (the rope goes
		# straight through them), they just make it lose to a clear one
		var los := _line_of_sight(c, p)
		if los == LOS_WALL:
			continue
		if los == LOS_PLATFORM:
			score += 0.3
			if score >= best_score:
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


enum { LOS_CLEAR, LOS_PLATFORM, LOS_WALL }
const PLATFORM_MAX_H := 64.0   # a slab this thin (and at least twice as wide) is a platform


## What lies between c and a grapple point p: nothing, only platforms (the
## rope may pass through), or a wall (no grapple). Something within a few px
## of the point is what the point is mounted on, not in the way.
func _line_of_sight(c: Vector2, p: Vector2) -> int:
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	var out := LOS_CLEAR
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(c, p, collision_mask, ex))
		if hit.is_empty() or hit.position.distance_to(p) < 8.0:
			break
		if not _is_platform(hit.collider):
			return LOS_WALL
		out = LOS_PLATFORM
		ex.append(hit.rid)
	return out


static func _is_platform(col: Object) -> bool:
	if col == null:
		return false
	if col.get("kind") == "oneway":
		return true
	if not col.has_meta("rect"):
		return false
	var r: Rect2 = col.get_meta("rect")
	return r.size.y <= PLATFORM_MAX_H and r.size.x >= r.size.y * 2.0


func _attach(t: Dictionary, mode: int) -> void:
	anchors = [t.pos]
	wrap_signs = []
	grapple_node = t.node
	grapple_buf = 0.0
	zip_buf = 0.0
	# grabbed through a platform: the rope goes straight through it (it only
	# bends around things that come between later)
	var c := center()
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	rope_ghosts.clear()
	for i in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(c, t.pos, collision_mask, ex))
		if hit.is_empty() or hit.position.distance_to(t.pos) < 4.0:
			break
		rope_ghosts.append(hit.rid)
		ex.append(hit.rid)
	rope_len = clampf(c.distance_to(anchors[-1]), ROPE_MIN, ROPE_MAX)
	state = mode
	if mode == ZIP:
		_begin_zip()
	has_air_jump = true
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
	rope_ghosts.clear()
	grapple_node = null
	grapple_cd = 0.08
	fx.emit("grapple_release", center(), jump)


func _begin_zip() -> void:
	state = ZIP
	zip_best = INF
	zip_stuck_t = 0.0


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
	# reel toward the nearest rope corner first, then on to the point itself
	var a: Vector2 = anchors[-1]
	var c := center()
	var to := a - c
	var dist := to.length()
	if anchors.size() > 1 and dist < 30.0:
		anchors.pop_back()
		wrap_signs.pop_back()
		a = anchors[-1]
		to = a - c
		dist = to.length()
	if anchors.size() == 1 and dist < 42.0:
		_detach(false)
		return
	var dir := to / maxf(dist, 0.001)
	velocity += dir * ZIP_ACCEL * dt
	velocity.y += GRAVITY * 0.2 * dt
	# kill sideways drift so the zip is snappy
	var along := velocity.dot(dir)
	var side := velocity - dir * along
	velocity = dir * minf(along, ZIP_MAX) + side * pow(0.02, dt)
	_move(dt)
	# pulled into a platform the rope went through: now it is in the way, bend
	# around it like anything else
	if not rope_ghosts.is_empty():
		for i in get_slide_collision_count():
			rope_ghosts.erase(get_slide_collision(i).get_collider_rid())
	# a platform crossing the line: bend around it instead of letting go
	c = center()
	var hit := _rope_hit(c, a)
	var wrapped := false
	if not hit.is_empty() and hit.position.distance_to(a) >= 4.0 and anchors.size() < 8:
		var corner = _zip_corner(hit.collider, c, a)
		if corner != null and corner.distance_to(a) >= 4.0:
			anchors.append(corner)
			wrap_signs.append(signf((corner - a).cross(c - corner)))
			wrapped = true
	# only give up when it really is stuck (pinned against something)
	var remaining := c.distance_to(anchors[-1])
	for i in range(anchors.size() - 1, 0, -1):
		remaining += (anchors[i] as Vector2).distance_to(anchors[i - 1])
	if wrapped:
		zip_best = remaining   # the way round is longer: measure progress from here
	elif remaining < zip_best - 2.0:
		zip_best = remaining
		zip_stuck_t = 0.0
	else:
		zip_stuck_t += dt
		if zip_stuck_t > ZIP_STUCK_T:
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
	var hit := _rope_hit(c, a)
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


## First thing the live rope segment (c -> a) runs into, skipping platforms
## the rope was thrown straight through. Those stay see-through until the rope
## is one straight segment clear of them again; after that they block (and
## get wrapped around) like anything else.
func _rope_hit(c: Vector2, a: Vector2) -> Dictionary:
	if rope_ghosts.is_empty():
		return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(c, a, collision_mask, [get_rid()]))
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	var crossing: Array = []
	for i in 8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(c, a, collision_mask, ex))
		if hit.is_empty():
			break
		if not rope_ghosts.has(hit.rid):
			return hit
		crossing.append(hit.rid)
		ex.append(hit.rid)
	if anchors.size() == 1:
		rope_ghosts = crossing
	return {}


## Zip: the corner of col on the shortest way round (c -> corner -> a) that
## can be reached in a straight line and isn't the one we're already at.
func _zip_corner(col: Object, c: Vector2, a: Vector2):
	var verts := _corners(col)
	if verts.is_empty():
		return null
	var space := get_world_2d().direct_space_state
	# already at a corner: the next one has to be reachable from there
	var from := c
	for v in verts:
		if v.distance_to(c) < 34.0:
			from = v
	var best = null
	var best_d := INF
	for v in verts:
		if v.distance_to(c) < 34.0:
			continue
		var d := c.distance_to(v) + v.distance_to(a)
		if d >= best_d:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, v, collision_mask, [get_rid()]))
		if not hit.is_empty() and hit.position.distance_to(v) > 4.0:
			continue
		best_d = d
		best = v
	return best


## A collider's corners, pushed 2 px outwards.
func _corners(col: Object) -> PackedVector2Array:
	var verts := PackedVector2Array()
	var mid := Vector2.ZERO
	if col and col.has_meta("rect"):
		var r: Rect2 = col.get_meta("rect")
		verts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	elif col and col.has_meta("poly"):
		verts = col.get_meta("poly")
	for v in verts:
		mid += v
	mid /= maxf(1.0, verts.size())
	var out := PackedVector2Array()
	for v in verts:
		out.append(v + (v - mid).normalized() * 2.0)
	return out


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
	var now_us := inp.now_us()
	if inp.just_pressed("snap"):
		last_snap_us = PlayerInput.stamp(inp.snap_us, now_us)
		if pending_late_snap and disc:
			var dtu := last_snap_us - last_release_us
			if dtu >= 0 and dtu <= ThrowTypes.SNAP_MAX_US:
				var s2 := ThrowTypes.snap_score(dtu)
				if s2 > float(_pending.get("score", 0.0)):
					_late_snap(s2, dtu)
	if pending_late_snap and now_us - last_release_us > ThrowTypes.SNAP_MAX_US:
		pending_late_snap = false
		if float(_pending.get("score", 0.0)) <= 0.0:
			_snap_feedback("NONE", -1, 0.0)

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
	var m := clampf(velocity.length() / THROW_MOVE_REF, 0.0, 1.4)
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
	var now_us := inp.now_us()
	last_release_us = PlayerInput.stamp(inp.throw_release_us, now_us)
	var mf := _move_factor()
	var oc := overcharge()
	# snap judged on |snap press - throw release|, either order; the exact
	# gap sets a continuous score, the label is just what we show
	var snap_dt := absi(last_release_us - last_snap_us)
	var score := ThrowTypes.snap_score(snap_dt)
	var label := ThrowTypes.snap_label(snap_dt)
	var power := charge_power()
	var lp := ThrowTypes.launch_params(ty, power, score, mf, oc)
	var ang := aim_dir.angle() + sway_angle() + _rng.randfn(0.0, 0.035 * mf + 0.04 * oc)
	var dir := Vector2.RIGHT.rotated(ang)
	var vel: Vector2 = dir * float(lp.speed) + velocity * 0.2
	var from := hand() + dir * 16.0
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(center(), from, collision_mask, [get_rid()])
	if not space.intersect_ray(q).is_empty():
		from = center()
	has_disc = false
	throws += 1
	disc.launch(from, vel, throw_type, lp.spin, nose * facing_sign_for(dir), lp.wobble, lp.quality)
	disc.thrower_id = 1
	# a snap that lands just after release can still improve the throw
	pending_late_snap = score < 1.0
	_pending = {"ty": ty, "power": power, "mf": mf, "oc": oc, "dir": dir, "score": score}
	if state == PIVOT:
		pivot_threw_t = 0.0
	if score > 0.0:
		_snap_feedback(label, snap_dt, score)
	var info := {"type": ty.id, "power": power, "quality": label if score > 0.0 else "", "score": score, "move": mf, "overcharge": oc}
	threw.emit(info)
	fx.emit("throw", from, info)


## Snap arrived just after release: upgrade the disc to exactly what an
## on-time snap with that timing would have produced.
func _late_snap(score: float, dt_us: int) -> void:
	if _pending.is_empty():
		return
	var cur := ThrowTypes.launch_params(_pending.ty, _pending.power, float(_pending.score), _pending.mf, _pending.oc)
	var lp := ThrowTypes.launch_params(_pending.ty, _pending.power, score, _pending.mf, _pending.oc)
	var add_vel: Vector2 = _pending.dir * (float(lp.speed) - float(cur.speed))
	disc.apply_late_snap(lp.spin, add_vel, lp.wobble, lp.quality)
	_pending.score = score
	if score >= 1.0:
		pending_late_snap = false
	_snap_feedback(ThrowTypes.snap_label(dt_us), dt_us, score)


func facing_sign_for(_dir: Vector2) -> float:
	return 1.0


func _snap_feedback(label: String, dt_us: int, score: float) -> void:
	last_snap_quality = "NO SNAP" if label == "NONE" else label
	last_snap_score = score
	fx.emit("snap", hand(), {"label": last_snap_quality, "ms": dt_us / 1000.0, "score": score})


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
		has_air_jump = true
		air_pivot_ready = true
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
			has_air_jump = true
			air_pivot_ready = true
			on_floor = false
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


## Versus penalty: stand frozen for `seconds` instead of adding time, so
## everyone's race clock stays comparable.
func freeze(seconds: float) -> void:
	if state == SWING or state == ZIP:
		_detach(false)
	if state == PIVOT:
		state = NORMAL
	frozen_t = maxf(frozen_t, seconds)
	velocity = Vector2.ZERO
	charging = false
	sliding = false
	fx.emit("frozen", center(), seconds)


func can_tackle() -> bool:
	return state == NORMAL and sliding and absf(velocity.x) > SLIDE_MIN_SPEED and stun_t <= 0.0 and frozen_t <= 0.0 and tackle_cd <= 0.0


func tackle_reaches(other_feet: Vector2) -> bool:
	var d := other_feet - global_position
	return absf(d.x) < TACKLE_REACH.x and absf(d.y) < TACKLE_REACH.y


## Hit by another runner's slide: knocked away and briefly out of control.
func tackled(dir: float) -> bool:
	if state == DEAD or stun_t > 0.0 or frozen_t > 0.0:
		return false
	if state == SWING or state == ZIP:
		_detach(false)
	state = NORMAL
	charging = false
	sliding = false
	crouched = false
	_set_low(false)
	velocity = Vector2(signf(dir) * TACKLE_KNOCK.x, -TACKLE_KNOCK.y)
	on_floor = false
	stun_t = TACKLE_STUN
	fx.emit("tackled", center(), dir)
	return true


## Which part of a runner standing at `feet` a disc at `p` touches:
## "head", "arm" (torso + arms), "leg", or "" for a miss.
static func disc_hit_zone(feet: Vector2, low: bool, p: Vector2) -> String:
	var h := LOW.y if low else STAND.y
	var dx := absf(p.x - feet.x)
	var up := feet.y - p.y   # height above the feet
	var r := Disc.RADIUS
	if dx > STAND.x * 0.5 + r or up < -r * 0.5 or up > h + r:
		return ""
	var k := up / h
	if k > 0.74:
		return "head"
	if k > 0.45:
		return "arm"
	return "leg"


## 0..1 effect strength for a disc hitting at `speed`; < 0 means no effect.
static func disc_hit_power(speed: float) -> float:
	if speed < DISC_HIT_MIN:
		return -1.0
	return clampf((speed - DISC_HIT_MIN) / (DISC_HIT_FULL - DISC_HIT_MIN), 0.0, 1.0)


## Hit by another runner's disc. Head: knocked down. Arm: drops the disc (or
## staggers if empty-handed). Leg: stumbles into a slide. Everything scales
## with the disc's speed. Returns false when it has no effect.
func disc_hit(zone: String, dir: Vector2, speed: float) -> bool:
	var pw := disc_hit_power(speed)
	if pw < 0.0 or state == DEAD or frozen_t > 0.0 or zone == "":
		return false
	var sx := signf(dir.x) if absf(dir.x) > 0.01 else facing
	if state == SWING or state == ZIP or state == PIVOT:
		if state == PIVOT:
			velocity = pivot_stored
		if state != PIVOT:
			_detach(false)
		state = NORMAL
	match zone:
		"head":
			if down_t > 0.0:
				return false
			charging = false
			sliding = false
			crouched = true
			_set_low(true)
			down_t = 0.5 + 0.9 * pw
			stun_t = maxf(stun_t, down_t)
			velocity = Vector2(sx * (160.0 + 340.0 * pw), -(140.0 + 220.0 * pw))
			on_floor = false
		"arm":
			charging = false
			if has_disc and disc:
				has_disc = false
				pending_late_snap = false
				var fling := Vector2(sx * (120.0 + 380.0 * pw), -(180.0 + 260.0 * pw)) + velocity * 0.5
				disc.launch(hand(), fling, throw_type, 0.15, 0.0, 0.8, 0.3)
				disc.hit_cd = 1.0   # a fumbled disc doesn't hit anyone
			else:
				stun_t = maxf(stun_t, 0.12 + 0.2 * pw)
				velocity.x += sx * (80.0 + 160.0 * pw)
		_:
			stumble_t = 0.35 + 0.65 * pw
			stun_t = maxf(stun_t, stumble_t)
			charging = false
			velocity.x = sx * maxf(absf(velocity.x) * 0.6 + 260.0 * pw, SLIDE_MIN_SPEED * 1.5)
			if not on_floor:
				velocity.y = minf(velocity.y, -120.0 * pw)
	fx.emit("disc_hit", center(), {"zone": zone, "power": pw})
	return true


func respawn(pos: Vector2) -> void:
	global_position = pos
	reset_physics_interpolation()
	prev_pos = pos
	cur_pos = pos
	velocity = Vector2.ZERO
	state = NORMAL
	anchors.clear()
	wrap_signs.clear()
	rope_ghosts.clear()
	grapple_node = null
	winds.clear()
	booster_dir = 0
	sliding = false
	crouched = false
	_set_low(false)
	has_air_jump = true
	air_pivot_ready = true
	charging = false
	on_floor = false
	frozen_t = 0.0
	stun_t = 0.0
	down_t = 0.0
	stumble_t = 0.0


## Compact state for network ghosts / replays.
func snapshot() -> Array:
	var flags := 0
	if on_floor: flags |= 1
	if sliding or crouched: flags |= 2
	if state == SWING or state == ZIP: flags |= 4
	if has_disc: flags |= 8
	if charging: flags |= 16
	if state == DEAD: flags |= 32
	if stun_t > 0.0: flags |= 128
	if frozen_t > 0.0: flags |= 256
	if down_t > 0.0: flags |= 512
	if mantle_t > 0.0: flags |= 1024
	var anchor := Vector2.ZERO
	if not anchors.is_empty():
		anchor = anchors[-1]
	return [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1),
		snappedf(velocity.x, 1), snappedf(velocity.y, 1), int(facing), flags,
		snappedf(anchor.x, 0.1), snappedf(anchor.y, 0.1)]
