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


func _process(dt: float) -> bool:
	var game = root.get_node("Game")
	if not started:
		started = true
		game.main = root
		var args := OS.get_cmdline_user_args()
		name_ = args[1]
		want = int(args[2])
		game.settings.player_name = name_
		net = root.get_node("Net")
		net.join(args[0])
		return false
	t += dt
	if t > 90.0:
		print("%s FAIL: timeout (players %d, source %s)" % [name_, net.players.size(), net.settings.source])
		quit(1)
		return true
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
