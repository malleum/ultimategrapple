extends SceneTree
## Online client smoke test against a running dedicated server.
##   godot4 --headless --path . -- --server --port=24699 &
##   godot4 --headless -s tools/test_online.gd -- localhost:24699 A
##   godot4 --headless -s tools/test_online.gd -- localhost:24699 B
## The first client to join is the lobby leader: it sets "first to 2" and
## starts the set. Both clients must then receive the round's course.

var net
var t := 0.0
var name_ := "A"
var asked := false
var start_at := -1.0
var started := false


func _process(dt: float) -> bool:
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
	if net.in_lobby and net.players.size() >= 2 and not asked and t > 1.0:
		asked = true
		if net.is_leader():
			net.update_settings({"wins": 2, "difficulty": 0.3, "bogus": 99, "source": "nope"})
			start_at = t + 1.0
		else:
			# a non-leader must not be able to change anything
			net.update_settings({"wins": 9})
			net.rpc_id(1, "request_settings", {"wins": 9})
	if start_at > 0.0 and t > start_at:
		start_at = -1.0
		print("%s leader: settings now %s" % [name_, net.settings])
		net.request_start()
	var lvl = game.current_scene
	if lvl and lvl.has_method("remote_state"):
		print("%s OK: round %d started, course '%s', players %d, leader=%s, wins=%d" % [
			name_, net.round_idx + 1, lvl.level_data.get("name", "?"), net.players.size(), net.is_leader(), int(net.settings.wins)])
		quit(0)
		return true
	if t > 20.0:
		print("%s FAIL: status '%s', in_lobby=%s players=%d" % [name_, net.status, net.in_lobby, net.players.size()])
		quit(1)
		return true
	return false
