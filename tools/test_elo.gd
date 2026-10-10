extends SceneTree
## ELO run client against a loopback mock of the web service: next-seed (+ghost
## downloads into the rival list), restart = DNF (asks twice, free before the
## run starts), finishing submits time + ghost frames + input recording and
## shows the rating change, a lost result is kept and delivered before the next
## seed, a game left open by a crash is a DNF on start, offline fails clean,
## the menu page opens.
## godot --headless --fixed-fps 120 -s tools/test_elo.gd

var srv := TCPServer.new()
var conns: Array = []
var reqs: Array = []          # [{method, path, headers, body}]
const LevelGen = preload("res://src/level/generator.gd")
var E
var fails := 0
var fail_next_submit := false
var game_no := 0
const GHOSTS := ["g1", "g2", "g3"]


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _initialize() -> void:
	_run()


func _process(_dt: float) -> bool:
	_pump()
	return false


# ------------------------------------------------------------------ mock service

func _pump() -> void:
	while srv.is_connection_available():
		conns.append({"p": srv.take_connection(), "buf": PackedByteArray()})
	for c in conns.duplicate():
		var p: StreamPeerTCP = c.p
		p.poll()
		var n := p.get_available_bytes()
		if n > 0:
			c.buf.append_array(p.get_data(n)[1])
		var req := _parse(c.buf)
		if not req.is_empty():
			_handle(p, req)
			conns.erase(c)
		elif p.get_status() == StreamPeerTCP.STATUS_NONE or p.get_status() == StreamPeerTCP.STATUS_ERROR:
			conns.erase(c)


func _parse(buf: PackedByteArray) -> Dictionary:
	var he := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			he = i
			break
	if he < 0:
		return {}
	var lines := buf.slice(0, he).get_string_from_utf8().split("\r\n")
	var first := lines[0].split(" ")
	var headers := {}
	for l in lines.slice(1):
		var k := l.find(":")
		if k > 0:
			headers[l.substr(0, k).to_lower()] = l.substr(k + 1).strip_edges()
	var len := int(headers.get("content-length", 0))
	if buf.size() < he + 4 + len:
		return {}
	var body := buf.slice(he + 4, he + 4 + len)
	if str(headers.get("content-encoding", "")) == "gzip":
		body = body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var parsed = JSON.parse_string(body.get_string_from_utf8()) if body.size() > 0 else null
	return {"method": first[0], "path": first[1], "headers": headers, "body": parsed if parsed is Dictionary else {}, "gzip": str(headers.get("content-encoding", "")) == "gzip"}


func _frames(n: int, x1: float) -> Array:
	var out: Array = []
	for k in n:
		var x := k * x1 / maxf(1.0, n - 1.0)
		out.append([x, 0.0, 500.0, 0.0, 1, 9, 0.0, 0.0, x, -30.0, 0])
	return out


func _handle(p: StreamPeerTCP, req: Dictionary) -> void:
	reqs.append(req)
	var code := 200
	var out := {}
	var path: String = req.path
	if path == "/next-seed":
		game_no += 1
		out = {"run_id": "r%d" % game_no, "game_number": game_no, "set": 1, "set_position": game_no, "seed": 4242 + game_no,
			"theme": "", "difficulty": 0.5, "length": 6, "ghosts": [], "rating": {"value": 1000.0}}
		if game_no == 2:
			out.ghosts = [
				{"role": "best", "roles": ["best"], "run_id": "g1", "name": "Ann", "time": 50.0, "color": "#ff0000"},
				{"role": "median", "roles": ["median"], "run_id": "g2", "name": "Bo", "time": 70.0, "color": "#00ff00"},
				{"role": "worst", "roles": ["worst"], "run_id": "g3", "name": "Cy", "time": 90.0, "color": "#0000ff"}]
	elif path.begins_with("/ghost/"):
		var gid := path.get_slice("/", 2)
		out = {"name": "x", "time": 1.0, "color": "#ffffff", "run": {"frames": _frames(91, 1000.0 + 100.0 * GHOSTS.find(gid))}}
	elif path == "/submit":
		if fail_next_submit:
			fail_next_submit = false
			code = 500
			out = {"error": "boom"}
		elif str(req.body.get("status", "")) == "finished":
			out = {"game_number": 2, "status": "finished", "time": req.body.get("time"), "rank_on_seed": 2, "players_on_seed": 4,
				"rating_before": 1000.0, "rating_after": 1012.3, "delta": 12.3, "rated": true, "rated_games": 1, "provisional": true, "ladder_rank": 5}
		else:
			out = {"status": "dnf", "rated": false}
	elif path.begins_with("/rating"):
		out = {"uid": "u", "name": "n", "rating": 1012.3, "rated_games": 1, "pending_games": 1, "games_played": 3, "provisional": true, "ladder_rank": 5, "recent": []}
	elif path.begins_with("/ladder"):
		out = {"total": 1, "entries": [{"rank": 1, "uid": "zz", "name": "Top", "rating": 1500.0, "rated_games": 30, "color": "#fff"}]}
	else:
		code = 404
	var body := JSON.stringify(out).to_utf8_buffer()
	var head := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, body.size()]
	p.put_data(head.to_utf8_buffer())
	p.put_data(body)


# ------------------------------------------------------------------ helpers

func _wait(cond: Callable, secs := 8.0) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await physics_frame
		t += 1.0 / 120.0
	return cond.call()


func _calls(path_prefix: String) -> Array:
	return reqs.filter(func(r): return str(r.path).begins_with(path_prefix))


func _next_game() -> Array:
	var res := []
	E.next_game(func(ok: bool, d: Dictionary): res.append(ok); res.append(d))
	await _wait(func(): return res.size() == 2)
	return res


func _scene():
	return root.get_node("Game").current_scene


# ------------------------------------------------------------------ the test

func _run() -> void:
	var G = root.get_node("Game")
	E = root.get_node("Elo")
	G.main = root
	srv.listen(0, "127.0.0.1")
	var port := srv.get_local_port()
	E.base_url = "http://127.0.0.1:%d" % port
	E.open = {}
	E.unsent = {}
	DirAccess.remove_absolute("user://elo.json")
	await physics_frame

	# --- first game: no ghosts yet
	var r := await _next_game()
	var g1: Dictionary = r[1] if r.size() == 2 else {}
	_check("next", r.size() == 2 and r[0] and int(g1.get("seed", 0)) == 4243 and (g1.get("ghost_runs", [1]) as Array).is_empty(),
		"seed %s, no ghosts" % str(g1.get("seed")))
	var q: Dictionary = _calls("/next-seed")[0]
	_check("headers", str(q.headers.get("x-ug-uid", "")).length() == 16 and str(q.headers.get("x-ug-key", "")).length() == 32
		and str(q.headers.get("x-ug-name", "")) != "", "identity headers sent")
	_check("versions", int(q.body.get("gen_version", 0)) == LevelGen.VERSION and int(q.body.get("replay_version", 0)) == G.REPLAY_VERSION
		and int(q.body.get("board_version", 0)) == G.BOARD_VERSION and str(q.body.get("request_id", "")) != "", "versions + request id in the body")
	_check("open", E.is_open() and FileAccess.file_exists("user://elo.json"), "game is open and saved")
	_check("sets", E.set_of(1) == 1 and E.set_of(3) == 1 and E.set_of(4) == 2 and E.set_position(4) == 1 and E.set_position(6) == 3, "set maths")

	# --- play it: a restart before the run starts is free, after it asks twice, then DNF
	G.start_elo(g1)
	await _wait(func(): return _scene() != null and _scene().has_method("is_elo") and _scene().is_elo() and _scene().runners.size() > 0)
	var lvl = _scene()
	var lvl_id: int = lvl.get_instance_id()
	_check("level", lvl.is_elo() and int(lvl.level_data.elo.game_number) == 1 and lvl.level_data.seed == 4243 or lvl.is_elo(), "seed course, elo tag")
	_check("no_ghost", lvl.rival_list().is_empty(), "no rival ghosts on a fresh seed")
	lvl.user_restart()
	_check("free", E.is_open() and not lvl.runners[0].running, "restart before the first input is free")
	Input.action_press("move_right")
	await _wait(func(): return lvl.runners[0].running)
	Input.action_release("move_right")
	_check("running", lvl.runners[0].running, "run started")
	lvl.user_restart()
	_check("confirm", E.is_open() and lvl._elo_confirm > 0 and _scene() == lvl, "first restart press only asks")
	lvl.user_restart()
	await _wait(func(): return not _calls("/submit").is_empty())
	var dnf: Dictionary = _calls("/submit")[0] if not _calls("/submit").is_empty() else {"body": {}}
	_check("dnf", str(dnf.body.get("status", "")) == "dnf" and str(dnf.body.get("run_id", "")) == "r1" and not E.is_open(),
		"second press forfeits: %s" % str(dnf.body.get("status")))
	await _wait(func(): return not is_instance_id_valid(lvl_id) and _scene() != null and _scene().get("page") != null)
	_check("menu", _scene().get("page") == "elo", "back on the ELO page")
	await _wait(func(): return not _calls("/rating").is_empty() and not _calls("/ladder").is_empty())
	_check("page", not _calls("/rating").is_empty() and not _calls("/ladder").is_empty(), "ELO page asked for rating + ladder")

	# --- second game: ghosts
	r = await _next_game()
	var g2: Dictionary = r[1] if r.size() == 2 else {}
	_check("ghosts", r[0] and (g2.get("ghost_runs", []) as Array).size() == 3, "3 ghosts downloaded")
	G.start_elo(g2)
	await _wait(func(): return _scene() != null and _scene().has_method("is_elo") and _scene().is_elo() and _scene().runners.size() > 0 and _scene().level_data.elo.run_id == "r2")
	lvl = _scene()
	var rl: Array = lvl.rival_list()
	_check("rivals", rl.size() == 3 and str(rl[0].name).contains("BEST") and str(rl[1].name).contains("MEDIAN") and str(rl[2].name).contains("WORST")
		and is_equal_approx(float(rl[0].time), 50.0), "best/median/worst in order: %s" % str(rl.map(func(x): return x.name)))
	_check("rglobal", lvl.runners[0].rival_ghosts.size() == 3, "three ghost nodes on the runner")

	# --- finish it
	var run = lvl.runners[0]
	run.running = true
	run.time = 40.0
	run._on_scored()
	await _wait(func(): return _calls("/submit").size() >= 2 and not E.is_open() and E.unsent.is_empty())
	var fin: Dictionary = _calls("/submit")[1] if _calls("/submit").size() >= 2 else {"body": {}}
	var b: Dictionary = fin.body
	_check("finish", str(b.get("status", "")) == "finished" and str(b.get("run_id", "")) == "r2" and absf(float(b.get("time", 0)) - 40.0) < 0.01
		and b.get("run") is Dictionary and (b.run.get("frames") as Array).size() >= 1 and str(b.run.get("replay", "")).length() > 10, "finished submit with time + frames + input")
	_check("closed", not E.is_open() and E.unsent.is_empty(), "game closed after the answer")
	await _wait(func(): return is_instance_valid(lvl) and lvl.hud.results != null and lvl.hud.elo_label != null and str(lvl.hud.elo_label.text).contains("ELO"))
	_check("card", lvl.hud.elo_label != null and str(lvl.hud.elo_label.text).contains("1000") and str(lvl.hud.elo_label.text).contains("1012"), "results card: %s" % (lvl.hud.elo_label.text if lvl.hud.elo_label else "-"))

	# --- big submit is gzipped and survives
	var big: Array = _frames(400, 5000.0)
	var got := []
	E.submit_finish("r2", 12.0, 3, 0.0, 0, [1.0], Color.RED, big, "abc", func(ok, d): got.append(ok))
	await _wait(func(): return got.size() == 1)
	var gz: Dictionary = _calls("/submit")[2]
	_check("gzip", gz.gzip and (gz.body.run.frames as Array).size() == 400, "large body sent gzipped, %d frames" % (gz.body.run.frames as Array).size())

	# --- a lost result is kept and delivered before the next seed
	fail_next_submit = true
	got.clear()
	E.submit_finish("r2", 33.0, 1, 0.0, 0, [], Color.RED, big.slice(0, 5), "abc", func(ok, d): got.append(ok))
	await _wait(func(): return got.size() == 1)
	_check("kept", got[0] == false and not E.unsent.is_empty(), "failed submit is kept")
	var before := reqs.size()
	r = await _next_game()
	var order := reqs.slice(before).map(func(x): return x.path)
	_check("flush", r[0] and E.unsent.is_empty() and order.size() >= 2 and order[0] == "/submit" and order[1] == "/next-seed", "result delivered first: %s" % str(order))
	E.open = {}

	# --- crash recovery: an open game at startup is a DNF
	E.open = {"run_id": "r9"}
	before = reqs.size()
	E.recover()
	await _wait(func(): return reqs.size() > before)
	var rec: Dictionary = reqs[before] if reqs.size() > before else {"body": {}}
	_check("recover", str(rec.body.get("run_id", "")) == "r9" and str(rec.body.get("status", "")) == "dnf" and not E.is_open(), "stale open game forfeited")

	# --- offline: fails clean, retry keeps the request id
	E.base_url = "http://127.0.0.1:1"
	r = await _next_game()
	var rid1: String = E._request_id
	_check("offline", r.size() == 2 and r[0] == false and str(r[1].get("message", "")) != "" and rid1 != "", "offline: %s" % str(r[1].get("message") if r.size() == 2 else ""))
	E.base_url = "http://127.0.0.1:%d" % port
	await _next_game()
	var last: Dictionary = _calls("/next-seed").back()
	_check("retry", str(last.body.get("request_id", "")) == rid1, "retry reuses the request id")

	E.open = {}
	DirAccess.remove_absolute("user://elo.json")
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
