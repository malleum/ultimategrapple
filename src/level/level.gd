extends Node2D
## A playable course: builds the world from level data and runs the game loop
## (timer, deaths, disc lie, finish, ghosts, multiplayer hooks).

const Themes = preload("res://src/core/theme_db.gd")
const Solid = preload("res://src/world/solid.gd")
const GrapplePoint = preload("res://src/world/grapple_point.gd")
const Zone = preload("res://src/world/zone.gd")
const Mover = preload("res://src/world/mover.gd")
const Gate = preload("res://src/world/gate.gd")
const Glass = preload("res://src/world/glass.gd")
const Basket = preload("res://src/world/basket.gd")
const Decor = preload("res://src/world/decor.gd")
const Background = preload("res://src/fx/background.gd")
const Player = preload("res://src/player/player.gd")
const Disc = preload("res://src/disc/disc.gd")
const Ghost = preload("res://src/player/ghost.gd")
const Overlay = preload("res://src/level/overlay.gd")
const Hud = preload("res://src/ui/hud.gd")

signal finished(time: float)

const RECALL_PENALTY := 3.0
const OOB_PENALTY := 2.0

var level_data: Dictionary = {}
var mode := "solo"
var th: Dictionary = {}

var world: Node2D
var player: CharacterBody2D
var disc: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer
var overlay: Node2D
var basket: Node2D
var pb_ghost: Node2D
var remote_ghosts := {}

var grapple_points: Array = []
var gates: Array = []
var resettables: Array = []
var basket_pos := Vector2.ZERO
var has_basket := true
var spawn := Vector2.ZERO
var kill_y := 4000.0
var medals: Dictionary = {}

var time := 0.0
var penalty := 0.0
var running := false
var done := false
var deaths := 0
var lie := Vector2.ZERO
var respawn_t := -1.0
var countdown := 0.0
var input_locked := false
var rec_frames: Array = []
var rec_tick := 0
var shake_amt := 0.0
var cam_zoom := 0.85
var level_id := ""
var finish_time := 0.0
var result_shown := false


func _ready() -> void:
	th = Themes.get_theme(level_data.get("theme", "cyber"))
	level_id = str(level_data.get("id", "custom"))
	spawn = _v(level_data.get("spawn", [0, 0]))
	basket_pos = _v(level_data.get("basket", [0, 0]))
	kill_y = float(level_data.get("kill_y", 4000))
	medals = level_data.get("medals", {})
	lie = spawn
	_build_environment()
	_build_world()
	_spawn_actors()
	hud = Hud.new()
	hud.level = self
	add_child(hud)
	Music.play_theme(level_data.get("theme", "cyber"))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	restart()
	if mode == "multi":
		input_locked = true
		player.input_enabled = false


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ================================================================== building

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = 5
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 1.0 + float(th.get("glow", 0.7))
	env.glow_strength = 1.1
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, [0.0, 1.0, 1.0, 0.8, 0.6, 0.3, 0.0][i])
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	camera = Camera2D.new()
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var bg := Background.new()
	add_child(bg)
	bg.setup(th, camera)


func _build_world() -> void:
	world = Node2D.new()
	add_child(world)
	for s in level_data.get("solids", []):
		var r: Array = s.r
		var node := Solid.new()
		node.setup(s.get("k", "ground"), Rect2(r[0], r[1], r[2], maxf(r[3], 8)), th)
		world.add_child(node)
	for p in level_data.get("polys", []):
		var pts := PackedVector2Array()
		var arr: Array = p.pts
		for i in range(0, arr.size(), 2):
			pts.append(Vector2(arr[i], arr[i + 1]))
		var node := Solid.new()
		node.setup(p.get("k", "ramp"), Rect2(), th, pts)
		world.add_child(node)
	for e in level_data.get("entities", []):
		_build_entity(e)
	if has_basket:
		basket = Basket.new()
		basket.th = th
		basket.position = basket_pos
		world.add_child(basket)


func _build_entity(e: Dictionary) -> void:
	match str(e.get("t", "")):
		"grapple":
			var g := GrapplePoint.new()
			g.setup(e, th)
			g.level = self
			world.add_child(g)
			grapple_points.append(g)
			resettables.append(g)
		"spikes", "kill", "wind", "booster", "pad", "laser", "saw":
			var z := Zone.new()
			z.setup(e, th)
			z.level = self
			world.add_child(z)
			resettables.append(z)
		"mover":
			var m := Mover.new()
			m.setup(e, th)
			world.add_child(m)
			resettables.append(m)
		"gate":
			var gt := Gate.new()
			gt.setup(e, th)
			gt.level = self
			world.add_child(gt)
			gates.append(gt)
			resettables.append(gt)
		"glass":
			var gl := Glass.new()
			gl.setup(e, th)
			gl.level = self
			world.add_child(gl)
			resettables.append(gl)
		"decor":
			var dc := Decor.new()
			dc.setup(e, th)
			world.add_child(dc)


func _spawn_actors() -> void:
	pb_ghost = Ghost.new()
	add_child(pb_ghost)
	disc = Disc.new()
	disc.level = self
	disc.set_color(th.get("disc", Color(2, 0.5, 1.5)))
	add_child(disc)
	disc.scored.connect(_on_scored)
	disc.impact.connect(_on_disc_impact)
	disc.out_of_bounds.connect(_on_disc_oob)
	player = Player.new()
	player.color = Game.player_color()
	player.level = self
	player.disc = disc
	add_child(player)
	player.fx.connect(_on_player_fx)
	player.died.connect(_on_player_died)
	player.recalled.connect(_on_recalled)
	overlay = Overlay.new()
	overlay.level = self
	add_child(overlay)


# ================================================================== flow

func restart() -> void:
	time = 0.0
	penalty = 0.0
	running = false
	done = false
	result_shown = false
	deaths = 0
	respawn_t = -1.0
	lie = spawn
	rec_frames.clear()
	rec_tick = 0
	for r in resettables:
		if is_instance_valid(r) and r.has_method("reset"):
			r.reset()
	player.respawn(spawn)
	player.has_disc = true
	player.throws = 0
	player.facing = 1.0
	disc.hold()
	camera.position = player.center()
	camera.reset_physics_interpolation()
	if hud:
		hud.on_restart()
	if mode == "solo":
		_setup_pb_ghost()
	if mode == "multi" and Net.round_active:
		running = true


func _setup_pb_ghost() -> void:
	pb_ghost.stop()
	pb_ghost.visible = false
	if not Game.settings.get("show_ghost", true):
		return
	var frames := Game.load_ghost(level_id)
	if frames.size() > 2:
		pb_ghost.setup_replay(frames, Color(1, 1, 1))
		pb_ghost.visible = true


func total_time() -> float:
	return time + penalty


func _physics_process(dt: float) -> void:
	if countdown > 0.0:
		countdown -= dt
		if countdown <= 0.0:
			_begin_race()
	if not running and not done and not input_locked and _any_input():
		running = true
		if pb_ghost.visible:
			pb_ghost.start()
	if running and not done:
		time += dt
		_record()
		if mode == "multi":
			Net.send_state(_frame())
	if respawn_t >= 0.0:
		respawn_t -= dt
		if respawn_t < 0.0:
			_do_respawn()
	_update_lie()
	_update_camera(dt)
	if not done and not input_locked and Input.is_action_just_pressed("restart"):
		if mode == "solo":
			restart()
		else:
			_multi_reset_position()
	elif done and mode == "solo" and Input.is_action_just_pressed("restart"):
		restart()


func _any_input() -> bool:
	for a in ["move_left", "move_right", "jump", "dash", "grapple", "zip", "throw", "move_down", "pivot"]:
		if Input.is_action_pressed(a):
			return true
	return false


func _update_lie() -> void:
	if player.state == Player.DEAD or not player.has_disc or not player.on_floor:
		return
	var col := player.get_last_slide_collision()
	if col and col.get_collider() is StaticBody2D and not col.get_collider().has_meta("glass") and col.get_normal().y < -0.7:
		lie = player.global_position


func _update_camera(dt: float) -> void:
	var target: Vector2
	if done:
		target = basket_pos + Vector2(0, -120)
	else:
		var c: Vector2 = player.center()
		var v: Vector2 = player.velocity
		var look := Vector2(clampf(v.x * 0.28, -420, 420), clampf(v.y * 0.12, -160, 240))
		var m := get_global_mouse_position() - c
		look += m.limit_length(900.0) * 0.18
		if disc.state != Disc.HELD and disc.state != Disc.SCORED:
			var dd: Vector2 = disc.global_position - c
			if dd.length() < 1100.0:
				look += dd * 0.15
		target = c + look
	var k := 1.0 - exp(-7.0 * dt)
	camera.position = camera.position.lerp(target, k)
	var spd: float = player.velocity.length()
	var want_zoom := lerpf(0.86, 0.72, clampf((spd - 500.0) / 900.0, 0.0, 1.0))
	cam_zoom = lerpf(cam_zoom, want_zoom, 1.0 - exp(-2.0 * dt))
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	shake_amt = maxf(0.0, shake_amt - 40.0 * dt)
	var s := shake_amt * float(Game.settings.get("screen_shake", 1.0))
	camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s))


func shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount)


# ================================================================== events

func _on_player_died() -> void:
	deaths += 1
	respawn_t = 0.35
	shake(10.0)


func _do_respawn() -> void:
	player.respawn(lie)
	if not player.has_disc and disc.state != Disc.SCORED:
		player.has_disc = true
		disc.hold()
	play_sfx("respawn", lie)
	spawn_burst(player.center(), player.color * 2.0, 20)


func _on_recalled() -> void:
	penalty += RECALL_PENALTY
	hud.popup("RECALL  +%.0fs" % RECALL_PENALTY, Color(2, 0.6, 0.3))


func _on_disc_oob() -> void:
	if player.has_disc:
		return
	penalty += OOB_PENALTY
	player.has_disc = true
	disc.hold()
	hud.popup("OUT OF BOUNDS  +%.0fs" % OOB_PENALTY, Color(2, 0.4, 0.3))
	play_sfx("recall", player.center())


func _multi_reset_position() -> void:
	player.respawn(lie)
	player.has_disc = true
	disc.hold()


func on_gate(g: Node) -> void:
	play_sfx("gate", g.ring_pos)
	spawn_burst(g.ring_pos, th.get("basket", Color(2, 2, 0.3)), 30)
	hud.popup("GATE OPEN" if g.mode == "open" else "BRIDGE ONLINE", th.get("basket", Color(2, 2, 0.3)))
	shake(4.0)


func _on_scored() -> void:
	if done:
		return
	done = true
	running = false
	finish_time = total_time()
	basket.hit(1500.0)
	spawn_burst(basket_pos + Vector2(0, -60), th.get("basket", Color(2, 2, 0.3)), 60)
	spawn_burst(basket_pos + Vector2(0, -60), player.color * 2.0, 40)
	play_sfx("chains_big", basket_pos)
	play_sfx("fanfare", basket_pos)
	shake(12.0)
	pb_ghost.stop()
	finished.emit(finish_time)
	if mode == "solo":
		var medal := medal_for(finish_time)
		var is_pb := Game.submit_record(level_id, finish_time, player.throws, medal)
		if is_pb:
			_record(true)
			Game.save_ghost(level_id, rec_frames)
		hud.show_results(finish_time, medal, is_pb)
	else:
		Net.report_finish(finish_time, player.throws)
		hud.popup("CHAINS!  " + Game.format_time(finish_time), th.get("basket", Color(2, 2, 0.3)))


func medal_for(t: float) -> String:
	for m in ["ace", "gold", "silver", "bronze"]:
		if medals.has(m) and t <= float(medals[m]):
			return m
	return ""


func _on_disc_impact(kind: String, strength: float) -> void:
	var p: Vector2 = disc.global_position
	match kind:
		"chains":
			basket.hit(strength)
			play_sfx("chains", p)
		"chain_spit":
			basket.hit(strength)
			play_sfx("chains", p, 0.7)
			hud.popup("SPIT OUT", Color(2, 0.5, 0.3))
		"pole":
			play_sfx("pole", p)
		"skip":
			play_sfx("skip", p)
			spawn_burst(p, disc.color, 8)
			hud.popup("SKIP", disc.color, 0.6)
		"wall", "ceiling":
			if strength > 200.0:
				play_sfx("disc_hit", p, clampf(strength / 1200.0, 0.3, 1.0))
		"land", "roll":
			play_sfx("disc_land", p, clampf(strength / 1200.0, 0.3, 1.0))
		"pad":
			play_sfx("pad", p)
		"glass":
			pass


func _on_player_fx(kind: String, pos: Vector2, data) -> void:
	match kind:
		"jump":
			play_sfx("jump", pos)
			spawn_dust(pos, 6)
		"walljump":
			play_sfx("walljump", pos)
			spawn_dust(pos + Vector2(data * 10, -20), 6)
		"land":
			play_sfx("land", pos, clampf(float(data) / 1400.0, 0.2, 1.0))
			spawn_dust(pos, int(clampf(float(data) / 150.0, 3, 12)))
		"dash":
			play_sfx("dash", pos)
			spawn_burst(pos, player.color * 1.6, 10)
			shake(3.0)
		"slide":
			play_sfx("slide", pos)
		"grapple_attach":
			play_sfx("grapple", pos)
			spawn_burst(pos, th.get("grapple", Color(2, 2, 0.4)), 8)
		"grapple_release":
			play_sfx("release", pos)
		"rope_wrap":
			play_sfx("tick", pos, 0.5)
		"boost":
			play_sfx("boost", pos)
			hud.popup("BOOST", th.get("basket", Color(2, 2, 0.3)), 0.6)
		"pivot":
			play_sfx("pivot", pos)
		"pivot_launch":
			play_sfx("boost", pos)
			spawn_burst(pos, player.color * 2.0, 14)
			hud.popup("PIVOT LAUNCH", player.color * 1.5, 0.8)
		"throw":
			var types := ["backhand", "forehand", "hammer", "roller", "scoober", "thumber"]
			play_sfx("throw", pos, 0.6 + data.power * 0.4, 0.9 + types.find(data.type) * 0.05)
		"snap":
			match str(data):
				"PERFECT":
					play_sfx("snap_perfect", pos)
					hud.snap_popup("PERFECT SNAP", Color(0.4, 2.4, 1.2))
				"GOOD":
					play_sfx("snap_good", pos)
					hud.snap_popup("GOOD SNAP", Color(1.8, 1.8, 0.4))
				_:
					hud.snap_popup("NO SNAP", Color(1.4, 0.4, 0.4))
		"catch":
			play_sfx("catch", pos)
			if data:
				spawn_burst(pos, disc.color, 16)
				hud.popup("SKY CATCH", disc.color, 0.8)
		"recall":
			play_sfx("recall", pos)
		"death":
			play_sfx("death", pos)
			spawn_burst(pos, player.color * 2.0, 30)
		"pad":
			pass
		"booster":
			play_sfx("booster", pos)
		"ui_tick":
			play_sfx("tick", pos, 0.4)
		"charge":
			play_sfx("charge", pos, 0.4)


# ================================================================== fx helpers

func play_sfx(name: String, pos: Vector2, vol := 1.0, pitch := 1.0) -> void:
	var d := pos.distance_to(camera.get_screen_center_position())
	var att := clampf(1.0 - (d - 700.0) / 1600.0, 0.15, 1.0)
	Sfx.play(name, vol * att, pitch)


func spawn_burst(pos: Vector2, color: Color, amount: int, area := Vector2.ZERO) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(amount, 1)
	p.lifetime = 0.6
	p.spread = 180.0
	p.initial_velocity_min = 120
	p.initial_velocity_max = 420
	p.gravity = Vector2(0, 600)
	p.damping_min = 80
	p.damping_max = 200
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	if area != Vector2.ZERO:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = area * 0.5
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func spawn_dust(pos: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(amount, 1)
	p.lifetime = 0.45
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 40
	p.initial_velocity_max = 160
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var dc: Color = th.get("edge", Color(1, 1, 1))
	p.color = Color(dc, 0.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ================================================================== recording / net

func _frame() -> Array:
	var f: Array = player.snapshot()
	var dvis := 0 if (disc.state == Disc.HELD) else 1
	f.append_array([snappedf(disc.global_position.x, 0.1), snappedf(disc.global_position.y, 0.1), dvis])
	return f


func _record(force := false) -> void:
	rec_tick += 1
	if force or rec_tick % 4 == 0:
		rec_frames.append(_frame())


## Multiplayer: called by Net when the round begins (after sync).
func start_countdown(seconds: float) -> void:
	countdown = seconds
	input_locked = true
	player.input_enabled = false
	hud.countdown_until = seconds


func _begin_race() -> void:
	input_locked = false
	player.input_enabled = true
	running = true
	time = 0.0
	play_sfx("go", player.center())


func add_remote_ghost(id: int, pname: String, color: Color) -> void:
	if remote_ghosts.has(id):
		return
	var g := Ghost.new()
	g.setup_remote(pname, color)
	add_child(g)
	remote_ghosts[id] = g


func remote_state(id: int, frame: Array) -> void:
	if remote_ghosts.has(id):
		remote_ghosts[id].push_state(frame)


func remove_remote_ghost(id: int) -> void:
	if remote_ghosts.has(id):
		remote_ghosts[id].queue_free()
		remote_ghosts.erase(id)


func pin_current() -> String:
	var path := Game.pin_level(level_data)
	hud.popup("PINNED  " + path.get_file(), Color(0.5, 2.0, 1.0), 2.0)
	return path
