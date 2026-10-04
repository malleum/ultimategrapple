extends RefCounted
## Local play stats (user://stats.json): time played in chrons (1 chron =
## 1% of a day = 14.4 min), and counters for everything a runner does, fed
## by the local runner's events (Runner hooks note()/sample()). Per course:
## attempts, clears, time played, deaths and throws; the built-in courses'
## attempts / clears / time also go to the online leaderboard.

const PATH := "user://stats.json"
## Off in headless runs (tests / the server) unless a test turns it on.
static var enabled: bool = DisplayServer.get_name() != "headless"
static var path := PATH
const CHRON := 864.0            # seconds
const PX_PER_M := 32.0
const MAX_LEVELS := 400         # per-course entries kept (least played dropped)

static var data := {}
static var _loaded := false
static var _dirty := false
static var _save_t := 0.0


## Start over from `p` (tests).
static func use_file(p: String) -> void:
	path = p
	_loaded = false
	_dirty = false
	data = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	data = d if d is Dictionary else {}
	if not data.get("g") is Dictionary:
		data["g"] = {}
	if not data.get("lv") is Dictionary:
		data["lv"] = {}


static func g() -> Dictionary:
	_ensure()
	return data.g


static func level(id: String) -> Dictionary:
	_ensure()
	var lv: Dictionary = data.lv
	if not lv.get(id) is Dictionary:
		lv[id] = {"att": 0, "comp": 0, "play": 0.0, "deaths": 0, "throws": 0}
	return lv[id]


static func add(key: String, n := 1.0) -> void:
	var gg := g()
	gg[key] = float(gg.get(key, 0.0)) + n
	_dirty = true


static func most(key: String, v: float) -> void:
	var gg := g()
	if v > float(gg.get(key, 0.0)):
		gg[key] = v
		_dirty = true


static func add_level(id: String, key: String, n := 1.0, name := "") -> void:
	if id == "":
		return
	var e := level(id)
	e[key] = float(e.get(key, 0.0)) + n
	if name != "":
		e["name"] = name
	_dirty = true


static func get_n(key: String) -> float:
	return float(g().get(key, 0.0))


static func chrons(seconds: float) -> float:
	return seconds / CHRON


## "3.42" (truncated, like every other number on screen)
static func chron_text(seconds: float) -> String:
	var c := int(floor(chrons(seconds) * 100.0 + 0.0001))
	return "%d.%02d" % [c / 100, c % 100]


## Save now and then (and when asked to); cheap to call every frame.
static func tick(dt: float) -> void:
	_save_t += dt
	if _dirty and _save_t > 30.0:
		save()


static func save() -> void:
	if not _loaded or not _dirty:
		return
	_save_t = 0.0
	_dirty = false
	var lv: Dictionary = data.lv
	if lv.size() > MAX_LEVELS:
		var ids := lv.keys()
		ids.sort_custom(func(a, b): return float(lv[a].get("play", 0.0)) > float(lv[b].get("play", 0.0)))
		for id in ids.slice(MAX_LEVELS):
			lv.erase(id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## Per-course numbers for the online board: attempts, clears, seconds played.
static func board_stats(id: String) -> Dictionary:
	var e := level(id)
	return {"att": int(e.get("att", 0)), "comp": int(e.get("comp", 0)), "play": snappedf(float(e.get("play", 0.0)), 0.1)}


## Every stat for the STATS page: [[section, [[label, value text], ...]], ...]
static func sections() -> Array:
	var n := func(k: String) -> String: return _num(get_n(k))
	var att := get_n("attempts")
	var comp := get_n("completions")
	var snaps := get_n("snap_perfect") + get_n("snap_good") + get_n("snap_none")
	var throws := get_n("throws")
	var out: Array = []
	out.append(["TIME", [
		["Chrons played", chron_text(get_n("play_s"))],
		["Real time", _hms(get_n("play_s"))],
		["Chrons airborne", chron_text(get_n("air_s"))],
		["Chrons swinging", chron_text(get_n("swing_s"))],
	]])
	out.append(["COURSES", [
		["Attempts", n.call("attempts")],
		["Clears", n.call("completions")],
		["Clear rate", "%d%%" % int(100.0 * comp / att) if att > 0.0 else "-"],
		["Restarts", n.call("restarts")],
		["Personal bests", n.call("pbs")],
		["Ace medals", n.call("medal_ace")],
		["Gold medals", n.call("medal_gold")],
		["Silver / bronze", "%s / %s" % [n.call("medal_silver"), n.call("medal_bronze")]],
	]])
	out.append(["MOVEMENT", [
		["Distance run", "%.2f km" % (get_n("run_px") / PX_PER_M / 1000.0)],
		["Top speed", "%.1f m/s" % (get_n("top_speed") / PX_PER_M)],
		["Jumps", n.call("jumps")],
		["Double jumps", n.call("airjumps")],
		["Wall jumps", n.call("walljumps")],
		["Ledge mantles", n.call("mantles")],
		["Slides", n.call("slides")],
		["Pad launches", n.call("pads")],
		["Pivot launches", n.call("pivot_launches")],
		["Longest airtime", "%.2f s" % get_n("longest_air")],
	]])
	out.append(["GRAPPLE", [
		["Grapples", n.call("grapples")],
		["Zips", n.call("zips")],
		["Rope wraps", n.call("wraps")],
		["Boosts", n.call("boosts")],
	]])
	out.append(["DISC", [
		["Throws", n.call("throws")],
		["Backhand / forehand", "%s / %s" % [n.call("throw_backhand"), n.call("throw_forehand")]],
		["Hammer / roller", "%s / %s" % [n.call("throw_hammer"), n.call("throw_roller")]],
		["Scoober / thumber", "%s / %s" % [n.call("throw_scoober"), n.call("throw_thumber")]],
		["Favourite throw", _favourite()],
		["Perfect snaps", n.call("snap_perfect")],
		["Frame-perfect snaps", n.call("snap_frame")],
		["Snap accuracy", "%d%%" % int(100.0 * get_n("snap_perfect") / snaps) if snaps > 0.0 else "-"],
		["Longest throw", "%.1f m" % (get_n("longest_throw") / PX_PER_M)],
		["Longest flight", "%.2f s" % get_n("longest_flight")],
		["Chains hit", n.call("chains")],
		["Spit out", n.call("spit_outs")],
		["Skips", n.call("skips")],
		["Sky catches", n.call("sky_catches")],
		["Catches", n.call("catches")],
		["Recalls", n.call("recalls")],
		["Out of bounds", n.call("oob")],
		["Glass shattered", n.call("glass")],
		["Gates opened", n.call("gates")],
		["Throws per clear", "%.1f" % (throws / comp) if comp > 0.0 else "-"],
	]])
	out.append(["MISHAPS", [
		["Deaths", n.call("deaths")],
		["Hazards", n.call("death_hazard")],
		["Falls", n.call("death_fall")],
		["Got tackled", n.call("tackled")],
		["Hit by discs", n.call("disc_hit")],
	]])
	out.append(["VERSUS", [
		["Rounds raced", n.call("rounds")],
		["Rounds won", n.call("rounds_won")],
		["Tackles landed", n.call("tackles")],
		["Disc clashes", n.call("clashes")],
	]])
	return out


static func _favourite() -> String:
	var best := ""
	var most_n := 0.0
	for t in ["backhand", "forehand", "hammer", "roller", "scoober", "thumber"]:
		if get_n("throw_" + t) > most_n:
			most_n = get_n("throw_" + t)
			best = t
	return best.capitalize() if best != "" else "-"


static func _num(v: float) -> String:
	var i := int(v)
	var s := str(i)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _hms(sec: float) -> String:
	var t := int(sec)
	return "%dh %02dm" % [t / 3600, (t / 60) % 60] if t >= 3600 else "%dm %02ds" % [t / 60, t % 60]
