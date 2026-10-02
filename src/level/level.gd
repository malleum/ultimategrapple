extends Node2D
## A playable course. Builds the shared world (terrain, hazards, movers,
## decor, basket) and hosts one Runner per local player. With several local
## players it switches to split-screen: each runner renders into its own
## SubViewport that shares this World2D.
##
## mode: "solo" (time trial, PB ghosts, medals), "multi" (online race, one
## local runner + remote ghosts), "couch" (local split-screen race).

const Perf = preload("res://src/core/perf.gd")

const Themes = preload("res://src/core/theme_db.gd")
const Solid = preload("res://src/world/solid.gd")
const Zone = preload("res://src/world/zone.gd")
const Mover = preload("res://src/world/mover.gd")
const Basket = preload("res://src/world/basket.gd")
const Decor = preload("res://src/world/decor.gd")
const Ghost = preload("res://src/player/ghost.gd")
const Runner = preload("res://src/level/runner.gd")
const PlayerInput = preload("res://src/core/player_input.gd")
const Validator = preload("res://src/level/validator.gd")
const Disc = preload("res://src/disc/disc.gd")
const View = preload("res://src/world/view.gd")
const Player = preload("res://src/player/player.gd")
const DiscCam = preload("res://src/ui/disc_cam.gd")
const MatchPlayback = preload("res://src/level/match_playback.gd")

const SPLIT_UI_BIT := 19

signal runner_finished(runner: Node)

var level_data: Dictionary = {}
var mode := "solo"
## One entry per local player: {"input": PlayerInput, "name": String, "color": Color}
var local_players: Array = []
## mode "replay": the saved run being played back (see Game.play_replay)
var replay: Dictionary = {}
var th: Dictionary = {}

var world: Node2D
var basket: Node2D
var runners: Array = []
var shared_resettables: Array = []
var remote_ghosts := {}
var split_layer: CanvasLayer = null

var basket_pos := Vector2.ZERO
var has_basket := true
var spawn := Vector2.ZERO
var kill_y := 4000.0
var medals: Dictionary = {}
var level_id := ""
var countdown := 0.0
var race_live := false


func _ready() -> void:
	Validator.repair(level_data)
	if OS.is_debug_build():
		for err in Validator.check(level_data):
			push_warning("course %s: %s" % [level_data.get("id", "?"), err])
	th = Themes.get_theme(level_data.get("theme", "cyber"))
	level_id = str(level_data.get("id", "custom"))
	spawn = _v(level_data.get("spawn", [0, 0]))
	basket_pos = _v(level_data.get("basket", [0, 0]))
	kill_y = float(level_data.get("kill_y", 4000))
	medals = level_data.get("medals", {})
	if local_players.is_empty():
		local_players = [{"input": PlayerInput.new(PlayerInput.ANY), "name": str(Game.settings.player_name), "color": Game.player_color()}]
	split_xs = _make_splits()
	_build_environment()
	_build_world()
	_build_runners()
	Music.play_theme(level_data.get("theme", "cyber"))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	restart()
	if not is_timetrial():
		for r in runners:
			r.lock_input(true)
	if mode == "match":
		match_playback = MatchPlayback.new()
		match_playback.level = self
		add_child(match_playback)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	View.reset()
	if mode == "couch" or mode == "multi":
		var rec := build_match()
		if not rec.is_empty():
			Game.save_match(rec)


# ================================================================== match recordings
# Every couch / online round is kept as a match recording: the course plus
# every runner's 30 Hz frames on the race clock (the same frames ghosts use),
# so it can be watched afterwards following any runner. Online, the others'
# frames are the ones their clients streamed to us.

var split_xs: Array = []     # x positions of the split lines (the finish is the last split)


## Split lines: the intended route cut into equal lengths, one split per two
## generator segments (3..8 splits counting the finish).
func _make_splits() -> Array:
	var route: Array = level_data.get("route", [])
	if route.size() < 2:
		return []
	var n := clampi(int(level_data.get("segments", []).size() / 2), 3, 8)
	var pts: Array = []
	for rp in route:
		pts.append(Vector2(float(rp[0]), float(rp[1])))
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total < 1.0:
		return []
	var xs: Array = []
	var acc := 0.0
	var k := 1
	var maxx: float = pts[0].x
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		while k < n and acc + seg >= total * k / n:
			var f := (total * k / n - acc) / maxf(seg, 0.001)
			var x: float = lerpf(pts[i - 1].x, pts[i].x, f)
			maxx = maxf(maxx, x)
			xs.append(maxx)
			k += 1
		acc += seg
	return xs


var rival := {}              # solo: a friend's run raced as a ghost {frames, name, time, color}
var wind_zones: Array = []   # Zone nodes of kind "wind" (for the aim readout)


## Sum of the wind forces at a world point.
func wind_at(p: Vector2) -> Vector2:
	var w := Vector2.ZERO
	for z in wind_zones:
		if z.rect.has_point(p):
			w += z.force
	return w


var race_start_ms := -1
var net_results := {}       # online: peer id -> finish time (from the server)
var match_playback: Node = null


func build_match() -> Dictionary:
	if race_start_ms < 0:
		return {}
	var rs: Array = []
	for r in runners:
		var t := -1.0
		if r.done:
			t = r.finish_time
		rs.append({"name": r.pname, "color": r.player.visual.color, "frames": r.rec_frames.duplicate(), "time": t, "throws": r.player.throws})
	if mode == "multi":
		var t0 := race_start_ms / 1000.0
		for id in remote_ghosts:
			var g = remote_ghosts[id]
			if not is_instance_valid(g):
				continue
			rs.append({"name": g.visual.name_tag, "color": g.visual.color, "frames": g.match_frames(t0),
				"time": float(net_results.get(id, -1.0)), "throws": 0})
	var longest := 0
	for e in rs:
		longest = maxi(longest, e.frames.size())
	if longest < 30:
		return {}
	var winner := ""
	var best := INF
	for e in rs:
		if float(e.time) >= 0.0 and float(e.time) < best:
			best = float(e.time)
			winner = str(e.name)
	return {"kind": "match", "mode": "online" if mode == "multi" else "couch", "level": level_data,
		"name": str(level_data.get("name", "Course")), "theme": str(level_data.get("theme", "")),
		"date": int(Time.get_unix_time_from_system()), "runners": rs, "winner": winner, "countdown": 3.0}


func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Back-compat helpers for single-runner code paths (tests, net, menus).
var player: CharacterBody2D:
	get: return runners[0].player if not runners.is_empty() else null
var disc: CharacterBody2D:
	get: return runners[0].disc if not runners.is_empty() else null
var hud: CanvasLayer:
	get: return runners[0].hud if not runners.is_empty() else null
var camera: Camera2D:
	get: return runners[0].camera if not runners.is_empty() else null
var done: bool:
	get: return runners.all(func(r): return r.done) if not runners.is_empty() else false
var grapple_points: Array:
	get: return runners[0].grapple_points if not runners.is_empty() else []


# ================================================================== building

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = 5
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = (1.0 + float(th.get("glow", 0.7))) * 0.85
	env.glow_strength = 1.1
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = float(th.get("glow_threshold", 1.0))
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, [0.0, 1.0, 1.0, 0.8, 0.6, 0.3, 0.0][i])
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)


func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
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
		match str(e.get("t", "")):
			"spikes", "kill", "wind", "booster", "pad", "laser", "saw":
				var z := Zone.new()
				z.setup(e, th)
				z.level = self
				world.add_child(z)
				shared_resettables.append(z)
				if z.kind == "wind":
					wind_zones.append(z)
			"mover":
				var m := Mover.new()
				m.setup(e, th)
				world.add_child(m)
				shared_resettables.append(m)
			"decor", "sign":
				if e.t == "sign":
					e = e.duplicate()
					e["k"] = "sign"
				var dc := Decor.new()
				dc.setup(e, th)
				world.add_child(dc)
			# grapple / gate / glass are personal: built per runner
	if has_basket:
		basket = Basket.new()
		basket.th = th
		basket.position = basket_pos
		world.add_child(basket)


func _build_runners() -> void:
	var n := local_players.size()
	if n <= 1:
		var r := Runner.new()
		var lp: Dictionary = local_players[0]
		r.pname = lp.get("name", "P1")
		r.color = lp.get("color", Game.player_color())
		r.setup(self, 0, lp.input, get_viewport(), self, null)
		add_child(r)
		runners.append(r)
		return
	# split-screen: one SubViewport per player sharing this World2D
	split_layer = CanvasLayer.new()
	split_layer.layer = -50
	add_child(split_layer)
	var grid := GridContainer.new()
	grid.columns = 1 if n == 2 else 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.visibility_layer = 1 << SPLIT_UI_BIT
	split_layer.add_child(grid)
	get_viewport().canvas_cull_mask = 1 << SPLIT_UI_BIT
	for i in n:
		var lp: Dictionary = local_players[i]
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cont.visibility_layer = 1 << SPLIT_UI_BIT
		grid.add_child(cont)
		var sv := SubViewport.new()
		sv.world_2d = get_viewport().world_2d
		sv.use_hdr_2d = true
		sv.physics_object_picking = false
		sv.handle_input_locally = false
		sv.canvas_cull_mask = 1 | (1 << (Runner.FIRST_PERSONAL_BIT + i)) | (1 << DiscCam.RUNNER_BIT)
		sv.audio_listener_enable_2d = false
		cont.add_child(sv)
		var r := Runner.new()
		r.pname = lp.get("name", "P%d" % (i + 1))
		r.color = lp.get("color", Game.player_palette(i))
		r.setup(self, i, lp.input, sv, sv, cont)
		add_child(r)
		runners.append(r)


# ================================================================== flow

## Solo time trial, or a replay of one (same rules, same reset).
func is_timetrial() -> bool:
	return mode == "solo" or mode == "replay"


func restart() -> void:
	if is_timetrial():
		for s in shared_resettables:
			if is_instance_valid(s) and s.has_method("reset"):
				s.reset()
	for r in runners:
		r.restart()


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("level.physics", _pt)


## What the cameras see (plus a margin), for View.sees() in world props.
func update_view() -> void:
	var r := Rect2()
	var first := true
	for rn in runners:
		if not is_instance_valid(rn) or rn.camera == null:
			continue
		var vp_size: Vector2 = rn.camera.get_viewport_rect().size
		var half: Vector2 = vp_size * 0.5 / rn.camera.zoom
		var c: Vector2 = rn.camera.get_screen_center_position()
		var cr := Rect2(c - half, half * 2.0)
		r = cr if first else r.merge(cr)
		first = false
	if first:
		View.reset()
	else:
		View.rect = r.grow(View.MARGIN)


func _physics_process_timed(dt: float) -> void:
	update_view()
	if countdown > 0.0:
		countdown -= dt
		if countdown <= 0.0:
			_begin_race()
	if mode == "couch" and runners.size() > 1:
		_local_contacts()


## Couch versus: slide tackles between runners, and discs colliding in the
## air (each applies its half from the other's pre-hit state).
func _local_contacts() -> void:
	for i in runners.size():
		for j in runners.size():
			if i == j:
				continue
			var a = runners[i]
			var b = runners[j]
			if a.player.can_tackle() and a.player.tackle_reaches(b.player.global_position):
				var dir := signf(a.player.velocity.x)
				a.player.tackle_cd = 0.6
				if b.player.stun_t <= 0.0:
					a.on_tackle_landed(b.pname)
					b.on_tackled_by(a.pname, dir)
			_local_disc_hit(a, b)
			if j > i:
				var da = a.disc
				var db = b.disc
				if da.state == Disc.FLIGHT and db.state == Disc.FLIGHT:
					var pa: Vector2 = da.global_position
					var va: Vector2 = da.velocity
					var pb: Vector2 = db.global_position
					var vb: Vector2 = db.velocity
					if pa.distance_to(pb) < Disc.CLASH_RADIUS:
						da.clash(pb, vb)
						db.clash(pa, va)


## Couch versus: runner a's disc in flight hitting runner b.
func _local_disc_hit(a, b) -> void:
	var d = a.disc
	if not d.can_hit_runner() or b.player.state == Player.DEAD:
		return
	var zone := Player.disc_hit_zone(b.player.global_position, b.player.sliding or b.player.crouched, d.global_position)
	if zone == "":
		return
	var v: Vector2 = d.velocity
	d.bounce_off_runner(b.player.center())
	if b.on_disc_hit_by(a.pname, zone, v):
		a.on_disc_hit_landed(b.pname, zone)


func medal_for(t: float) -> String:
	for m in ["ace", "gold", "silver", "bronze"]:
		if medals.has(m) and t <= float(medals[m]):
			return m
	return ""


func par_time() -> float:
	return float(medals.get("par", medals.get("gold", 0.0)))


func on_runner_finished(r: Node) -> void:
	runner_finished.emit(r)
	if mode == "multi":
		# someone else already won the round: show us our own throw instead
		if Net.round_winner != -1 and Net.round_winner != Net.my_id():
			show_round_cam(r.pov_frames, r.player.visual.color, r.disc.color, "YOUR THROW")
		Net.report_finish(r.finish_time, r.player.throws)
	elif mode == "couch":
		Game.couch_runner_finished(r.index, r.finish_time)


# ================================================================== disc cam (versus)

var round_cam: Control = null
var _cam_layer: CanvasLayer = null


## Show a disc cam in the corner once the clip has its moment after the
## chains. `clip_fn` is called then and returns a DiscCam clip.
func show_round_cam(clip_fn: Callable, color: Color, disc_color: Color, title: String) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	var clip: Dictionary = clip_fn.call()
	if clip.frames.size() < 60:
		return
	if round_cam and is_instance_valid(round_cam):
		round_cam.queue_free()
	if _cam_layer == null:
		_cam_layer = CanvasLayer.new()
		_cam_layer.layer = 40
		add_child(_cam_layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.015, 0.06, 0.88)
	sb.border_color = Color(1.0, 0.8, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var cam := DiscCam.new()
	panel.add_child(cam)
	cam.setup(self, clip, color, disc_color, title, true)
	_cam_layer.add_child(panel)
	# bottom right, above the control hints; never takes the mouse
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	panel.position.y -= 70.0
	_ui_only(panel)
	round_cam = panel
	var tw := create_tween().bind_node(panel)
	panel.modulate.a = 0.0
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)


## The corner cam: drawn by every game view (couch views only draw some
## layers) and transparent to the mouse. Stops at the cam's own viewport.
func _ui_only(n: Node) -> void:
	if n is SubViewport:
		return
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if split_layer:
			(n as Control).visibility_layer = 1 | (1 << SPLIT_UI_BIT)
	for c in n.get_children():
		_ui_only(c)


## Couch: the round winner's throw, for everyone.
func show_couch_winner_cam(index: int) -> void:
	var r = runners[index]
	show_round_cam(r.pov_frames, r.player.visual.color, r.disc.color, "%s SANK IT" % r.pname.to_upper())


## Online: the round winner's throw. Ours if we won, else rebuilt from the
## frames their client sent us.
func show_net_winner_cam(id: int, pname: String) -> void:
	if id == Net.my_id():
		var r = runners[0]
		show_round_cam(r.pov_frames, r.player.visual.color, r.disc.color, "YOUR THROW")
		return
	var g = remote_ghosts.get(id)
	if g == null:
		return
	var score_t := Time.get_ticks_msec() / 1000.0
	var clip_fn := func() -> Dictionary:
		if not is_instance_valid(g):
			return {"frames": [], "score_at": 0}
		return g.pov_clip(score_t, Time.get_ticks_msec() / 1000.0)
	show_round_cam(clip_fn, g.visual.color, g.disc_color, "%s SANK IT" % pname.to_upper())


## Race modes: freeze everyone, count down, then release together.
func start_countdown(seconds: float) -> void:
	countdown = seconds
	race_live = false
	for r in runners:
		r.lock_input(true)
		r.hud.countdown_until = seconds


func _begin_race() -> void:
	race_live = true
	race_start_ms = Time.get_ticks_msec()
	for r in runners:
		if mode != "match":
			r.lock_input(false)
		r.running = true
		r.time = 0.0
	play_sfx("go", spawn)
	if match_playback:
		match_playback.start()


func couch_popup(text: String, c: Color, dur := 2.5) -> void:
	for r in runners:
		r.hud.popup(text, c, dur)


# ================================================================== online ghosts

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
	for r in runners:
		r.hud.popup("PINNED  " + path.get_file(), Color(0.5, 2.0, 1.0), 2.0)
	return path


# ================================================================== fx helpers

func play_sfx(sfx_name: String, pos: Vector2, vol := 1.0, pitch := 1.0) -> void:
	var d := INF
	for r in runners:
		if r.camera:
			d = minf(d, pos.distance_to(r.camera.get_screen_center_position()))
	if d == INF:
		d = 0.0
	var att := clampf(1.0 - (d - 700.0) / 1600.0, 0.15, 1.0)
	Sfx.play(sfx_name, vol * att, pitch)


func spawn_burst(pos: Vector2, color: Color, amount: int, area := Vector2.ZERO) -> void:
	if Perf.on:
		Perf.end("burst x" + str(amount), Perf.begin())   # count only
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
