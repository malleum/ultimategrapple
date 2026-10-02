extends SceneTree
## Replay determinism: plays several courses with random inputs (keys + mouse
## aim, including throws with snaps), saves the run as a replay through the
## normal save/load path, plays it back and compares the player's position
## on every tick. Any drift is a bug.
## godot --headless --fixed-fps 120 -s tools/test_replay.gd -- [courses] [ticks]

const ACTIONS := ["move_left", "move_right", "jump", "dash", "grapple", "zip", "throw", "snap", "pivot", "move_down", "move_up", "throw_next", "recall"]

var rng := RandomNumberGenerator.new()
var n_courses := 4
var n_ticks := 1500
var course := 0
var phase := ""          # "rec" | "play"
var lvl
var tick := 0
var aim := Vector2.ZERO
var rec_track := PackedVector2Array()
var fails := 0
var started := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0 and a[0].is_valid_int(): n_courses = int(a[0])
	if a.size() > 1 and a[1].is_valid_int(): n_ticks = int(a[1])
	rng.seed = 777


func _game():
	return root.get_node("Game")


func _start_record() -> void:
	var G = _game()
	G.main = root
	var themes := ["field", "cyber", "canyon", "frost", "fantasy", "heaven", "foundry"]
	var data: Dictionary = G.generate_level(9100 + course, themes[course % 7], 0.4 + 0.1 * (course % 5), 8)
	data["id"] = "test_replay_%d" % course
	lvl = G.play_level(data)
	var p = lvl.player
	p.throw_type = course % 6
	lvl.restart()
	lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
	phase = "rec"
	tick = 0


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_start_record()
		return false
	if phase.begins_with("e2e"):
		return _e2e_tick()
	tick += 1
	var r = lvl.runners[0]
	if phase == "rec":
		if tick % 7 == 0:
			for a in ACTIONS:
				if rng.randf() < (0.55 if a == "move_right" else 0.13):
					Input.action_press(a)
				else:
					Input.action_release(a)
			aim = r.player.center() + Vector2(rng.randf_range(-300, 900), rng.randf_range(-500, 250))
		if tick >= n_ticks:
			for a in ACTIONS:
				Input.action_release(a)
			rec_track = r.track.duplicate()
			var G = _game()
			G.save_replay(r._make_replay(""))
			if not G.play_replay(lvl.level_id):
				print("FAIL could not load replay")
				quit(1)
				return true
			lvl = G.current_scene
			phase = "play"
			tick = 0
		return false
	# playback: compare where the runner is each tick with the recording.
	# Playback pins player + disc to the recording each tick; replay_fix_max is
	# how far it had to (natural re-simulation drift, should be ~0).
	if tick >= n_ticks:
		var track: PackedVector2Array = r.track
		var n := mini(track.size(), rec_track.size())
		var worst := 0.0
		for i in range(0, n, 2):
			worst = maxf(worst, track[i].distance_to(rec_track[i]))
		var ok: bool = worst < 0.0001 and r.replay_fix_max < 1.0 and n > 400
		if not ok:
			fails += 1
		print("%s course %d (%s): %d ticks, max offset %.4f px, re-sim drift fixed %.4f px, throws %d, deaths %d" % [
			"OK  " if ok else "FAIL", course, lvl.level_data.theme, n / 4, worst, r.replay_fix_max, r.player.throws, r.deaths])
		_game().save_ghost(lvl.level_id, [])
		_game().delete_replay(lvl.level_id)
		course += 1
		if course >= n_courses:
			print("replay: %d/%d courses identical" % [n_courses - fails, n_courses])
			_start_e2e()
			return false
		_start_record()
	return false


# ---- end to end: a real finish saves the PB replay, watching it finishes the same

const E2E_ID := "test_replay_e2e"
var e2e_attempt := 0
var e2e_t := 0
var e2e_time := 0.0


func _e2e_level() -> Dictionary:
	return {"version": 2, "id": E2E_ID, "name": "Replay Test", "theme": "field", "seed": 1, "difficulty": 0.1,
		"spawn": [64, 0], "basket": [520, 0], "kill_y": 3000, "bounds": [-600, -1500, 2600, 3500],
		"solids": [{"r": [-500, 0, 2000, 600], "k": "ground"}], "polys": [], "entities": [],
		"route": [[64, 0], [520, 0]], "segments": [], "sections": [],
		"medals": {"par": 6.0, "ace": 2.0, "gold": 6.0, "silver": 9.0, "bronze": 14.0}}


func _start_e2e() -> void:
	var G = _game()
	G.records.erase(E2E_ID)
	lvl = G.play_level(_e2e_level())
	lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
	phase = "e2e_rec"
	e2e_t = 0


func _e2e_tick() -> bool:
	var G = _game()
	var r = lvl.runners[0]
	e2e_t += 1
	if phase == "e2e_rec":
		# a few charge lengths and aim heights until one goes in the chains
		var hold := 4 + (e2e_attempt % 6) * 3
		var lift := -40.0 - (e2e_attempt / 6) * 25.0
		aim = Vector2(520, -80 + lift)
		if e2e_t == 6:
			Input.action_press("throw")
		elif e2e_t == 6 + hold:
			Input.action_release("throw")
		if r.done:
			e2e_time = r.finish_time
			if not G.has_replay(E2E_ID):
				print("FAIL e2e: finished but no replay saved")
				quit(1)
				return true
			G.play_replay(E2E_ID)
			lvl = G.current_scene
			phase = "e2e_play"
			e2e_t = 0
		elif e2e_t > 300:
			e2e_attempt += 1
			if e2e_attempt > 40:
				print("FAIL e2e: could not score a test throw")
				quit(1)
				return true
			lvl.restart()
			e2e_t = 0
		return false
	if r.done or e2e_t > 900:
		var ok: bool = r.done and absf(r.finish_time - e2e_time) < 0.0001
		print("%s e2e: PB %.3fs saved as a replay (attempt %d); watching it finished %s at %.3fs, keys shown: %s" % [
			"OK  " if ok else "FAIL", e2e_time, e2e_attempt + 1, "too" if r.done else "NOT", r.finish_time, str(lvl.replay.labels.kbm.throw)])
		if not OS.get_cmdline_user_args().has("--keep"):
			G.delete_replay(E2E_ID)
		G.save_ghost(E2E_ID, [])
		quit(0 if ok and fails == 0 else 1)
		return true
	return false
