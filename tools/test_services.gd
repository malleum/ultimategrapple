extends SceneTree
## Online services over loopback: a services server and two clients in one
## process (the Online autoload plus a second instance with its own id).
##   hello     both clients get in and see each other online
##   board     runs posted on a built-in course come back ranked, fastest first;
##             a slower resubmit doesn't replace a best
##   run       a runner's ghost frames can be fetched
##   relay     a replay sent to the other client lands in their Friends' runs
##   impostor  a second client claiming an id with the wrong secret is refused
##   names     a "Runner" (default name) is off the online list and the boards,
##             a lookalike of a taken name is refused, and once the Runner
##             picks a name their earlier run shows up under it
##   oldserver an older server's shorter welcome still gets the client online
##   stats     tries / clears / time per course reach the board and only grow
##   courses   a runner saves a course (the whole level), posts a run on it,
##             another runner sees it in the catalog with its podium and
##             downloads it; 7 at most, then a save must replace one (the
##             replaced course's board goes); REMOVE drops one
## godot --headless -s tools/test_services.gd

const PORT := 24782
var OnlineScript   # loaded at runtime: it uses the Game autoload

var srv
var c1
var c2
var c3
var c4   # still called "Runner"
var c5   # tries a lookalike of a taken name
var f := 0
var phase := "connect"
var fails := 0
var started := false
var course := ""
var lid := ""
var got := {}
var shares: Array = []     # courses c1 still has to save
var share_ids: Array = []
var m_extra := {}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _frames(n: int) -> Array:
	var out: Array = []
	for k in n:
		out.append([k * 10.0, 0.0, 300.0, 0.0, 1, 9, 0.0, 0.0, k * 10.0, -30.0, 0])
	return out


func _process(_dt: float) -> bool:
	if not started:
		started = true
		OnlineScript = load("res://src/net/online.gd")
		srv = OnlineScript.new()
		srv.name = "SrvTest"
		srv.server_dir = "user://test_services_server"
		root.add_child(srv)
		srv.start_server(PORT)
		c1 = root.get_node("Online")
		c1.auto_sync = false
		c1.name_override = "Alpha"
		c1.connect_to("127.0.0.1:%d" % PORT)
		c2 = OnlineScript.new()
		c2.name = "Cli2Test"
		root.add_child(c2)
		c2.uid = "0123456789abcdef"
		c2._key = "00112233445566778899aabbccddeeff"
		c2.auto_sync = false
		c2.name_override = "Bravo"
		c2.connect_to("127.0.0.1:%d" % PORT)
		c4 = OnlineScript.new()
		c4.name = "Cli4Test"
		root.add_child(c4)
		c4.uid = "aaaaaaaaaaaaaaaa"
		c4._key = "0000000000000000000000000000000a"
		c4.auto_sync = false
		c4.name_override = "Runner"
		c4.submitted.connect(func(c, r, t, imp): got["s4"] = [c, r, t, imp])
		c4.connect_to("127.0.0.1:%d" % PORT)
		var keys: Array = OnlineScript.builtin_courses().keys()
		keys.sort()
		course = keys[0]
		lid = str(OnlineScript.builtin_courses()[course])
		c1.submitted.connect(func(c, r, t, imp): got["s1"] = [c, r, t, imp])
		c2.submitted.connect(func(c, r, t, imp): got["s2"] = [c, r, t, imp])
		c1.board_received.connect(func(c, list): got["board"] = list)
		c1.run_received.connect(func(c, who, info, data): got["run"] = [who, info, data])
		c1.send_result.connect(func(ok, txt): got["sent"] = [ok, txt])
		return false
	f += 1
	if f > 6000:
		fails += 1
		print("FAIL timeout in phase %s" % phase)
		return _finish()
	match phase:
		"connect":
			if c1.is_online() and c2.is_online() and c4.is_online() and c1.presence.size() == 2 and c2.presence.size() == 2 and f > 30:
				_check("hello", c1.courses.has(course) and OnlineScript.course_key(lid) == course and c1.name_ok and c2.name_ok,
					"both online, %d courses with boards, %s -> %s" % [c1.courses.size(), lid, course])
				_check("runner", not c4.name_ok and c4.name_msg.contains("default"), "a \"Runner\" is online but unnamed: %s" % c4.name_msg)
				c4.submit_run(lid, 9.0, 1, "ace", _frames(25), [3.0, 6.0, 9.0])
				phase = "submit4"
		"submit4":
			if got.has("s4"):
				_check("hidden", int(got.s4[1]) == 0, "the Runner's (fastest) run is kept but not ranked: #%d of %d" % [got.s4[1], got.s4[2]])
				c1.submit_run(lid, 12.5, 2, "gold", _frames(40), [4.0, 8.0, 12.5])
				phase = "submit1"
		"submit1":
			if got.has("s1"):
				c2.submit_run(lid, 11.0, 1, "ace", _frames(30), [3.5, 7.0, 11.0])
				phase = "submit2"
		"submit2":
			if got.has("s2"):
				_check("rank", int(got.s1[1]) == 1 and int(got.s2[1]) == 1 and int(got.s2[2]) == 2,
					"first post #%d, faster second runner #%d of %d" % [got.s1[1], got.s2[1], got.s2[2]])
				got.erase("s1")
				c1.submit_run(lid, 20.0, 5, "", _frames(50), [9.0, 15.0, 20.0])
				phase = "slower"
		"slower":
			if got.has("s1"):
				_check("keep", not bool(got.s1[3]) and int(got.s1[1]) == 2, "a slower resubmit keeps the best (improved=%s, #%d)" % [got.s1[3], got.s1[1]])
				# per-course play stats ride on submit with no run; they only grow
				c1.rpc_id(1, "submit", course, {"stats": {"att": 7, "comp": 3, "play": 1728.0}}, PackedByteArray())
				c1.rpc_id(1, "submit", course, {"stats": {"att": 2, "comp": 1, "play": 10.0}}, PackedByteArray())
				c1.request_board(course)
				phase = "board"
		"board":
			if got.has("board"):
				var b: Array = got.board
				_check("board", b.size() == 2 and str(b[0].uid) == c2.uid and float(b[1].time) == 12.5 and (b[1].splits as Array).size() == 3,
					"%d entries: %s %.1f, %s %.1f" % [b.size(), b[0].name, b[0].time, b[1].name, b[1].time])
				_check("stats", int(b[1].get("att", -1)) == 7 and int(b[1].get("comp", -1)) == 3 and float(b[1].get("play", -1.0)) == 1728.0,
					"Alpha on the board: %s tries, %s clears, %s s played (a lower resend doesn't wind them back)" % [b[1].get("att"), b[1].get("comp"), b[1].get("play")])
				c5 = OnlineScript.new()
				c5.name = "Cli5Test"
				root.add_child(c5)
				c5.uid = "bbbbbbbbbbbbbbbb"
				c5._key = "0000000000000000000000000000000b"
				c5.auto_sync = false
				c5.name_override = " br4VO"
				c5.connect_to("127.0.0.1:%d" % PORT)
				phase = "lookalike"
		"lookalike":
			if c5.is_online() and c5.name_msg != "":
				_check("taken", not c5.name_ok and c5.name_msg.contains("taken"), "\" br4VO\" vs Bravo: %s" % c5.name_msg)
				got.erase("board")
				c4.name_override = "Charlie"
				c4.update_profile()
				phase = "rename"
		"rename":
			if c4.name_ok and not got.has("asked"):
				got["asked"] = true
				c1.request_board(course)
			if got.has("board"):
				var b2: Array = got.board
				_check("renamed", b2.size() == 3 and str(b2[0].name) == "Charlie" and float(b2[0].time) == 9.0,
					"after choosing a name the Runner's run shows: %s" % [b2.map(func(e): return "%s %.1f" % [e.name, e.time])])
				c1.request_run(course, c2.uid)
				phase = "run"
		"run":
			if got.has("run"):
				var data: Dictionary = got.run[2]
				_check("run", str(got.run[0]) == c2.uid and (data.get("frames", []) as Array).size() == 30,
					"fetched %d ghost frames of the #1 run" % (data.get("frames", []) as Array).size())
				var rep := {"level_id": "svc_test", "level": {"id": "svc_test", "name": "Svc Test"}, "name": "Svc Test",
					"time": 9.87, "player": "Sender", "ghost": _frames(12)}
				c1.send_to(c2.uid, "run", "Svc Test 9.87", rep)
				phase = "relay"
		"relay":
			if got.has("sent"):
				var listed := false
				for e in root.get_node("Game").list_rivals():
					listed = listed or str(e.get("level_id", "")) == "svc_test"
				if listed or f > 600:
					_check("relay", bool(got.sent[0]) and listed, "send: %s; landed in the other client's Friends' runs: %s" % [got.sent[1], listed])
					c3 = OnlineScript.new()
					c3.name = "Cli3Test"
					root.add_child(c3)
					c3.uid = c2.uid
					c3._key = "ffffffffffffffffffffffffffffffff"
					c3.auto_sync = false
					c3.notice.connect(func(t): got["c3"] = t)
					c3.connect_to("127.0.0.1:%d" % PORT)
					phase = "impostor"
		"impostor":
			if got.has("c3"):
				_check("impostor", not c3.is_online() and str(got.c3).contains("someone else"), "refused: %s" % got.c3)
				# an older server (before owned names) answers with a 3-value welcome
				c1.connected = false
				c1.name_ok = false
				c1.link = "connecting"
				for id in srv._peers:
					if str(srv._peers[id].uid) == c1.uid:
						srv.rpc_id(id, "welcome", true, "", srv.courses.keys())
				got.erase("board")
				phase = "oldwelcome"
				f = 2000
		"oldwelcome":
			if f == 2030:
				_check("oldserver", c1.is_online() and c1.name_ok and c1.link == "online", "a 3-value welcome from an older server is still understood (link %s)" % c1.link)
				c1.share_result.connect(func(ok, msg, cid): got["share"] = [ok, msg, cid])
				c1.catalog_received.connect(func(l): got["cat1"] = l)
				c2.catalog_received.connect(func(l): got["cat2"] = l)
				c2.course_received.connect(func(cid, d): got["course2"] = [cid, d])
				var Gen = load("res://src/level/generator.gd")
				for i in 7:
					shares.append(Gen.new().generate(500 + i, "field", 0.4, 3))
				c1.share_course(shares.pop_front(), -1)
				phase = "share1"
		"share1":
			if got.has("share") and got.has("cat1"):
				var cid: String = str(got.share[2])
				share_ids.append(cid)
				var mine: Array = c1.my_courses()
				_check("share", bool(got.share[0]) and OnlineScript.is_shared_id(cid) and mine.size() == 1 and str(mine[0].key) == OnlineScript.shared_key(cid),
					"saved as %s: %s; my courses %d" % [cid, got.share[1], mine.size()])
				got.erase("s1")
				c1.submit_run(cid, 15.0, 1, "gold", _frames(20), [5.0, 10.0, 15.0])
				phase = "share_run"
		"share_run":
			if got.has("s1"):
				got.erase("cat2")
				c2.request_catalog()
				c2.request_course(str(share_ids[0]))
				phase = "share_seen"
		"share_seen":
			if got.has("cat2") and got.has("course2"):
				var alpha: Dictionary = {}
				for p in got.cat2:
					if str(p.uid) == c1.uid:
						alpha = p
				var cs: Array = alpha.get("courses", [])
				var top: Array = cs[0].get("top", []) if not cs.is_empty() else []
				var lvd: Dictionary = got.course2[1]
				_check("catalog", cs.size() == 1 and top.size() == 1 and str(top[0][0]) == "Alpha" and float(top[0][1]) == 15.0 and int(got.s1[1]) == 1,
					"the other runner sees %s's course: %d runs, gold %s" % [alpha.get("name", "?"), int(cs[0].runs) if not cs.is_empty() else -1, top])
				_check("download", str(lvd.get("id", "")) == str(share_ids[0]) and (lvd.get("solids", []) as Array).size() > 3,
					"downloaded the whole course: %d solids, %d entities" % [(lvd.get("solids", []) as Array).size(), (lvd.get("entities", []) as Array).size()])
				got.erase("share")
				c1.share_course(shares.pop_front(), -1)
				phase = "share_fill"
		"share_fill":
			if got.has("share"):
				share_ids.append(str(got.share[2]))
				got.erase("share")
				if not shares.is_empty():
					c1.share_course(shares.pop_front(), -1)
				else:
					var Gen2 = load("res://src/level/generator.gd")
					m_extra = Gen2.new().generate(999, "cyber", 0.5, 3)
					c1.share_course(m_extra, -1)
					phase = "share_full"
		"share_full":
			if got.has("share"):
				_check("full", not bool(got.share[0]) and str(got.share[1]).contains("7") and c1.my_courses().size() == 7, "an 8th save: %s" % got.share[1])
				got.erase("share")
				got.erase("cat1")
				c1.share_course(m_extra, 0)
				phase = "share_replace"
		"share_replace":
			if got.has("share") and got.has("cat1"):
				var ids: Array = c1.my_courses().map(func(c): return str(c.cid))
				var gone: String = str(share_ids[0])
				_check("replace", bool(got.share[0]) and ids.size() == 7 and not ids.has(gone) and ids.has(str(got.share[2])) and not srv._boards.has(OnlineScript.shared_key(gone)),
					"replaced the first course: still %d, the old one and its board are gone" % ids.size())
				got.erase("cat1")
				c1.unshare_course(str(ids[1]))
				phase = "share_remove"
		"share_remove":
			if got.has("cat1"):
				_check("remove", c1.my_courses().size() == 6, "after REMOVE: %d courses" % c1.my_courses().size())
				_migrate()
				return _finish()
	return false


## A server restarting on boards from before names were owned: "Runner"s
## and the second "bob" drop off until they choose; the first Bob keeps it.
func _migrate() -> void:
	var dir := "user://test_services_server2"
	DirAccess.make_dir_recursive_absolute(dir)
	var acc := {"1111111111111111": {"h": "x", "name": "Runner"}, "2222222222222222": {"h": "x", "name": "Bob"},
		"3333333333333333": {"h": "x", "name": "b0b"}, "4444444444444444": {"h": "x", "name": "Dee"}}
	var brd := {}
	brd[course] = {}
	for u in acc:
		brd[course][u] = {"time": 10.0 + float(u.substr(0, 1)), "splits": [], "color": 0, "medal": "", "throws": 1, "date": 0}
	FileAccess.open(dir + "/accounts.json", FileAccess.WRITE).store_string(JSON.stringify(acc))
	FileAccess.open(dir + "/boards.json", FileAccess.WRITE).store_string(JSON.stringify(brd))
	var s2 = OnlineScript.new()
	s2.name = "SrvMigrate"
	s2.server_dir = dir
	root.add_child(s2)
	s2.start_server(PORT + 1)
	var names: Array = s2._entries(course).map(func(e): return str(e.name))
	_check("migrate", names == ["Bob", "Dee"], "boards after restart show %s (Runner and the second bob hidden)" % [names])
	s2.queue_free()
	_rm(dir)


func _finish() -> bool:
	var G = root.get_node("Game")
	for e in G.list_rivals():
		if str(e.get("level_id", "")) == "svc_test":
			G.delete_rival(str(e.id))
	_rm("user://test_services_server")
	for cid in share_ids:
		DirAccess.remove_absolute("%s/%s.json" % [OnlineScript.SHARED_DIR, cid])
	print("services: %d failures" % fails)
	quit(0 if fails == 0 else 1)
	return true


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm(path + "/" + sub)
	for fn in d.get_files():
		DirAccess.remove_absolute(path + "/" + fn)
	DirAccess.remove_absolute(path)
