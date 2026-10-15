extends SceneTree
## Battle Rush replays: random fighting on generated battle courses (every
## weapon) re-simulates exactly, and a real finish (killing the leader) saves
## the PB replay and watching it ends on the same time.
## godot --headless --fixed-fps 120 -s tools/test_battle_replay.gd

const ACTIONS := ["move_left", "move_right", "jump", "grapple", "zip", "throw", "snap", "move_down", "move_up"]
const WEAPONS := ["sword", "bow", "axe", "pike"]

var rng := RandomNumberGenerator.new()
var course := 0
var phase := ""
var lvl
var tick := 0
var aim := Vector2.ZERO
var rec_track := PackedVector2Array()
var fails := 0
var started := false
var n_ticks := 1500


func _initialize() -> void:
	rng.seed = 4242


func _game():
	return root.get_node("Game")


func _start_record() -> void:
	var G = _game()
	G.main = root
	var themes := ["field", "cyber", "canyon", "frost"]
	var data: Dictionary = G.battle_level(7700 + course, themes[course % 4], 0.5, 6, WEAPONS[course % 4])
	data["id"] = "test_battle_replay_%d" % course
	lvl = G.play_level(data)
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
		if tick % 5 == 0:
			for a in ACTIONS:
				if rng.randf() < (0.6 if a == "move_right" else (0.25 if a == "throw" else 0.1)):
					Input.action_press(a)
				else:
					Input.action_release(a)
			aim = r.player.center() + Vector2(rng.randf_range(-100, 900), rng.randf_range(-300, 150))
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
	if tick >= n_ticks:
		var track: PackedVector2Array = r.track
		var n := mini(track.size(), rec_track.size())
		var worst := 0.0
		for i in range(0, n, 2):
			worst = maxf(worst, track[i].distance_to(rec_track[i]))
		var ok: bool = worst < 0.0001 and r.replay_fix_max < 1.0 and n > 400 and lvl.is_battle()
		if not ok:
			fails += 1
		print("%s course %d (%s, %s): %d ticks, max offset %.4f px, drift fixed %.4f px, kills %d, deaths %d" % [
			"OK  " if ok else "FAIL", course, lvl.level_data.theme, lvl.battle_weapon(), n / 4, worst, r.replay_fix_max, r.kills, r.deaths])
		_game().delete_replay(lvl.level_id)
		course += 1
		if course >= 4:
			_start_e2e()
			return false
		_start_record()
	return false


# ---- end to end: kill the leader for real, watch the saved PB

const E2E_ID := "test_battle_e2e"
var e2e_attempt := 0
var e2e_t := 0
var e2e_time := 0.0


func _e2e_level() -> Dictionary:
	return {"version": 8, "id": E2E_ID, "name": "Battle Replay Test", "theme": "field", "spawn": [64, 0], "basket": [1700, 0],
		"kill_y": 3000, "bounds": [-600, -1500, 3600, 3500], "battle": {"weapon": "sword"},
		"solids": [{"r": [-500, 0, 4000, 600], "k": "ground"}], "polys": [], "route": [[64, 0], [1700, 0]], "segments": [], "sections": [],
		"medals": {"par": 6.0, "ace": 2.0, "gold": 6.0, "silver": 9.0, "bronze": 14.0},
		"entities": [
			{"t": "arena", "id": 1, "r": [500, -512, 1800, 512], "entry": [450, -512, 32, 512], "exit": [], "spawn": [350, 0], "leader": true},
			{"t": "enemy", "k": "leader", "p": [1700, 0], "x0": 1200, "x1": 2100, "a": 1, "hp": 2}]}


func _start_e2e() -> void:
	var G = _game()
	G.records.erase(E2E_ID)
	lvl = G.play_level(_e2e_level())
	lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return lvl.player.center() + Vector2(600, -4)
	phase = "e2e_rec"
	e2e_t = 0
	e2e_attempt += 1


func _e2e_tick() -> bool:
	var G = _game()
	var r = lvl.runners[0]
	e2e_t += 1
	if phase == "e2e_rec":
		if e2e_t == 2:
			Input.action_press("move_right")
		# swing now and then on the way in, then hold the line
		if e2e_t % 40 == 20:
			Input.action_press("throw")
		if e2e_t % 40 == 24:
			Input.action_release("throw")
		if r.done or e2e_t > 1400:
			Input.action_release("move_right")
			Input.action_release("throw")
			if not r.done:
				print("FAIL e2e: did not kill the leader in attempt %d (deaths %d)" % [e2e_attempt, r.deaths])
				fails += 1
				quit(1)
				return true
			e2e_time = r.finish_time
			phase = "e2e_wait"
			e2e_t = 0
		return false
	if phase == "e2e_wait":
		if e2e_t < 130:
			return false
		var rec = G.get_record(E2E_ID)
		if rec == null or not G.has_replay(E2E_ID):
			print("FAIL e2e: no PB / replay saved after killing the leader")
			fails += 1
			quit(1)
			return true
		if not G.play_replay(E2E_ID):
			print("FAIL e2e: replay would not load")
			quit(1)
			return true
		lvl = G.current_scene
		phase = "e2e_play"
		e2e_t = 0
		return false
	if phase == "e2e_play":
		if r.done or e2e_t > 2400:
			var ok: bool = r.done and absf(r.finish_time - e2e_time) < 0.0001
			if not ok:
				fails += 1
			print("%s e2e: killed the leader in %.3fs, replay finished in %.3fs (done=%s)" % ["OK  " if ok else "FAIL", e2e_time, r.finish_time, r.done])
			G.delete_replay(E2E_ID)
			G.records.erase(E2E_ID)
			print("battle replay: %d failures" % fails)
			quit(0 if fails == 0 else 1)
			return true
	return false
