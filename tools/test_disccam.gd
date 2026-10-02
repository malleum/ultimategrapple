extends SceneTree
## Results card disc cam: score a throw on a flat course, then check the clip,
## the lock-to-disc view (world turns to keep the disc level) and that the
## live runner gets its layers back on restart.
## godot --headless --fixed-fps 120 -s tools/test_disccam.gd -- [throw_type] [--attempt n] [--shot out_prefix]
## (with --shot it needs a display, e.g. xvfb-run, and saves a few frames)

var DiscCam   # loaded at runtime: it uses the Game autoload
const ID := "test_disccam"

var lvl
var f := 0
var attempt := 0
var phase := "throw"
var aim := Vector2.ZERO
var cam
var fails := 0
var started := false
var throw_type := 0
var shot := ""
var lock_was := true
var shots_done := 0
var max_dev := 0.0
var flipped_seen := false
var shot_rot := 0.0
var shot_flip := 1.0
var shot_chains := false


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-10s %s" % ["OK  " if ok else "FAIL", name, detail])


func _bx() -> float:
	return 900.0 if throw_type == 0 else 560.0


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Disc Cam", "theme": "field", "seed": 1, "difficulty": 0.1,
		"spawn": [64, 0], "basket": [_bx(), 0], "kill_y": 3000, "bounds": [-900, -2500, 3600, 4500],
		"solids": [{"r": [-800, 0, 3400, 600], "k": "ground"}], "polys": [], "entities": [],
		"route": [[64, 0], [_bx(), 0]], "segments": [], "sections": [],
		"medals": {"par": 6.0, "ace": 2.0, "gold": 6.0, "silver": 9.0, "bronze": 14.0}}


func _game():
	return root.get_node("Game")


func _start() -> void:
	var G = _game()
	G.main = root
	G.records.erase(ID)
	lvl = G.play_level(_level())
	lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
	lvl.player.throw_type = throw_type
	f = 0


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		DiscCam = load("res://src/ui/disc_cam.gd")
		var a := OS.get_cmdline_user_args()
		if a.size() > 0 and a[0].is_valid_int():
			throw_type = int(a[0])
		var ai := a.find("--attempt")
		if ai >= 0 and ai + 1 < a.size():
			attempt = int(a[ai + 1])
		var si := a.find("--shot")
		if si >= 0 and si + 1 < a.size():
			shot = a[si + 1]
		lock_was = bool(_game().settings.get("disc_cam_lock", true))
		_game().settings["disc_cam_lock"] = true
		_start()
		return false
	f += 1
	var r = lvl.runners[0]
	match phase:
		"throw":
			# run left and back first so the clip has some carrying in it
			if f == 2:
				Input.action_press("move_left")
			if f == 60:
				Input.action_release("move_left")
				Input.action_press("move_right")
			if f == 110:
				Input.action_release("move_right")
			var hold := 20 + (attempt % 10) * 6
			var lift := -40.0 - (attempt / 10) * 40.0
			aim = Vector2(_bx(), -120 + lift)
			if f == 130:
				Input.action_press("throw")
			elif f == 130 + hold:
				Input.action_release("throw")
			if r.done:
				phase = "results"
				f = 0
			elif f > 520:
				if OS.get_environment("DBG") != "":
					print("attempt %d: from %s disc ended %s state %d" % [attempt, r.player.global_position, r.disc.global_position, r.disc.state])
				attempt += 1
				if attempt > 60:
					print("FAIL could not score a test throw")
					quit(1)
					return true
				lvl.restart()
				f = 0
		"results":
			if f == 200:
				cam = _find_cam(lvl)
				if cam == null:
					_check("card", false, "no disc cam on the results card")
					return _finish()
				var main_vp = r.player.get_viewport()
				_check("clip", cam.frames.size() > 200 and cam.score_at > 100 and cam.score_at < cam.frames.size(),
					"%d frames, chains at frame %d (attempt %d)" % [cam.frames.size(), cam.score_at, attempt + 1])
				_check("layers", r.player.visibility_layer == 1 << DiscCam.RUNNER_BIT and main_vp.canvas_cull_mask & (1 << DiscCam.CAM_BIT) == 0
					and cam.sv.canvas_cull_mask & (1 << DiscCam.RUNNER_BIT) == 0,
					"live runner hidden from the cam, cam puppet hidden from the main view")
				phase = "watch"
				f = 0
		"watch":
			# lock on: wherever the disc flies, the disc is drawn level on screen
			if cam.t > 2.0 and cam.t < cam.frames.size() - 2 and cam.hold_t == 0.0:
				var xf: Transform2D = cam.sv.canvas_transform
				var on_screen: float = (xf * Vector2.RIGHT.rotated(cam.disc_draw.ang) - xf * Vector2.ZERO).angle()
				var settled: bool = absf(angle_difference(cam.cam_rot, cam.disc_draw.ang)) < 0.05
				if settled and absf(cam.flip) > 0.99:
					var dev := absf(angle_difference(on_screen, 0.0 if cam.flip > 0.0 else 0.0))
					if cam.flip < 0.0:
						dev = minf(dev, absf(angle_difference(on_screen, PI)))
					max_dev = maxf(max_dev, dev)
				if cam.flip < -0.9:
					flipped_seen = true
			# shots: whenever the view has turned well away from the last shot
			# (or flipped over), plus one in the chains
			var in_flight: bool = int(cam.t) < cam.frames.size() and (cam.frames[int(cam.t)][0] as Array)[10] != 0
			var turned: bool = absf(angle_difference(cam.cam_rot, float(shot_rot))) > 0.45 or signf(cam.flip) != signf(shot_flip)
			var chains: bool = cam.t >= cam.score_at + 20 and not shot_chains
			if shot != "" and shots_done < 8 and cam.hold_t == 0.0 and ((in_flight and turned) or chains):
				shot_rot = cam.cam_rot
				shot_flip = cam.flip
				shot_chains = shot_chains or chains
				if true:
					var img := root.get_viewport().get_texture().get_image()
					var path := "%s_%d.png" % [shot, shots_done]
					img.save_png(path)
					print("saved %s  t=%d rot=%.2f flip=%.2f" % [path, int(cam.t), cam.cam_rot, cam.flip])
					shots_done += 1
			if cam.hold_t > 0.5:
				_check("lock", max_dev < 0.06, "disc drawn within %.3f rad of level for the whole clip%s" % [max_dev, " (saw it upside down)" if flipped_seen else ""])
				cam._toggle_lock()
				_check("setting", _game().settings.disc_cam_lock == false and cam.lock_btn.text.ends_with("OFF"), "toggle saved: disc_cam_lock=%s" % _game().settings.disc_cam_lock)
				phase = "unlocked"
				f = 0
		"unlocked":
			if f == 240:
				var rot: float = cam.sv.canvas_transform.get_rotation()
				_check("unlocked", absf(rot) < 0.02 and cam.flip > 0.99, "world upright with lock off (rot %.3f, flip %.2f)" % [rot, cam.flip])
				lvl.restart()
				phase = "restarted"
				f = 0
		"restarted":
			if f == 10:
				var main_vp2 = r.player.get_viewport()
				_check("restore", r.player.visibility_layer == 1 and r.disc.visibility_layer == 1 and main_vp2.canvas_cull_mask & (1 << DiscCam.CAM_BIT) != 0,
					"restart gives the runner its layers back")
				return _finish()
	return false


func _finish() -> bool:
	var G = _game()
	G.settings["disc_cam_lock"] = lock_was
	G.save_settings()
	G.records.erase(ID)
	G.save_ghost(ID, [])
	G.delete_replay(ID)
	print("disccam: %d failures" % fails)
	quit(0 if fails == 0 else 1)
	return true


func _find_cam(n: Node):
	if n.get_script() == DiscCam:
		return n
	for c in n.get_children():
		var x = _find_cam(c)
		if x:
			return x
	return null
