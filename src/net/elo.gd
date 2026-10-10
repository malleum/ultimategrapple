extends Node
## ELO run client. One generated course per game, each seed handed out by the
## ELO web service (not the ENet race server): one run per seed, ever. A
## restart, quit or crash on an open game is a DNF. Seeds already played by
## others come with the best / median / worst ghost to race.
##
## Auth is an ELO-only identity (user://elo_id.json, made on first use): X-UG-Uid /
## X-UG-Key headers, X-UG-Name percent-encoded. Never the Online key: the ELO
## service is run by someone else, and that key signs leaderboard runs. Contract: POST next-seed, POST submit,
## GET ghost/<run_id>, GET rating, GET ladder.
##
## Every call takes a callback and calls it once: cb(ok: bool, data: Dictionary).
## On failure data = {"code": http status or 0, "error": str, "message": str}.

const LevelGen = preload("res://src/level/generator.gd")

const BASE_URL := "https://rhysfuller.com/ug"
const STATE_PATH := "user://elo.json"
const ID_PATH := "user://elo_id.json"
const TIMEOUT := 20.0
const GZIP_OVER := 4096          # request bodies bigger than this are gzipped
const SET_SIZE := 3

var base_url := BASE_URL
var uid := ""                    # ELO identity, separate from Online.uid
var _key := ""
var open := {}                   # the game being played: {run_id, game_number, seed, ..., ghosts: [...]}
var unsent := {}                 # a result the service has not acknowledged yet (submit body)
var last_result := {}            # the latest submit answer
var _request_id := ""            # reused until next-seed answers, so a retry never burns a seed
var _busy := false
var _sending := false
var _waiters: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--elo-url="):
			base_url = a.get_slice("=", 1).trim_suffix("/")
	if Game.server_mode:
		return
	_load_identity()
	_load_state()
	recover()


# ------------------------------------------------------------------ versions

static func versions() -> Dictionary:
	return {"gen_version": LevelGen.VERSION, "replay_version": Game.REPLAY_VERSION, "board_version": Game.BOARD_VERSION}


static func set_of(game_number: int) -> int:
	return int(ceil(float(game_number) / SET_SIZE))


static func set_position(game_number: int) -> int:
	return (game_number - 1) % SET_SIZE + 1


# ------------------------------------------------------------------ games

## Ask for the next seed (plus ghosts, downloaded). cb(true, game) where game =
## the service's answer + "ghost_runs": [{role, name, color, time, frames}].
func next_game(cb: Callable) -> void:
	if _busy:
		_done(cb, false, {"message": "Already waiting for the service"})
		return
	_busy = true
	if not unsent.is_empty():
		# the open game's result is still ours to deliver; asking for a new seed first would DNF it
		_send_unsent(func(ok: bool, d: Dictionary):
			if ok:
				_request_game(cb)
			else:
				_busy = false
				d["message"] = "Couldn't send your last result yet. " + str(d.get("message", ""))
				_done(cb, false, d))
		return
	_request_game(cb)


func _request_game(cb: Callable) -> void:
	if _request_id == "":
		_request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var body := {"request_id": _request_id}
	body.merge(versions())
	_call(HTTPClient.METHOD_POST, "/next-seed", body, func(ok: bool, d: Dictionary):
		if not ok:
			_busy = false
			_done(cb, false, d)
			return
		_request_id = ""
		if str(d.get("run_id", "")) == "" or not d.has("seed"):
			_busy = false
			_done(cb, false, {"code": 0, "error": "bad_answer", "message": "The service sent something unexpected"})
			return
		d["issued_msec"] = Time.get_ticks_msec()
		open = d.duplicate(true)
		open.erase("ghost_runs")
		_save_state()
		_fetch_ghosts(d, func():
			_busy = false
			_done(cb, true, d)))


func _fetch_ghosts(game: Dictionary, then: Callable) -> void:
	var list: Array = game.get("ghosts", []) if game.get("ghosts") is Array else []
	game["ghost_runs"] = []
	if list.is_empty():
		then.call()
		return
	var left := [list.size()]
	var slots: Array = []
	slots.resize(list.size())
	for i in list.size():
		var g: Dictionary = list[i] if list[i] is Dictionary else {}
		var rid := str(g.get("run_id", ""))
		_call(HTTPClient.METHOD_GET, "/ghost/" + rid.uri_encode(), null, func(ok: bool, d: Dictionary):
			if ok:
				var frames := frames_of(d)
				if frames.size() >= 3:
					slots[i] = {"roles": g.get("roles", [g.get("role", "")]), "name": str(g.get("name", d.get("name", "Runner"))),
						"color": color_of(g.get("color", d.get("color", ""))), "time": float(g.get("time", d.get("time", 0.0))), "frames": frames}
			left[0] -= 1
			if left[0] == 0:
				for s in slots:
					if s != null:
						(game.ghost_runs as Array).append(s)
				then.call())


## Ghost frames out of a stored run ({"run": {"frames": [...]}} or the run itself).
static func frames_of(d: Dictionary) -> Array:
	var run = d.get("run", d)
	if run is Dictionary and run.get("frames") is Array:
		return run.frames
	return []


static func color_of(v) -> Color:
	var s := str(v)
	if s.is_valid_html_color():
		return Color(s)
	return Color(1.0, 0.6, 0.2)


## Rival dict for Level (first ghost + .more) from fetched ghost runs, best first.
static func rival_from(ghost_runs: Array) -> Dictionary:
	var order := ["best", "median", "worst"]
	var items: Array = []
	for g in ghost_runs:
		var role := ""
		for o in order:
			if o in (g.get("roles", []) as Array):
				role = o
				break
		items.append({"frames": g.frames, "name": "%s %s" % [str(g.name), role.to_upper()] if role != "" else str(g.name),
			"time": float(g.time), "color": g.color, "no_pb": true, "_o": order.find(role) if role != "" else 9})
	items.sort_custom(func(a, b): return int(a._o) < int(b._o))
	if items.is_empty():
		return {}
	var first: Dictionary = items[0]
	first["more"] = items.slice(1)
	return first


# ------------------------------------------------------------------ results

## The run is over (scored). Sends it; cb(ok, result) with the rating change.
func submit_finish(run_id: String, time: float, throws: int, penalty: float, deaths: int, splits: Array, color: Color,
		frames: Array, replay_blob: String, cb: Callable) -> void:
	var body := {"run_id": run_id, "status": "finished", "time": snappedf(time, 0.001), "throws": throws,
		"penalty": snappedf(penalty, 0.001), "deaths": deaths,
		"splits": splits.slice(0, 16).map(func(s): return snappedf(float(s), 0.001)),
		"color": "#" + color.to_html(false), "run": {"frames": frames, "replay": replay_blob, "v": Game.REPLAY_VERSION}}
	body.merge(versions())
	_close(body, cb)


## Give up the open game (restart, quit): scored as a DNF.
func forfeit(cb := Callable()) -> void:
	if open.is_empty():
		return
	var body := {"run_id": str(open.run_id), "status": "dnf"}
	body.merge(versions())
	_close(body, cb)


func is_open() -> bool:
	return not open.is_empty()


func _close(body: Dictionary, cb: Callable) -> void:
	open = {}
	unsent = body
	_save_state()
	_send_unsent(func(ok: bool, d: Dictionary):
		if ok:
			last_result = d
		_done(cb, ok, d))


func _send_unsent(cb: Callable) -> void:
	if unsent.is_empty():
		_done(cb, true, {})
		return
	_waiters.append(cb)
	if _sending:
		return   # one submit at a time; this caller gets the same answer
	_sending = true
	var body := unsent.duplicate()
	_call(HTTPClient.METHOD_POST, "/submit", body, func(ok: bool, d: Dictionary):
		# a rejected result (not_open: the service already closed it) is final; only network trouble keeps it
		if ok or (int(d.get("code", 0)) >= 400 and int(d.get("code", 0)) < 500 and int(d.get("code", 0)) != 429):
			if unsent.get("run_id", "") == body.run_id:
				unsent = {}
				_save_state()
		_sending = false
		var ws := _waiters
		_waiters = []
		for w in ws:
			_done(w, ok, d))


## Startup / menu: deliver anything left over from a crash or a lost connection.
func recover() -> void:
	if not open.is_empty() and unsent.is_empty():
		# the game died with the app: that run is a DNF
		forfeit()
		return
	if not unsent.is_empty():
		_send_unsent(Callable())


# ------------------------------------------------------------------ rating / ladder

func fetch_rating(cb: Callable) -> void:
	_call(HTTPClient.METHOD_GET, "/rating", null, cb)


func fetch_ladder(limit: int, cb: Callable) -> void:
	_call(HTTPClient.METHOD_GET, "/ladder?limit=%d" % limit, null, cb)


# ------------------------------------------------------------------ http

func my_name() -> String:
	var n := str(Game.settings.get("player_name", "Runner")).strip_edges().substr(0, 24)
	return n if n != "" else "Runner"


func _done(cb: Callable, ok: bool, d: Dictionary) -> void:
	if cb.is_valid():
		cb.call(ok, d)


func _call(method: int, path: String, body, cb: Callable) -> void:
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT
	add_child(h)
	var headers := PackedStringArray(["X-UG-Uid: " + uid, "X-UG-Key: " + _key,
		"X-UG-Name: " + my_name().uri_encode(), "Accept: application/json"])
	var raw := PackedByteArray()
	if body != null:
		raw = JSON.stringify(body).to_utf8_buffer()
		headers.append("Content-Type: application/json")
		if raw.size() > GZIP_OVER:
			raw = raw.compress(FileAccess.COMPRESSION_GZIP)
			headers.append("Content-Encoding: gzip")
	h.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray):
		h.queue_free()
		var parsed = JSON.parse_string(resp.get_string_from_utf8()) if resp.size() > 0 else null
		var d: Dictionary = parsed if parsed is Dictionary else {}
		if result != HTTPRequest.RESULT_SUCCESS:
			_done(cb, false, {"code": 0, "error": "network", "message": "Can't reach the ELO service"})
		elif code >= 200 and code < 300:
			_done(cb, true, d)
		else:
			d["code"] = code
			if not d.has("message"):
				d["message"] = "Update the game to play ELO runs" if code == 426 else "The ELO service said %d" % code
			_done(cb, false, d))
	var err := h.request_raw(base_url + path, headers, method, raw)
	if err != OK:
		h.queue_free()
		_done.call_deferred(cb, false, {"code": 0, "error": "network", "message": "Can't reach the ELO service"})


# ------------------------------------------------------------------ persistence

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


func _load_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary:
		open = d.get("open", {}) if d.get("open") is Dictionary else {}
		unsent = d.get("unsent", {}) if d.get("unsent") is Dictionary else {}
		_request_id = str(d.get("request_id", ""))


func _save_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"open": open, "unsent": unsent, "request_id": _request_id}))
