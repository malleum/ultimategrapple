extends Node2D
## One local player's context inside a Level: body, disc, camera, HUD, input,
## run timer/stats and *personal* world state (gates, glass, grapple point
## states). Personal objects live on this runner's own physics layer and
## visibility layer, so in split-screen one player's disc opening a gate never
## opens it for anyone else.

const Perf = preload("res://src/core/perf.gd")

const GrapplePoint = preload("res://src/world/grapple_point.gd")
const Gate = preload("res://src/world/gate.gd")
const Glass = preload("res://src/world/glass.gd")
const Background = preload("res://src/fx/background.gd")
const Player = preload("res://src/player/player.gd")
const Disc = preload("res://src/disc/disc.gd")
const Ghost = preload("res://src/player/ghost.gd")
const Bindings = preload("res://src/core/bindings.gd")
const Overlay = preload("res://src/level/overlay.gd")
const SpeedTrail = preload("res://src/fx/speed_trail.gd")
const Hud = preload("res://src/ui/hud.gd")
const PlayerInput = preload("res://src/core/player_input.gd")
const Rumble = preload("res://src/core/rumble.gd")

const POV_TICKS := 1200   # disc cam on the results card: the last 10 s before the chains
const POV_AFTER := 100    # ... and a moment after
const RECALL_PENALTY := 3.0
const OOB_PENALTY := 2.0
const FIRST_PERSONAL_BIT := 10   # physics + visibility layer bit for runner 0

var level: Node = null
var index := 0
var inp: PlayerInput = null
var pname := "P1"
var color := Color(0.2, 1.0, 0.9)

var view: Viewport = null        # the viewport this runner is rendered into
var view_root: Node = null       # where camera / background / hud live
var container: Control = null    # split-screen container (null in single view)

var player: CharacterBody2D
var disc: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer
var overlay: Node2D
var pb_ghost: Node2D
var rival_ghost: Node2D = null   # a friend's imported run (Game.race_rival)
var speed_trail: Node2D
var pov_clip: Array = []   # per tick: [frame, disc pos, disc pose] (see _record_pov)
var pov_after := 0
var split_times: Array = []   # cumulative times at each split crossed this run (finish last)
var split_gold: Array = []    # per split: that segment was a best-ever
## PB splits this run is compared against. Kept after a new PB is saved so the
## column keeps showing what you beat (not all zeros against yourself).
var split_ref: Array = []
var last_replay: Dictionary = {}   # solo: the finished run as a replay (see _on_scored)
var zoom_override := 0.0      # photo mode / tools: fixed camera zoom
var follow_fn := Callable()   # match playback: [pos, vel] the camera follows instead
var background: Node2D

var grapple_points: Array = []
var gates: Array = []
var personal: Array = []

var time := 0.0
var penalty := 0.0
var running := false
var done := false
var deaths := 0
var lie := Vector2.ZERO
var respawn_t := -1.0
## A death holds you this long before respawning (the camera glides to the
## lie meanwhile) so you can plan the next attempt.
const RESPAWN_WAIT := 1.0
var finish_time := 0.0
var rec_frames: Array = []
var rec_tick := 0
var shake_amt := 0.0
var cam_zoom := 0.85
var cam_look := Vector2.ZERO
var input_locked := false
# replays: the seed this run's randomness came from, what the player had
# selected when it started, and where the player was each tick (sync check)
var run_seed := 0
var start_throw := 0
var start_nose := 0.0
var track := PackedVector2Array()
var replay_fix_max := 0.0


func personal_layer() -> int:
	return 1 << (FIRST_PERSONAL_BIT + index)


func setup(p_level: Node, p_index: int, p_input, p_view: Viewport, p_root: Node, p_container: Control) -> void:
	level = p_level
	index = p_index
	inp = p_input
	view = p_view
	view_root = p_root
	container = p_container
	name = "Runner%d" % index


func _ready() -> void:
	var th: Dictionary = level.th
	# ---- personal entities
	for e in level.level_data.get("entities", []):
		match str(e.get("t", "")):
			"grapple":
				var g := GrapplePoint.new()
				g.setup(e, th)
				g.level = self
				_personal(g)
				grapple_points.append(g)
			"gate":
				var gt := Gate.new()
				gt.setup(e, th)
				gt.level = self
				_personal(gt)
				gt.set_physics_layer(personal_layer())
				gates.append(gt)
			"glass":
				var gl := Glass.new()
				gl.setup(e, th)
				gl.level = self
				_personal(gl)
				gl.set_physics_layer(personal_layer())
	# ---- camera + background into this runner's view
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	view_root.add_child(camera)
	camera.make_current()
	background = Background.new()
	view_root.add_child(background)
	background.setup(th, camera)
	if container:
		_set_vis_recursive(background, personal_layer())
	# ---- actors
	pb_ghost = Ghost.new()
	add_child(pb_ghost)
	if not level.rival.is_empty():
		rival_ghost = Ghost.new()
		add_child(rival_ghost)
	disc = Disc.new()
	disc.level = level
	disc.runner = self
	disc.collision_mask = 1 | personal_layer()
	disc.set_color(th.get("disc", Color(2, 0.5, 1.5)) if index == 0 else color * 1.6)
	add_child(disc)
	disc.scored.connect(_on_scored)
	disc.impact.connect(_on_disc_impact)
	disc.out_of_bounds.connect(_on_disc_oob)
	var trail := SpeedTrail.new()
	trail.runner = self
	add_child(trail)
	speed_trail = trail
	player = Player.new()
	player.color = color
	player.level = level
	player.runner = self
	player.inp = inp
	player.disc = disc
	player.collision_mask = 1 | personal_layer()
	add_child(player)
	player.fx.connect(_on_player_fx)
	player.died.connect(_on_player_died)
	player.recalled.connect(_on_recalled)
	if container:
		var sv := view as SubViewport
		inp.mouse_world_fn = func() -> Vector2:
			if container.size.x < 1.0 or container.size.y < 1.0:
				return player.center() + Vector2(player.facing * 200.0, 0)
			var local := container.get_local_mouse_position() * (Vector2(sv.size) / container.size)
			return sv.canvas_transform.affine_inverse() * local
	overlay = Overlay.new()
	overlay.runner = self
	add_child(overlay)
	if container:
		overlay.visibility_layer = personal_layer()
	hud = Hud.new()
	hud.runner = self
	view_root.add_child(hud)


func _personal(node: CanvasItem) -> void:
	add_child(node)
	personal.append(node)
	if container:
		node.visibility_layer = personal_layer()


func _set_vis_recursive(n: Node, bits: int) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visibility_layer = bits
	for c in n.get_children():
		_set_vis_recursive(c, bits)


func th() -> Dictionary:
	return level.th


# ================================================================== flow

func restart() -> void:
	if level.mode == "replay":
		var rp: Dictionary = level.replay
		run_seed = int(rp.seed)
		player.throw_type = int(rp.throw_type)
		player.nose = float(rp.nose)
		inp.rewind()
	else:
		run_seed = randi()
	player.reset_run_state(run_seed)
	disc.seed_rng(run_seed ^ 0x5bd1e995)
	start_throw = player.throw_type
	start_nose = player.nose
	track = PackedVector2Array()
	replay_fix_max = 0.0
	if level.mode == "solo":
		inp.start_recording()
	time = 0.0
	penalty = 0.0
	running = false
	done = false
	deaths = 0
	respawn_t = -1.0
	lie = level.spawn
	rec_frames.clear()
	split_times.clear()
	split_gold.clear()
	split_ref = []
	last_replay = {}
	if level.mode == "solo":
		Game.save_splits()
	pov_clip.clear()
	pov_after = 0
	rec_tick = 0
	for r in personal:
		if is_instance_valid(r) and r.has_method("reset"):
			r.reset()
	player.respawn(level.spawn + Vector2(index * 26, 0))
	player.has_disc = true
	player.throws = 0
	player.facing = 1.0
	disc.hold()
	camera.position = player.center()
	camera.reset_physics_interpolation()
	cam_look = Vector2.ZERO
	if hud:
		hud.on_restart()
	if level.mode == "solo":
		_setup_pb_ghost()
	if not level.is_timetrial() and level.race_live:
		running = true


func _setup_pb_ghost() -> void:
	if rival_ghost:
		rival_ghost.stop()
		rival_ghost.setup_replay(level.rival.frames, level.rival.color)
		rival_ghost.visual.name_tag = str(level.rival.name)
		rival_ghost.visual.alpha = 0.6
		rival_ghost.clock = _ghost_clock
		rival_ghost.rewind()
	pb_ghost.stop()
	pb_ghost.visible = false
	if not Game.settings.get("show_ghost", true):
		return
	var frames := Game.load_ghost(level.level_id)
	if frames.size() > 2:
		pb_ghost.setup_replay(frames, Color(1, 1, 1))
		pb_ghost.clock = _ghost_clock
		pb_ghost.rewind()
		pb_ghost.visible = true


func total_time() -> float:
	return time + penalty


## Where the PB / rival ghosts are: the run clock (penalties included, so a
## recall jumps them ahead with your timer), smoothed between physics ticks.
func _ghost_clock() -> float:
	var t := total_time()
	if running and not done and not get_tree().paused:
		t += Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	return t


func lock_input(locked: bool) -> void:
	input_locked = locked
	player.input_enabled = not locked


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("runner.physics", _pt)


func _physics_process_timed(dt: float) -> void:
	if level.is_timetrial() and not done:
		# Player and disc state at the start of every tick. Playback re-simulates
		# from the recorded inputs but pins these each tick: Godot's contact
		# ordering can differ between sessions by a hair, and a run must not
		# drift. replay_fix_max tracks how far the pins actually had to move.
		if level.mode == "replay":
			_pin_to_recording(track.size() / 4)
		track.append(player.global_position)
		track.append(player.velocity)
		track.append(disc.global_position)
		track.append(disc.velocity)
	if not running and not done and not input_locked and level.is_timetrial() and _any_input():
		running = true
		if pb_ghost.visible:
			pb_ghost.start()
		if rival_ghost:
			rival_ghost.start()
	# disc cam clip; online, keep sending a moment after the chains too so the
	# others' disc cam sees it go in
	var post := done and pov_after < POV_AFTER
	if running or post:
		if done:
			pov_after += 1
		_record_pov()
	if running and not done:
		time += dt
		_record()
		if level.is_timetrial():
			_check_splits()
	if level.mode == "multi" and ((running and not done) or post):
		Net.send_state(_frame())
		if not done:
			_remote_contacts()
	if respawn_t >= 0.0:
		respawn_t -= dt
		if respawn_t < 0.0:
			_do_respawn()
	_update_lie()
	_update_camera(dt)
	if level.mode == "replay":
		# the recorded run never contains a restart; R / START re-watch it
		if Input.is_action_just_pressed("restart") and not get_tree().paused:
			level.restart()
	elif not input_locked and inp.just_pressed("restart"):
		if level.mode == "solo":
			level.restart()
		else:
			_reset_to_lie()
	elif done and level.mode == "solo" and Input.is_action_just_pressed("restart"):
		level.restart()


func _pin_to_recording(k: int) -> void:
	var rt: PackedVector2Array = level.replay.get("track", PackedVector2Array())
	if (k + 1) * 4 > rt.size():
		return
	replay_fix_max = maxf(replay_fix_max, player.global_position.distance_to(rt[k * 4]))
	replay_fix_max = maxf(replay_fix_max, disc.global_position.distance_to(rt[k * 4 + 2]))
	player.global_position = rt[k * 4]
	player.velocity = rt[k * 4 + 1]
	disc.global_position = rt[k * 4 + 2]
	disc.velocity = rt[k * 4 + 3]


## Online versus: tackles and disc clashes against the other racers' ghosts.
## Each client handles its own runner and disc, then tells the other player
## (they apply theirs on their side, see Net.net_tackle / net_clash).
func _remote_contacts() -> void:
	for id in level.remote_ghosts:
		var g = level.remote_ghosts[id]
		if not is_instance_valid(g) or g.cur.is_empty():
			continue
		if player.can_tackle() and player.tackle_reaches(g.position) and not g.is_stunned():
			var dir := signf(player.velocity.x)
			player.tackle_cd = 0.6
			Net.send_tackle(id, dir)
			on_tackle_landed(g.visual.name_tag)
		if disc.state == Disc.FLIGHT and g.disc_flying:
			var my_pos: Vector2 = disc.global_position
			var my_vel: Vector2 = disc.velocity
			var seen: Vector2 = g.disc_pos
			if disc.clash(seen, g.disc_vel):
				Net.send_clash(id, seen, my_pos, my_vel)
		if disc.can_hit_runner():
			var zone := Player.disc_hit_zone(g.position, g.is_low(), disc.global_position)
			if zone != "":
				var v: Vector2 = disc.velocity
				var at: Vector2 = disc.global_position
				disc.bounce_off_runner(g.position + Vector2(0, -22))
				if Player.disc_hit_power(v.length()) >= 0.0 and int(g.cur[5]) & (32 | 256) == 0:
					Net.send_disc_hit(id, zone, v, at)
					on_disc_hit_landed(g.visual.name_tag, zone)


func on_tackle_landed(victim: String) -> void:
	rumble("tackle_landed")
	hud.popup("TACKLE!" if victim == "" else "TACKLED %s!" % victim.to_upper(), Color(2.2, 1.6, 0.3), 1.2)
	shake(6.0)


func on_tackled_by(attacker: String, dir: float) -> void:
	if player.tackled(dir):
		hud.popup("TACKLED" if attacker == "" else "TACKLED BY %s" % attacker.to_upper(), Color(2.2, 0.5, 0.4), 1.4)
		shake(10.0)


const DISC_HIT_TEXT := {"head": ["HEADSHOT", "KNOCKED DOWN"], "arm": ["DISARMED", "DROPPED IT"], "leg": ["TRIPPED", "TRIPPED"]}


func on_disc_hit_landed(victim: String, zone: String) -> void:
	rumble("hit_landed")
	var t: String = DISC_HIT_TEXT.get(zone, ["HIT", "HIT"])[0]
	hud.popup("%s!" % t if victim == "" else "%s %s!" % [t, victim.to_upper()], Color(2.2, 1.6, 0.3), 1.2)
	shake(4.0)


## Returns whether the hit had an effect.
func on_disc_hit_by(attacker: String, zone: String, vel: Vector2) -> bool:
	if not player.disc_hit(zone, vel, vel.length()):
		return false
	var t: String = DISC_HIT_TEXT.get(zone, ["HIT", "HIT"])[1]
	hud.popup(t if attacker == "" else "%s BY %s" % [t, attacker.to_upper()], Color(2.2, 0.5, 0.4), 1.4)
	shake(12.0 if zone == "head" else 7.0)
	return true


func _any_input() -> bool:
	if inp.move.length() > 0.2:
		return true
	for a in ["jump", "grapple", "zip", "throw", "move_down", "pivot"]:
		if inp.pressed(a):
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
		target = level.basket_pos + Vector2(0, -140)
	elif follow_fn.is_valid():
		# match playback: ride along with the recorded runner being watched
		var fv: Array = follow_fn.call()
		var raw2 := Vector2(clampf(fv[1].x * 0.28, -420, 420), clampf(fv[1].y * 0.05, -60, 140))
		cam_look = cam_look.lerp(raw2, 1.0 - exp(-3.0 * dt))
		target = fv[0] + Vector2(0, -22) + cam_look
	else:
		var c: Vector2 = player.center()
		if respawn_t >= 0.0 and respawn_t < RESPAWN_WAIT - 0.3:
			c = lie + (c - player.global_position)
		var v: Vector2 = player.velocity
		# look-ahead is low-passed: feeding raw velocity in made the camera bob
		# with every jump, apex and landing
		var raw := Vector2(clampf(v.x * 0.28, -420, 420), clampf(v.y * 0.05, -60, 140))
		cam_look = cam_look.lerp(raw, 1.0 - exp(-3.0 * dt))
		var look := cam_look
		var m: Vector2 = player.mouse_world() - c
		look += m.limit_length(900.0) * 0.18
		if disc.state != Disc.HELD and disc.state != Disc.SCORED:
			var dd: Vector2 = disc.global_position - c
			if dd.length() < 1100.0:
				look += dd * 0.15
		target = c + look
	# horizontal follows briskly, vertical more softly (no jump jitter)
	camera.position.x = lerpf(camera.position.x, target.x, 1.0 - exp(-7.0 * dt))
	camera.position.y = lerpf(camera.position.y, target.y, 1.0 - exp(-4.5 * dt))
	var spd: float = player.velocity.length()
	var base := 0.86 if container == null else 0.7
	var want_zoom := lerpf(base, base * 0.84, clampf((spd - 500.0) / 900.0, 0.0, 1.0))
	cam_zoom = lerpf(cam_zoom, want_zoom, 1.0 - exp(-2.0 * dt))
	if zoom_override > 0.0:
		cam_zoom = zoom_override
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	shake_amt = maxf(0.0, shake_amt - 40.0 * dt)
	var s := shake_amt * float(Game.settings.get("screen_shake", 1.0))
	camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s))


func shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount)


# ================================================================== events

func _on_player_died() -> void:
	deaths += 1
	respawn_t = RESPAWN_WAIT
	shake(10.0)


func _do_respawn() -> void:
	player.respawn(lie)
	if not player.has_disc and disc.state != Disc.SCORED:
		player.has_disc = true
		disc.hold()
	play_sfx("respawn", lie)
	spawn_burst(player.center(), player.color * 2.0, 20)


func _reset_to_lie() -> void:
	player.respawn(lie)
	if disc.state != Disc.SCORED:
		player.has_disc = true
		disc.hold()


## Solo: penalties add to your time. Versus: you stand frozen for that long
## instead, so every runner's clock stays honest against the others.
func _penalize(seconds: float, what: String, c: Color) -> void:
	if level.is_timetrial():
		penalty += seconds
		hud.popup("%s  +%.0fs" % [what, seconds], c)
		# the ghost recording follows the clock: it stands still for the
		# penalty, so a PB ghost with a recall in it stays level with your timer
		if running and not done:
			var hold := _frame()
			for k in int(round(seconds / Ghost.REC_INTERVAL)):
				rec_frames.append(hold)
	else:
		player.freeze(seconds)
		hud.popup("%s  FROZEN %.0fs" % [what, seconds], c)


func _on_recalled() -> void:
	_penalize(RECALL_PENALTY, "RECALL", Color(2, 0.6, 0.3))


func _on_disc_oob() -> void:
	if player.has_disc:
		return
	player.has_disc = true
	disc.hold()
	_penalize(OOB_PENALTY, "OUT OF BOUNDS", Color(2, 0.4, 0.3))
	play_sfx("recall", player.center())


func on_gate(g: Node) -> void:
	var th: Dictionary = level.th
	play_sfx("gate", g.ring_pos)
	spawn_burst(g.ring_pos, th.get("basket", Color(2, 2, 0.3)), 30)
	hud.popup("GATE OPEN" if g.mode == "open" else "BRIDGE ONLINE", th.get("basket", Color(2, 2, 0.3)))
	hud.flow_event("GATE")
	shake(4.0)


func _on_scored() -> void:
	if done:
		return
	done = true
	running = false
	finish_time = total_time()
	var th: Dictionary = level.th
	level.basket.hit(1500.0)
	spawn_burst(level.basket_pos + Vector2(0, -85), th.get("basket", Color(2, 2, 0.3)), 60)
	spawn_burst(level.basket_pos + Vector2(0, -85), player.color * 2.0, 40)
	play_sfx("chains_big", level.basket_pos)
	rumble("chains")
	play_sfx("fanfare", level.basket_pos)
	shake(12.0)
	pb_ghost.stop()
	if rival_ghost:
		rival_ghost.stop()
	if split_count() > 0:
		while split_times.size() < split_count() - 1:   # finished past a split line we never crossed
			_split(finish_time)
		_split(finish_time)
	if level.mode == "solo":
		inp.stop_recording()
		var medal: String = level.medal_for(finish_time)
		var prev = Game.records.get(level.level_id)
		var old_pb: float = float(prev.time) if prev is Dictionary and prev.has("time") else -1.0
		var is_pb := Game.submit_record(level.level_id, finish_time, player.throws, medal)
		if is_pb and split_count() > 0:
			split_ref = (Game.get_splits(level.level_id, split_count()).pb as Array).duplicate()
			Game.set_pb_splits(level.level_id, split_count(), split_times)
		Game.save_splits()
		_record(true)
		last_replay = _make_replay(medal)   # kept for ★ FAVORITE on the results card, PB or not
		if is_pb:
			Game.save_ghost(level.level_id, rec_frames)
			Game.save_replay(last_replay)
		hud.show_results(finish_time, medal, is_pb, old_pb if is_pb else -1.0)
	elif level.mode == "replay":
		hud.show_results(finish_time, level.medal_for(finish_time), false)
	else:
		hud.popup("CHAINS!  " + Game.format_time(finish_time), th.get("basket", Color(2, 2, 0.3)))
	level.on_runner_finished(self)


func _make_replay(medal: String) -> Dictionary:
	var data: Dictionary = level.level_data.duplicate(true)
	data.erase("_builtin")
	return {
		"v": Game.REPLAY_VERSION,
		"level_id": level.level_id,
		"level": data,
		"name": str(data.get("name", "Course")),
		"theme": str(data.get("theme", "")),
		"time": finish_time,
		"medal": medal,
		"throws": player.throws,
		"deaths": deaths,
		"penalty": penalty,
		"player": pname,
		"color": color,
		"seed": run_seed,
		"throw_type": start_throw,
		"nose": start_nose,
		"labels": Bindings.snapshot_labels(),
		"date": int(Time.get_unix_time_from_system()),
		"input": inp.rec,
		"track": track,
		"ghost": rec_frames.duplicate(),
	}


## Controller rumble for this runner's own pad(s).
func rumble(name: String, scale := 1.0) -> void:
	if level.mode != "replay" and level.mode != "match":
		Rumble.play(inp, name, scale)


func _rumble_fx(kind: String, data) -> void:
	if level.mode == "replay" or level.mode == "match":
		return
	match kind:
		"throw":
			rumble("throw", 0.5 + 0.5 * float(data.power))
		"snap":
			Rumble.snap(inp, float(data.score))
		"catch":
			rumble("sky_catch" if data else "catch")
		"grapple_attach":
			rumble("grapple")
		"land":
			if float(data) > 900.0:
				rumble("land_hard", clampf(float(data) / 1600.0, 0.3, 1.0))
		"boost", "booster", "pivot_launch":
			rumble("pad")
		"death":
			rumble("death")
		"frozen":
			rumble("frozen")
		"tackled":
			rumble("tackled")
		"disc_hit":
			rumble("hit_" + str(data.zone), 0.5 + 0.5 * float(data.power))


func _on_disc_impact(kind: String, strength: float) -> void:
	var p: Vector2 = disc.global_position
	match kind:
		"chains":
			level.basket.hit(strength)
			play_sfx("chains", p)
		"chain_spit":
			level.basket.hit(strength)
			play_sfx("chains", p, 0.7)
			hud.popup("SPIT OUT", Color(2, 0.5, 0.3))
		"pole":
			play_sfx("pole", p)
		"skip":
			play_sfx("skip", p)
			spawn_burst(p, disc.color, 8)
			hud.popup("SKIP", disc.color, 0.6)
			hud.flow_event("SKIP")
		"wall", "ceiling":
			if strength > 200.0:
				play_sfx("disc_hit", p, clampf(strength / 1200.0, 0.3, 1.0))
		"land", "roll":
			play_sfx("disc_land", p, clampf(strength / 1200.0, 0.3, 1.0))
		"pad":
			play_sfx("pad", p)
		"runner":
			play_sfx("disc_hit", p, clampf(strength / 1100.0, 0.3, 1.0), 1.15)
		"clash":
			rumble("clash")
			play_sfx("pole", p, 1.0, 1.4)
			spawn_burst(p, Color(2.2, 2.0, 2.2), 16)
			hud.popup("CLASH!", Color(2.0, 1.8, 2.2), 0.8)


func _on_player_fx(kind: String, pos: Vector2, data) -> void:
	var th: Dictionary = level.th
	_rumble_fx(kind, data)
	match kind:
		"jump":
			play_sfx("jump", pos)
			level.spawn_dust(pos, 6)
		"walljump":
			play_sfx("walljump", pos)
			level.spawn_dust(pos + Vector2(data * 10, -20), 6)
		"land":
			play_sfx("land", pos, clampf(float(data) / 1400.0, 0.2, 1.0))
			level.spawn_dust(pos, int(clampf(float(data) / 150.0, 3, 12)))
		"frozen":
			play_sfx("recall", pos, 0.8, 0.7)
			spawn_burst(pos, Color(0.6, 1.4, 2.2), 18)
		"tackled":
			play_sfx("land", pos, 1.0, 0.8)
			spawn_burst(pos, Color(2.2, 1.6, 0.4), 22)
		"disc_hit":
			play_sfx("disc_hit", pos, 0.6 + 0.4 * float(data.power), 0.8 if data.zone == "head" else 1.0)
			spawn_burst(pos + Vector2(0, -14 if data.zone == "head" else (0 if data.zone == "arm" else 14)), Color(2.2, 1.2, 0.4), int(10 + 14 * float(data.power)))
		"mantle":
			play_sfx("land", pos, 0.45, 1.25)
			level.spawn_dust(pos, 4)
		"airjump":
			play_sfx("jump", pos, 0.9, 1.3)
			spawn_burst(pos + Vector2(0, 18), player.color * 1.6, 12, Vector2(26, 4))
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
			hud.flow_event("BOOST")
		"pivot":
			play_sfx("pivot", pos)
		"pivot_launch":
			play_sfx("boost", pos)
			spawn_burst(pos, player.color * 2.0, 14)
			hud.popup("PIVOT LAUNCH", player.color * 1.5, 0.8)
			hud.flow_event("PIVOT")
		"throw":
			var types := ["backhand", "forehand", "hammer", "roller", "scoober", "thumber"]
			play_sfx("throw", pos, 0.6 + data.power * 0.4, 0.9 + types.find(data.type) * 0.05)
		"snap":
			var sc: float = data.score
			var detail := "%.0f ms  ·  %d%%" % [data.ms, int(round(sc * 100.0))] if data.ms >= 0.0 else ""
			if data.ms >= 0.0 and data.ms < 1.0:
				detail = "FRAME PERFECT  ·  100%"
			match str(data.label):
				"PERFECT":
					play_sfx("snap_perfect", pos, 1.0, 0.94 + sc * 0.1)
					hud.snap_popup("PERFECT SNAP", Color(0.4, 2.4, 1.2), detail, sc)
					hud.flow_event("SNAP")
				"GOOD":
					play_sfx("snap_good", pos)
					hud.snap_popup("GOOD SNAP", Color(1.8, 1.8, 0.4), detail, sc)
				_:
					hud.snap_popup("NO SNAP", Color(1.4, 0.4, 0.4), detail, sc)
		"catch":
			play_sfx("catch", pos)
			if data:
				spawn_burst(pos, disc.color, 16)
				hud.popup("SKY CATCH", disc.color, 0.8)
				hud.flow_event("CATCH")
		"recall":
			play_sfx("recall", pos)
		"death":
			play_sfx("death", pos)
			spawn_burst(pos, player.color * 2.0, 30)
		"booster":
			play_sfx("booster", pos)
		"ui_tick":
			play_sfx("tick", pos, 0.4)
		"charge":
			play_sfx("charge", pos, 0.4)


func play_sfx(sfx_name: String, pos: Vector2, vol := 1.0, pitch := 1.0) -> void:
	level.play_sfx(sfx_name, pos, vol, pitch)


func spawn_burst(pos: Vector2, c: Color, amount: int, area := Vector2.ZERO) -> void:
	level.spawn_burst(pos, c, amount, area)


# ================================================================== recording / net

func _frame() -> Array:
	var f: Array = player.snapshot()
	if disc.state == Disc.FLIGHT:
		f[5] = int(f[5]) | 64    # disc airborne: others can clash with it
	var dvis := 0 if (disc.state == Disc.HELD) else 1
	var pz: Vector2 = disc.pose()
	f.append_array([snappedf(disc.global_position.x, 0.1), snappedf(disc.global_position.y, 0.1), dvis,
		snappedf(pz.x, 0.01), snappedf(pz.y, 0.01)])
	return f


## The PB splits the column compares against (see split_ref).
func split_pb() -> Array:
	if done and not split_ref.is_empty():
		return split_ref
	return Game.get_splits(level.level_id, split_count()).pb


func split_count() -> int:
	return level.split_xs.size() + 1 if not level.split_xs.is_empty() else 0


func _check_splits() -> void:
	var xs: Array = level.split_xs
	# progress is the runner, or the disc while it's out (a long throw carries
	# you through split lines too)
	var x: float = player.global_position.x
	if disc.state != Disc.HELD and disc.state != Disc.SCORED:
		x = maxf(x, disc.global_position.x)
	while split_times.size() < xs.size() and x >= float(xs[split_times.size()]):
		_split(total_time())


func _split(tm: float) -> void:
	var i := split_times.size()
	var prev: float = split_times[-1] if i > 0 else 0.0
	split_times.append(tm)
	var gold := false
	if level.mode == "solo" and tm - prev > 0.001:
		gold = Game.note_segment(level.level_id, split_count(), i, tm - prev)
	else:
		var e: Dictionary = Game.get_splits(level.level_id, split_count())
		gold = i < e.gold.size() and float(e.gold[i]) >= 0.0 and tm - prev <= float(e.gold[i]) + 0.0005
	split_gold.append(gold)
	hud.on_split(i)


func _record_pov() -> void:
	var f: Array = _frame()
	f[5] = int(f[5]) & ~8   # the disc cam draws the disc itself
	var held: bool = disc.state == Disc.HELD
	var dp: Vector2 = player.hand() if held else disc.global_position
	var pz: Vector2 = Vector2(0.0, 0.3) if held else disc.pose()
	pov_clip.append([f, dp, pz])
	if pov_clip.size() > 2 * (POV_TICKS + POV_AFTER):
		pov_clip = pov_clip.slice(-(POV_TICKS + POV_AFTER))


## The disc cam clip: up to the last 10 s before scoring plus a moment after.
## Also returns the index of the scoring tick.
func pov_frames() -> Dictionary:
	var n := mini(pov_clip.size(), POV_TICKS + pov_after)
	return {"frames": pov_clip.slice(-n), "score_at": n - pov_after}


func _record(force := false) -> void:
	rec_tick += 1
	if force or rec_tick % 4 == 0:
		rec_frames.append(_frame())
