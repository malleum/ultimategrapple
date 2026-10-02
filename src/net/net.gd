extends Node
## Multiplayer: ENet host/join, LAN discovery, lobby, and "first to X" race sets.
## Everyone races the same course simultaneously as non-colliding ghosts.
## The server (listen or dedicated) is authoritative for round order/scoring.

const Themes = preload("res://src/core/theme_db.gd")

const PORT := 24680
## Public dedicated server (minimus, UDP 24680). Players can type another.
const ONLINE_SERVER := "joshammer.com"
const DISCOVERY_PORT := 24681
const STATE_HZ := 30.0
const ROUND_BREAK := 5.0

signal lobby_changed
signal status_changed(text: String)
signal servers_changed

var peer: ENetMultiplayerPeer = null
var players := {}          # id -> {name, color, wins, ready}
var settings := {"wins": 3, "source": "random", "difficulty": 0.5, "length": 10, "theme": ""}
var in_lobby := false
var dedicated := false
var round_active := false
var round_idx := 0
var round_winner := -1
var round_results := {}    # id -> time
var set_winner := -1
var next_round_at := -1.0
var champion_text := ""
var status := ""
var servers := {}          # "ip:port" -> {name, count, t}

var _send_accum := 0.0
var _last_frame: Array = []
var _bcast: PacketPeerUDP = null
var _listen: PacketPeerUDP = null
var _bcast_t := 0.0
var _round_timer := -1.0
var _join_seq := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func is_server() -> bool:
	return peer != null and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if peer else 1


func _my_info() -> Dictionary:
	return {"name": str(Game.settings.player_name).substr(0, 16), "color": int(Game.settings.player_color), "wins": 0, "ready": false}


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)
	if dedicated:
		print("[server] ", t)


# ================================================================ connect

func host(port := PORT, as_dedicated := false) -> bool:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 12)
	if err != OK:
		peer = null
		_set_status("Could not host on port %d (error %d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	dedicated = as_dedicated
	players.clear()
	if not dedicated:
		players[1] = _my_info()
	in_lobby = true
	_start_broadcast(port)
	_set_status("Hosting on port %d" % port)
	lobby_changed.emit()
	return true


func join(address: String) -> void:
	leave()
	var ip := address
	var port := PORT
	if ":" in address:
		ip = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	if ip == "":
		ip = "127.0.0.1"
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		peer = null
		_set_status("Could not connect (error %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s:%d ..." % [ip, port])


func leave() -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_lobby = false
	round_active = false
	set_winner = -1
	_round_timer = -1.0
	if _bcast:
		_bcast.close()
		_bcast = null
	lobby_changed.emit()


func leave_if_solo() -> void:
	pass


func start_dedicated_server() -> void:
	var port := PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.get_slice("=", 1))
		elif a.begins_with("--wins="):
			settings.wins = int(a.get_slice("=", 1))
		elif a.begins_with("--source="):
			settings.source = a.get_slice("=", 1)
		elif a.begins_with("--difficulty="):
			settings.difficulty = float(a.get_slice("=", 1))
	Game.settings.player_name = "Dedicated"
	host(port, true)
	print("Ultimate Grapple dedicated server on port %d. First to %d. Source: %s" % [port, settings.wins, settings.source])


func _on_connected() -> void:
	in_lobby = true
	_set_status("Connected")
	rpc_id(1, "register", _my_info())


func _on_failed() -> void:
	_set_status("Connection failed")
	leave()


func _on_server_gone() -> void:
	_set_status("Server closed the connection")
	var was_racing := round_active
	leave()
	if was_racing or Game.current_scene and Game.current_scene.has_method("restart"):
		Game.goto_menu("multi")


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var n: String = players[id].name
		players.erase(id)
		_set_status("%s left" % n)
	var lvl = _level()
	if lvl:
		lvl.remove_remote_ghost(id)
	if is_server():
		if dedicated and players.is_empty():
			# everyone left: drop the set so the next group starts fresh
			round_active = false
			set_winner = -1
			_round_timer = -1.0
		_push_lobby()
		_check_round_complete()


@rpc("any_peer", "reliable")
func register(info: Dictionary) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	info.wins = 0
	info.ready = false
	info.name = str(info.get("name", "Runner")).substr(0, 16)
	info.color = posmod(int(info.get("color", 0)), 8)
	_join_seq += 1
	info.order = _join_seq
	players[id] = info
	_set_status("%s joined" % info.name)
	_push_lobby()


func _push_lobby() -> void:
	rpc("sync_lobby", players, settings, round_active)


@rpc("authority", "call_local", "reliable")
func sync_lobby(p: Dictionary, s: Dictionary, active: bool) -> void:
	players = p
	settings = s
	round_active = active
	lobby_changed.emit()


@rpc("any_peer", "call_local", "reliable")
func set_ready(r: bool) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id].ready = r
		_push_lobby()


func toggle_ready() -> void:
	var me: Dictionary = players.get(my_id(), {})
	var want: bool = not me.get("ready", false)
	if is_server():
		set_ready(want)
	else:
		rpc_id(1, "set_ready", want)


## Who may change settings and start a set: the host on a listen server,
## the player who has been connected longest on a dedicated one.
func leader_id() -> int:
	var best := -1
	var best_order := 0
	for id in players:
		var o := int(players[id].get("order", 0))
		if best == -1 or o < best_order:
			best = int(id)
			best_order = o
	return best


func is_leader() -> bool:
	return peer != null and leader_id() == my_id()


func update_settings(s: Dictionary) -> void:
	if is_server():
		_apply_settings(s)
	elif is_leader():
		rpc_id(1, "request_settings", s)


func _apply_settings(s: Dictionary) -> void:
	# clients can send anything: only take known keys, clamped
	if s.has("wins"):
		settings.wins = clampi(int(s.wins), 1, 15)
	if s.has("source") and str(s.source) in ["random", "pinned"]:
		settings.source = str(s.source)
	if s.has("difficulty"):
		settings.difficulty = clampf(float(s.difficulty), 0.0, 1.0)
	if s.has("length"):
		settings.length = clampi(int(s.length), 4, 30)
	if s.has("theme") and (str(s.theme) == "" or Themes.THEMES.has(str(s.theme))):
		settings.theme = str(s.theme)
	_push_lobby()


@rpc("any_peer", "reliable")
func request_settings(s: Dictionary) -> void:
	if is_server() and multiplayer.get_remote_sender_id() == leader_id() and not round_active:
		_apply_settings(s)


func request_start() -> void:
	if is_server():
		start_set()
	elif is_leader():
		rpc_id(1, "remote_start")


@rpc("any_peer", "reliable")
func remote_start() -> void:
	if is_server() and multiplayer.get_remote_sender_id() == leader_id() and not round_active:
		start_set()


# ================================================================ rounds

func start_set() -> void:
	if not is_server() or players.is_empty():
		return
	for id in players:
		players[id].wins = 0
	set_winner = -1
	round_idx = 0
	_start_round()


func _start_round() -> void:
	var data: Dictionary
	if settings.source == "pinned":
		var pool := Game.list_pinned_levels()
		if pool.is_empty():
			data = Game.generate_level(randi() % 1000000, settings.theme, settings.difficulty, settings.length)
		else:
			data = pool[round_idx % pool.size()]
	else:
		data = Game.generate_level(randi() % 1000000, settings.theme, settings.difficulty, settings.length)
	var raw := JSON.stringify(data).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	round_active = true
	round_winner = -1
	round_results = {}
	_round_timer = -1.0
	_set_status("Round %d: %s" % [round_idx + 1, data.get("name", "")])
	rpc("begin_round", packed, raw.size(), round_idx, players)


@rpc("authority", "call_local", "reliable")
func begin_round(packed: PackedByteArray, size: int, idx: int, p: Dictionary) -> void:
	players = p
	round_idx = idx
	round_active = true
	round_winner = -1
	round_results = {}
	set_winner = -1
	next_round_at = -1.0
	if dedicated:
		return
	var txt := packed.decompress(size, FileAccess.COMPRESSION_ZSTD).get_string_from_utf8()
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		_set_status("Bad level data from server")
		return
	var lvl = Game.play_level(data, "multi")
	for id in players:
		if id != my_id():
			var info: Dictionary = players[id]
			lvl.add_remote_ghost(id, info.name, Game.player_palette(int(info.color)))
	lvl.start_countdown(3.0)
	Sfx.play("beep")


func send_state(frame: Array) -> void:
	_last_frame = frame
	_send_accum += 1.0 / Engine.physics_ticks_per_second
	if _send_accum >= 1.0 / STATE_HZ and peer:
		_send_accum = 0.0
		rpc("state", frame)


@rpc("any_peer", "unreliable_ordered")
func state(frame: Array) -> void:
	var lvl = _level()
	if lvl:
		lvl.remote_state(multiplayer.get_remote_sender_id(), frame)


## Versus contacts. The attacker's client spots the contact against its view
## of the victim's ghost; the victim's client checks the attacker really is
## near in its own view (lag allowance) before applying it.
func send_tackle(to_id: int, dir: float) -> void:
	if peer:
		rpc_id(to_id, "net_tackle", dir)


@rpc("any_peer", "reliable")
func net_tackle(dir: float) -> void:
	var lvl = _level()
	if lvl == null or lvl.runners.is_empty():
		return
	var from := multiplayer.get_remote_sender_id()
	var g = lvl.remote_ghosts.get(from)
	var r = lvl.runners[0]
	if g == null or g.position.distance_to(r.player.global_position) > 180.0:
		return
	r.on_tackled_by(str(players.get(from, {}).get("name", "")), signf(dir))


## Our disc hit theirs (as we saw it): `seen` is where their disc was in our
## view, `pos`/`vel` our disc at the hit.
func send_clash(to_id: int, seen: Vector2, pos: Vector2, vel: Vector2) -> void:
	if peer:
		rpc_id(to_id, "net_clash", seen, pos, vel)


@rpc("any_peer", "reliable")
func net_clash(seen: Vector2, pos: Vector2, vel: Vector2) -> void:
	var lvl = _level()
	if lvl == null or lvl.runners.is_empty():
		return
	var d = lvl.runners[0].disc
	# their view lags ours: our disc only has to be near where they saw it
	if d.global_position.distance_to(seen) > 400.0 or seen.distance_to(pos) > 120.0:
		return
	var n := seen - pos
	n = n.normalized() if n.length() > 0.001 else Vector2.UP
	# their disc hit ours: apply our half (unless we already saw the same hit)
	d.clash_hit(n, vel.limit_length(3000.0))


## Our disc hit their runner (as we saw them).
func send_disc_hit(to_id: int, zone: String, vel: Vector2, at: Vector2) -> void:
	if peer:
		rpc_id(to_id, "net_disc_hit", zone, vel, at)


@rpc("any_peer", "reliable")
func net_disc_hit(zone: String, vel: Vector2, at: Vector2) -> void:
	var lvl = _level()
	if lvl == null or lvl.runners.is_empty() or not zone in ["head", "arm", "leg"]:
		return
	var r = lvl.runners[0]
	# their view of us lags a little: the disc only has to be near us
	if at.distance_to(r.player.center()) > 220.0:
		return
	var from := multiplayer.get_remote_sender_id()
	r.on_disc_hit_by(str(players.get(from, {}).get("name", "")), zone, vel.limit_length(3000.0))


func report_finish(t: float, throws: int) -> void:
	if is_server():
		finish(t, throws)
	else:
		rpc_id(1, "finish", t, throws)


@rpc("any_peer", "reliable")
func finish(t: float, _throws: int) -> void:
	if not is_server() or not round_active:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if round_results.has(id) or not players.has(id):
		return
	round_results[id] = t
	if round_winner == -1:
		round_winner = id
		players[id].wins = int(players[id].wins) + 1
		if int(players[id].wins) >= int(settings.wins):
			set_winner = id
		_round_timer = ROUND_BREAK + 3.0
	rpc("round_update", players, round_winner, round_results, set_winner, _round_timer)
	_check_round_complete()


func _check_round_complete() -> void:
	if not is_server() or not round_active or round_winner == -1:
		return
	if round_results.size() >= players.size():
		_round_timer = minf(_round_timer, ROUND_BREAK)
		rpc("round_update", players, round_winner, round_results, set_winner, _round_timer)


@rpc("authority", "call_local", "reliable")
func round_update(p: Dictionary, winner: int, results: Dictionary, s_winner: int, next_in: float) -> void:
	var first := round_winner == -1 and winner != -1
	players = p
	round_winner = winner
	round_results = results
	set_winner = s_winner
	next_round_at = Time.get_ticks_msec() / 1000.0 + next_in
	var lvl = _level()
	if first and lvl and players.has(winner):
		var who: String = "YOU" if winner == my_id() else str(players[winner].name)
		lvl.hud.popup("%s SANK IT FIRST!" % who, Color(2.2, 1.8, 0.3), 2.5)
		Sfx.play("fanfare" if winner == my_id() else "chains")
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func set_over(winner: int, p: Dictionary) -> void:
	players = p
	round_active = false
	var who: String = str(players.get(winner, {}).get("name", "?"))
	champion_text = "%s WINS THE SET!" % who
	for id in players:
		players[id].ready = false
	if not dedicated:
		Game.goto_menu("multi")
	lobby_changed.emit()


func _process(dt: float) -> void:
	_poll_discovery()
	if _bcast:
		_bcast_t -= dt
		if _bcast_t <= 0.0:
			_bcast_t = 1.0
			_broadcast()
	if is_server() and round_active and _round_timer > 0.0:
		_round_timer -= dt
		if _round_timer <= 0.0:
			_round_timer = -1.0
			if set_winner != -1:
				round_active = false
				rpc("set_over", set_winner, players)
			else:
				round_idx += 1
				_start_round()
	if is_server() and dedicated and not round_active and players.size() >= 2:
		var all_ready := true
		for id in players:
			if not players[id].get("ready", false):
				all_ready = false
		if all_ready:
			start_set()


func _level():
	var s = Game.current_scene
	if s and is_instance_valid(s) and s.has_method("remote_state"):
		return s
	return null


func scoreboard_text() -> String:
	var ids := players.keys()
	ids.sort_custom(func(a, b): return int(players[a].wins) > int(players[b].wins))
	var lines := ["FIRST TO %d" % int(settings.wins)]
	for id in ids:
		var p: Dictionary = players[id]
		var stars := ""
		for i in int(settings.wins):
			stars += "●" if i < int(p.wins) else "○"
		var t := ""
		if round_results.has(id):
			t = "  " + Game.format_time(float(round_results[id]))
		lines.append("%s %-12s%s%s" % [stars, str(p.name).substr(0, 12), t, "  <" if id == my_id() else ""])
	return "\n".join(lines)


func waiting_text() -> String:
	if round_winner == -1 or next_round_at < 0.0:
		return ""
	var left := maxf(0.0, next_round_at - Time.get_ticks_msec() / 1000.0)
	var who: String = str(players.get(round_winner, {}).get("name", "?"))
	if set_winner != -1:
		return "%s TAKES THE SET  ·  back to lobby in %d" % [who, int(ceil(left))]
	return "%s won round %d  ·  next course in %d" % [who, round_idx + 1, int(ceil(left))]


# ================================================================ LAN discovery

func _start_broadcast(port: int) -> void:
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	set_meta("port", port)


func _broadcast() -> void:
	var msg := JSON.stringify({"g": "ugrapple", "n": str(Game.settings.player_name) + ("'s server" if not dedicated else " server"), "p": get_meta("port", PORT), "c": players.size()})
	_bcast.put_packet(msg.to_utf8_buffer())


func start_discovery() -> void:
	if _listen:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null


func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null


func _poll_discovery() -> void:
	if _listen == null:
		return
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if d is Dictionary and d.get("g", "") == "ugrapple":
			var key := "%s:%d" % [ip, int(d.get("p", PORT))]
			servers[key] = {"name": d.get("n", "?"), "count": int(d.get("c", 0)), "t": Time.get_ticks_msec()}
			changed = true
	var now := Time.get_ticks_msec()
	for k in servers.keys():
		if now - servers[k].t > 4000:
			servers.erase(k)
			changed = true
	if changed:
		servers_changed.emit()
