extends SceneTree
## Online versus contacts through a real dedicated server: A slide-tackles B
## (B must get stunned on its own client), then both throw at each other and
## the discs must clash (each client's own disc gets knocked).
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
	if race_t > 5.0:
		var ok: bool
		var detail: String
		if name_ == "A":
			ok = res.has("tackle") and res.has("hit")
			detail = "tackle landed at %ss, disc hit at %ss" % [res.get("tackle", "-"), res.get("hit", "-")]
		else:
			ok = float(res.stun) > 0.3 and res.has("hit")
			detail = "stunned %.2fs by the tackle, disc hit at %ss" % [res.stun, res.get("hit", "-")]
		print("%s %s: %s" % [name_, "OK" if ok else "FAIL", detail])
		quit(0 if ok else 1)
		return true
	return false
