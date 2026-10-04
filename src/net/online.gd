extends Node
## Online services: a second, lobby-independent connection to the race
## server (its own ENet port and MultiplayerAPI branch), for
##   leaderboards  the built-in courses only: each runner's best time, splits
##                 and ghost frames. The only thing the server keeps.
##   presence      who is online right now
##   relay         send a replay or a match recording to someone online. The
##                 server forwards it and stores nothing.
##
## One script plays both roles so both ends declare the same RPC table: the
## Online autoload is the client (or, with --server, the server); tests start
## a second instance as a local server.
##
## Identity: a random id + secret made on first run (user://online_id.json).
## The server remembers the secret's hash per id, so nobody can overwrite
## your records by taking your name.

const SERVICE_PORT := 24682
const MAX_BLOB := 4 * 1024 * 1024      # biggest run / match the server relays
const MAX_RUN_BLOB := 1024 * 1024      # biggest leaderboard run it keeps
const BOARD_SIZE := 100
const ID_PATH := "user://online_id.json"
const SERVER_DIR := "user://server"
const RECONNECT_T := 20.0

signal state_changed                                   # connected / presence / courses
signal notice(text: String)                            # toast-worthy news
signal board_received(course: String, entries: Array)
signal run_received(course: String, uid: String, info: Dictionary, data: Dictionary)
signal submitted(course: String, rank: int, total: int, improved: bool)
signal send_result(ok: bool, text: String)
signal name_needed(msg: String)                        # the server won't show us until we pick a (free) name

var server := false
var connected := false        # client: hello answered
var presence: Array = []      # [{uid, name, color}]
var courses := {}             # course key -> level id (what the server keeps boards for)
var uid := ""
var _key := ""
var server_dir := SERVER_DIR  # where a server keeps its boards (tests use their own)
var auto_sync := true         # upload local PBs on connect
var name_ok := false          # client: the server accepted our name (we're on the boards)
var name_msg := ""
var name_override := ""       # tests: a name other than the settings' one
var _hello_t := -1.0          # seconds since hello while waiting for the welcome
const HELLO_TIMEOUT := 8.0
var link := "off"             # off / connecting / online / no_answer / refused
var link_msg := ""
var last_submit := {}         # the latest submit answer (the results card may open after it)
var _peer: ENetMultiplayerPeer = null
var _retry_t := -1.0
var _address := ""

# --- server state
var _accounts := {}           # uid -> {"h": sha256(secret), "name": str, "named": bool, "seen": unix}
var _names := {}              # normalised name -> uid that owns it
var _boards := {}             # course -> {uid -> {name, color, time, throws, medal, date, splits}}
var _peers := {}              # peer id -> {uid, name, color}
var _rate := {}               # peer id -> {kind -> last usec}


func _enter_tree() -> void:
	# own MultiplayerAPI: RPCs here never mix with the lobby's (Net)
	var api := SceneMultiplayer.new()
	api.server_relay = false
	get_tree().set_multiplayer(api, get_path())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_dropped)
	multiplayer.server_disconnected.connect(_on_dropped)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	_load_identity()


func _process(dt: float) -> void:
	if server:
		return
	# connected, said hello, no welcome: the server speaks another version of
	# this protocol (its RPCs don't line up with ours and get dropped)
	if _hello_t >= 0.0 and not connected:
		_hello_t += dt
		if _hello_t > HELLO_TIMEOUT:
			_hello_t = -1.0
			_set_link("mismatch", "")
	if _retry_t < 0.0:
		return
	_retry_t -= dt
	if _retry_t < 0.0 and _address != "":
		connect_to(_address)


# ================================================================ keys

## Leaderboard key of a built-in course: its id, a hash of the course file
## and the physics version, so an edited course or a physics change starts a
## fresh board instead of mixing incomparable times. "" if not built in.
static func course_key(level_id: String) -> String:
	var path := "res://levels/%s.json" % level_id.validate_filename()
	if not FileAccess.file_exists(path):
		return _key_by_scan(level_id)
	return "%s:%s:v%d" % [level_id, FileAccess.get_file_as_string(path).md5_text().substr(0, 10), _replay_version()]


static func _key_by_scan(level_id: String) -> String:
	for k in builtin_courses():
		if str(builtin_courses()[k]) == level_id:
			return k
	return ""


## course key -> level id for every course shipped in res://levels.
static func builtin_courses() -> Dictionary:
	var out := {}
	var d := DirAccess.open("res://levels")
	if d == null:
		return out
	for fname in d.get_files():
		if not fname.ends_with(".json"):
			continue
		var txt := FileAccess.get_file_as_string("res://levels/" + fname)
		var data = JSON.parse_string(txt)
		if data is Dictionary and data.has("id"):
			out["%s:%s:v%d" % [str(data.id), txt.md5_text().substr(0, 10), _replay_version()]] = str(data.id)
	return out


static func _replay_version() -> int:
	return int(load("res://src/core/game.gd").REPLAY_VERSION)


static func pack(v) -> PackedByteArray:
	return var_to_bytes(v).compress(FileAccess.COMPRESSION_GZIP)


static func unpack(b: PackedByteArray, max_size: int):
	if b.is_empty() or b.size() > max_size:
		return null
	var raw := b.decompress_dynamic(max_size * 8, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	return bytes_to_var(raw)   # no objects: plain data only


# ================================================================ names
# A name is owned by the first online id that uses it. "Runner" (the default),
# empty and junk names don't count: those runners stay off the boards and the
# online list until they choose one. Names are compared case-insensitively
# and with lookalikes folded (M4lleum = malleum), and a name whose owner
# hasn't been seen for NAME_STALE_DAYS can be taken by someone else.

const NAME_STALE_DAYS := 180
const DEFAULT_NAMES := ["runner", "dedlcated", "player", "guest", "anonymous", "anon"]   # normalised (i -> l)


## The form two names are compared in.
static func norm_name(n: String) -> String:
	var out := ""
	for ch in n.to_lower():
		match ch:
			"0", "o": out += "o"
			"1", "i", "l", "|", "!": out += "l"
			"3": out += "e"
			"4", "@": out += "a"
			"5", "$": out += "s"
			"7": out += "t"
			"8": out += "b"
			"9": out += "g"
			_:
				if (ch >= "a" and ch <= "z") or (ch >= "2" and ch <= "9"):
					out += ch
				elif ch.unicode_at(0) > 127 and ch.strip_edges() != "":
					out += ch   # other scripts count as themselves
	return out


## Why a name can't be used ("" if it can).
static func name_problem(n: String) -> String:
	var t := n.strip_edges()
	var k := norm_name(t)
	if t.length() < 2 or k.length() < 2:
		return "Pick a name with at least 2 letters or digits."
	if t.length() > 16:
		return "Names are at most 16 characters."
	if k in DEFAULT_NAMES or norm_name("Runner") == k:
		return "\"%s\" is the default name: pick your own." % t
	return ""


# ================================================================ client

func _load_identity() -> void:
	var f := FileAccess.open(ID_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary and str(d.get("uid", "")).length() == 16 and str(d.get("key", "")).length() == 32:
		uid = str(d.uid)
		_key = str(d.key)
		return
	var c := Crypto.new()
	uid = c.generate_random_bytes(8).hex_encode()
	_key = c.generate_random_bytes(16).hex_encode()
	var w := FileAccess.open(ID_PATH, FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify({"uid": uid, "key": _key}))


## Connect (and keep reconnecting) to the services port of host[:port].
func connect_to(address: String) -> void:
	_address = address
	if server:
		return
	_close()
	var host := address.get_slice(":", 0) if ":" in address else address
	var port := int(address.get_slice(":", 1)) if ":" in address else SERVICE_PORT
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(host, port) != OK:
		_peer = null
		_retry_t = RECONNECT_T
		_set_link("no_answer", "")
		return
	multiplayer.multiplayer_peer = _peer
	_retry_t = -1.0
	if link != "no_answer":   # keep saying why while it retries
		_set_link("connecting", "")


func _set_link(l: String, msg: String) -> void:
	link = l
	link_msg = msg
	state_changed.emit()


## What the menus say about the services connection.
func link_text() -> String:
	var host := _address if _address != "" else str(Game.settings.get("online_server", ""))
	if not ":" in host:
		host += ":%d" % SERVICE_PORT
	match link:
		"online":
			return "Online"
		"connecting":
			return "Connecting to %s (UDP) ..." % host
		"no_answer":
			return "No answer from %s (UDP). The server may be an older version without online services, or UDP %s isn't open in its firewall. Retrying..." % [host, host.get_slice(":", 1)]
		"refused":
			return "The online server refused us: %s" % link_msg
		"mismatch":
			return "%s answered but runs a different version of the game (its online protocol doesn't match). Update the server and the game to the same version." % host
	return "Online services are off (Settings)."


func disconnect_services() -> void:
	_address = ""
	_retry_t = -1.0
	_close()
	_set_link("off", "")


func _close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connected = false
	presence = []
	_hello_t = -1.0


func is_online() -> bool:
	return connected and _peer != null


func _on_connected() -> void:
	_hello_t = 0.0
	rpc_id(1, "hello", uid, _key, _my_name(), int(Game.settings.player_color))


func _on_dropped() -> void:
	var was := connected
	_close()
	if was:
		notice.emit("Lost the connection to the online server")
	_set_link("connecting" if was else "no_answer", "")
	if _address != "":
		_retry_t = RECONNECT_T


func _my_name() -> String:
	if name_override != "":
		return name_override
	return str(Game.settings.player_name).strip_edges().substr(0, 16)


## Re-announce name / colour after they change in the menu.
func update_profile() -> void:
	if is_online():
		rpc_id(1, "hello", uid, _key, _my_name(), int(Game.settings.player_color))


## Submit a finished run on a built-in course (server keeps it if it's your best).
func submit_run(level_id: String, time: float, throws: int, medal: String, frames: Array, splits: Array) -> bool:
	var ck := course_key(level_id)
	if not is_online() or ck == "" or not courses.has(ck) or frames.size() < 3:
		return false
	var blob := pack({"frames": frames})
	if blob.size() > MAX_RUN_BLOB:
		return false
	rpc_id(1, "submit", ck, {"time": time, "throws": throws, "medal": medal, "splits": splits}, blob)
	return true


func request_board(course: String) -> void:
	if is_online():
		rpc_id(1, "get_board", course)


func request_run(course: String, who: String) -> void:
	if is_online():
		rpc_id(1, "get_run", course, who)


## Relay a replay ("run") or a match recording ("match") to someone online.
func send_to(target_uid: String, kind: String, title: String, data: Dictionary) -> void:
	if not is_online():
		send_result.emit(false, "Not connected to the online server")
		return
	var blob := pack(data)
	if blob.size() > MAX_BLOB:
		send_result.emit(false, "That recording is too big to send (%d MB)" % (blob.size() >> 20))
		return
	rpc_id(1, "relay", target_uid, kind, title.substr(0, 80), blob)


## Upload local PBs on built-in courses the server may not have yet (it keeps
## only improvements, so resending is harmless).
func sync_local_records() -> void:
	if not is_online() or not auto_sync or not bool(Game.settings.get("share_records", true)):
		return
	for ck in courses:
		var lid: String = str(courses[ck])
		var rec = Game.get_record(lid)
		if rec == null:
			continue
		var frames := Game.load_ghost(lid)
		var e: Dictionary = Game.get_splits_any(lid)
		submit_run(lid, float(rec.time), int(rec.get("throws", 0)), str(rec.get("medal", "")), frames, e.get("pb", []))


# --- server -> client

@rpc("authority", "reliable")
func welcome(ok: bool, msg: String, keys: Array, named := true, nmsg := "") -> void:
	# (named / nmsg default: an older server without owned names sends 3 args)
	_hello_t = -1.0
	connected = ok
	name_ok = ok and named
	name_msg = nmsg
	if ok and not named and name_override == "":
		Game.settings["name_chosen"] = false
		Game.save_settings()
	if ok and not named:
		name_needed.emit(nmsg)
		notice.emit("%s You're off the leaderboards until you choose a name (menu)." % nmsg)
	courses = {}
	var local := builtin_courses()
	for k in keys:
		if local.has(str(k)):
			courses[str(k)] = local[str(k)]
	if not ok:
		notice.emit(msg)
		disconnect_services()
		_set_link("refused", msg)
	else:
		_set_link("online", "")
	state_changed.emit()
	if ok:
		sync_local_records()


@rpc("authority", "reliable")
func presence_list(list: Array) -> void:
	presence = list
	state_changed.emit()


@rpc("authority", "reliable")
func board(course: String, entries: Array) -> void:
	board_received.emit(course, entries)


@rpc("authority", "reliable")
func run(course: String, who: String, info: Dictionary, blob: PackedByteArray) -> void:
	var d = unpack(blob, MAX_RUN_BLOB)
	run_received.emit(course, who, info, d if d is Dictionary else {})


@rpc("authority", "reliable")
func submit_ok(course: String, rank: int, total: int, improved: bool) -> void:
	last_submit = {"course": course, "rank": rank, "total": total, "improved": improved, "ms": Time.get_ticks_msec()}
	submitted.emit(course, rank, total, improved)


@rpc("authority", "reliable")
func relay_ok(ok: bool, msg: String) -> void:
	send_result.emit(ok, msg)


@rpc("authority", "reliable")
func inbox(from_name: String, kind: String, title: String, blob: PackedByteArray) -> void:
	var d = unpack(blob, MAX_BLOB)
	if not d is Dictionary:
		return
	var who := from_name.substr(0, 16)
	match kind:
		"run":
			d["player"] = str(d.get("player", who))
			var err: String = Game.import_rival_data(d)
			notice.emit(("%s sent you a run: %s. It's under Replays → Friends' runs." % [who, title]) if err == "" else ("%s sent a run that couldn't be read: %s" % [who, err]))
		"match":
			if str(d.get("kind", "")) == "match" and d.get("level") is Dictionary and d.get("runners") is Array:
				d["from"] = who
				Game.save_match(d)
				notice.emit("%s sent you a match: %s. It's under Replays → Matches." % [who, title])


# ================================================================ server

func start_server(port := SERVICE_PORT) -> bool:
	server = true
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(port, 64) != OK:
		push_error("online services: could not listen on UDP %d" % port)
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	courses = builtin_courses()
	_load_server_state()
	print("Online services on port %d: %d leaderboard courses" % [port, courses.size()])
	return true


func _on_peer_gone(id: int) -> void:
	if not server:
		return
	_rate.erase(id)
	if _peers.erase(id):
		_push_presence()


func _sender() -> Dictionary:
	return _peers.get(multiplayer.get_remote_sender_id(), {})


## At most one `kind` action per `gap` seconds per peer.
func _allow(kind: String, gap: float) -> bool:
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _rate.get(id, {})
	var now := Time.get_ticks_usec()
	if now - int(r.get(kind, -100000000)) < int(gap * 1000000.0):
		return false
	r[kind] = now
	_rate[id] = r
	return true


## At most `count` `kind` actions per `window` seconds per peer.
func _budget(kind: String, count: int, window: float) -> bool:
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _rate.get(id, {})
	var now := Time.get_ticks_usec()
	var times: Array = (r.get(kind, []) as Array).filter(func(t): return now - int(t) < int(window * 1000000.0)) if r.get(kind) is Array else []
	if times.size() >= count:
		return false
	times.append(now)
	r[kind] = times
	_rate[id] = r
	return true


func _push_presence() -> void:
	var list: Array = []
	for id in _peers:
		var p: Dictionary = _peers[id]
		if bool(p.get("named", false)):
			list.append({"uid": p.uid, "name": p.name, "color": p.color})
	for id in _peers:
		rpc_id(id, "presence_list", list)


@rpc("any_peer", "reliable")
func hello(who: String, key: String, pname: String, color: int) -> void:
	if not server:
		return
	var id := multiplayer.get_remote_sender_id()
	if who.length() != 16 or key.length() != 32 or not who.is_valid_hex_number():
		rpc_id(id, "welcome", false, "Bad online id", [], false, "")
		return
	var h := key.sha256_text()
	var acc: Dictionary = _accounts.get(who, {})
	if not acc.is_empty() and str(acc.get("h", "")) != h:
		rpc_id(id, "welcome", false, "That online id belongs to someone else (delete user://online_id.json)", [], false, "")
		return
	pname = pname.strip_edges().substr(0, 16)
	var nmsg := _claim_name(who, pname)
	acc = _accounts.get(who, {})
	acc["h"] = h
	acc["seen"] = int(Time.get_unix_time_from_system())
	if nmsg == "":
		acc["name"] = pname
		acc["named"] = true
	else:
		acc["named"] = false
		if str(acc.get("name", "")) == "":
			acc["name"] = pname
	_accounts[who] = acc
	_save_accounts()
	_peers[id] = {"uid": who, "name": str(acc.name), "color": posmod(color, 8), "named": bool(acc.named)}
	rpc_id(id, "welcome", true, "", courses.keys(), bool(acc.named), nmsg)
	_push_presence()


## Give `pname` to `who` if it's a proper name nobody else holds; frees
## their previous one. Returns why not ("" when claimed).
func _claim_name(who: String, pname: String) -> String:
	var why := name_problem(pname)
	if why != "":
		return why
	var k := norm_name(pname)
	var owner := str(_names.get(k, ""))
	if owner != "" and owner != who:
		var oacc: Dictionary = _accounts.get(owner, {})
		var idle := int(Time.get_unix_time_from_system()) - int(oacc.get("seen", 0))
		if idle < NAME_STALE_DAYS * 86400 or _online_uid(owner):
			return "\"%s\" is already taken: pick another name." % pname
		oacc["named"] = false   # long gone: the name is free again
	for nk in _names.keys():
		if str(_names[nk]) == who:
			_names.erase(nk)
	_names[k] = who
	return ""


func _online_uid(who: String) -> bool:
	for id in _peers:
		if str(_peers[id].uid) == who:
			return true
	return false


@rpc("any_peer", "reliable")
func submit(course: String, info: Dictionary, blob: PackedByteArray) -> void:
	var me := _sender()
	if not server or me.is_empty() or not courses.has(course) or not _budget("submit", 40, 60.0):
		return
	var t := float(info.get("time", 0.0))
	if t <= 0.5 or t > 3600.0 or blob.size() > MAX_RUN_BLOB:
		return
	var d = unpack(blob, MAX_RUN_BLOB)
	if not (d is Dictionary and d.get("frames") is Array and (d.frames as Array).size() >= 3):
		return
	var b: Dictionary = _boards.get(course, {})
	var old: Dictionary = b.get(me.uid, {})
	var improved := old.is_empty() or Game.centis(t) < Game.centis(float(old.get("time", INF)))
	if improved:
		var splits: Array = []
		if info.get("splits") is Array:
			for s in (info.splits as Array).slice(0, 16):
				splits.append(snappedf(float(s), 0.001))
		b[me.uid] = {"time": t, "throws": clampi(int(info.get("throws", 0)), 0, 999), "medal": str(info.get("medal", "")).substr(0, 8),
			"date": int(Time.get_unix_time_from_system()), "splits": splits, "color": me.color}
		_boards[course] = b
		_write_run(course, me.uid, blob)
		_trim(course)
		_save_boards()
	var rank := _rank(course, me.uid)
	rpc_id(multiplayer.get_remote_sender_id(), "submit_ok", course, rank, _entries(course).size(), improved)


@rpc("any_peer", "reliable")
func get_board(course: String) -> void:
	if not server or _sender().is_empty() or not courses.has(course) or not _budget("board", 30, 10.0):
		return
	rpc_id(multiplayer.get_remote_sender_id(), "board", course, _entries(course))


@rpc("any_peer", "reliable")
func get_run(course: String, who: String) -> void:
	if not server or _sender().is_empty() or not courses.has(course) or not _budget("run", 120, 10.0):
		return
	var e: Dictionary = (_boards.get(course, {}) as Dictionary).get(who, {})
	var blob := _read_run(course, who)
	if e.is_empty() or blob.is_empty() or not bool((_accounts.get(who, {}) as Dictionary).get("named", false)):
		return
	var info := e.duplicate()
	info["uid"] = who
	info["name"] = str((_accounts.get(who, {}) as Dictionary).get("name", "Runner"))
	rpc_id(multiplayer.get_remote_sender_id(), "run", course, who, info, blob)


@rpc("any_peer", "reliable")
func relay(target: String, kind: String, title: String, blob: PackedByteArray) -> void:
	var me := _sender()
	var from_id := multiplayer.get_remote_sender_id()
	if not server or me.is_empty():
		return
	if not bool(me.get("named", false)):
		rpc_id(from_id, "relay_ok", false, "Choose a name first")
		return
	if not _allow("relay", 3.0):
		rpc_id(from_id, "relay_ok", false, "Slow down: one send every few seconds")
		return
	if not kind in ["run", "match"] or blob.size() > MAX_BLOB:
		rpc_id(from_id, "relay_ok", false, "Can't send that")
		return
	for id in _peers:
		if str(_peers[id].uid) == target:
			rpc_id(id, "inbox", str(me.name), kind, title, blob)
			rpc_id(from_id, "relay_ok", true, "Sent to %s" % _peers[id].name)
			return
	rpc_id(from_id, "relay_ok", false, "They're not online any more")


func _entries(course: String) -> Array:
	var b: Dictionary = _boards.get(course, {})
	var out: Array = []
	for who in b:
		var acc: Dictionary = _accounts.get(who, {})
		if not bool(acc.get("named", false)):
			continue   # no chosen name (still "Runner", or taken): hidden until they pick one
		var e: Dictionary = (b[who] as Dictionary).duplicate()
		e["uid"] = who
		e["name"] = str(acc.get("name", ""))
		out.append(e)
	out.sort_custom(func(a, c): return float(a.time) < float(c.time))
	return out


func _rank(course: String, who: String) -> int:
	var es := _entries(course)
	for i in es.size():
		if str(es[i].uid) == who:
			return i + 1
	return 0


## Keep the BOARD_SIZE fastest per course.
func _trim(course: String) -> void:
	var es := _entries(course)
	for i in range(BOARD_SIZE, es.size()):
		(_boards[course] as Dictionary).erase(str(es[i].uid))
		DirAccess.remove_absolute(_run_path(course, str(es[i].uid)))


func _run_path(course: String, who: String) -> String:
	return "%s/runs/%s/%s.bin" % [server_dir, course.validate_filename(), who.validate_filename()]


func _write_run(course: String, who: String, blob: PackedByteArray) -> void:
	var p := _run_path(course, who)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_buffer(blob)


func _read_run(course: String, who: String) -> PackedByteArray:
	var p := _run_path(course, who)
	return FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()


func _load_server_state() -> void:
	DirAccess.make_dir_recursive_absolute(server_dir)
	var a = JSON.parse_string(FileAccess.get_file_as_string(server_dir + "/accounts.json")) if FileAccess.file_exists(server_dir + "/accounts.json") else null
	_accounts = a if a is Dictionary else {}
	# names, first come first served (accounts keep the order they joined in);
	# a second "Bob" or a default "Runner" stays unnamed until they pick one
	_names = {}
	for who in _accounts:
		var acc: Dictionary = _accounts[who]
		var nm := str(acc.get("name", ""))
		var k := norm_name(nm)
		if name_problem(nm) == "" and not _names.has(k):
			_names[k] = who
			acc["named"] = true
		else:
			acc["named"] = false
	var b = JSON.parse_string(FileAccess.get_file_as_string(server_dir + "/boards.json")) if FileAccess.file_exists(server_dir + "/boards.json") else null
	_boards = {}
	if b is Dictionary:
		for k in b:
			if courses.has(k):   # boards of old courses / physics versions drop off
				_boards[k] = b[k]


func _save_accounts() -> void:
	var f := FileAccess.open(server_dir + "/accounts.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_accounts))


func _save_boards() -> void:
	var f := FileAccess.open(server_dir + "/boards.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_boards))
