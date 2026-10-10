extends SceneTree
## Big online lobby on a real dedicated server: N clients join (more than the
## old 12-player cap when N is large), the leader hands the server a pool of
## saved courses (source "saved"), starts the set, and every client must get
## round 1 on the pool's first course. Run through tools/test_lobby.sh.
##   godot4 --headless -s tools/test_lobby.gd -- host:port name expected_players

var net
var t := 0.0
var name_ := "A"
var want := 2
var sent := false
var started_set := false
var started := false
## "abandon": start a random set, race a few seconds, leave mid-race.
## "late": join while that race is on and must be dropped into it.
var mode := ""
var raced_at := -1.0


func _process(dt: float) -> bool:
	var game = root.get_node("Game")
	if not started:
		started = true
		game.main = root
		var args := OS.get_cmdline_user_args()
		name_ = args[1]
		want = int(args[2])
		mode = args[3] if args.size() > 3 else ""
		game.settings.player_name = name_
		net = root.get_node("Net")
		net.join(args[0])
		return false
	t += dt
	if t > 90.0:
		print("%s FAIL: timeout (players %d, source %s)" % [name_, net.players.size(), net.settings.source])
		quit(1)
		return true
	if mode != "":
		return _side_run(game)
	if net.in_lobby and net.is_leader() and net.players.size() >= want and not sent:
		sent = true
		var pool: Array = []
		for i in 2:
			var d: Dictionary = game.generate_level(4100 + i, "field", 0.3, 4)
			d["id"] = "pool_%d" % i
			pool.append(d)
		var raw := JSON.stringify(pool).to_utf8_buffer()
		net.rpc_id(1, "set_pool", raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), "Tester")
	if sent and not started_set and str(net.settings.source) == "saved" and int(net.settings.get("pool_n", 0)) == 2:
		started_set = true
		print("%s: lobby of %d racing %s" % [name_, net.players.size(), net.source_text()])
		net.request_start()
	var lvl = game.current_scene
	if lvl and is_instance_valid(lvl) and lvl.get("level_data") is Dictionary and str(lvl.level_data.get("id", "")) != "":
		var id := str(lvl.level_data.id)
		var ok: bool = id == "pool_0" and net.players.size() >= want
		print("%s %s: round 1 on %s with %d players" % [name_, "OK" if ok else "FAIL", id, net.players.size()])
		quit(0 if ok else 1)
		return true
	return false


func _side_run(game) -> bool:
	var lvl = game.current_scene
	var racing: bool = lvl and is_instance_valid(lvl) and lvl.get("mode") == "multi"
	if mode == "abandon":
		if net.in_lobby and net.is_leader() and not sent:
			sent = true
			net.request_start()
		if racing and raced_at < 0.0:
			raced_at = t
			print("%s: racing, leaving in 6s" % name_)
		if raced_at >= 0.0 and t - raced_at > 6.0:
			net.leave()
			print("%s OK: left mid-race" % name_)
			quit(0)
			return true
	elif mode == "late":
		if racing:
			print("%s OK: joined the race in progress" % name_)
			net.leave()
			quit(0)
			return true
	return false
