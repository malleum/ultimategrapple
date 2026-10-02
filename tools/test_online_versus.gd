extends SceneTree
## Online versus contacts through a real dedicated server: A slide-tackles B
## (B must get stunned on its own client), then both throw at each other and
## the discs must clash (each client's own disc gets knocked), then A hits B
## in the head with a throw (B must get knocked down on its own client), then
## A sinks it and both clients show A's disc cam; leaving the round saves it
## as a match recording with both runners' paths.
##   godot4 --headless --path . -- --server --port=24699 &
##   godot4 --headless -s tools/test_online_versus.gd -- localhost:24699 A &
##   godot4 --headless -s tools/test_online_versus.gd -- localhost:24699 B
## A and B must join in that order (A leads the lobby and starts the round).

var net
var t := 0.0
var name_ := "A"
var asked := false
var started := false
var race_t := -1.0
var res := {}
var final := {}      # result line waiting on the match recording check


func _physics_process(dt: float) -> bool:
	var game = root.get_node("Game")
	if not started:
		started = true
		game.main = root
		var args := OS.get_cmdline_user_args()
		name_ = args[1] if args.size() > 1 else "A"
		game.settings.player_name = name_
		net = root.get_node("Net")
		net.join(args[0])
		return false
	t += dt
	if not final.is_empty():
		# the round was left: it must be saved as a match with both runners
		final["n"] = int(final.n) + 1
		if int(final.n) == (3 if name_ == "A" else 30):
			# both test clients share one user:// folder: find ours (local runner first)
			var rec: Dictionary = {}
			# (and its index, which they both rewrite at once): scan the files
			for fn in DirAccess.get_files_at(game.MATCH_DIR):
				var r2: Dictionary = game.load_match(fn.get_basename())
				if not r2.is_empty() and str(r2.runners[0].name) == name_:
					rec = r2
					break
			var rs: Array = rec.get("runners", [])
			var other := 0
			for e in rs:
				if str(e.name) != name_:
					other = e.frames.size()
			var m_ok: bool = rs.size() == 2 and other > 150 and str(rec.get("winner", "")) == "A"
			if not rec.is_empty():
				game.delete_match(str(rec.id))
			var ok2: bool = final.ok and m_ok
			print("%s %s: %s; match saved with %d runners (other's path %d frames), winner %s" % [name_, "OK" if ok2 else "FAIL", final.detail, rs.size(), other, rec.get("winner", "-")])
			quit(0 if ok2 else 1)
			return true
		return false
	if t > 40.0:
		print("%s FAIL: timed out (%s)" % [name_, res])
		quit(1)
		return true
	if net.in_lobby and net.players.size() >= 2 and not asked and t > 1.0:
		asked = true
		if net.is_leader():
			net.request_start()
	var lvl = game.current_scene
	if lvl == null or not lvl.has_method("remote_state"):
		return false
	var r = lvl.runners[0]
	var p = r.player
	var spawn := Vector2(lvl.level_data.spawn[0], lvl.level_data.spawn[1])
	if race_t < 0.0:
		if lvl.countdown <= 0.0 and not r.input_locked and lvl.remote_ghosts.size() > 0:
			race_t = 0.0
		return false
	race_t += dt
	# ---- tackle: B stands on the spawn, A slides in from the left
	if name_ == "A":
		if race_t > 0.5 and not res.has("slid"):
			res["slid"] = true
			p.respawn(spawn + Vector2(-90, 0))
			p.velocity.x = 650.0
			Input.action_press("move_right")
			Input.action_press("move_down")
		if race_t > 1.5 and race_t < 1.6:
			Input.action_release("move_right")
			Input.action_release("move_down")
			p.respawn(spawn)
		if p.tackle_cd > 0.0 and not res.has("tackle"):
			res["tackle"] = race_t
	else:
		if not res.has("placed"):
			res["placed"] = true
			p.respawn(spawn)
		if race_t < 3.0:
			res["stun"] = maxf(float(res.get("stun", 0.0)), p.stun_t)
	# ---- clash: discs meet above the spawn
	var side := -1.0 if name_ == "A" else 1.0
	if race_t > 3.0 and not res.has("thrown"):
		res["thrown"] = true
		p.has_disc = false
		r.disc.launch(spawn + Vector2(side * 350.0, -700.0), Vector2(-side * 700.0, 0.0), 0, 1.0, 0.0, 0.0)
		res["spin"] = r.disc.spin
	# each client sees the other's disc a little late, so the hit is rarely
	# head-on; what must hold is that both discs got hit (spin knocked off)
	if res.has("thrown") and not res.has("hit") and r.disc.spin < float(res.spin) * 0.7:
		res["hit"] = race_t
	# ---- disc to the head: B back on the spawn, A throws at head height
	if name_ == "B" and race_t > 5.0 and not res.has("back"):
		res["back"] = true
		p.respawn(spawn)
	if name_ == "B":
		res["down"] = maxf(float(res.get("down", 0.0)), p.down_t)
	if name_ == "A" and race_t > 5.6 and not res.has("shot"):
		res["shot"] = true
		p.respawn(spawn + Vector2(-400, 0))
		r.disc.launch(spawn + Vector2(-150, -42), Vector2(1000, 0), 0, 1.0, 0.0, 0.0)
	# ---- A sinks it: both clients show A's disc cam (B's rebuilt from A's frames)
	if name_ == "A" and race_t > 6.5 and not res.has("scored"):
		res["scored"] = true
		r._on_scored()
	if race_t > 8.5 and not res.has("cam"):
		var rc = lvl.round_cam
		var cam = rc.get_child(0) if rc and is_instance_valid(rc) else null
		res["cam"] = cam.frames.size() if cam else 0
		var tilted := 0
		if cam:
			for fr in cam.frames:
				if absf((fr[2] as Vector2).x) > 0.05:
					tilted += 1
		res["tilted"] = tilted
	if race_t > 9.0:
		var ok: bool
		var detail: String
		var cam_ok: bool = int(res.get("cam", 0)) > 300 and int(res.get("tilted", 0)) > 20
		var cam_txt := "; winner cam %d frames (%d with the disc tilted)" % [int(res.get("cam", 0)), int(res.get("tilted", 0))]
		if name_ == "A":
			ok = res.has("tackle") and res.has("hit") and cam_ok
			detail = "tackle landed at %ss, disc clash at %ss" % [res.get("tackle", "-"), res.get("hit", "-")]
		else:
			ok = float(res.stun) > 0.3 and res.has("hit") and float(res.down) > 0.5 and cam_ok
			detail = "stunned %.2fs by the tackle, disc clash at %ss, knocked down %.2fs by the headshot" % [res.stun, res.get("hit", "-"), res.down]
		final = {"ok": ok, "detail": detail + cam_txt, "n": 0}
		game.goto_menu()
		return false
	return false
