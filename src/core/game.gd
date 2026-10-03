extends Node
## Global game state: settings, save data, input map, scene flow.

const LevelGen = preload("res://src/level/generator.gd")
const LevelScript = preload("res://src/level/level.gd")
const MenuScript = preload("res://src/ui/menu.gd")
const Bindings = preload("res://src/core/bindings.gd")

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const PINNED_USER_DIR := "user://pinned"
const GHOST_DIR := "user://ghosts"
const REPLAY_DIR := "user://replays"
const REPLAY_INDEX := "user://replays/index.json"
const RECENT_PATH := "user://recent.json"
const RECENT_MAX := 40
## Bump when movement / physics / input layout change: older replays can't
## re-simulate faithfully any more. 2: no dash, double jump, faster running.
const REPLAY_VERSION := 5   # 3: bigger basket, 3x air pivot; 4: speeds, mantle, smoother jumps; 5: slower zip, rope through platforms
const ReplayInput = preload("res://src/core/replay_input.gd")
const GENERATOR_VERSION := 1

signal settings_changed
## MP4 export progress for the replays menu / replay HUD.
signal export_status(text: String, done: bool)

var main: Node = null
var current_scene: Node = null

var settings := {
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"fullscreen": false,
	"vsync": false,
	"max_fps": 0,
	"show_ghost": true,
	"screen_shake": 1.0,
	"player_name": "Runner",
	"player_color": 0,
	"bindings": {},
	"online_server": "joshammer.com",
	"disc_cam_lock": true,
	"rumble": 1.0,           # controller vibration strength (0 = off)   # finish replay: the disc stays level and the world turns
}

## level_id -> {time: float, throws: int, medal: String}
var records := {}

var server_mode := false  # headless dedicated server
var render_mode := false  # rendering a replay to video (no menus, no saving)

## What "NEXT" does after a finish: {"kind": "random", ...} or {"kind": "pinned", "index": i}
var session := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	Bindings.load_from(settings.bindings)
	_load_records()
	DirAccess.make_dir_recursive_absolute(PINNED_USER_DIR)
	get_tree().root.files_dropped.connect(_on_files_dropped)
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var args := OS.get_cmdline_user_args()
	server_mode = args.has("--server")
	apply_settings()


# ---------------------------------------------------------------- input map

## Rebind from the menu, then call this to persist.
func save_bindings() -> void:
	settings.bindings = Bindings.to_dict()
	save_settings()


# ---------------------------------------------------------------- settings

func _load_json(path: String, fallback):
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var data = JSON.parse_string(f.get_as_text())
	return fallback if data == null else data


func _save_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func _load_settings() -> void:
	var s = _load_json(SETTINGS_PATH, {})
	if s is Dictionary:
		for k in s:
			if settings.has(k):
				settings[k] = s[k]


func save_settings() -> void:
	_save_json(SETTINGS_PATH, settings)
	apply_settings()
	settings_changed.emit()


func apply_settings() -> void:
	if server_mode:
		return
	var win_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != win_mode:
		DisplayServer.window_set_mode(win_mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.max_fps)
	_set_bus_volume("Master", settings.master_volume)
	_set_bus_volume("Music", settings.music_volume)
	_set_bus_volume("SFX", settings.sfx_volume)


func _set_bus_volume(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func player_color() -> Color:
	return player_palette(int(settings.player_color))


static func player_palette(i: int) -> Color:
	var cols := [Color(0.2, 1.0, 0.9), Color(1.0, 0.3, 0.7), Color(1.0, 0.85, 0.2), Color(0.5, 0.6, 1.0),
		Color(0.4, 1.0, 0.3), Color(1.0, 0.5, 0.2), Color(0.8, 0.4, 1.0), Color(1, 1, 1)]
	return cols[posmod(i, cols.size())]


# ---------------------------------------------------------------- records

func _load_records() -> void:
	var r = _load_json(SAVE_PATH, {})
	records = r if r is Dictionary else {}


func submit_record(level_id: String, time: float, throws: int, medal: String) -> bool:
	var prev = records.get(level_id)
	var better: bool = prev == null or time < float(prev.time)
	if better:
		records[level_id] = {"time": time, "throws": throws, "medal": medal}
		_save_json(SAVE_PATH, records)
	return better


# ---------------------------------------------------------------- splits
# Per course: the PB run's cumulative split times and the best time ever for
# each segment ("gold"), LiveSplit style. Reset when the split count changes.

const SPLITS_PATH := "user://splits.json"
var _splits := {}
var _splits_loaded := false


func get_splits(level_id: String, n: int) -> Dictionary:
	if not _splits_loaded:
		_splits_loaded = true
		var d = _load_json(SPLITS_PATH, {})
		_splits = d if d is Dictionary else {}
	var e = _splits.get(level_id)
	if not e is Dictionary or int(e.get("n", 0)) != n:
		e = {"n": n, "pb": [], "gold": []}
		_splits[level_id] = e
	return e


## A segment was completed in `seg` seconds: keep it if it's the best yet.
func note_segment(level_id: String, n: int, i: int, seg: float) -> bool:
	var e := get_splits(level_id, n)
	var gold: Array = e.gold
	while gold.size() <= i:
		gold.append(-1.0)
	if float(gold[i]) < 0.0 or seg < float(gold[i]):
		gold[i] = seg
		return true
	return false


func set_pb_splits(level_id: String, n: int, times: Array) -> void:
	get_splits(level_id, n).pb = times.duplicate()


func save_splits() -> void:
	if _splits_loaded and not render_mode:
		_save_json(SPLITS_PATH, _splits)


func get_record(level_id: String):
	return records.get(level_id)


func save_ghost(level_id: String, frames: Array) -> void:
	_save_json(GHOST_DIR + "/" + level_id.validate_filename() + ".json", frames)


func load_ghost(level_id: String) -> Array:
	var g = _load_json(GHOST_DIR + "/" + level_id.validate_filename() + ".json", [])
	return g if g is Array else []


# ---------------------------------------------------------------- levels

## Returns array of level dictionaries: pinned (res://levels) + user pinned.
func list_pinned_levels() -> Array:
	var out := []
	var seen := {}
	for dir_path in ["res://levels", PINNED_USER_DIR]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		var files := d.get_files()
		files.sort()
		for fname in files:
			if not fname.ends_with(".json"):
				continue
			var data = _load_json(dir_path + "/" + fname, null)
			if data is Dictionary and data.has("solids"):
				if seen.has(data.get("id", "")):
					continue
				seen[data.get("id", "")] = true
				data["_builtin"] = dir_path == "res://levels"
				out.append(data)
	return out


func generate_level(seed_value: int, theme: String = "", difficulty: float = 0.5, length: int = 12) -> Dictionary:
	var gen := LevelGen.new()
	return gen.generate(seed_value, theme, difficulty, length)


## Save a level permanently. Tries the project folder (when running from source),
## always saves to user://pinned.
func pin_level(data: Dictionary) -> String:
	var copy := data.duplicate(true)
	copy.erase("_builtin")
	copy["pinned"] = true
	var fname: String = str(copy.get("id", "level")).validate_filename() + ".json"
	var user_path := PINNED_USER_DIR + "/" + fname
	_save_json(user_path, copy)
	var project_levels := ProjectSettings.globalize_path("res://levels")
	if DirAccess.dir_exists_absolute(project_levels) and not OS.has_feature("template"):
		var f := FileAccess.open(project_levels + "/" + fname, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(copy, "\t"))
			return project_levels + "/" + fname
	return ProjectSettings.globalize_path(user_path)


func is_pinned(level_id: String) -> bool:
	return FileAccess.file_exists(PINNED_USER_DIR + "/" + level_id.validate_filename() + ".json") \
		or FileAccess.file_exists("res://levels/" + level_id.validate_filename() + ".json")


# ---------------------------------------------------------------- scene flow

func change_scene(node: Node) -> void:
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = node
	get_tree().paused = false
	main.add_child(node)


func goto_menu(page: String = "title") -> void:
	Net.leave_if_solo()
	var m := MenuScript.new()
	m.start_page = page
	change_scene(m)


## mode: "solo" | "multi"
func play_level(data: Dictionary, mode: String = "solo", local_players: Array = [], replay: Dictionary = {}, rival: Dictionary = {}) -> Node:
	var lvl := LevelScript.new()
	lvl.level_data = data
	lvl.mode = mode
	lvl.local_players = local_players
	lvl.replay = replay
	lvl.rival = rival
	if mode == "solo":
		_note_recent(str(data.get("id", "")))
	change_scene(lvl)
	return lvl


# ---------------------------------------------------------------- replays
# The personal-best run of each course is kept as a replay: the course, the
# run's random seed and every tick of input, so playback re-simulates it and
# looks exactly like the run did (HUD, particles, sound), plus a keystroke
# overlay. Stored zstd-compressed with store_var (bit-exact floats).

func _replay_path(level_id: String) -> String:
	return REPLAY_DIR + "/" + level_id.validate_filename() + ".rep"


func save_replay(rep: Dictionary) -> void:
	var id: String = rep.level_id
	var f := FileAccess.open_compressed(_replay_path(id), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("could not save replay for %s" % id)
		return
	f.store_var(rep)
	f.close()
	var idx = _load_json(REPLAY_INDEX, {})
	if not idx is Dictionary:
		idx = {}
	idx[id] = {"name": rep.name, "theme": rep.theme, "time": rep.time, "medal": rep.medal, "date": rep.date, "v": rep.v}
	_save_json(REPLAY_INDEX, idx)


func load_replay(level_id: String) -> Dictionary:
	var path := _replay_path(level_id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	if not (v is Dictionary and v.has("input")) or int(v.get("v", 1)) != REPLAY_VERSION:
		return {}
	return v


func has_replay(level_id: String) -> bool:
	return FileAccess.file_exists(_replay_path(level_id))


## Saved replays, most recently played course first:
## [{id, name, theme, time, medal, date}]
func list_replays() -> Array:
	var idx = _load_json(REPLAY_INDEX, {})
	if not idx is Dictionary:
		return []
	var recent = _load_json(RECENT_PATH, [])
	if not recent is Array:
		recent = []
	var out := []
	for id in recent:
		if idx.has(id) and has_replay(id) and int(idx[id].get("v", 1)) == REPLAY_VERSION:
			var e: Dictionary = idx[id].duplicate()
			e["id"] = id
			out.append(e)
	var rest := []
	for id in idx:
		if not recent.has(id) and has_replay(id) and int(idx[id].get("v", 1)) == REPLAY_VERSION:
			var e2: Dictionary = idx[id].duplicate()
			e2["id"] = id
			rest.append(e2)
	rest.sort_custom(func(a, b): return int(a.get("date", 0)) > int(b.get("date", 0)))
	out.append_array(rest)
	return out


func delete_replay(level_id: String) -> void:
	DirAccess.remove_absolute(_replay_path(level_id))
	var idx = _load_json(REPLAY_INDEX, {})
	if idx is Dictionary and idx.has(level_id):
		idx.erase(level_id)
		_save_json(REPLAY_INDEX, idx)


func _note_recent(level_id: String) -> void:
	if level_id == "":
		return
	var recent = _load_json(RECENT_PATH, [])
	if not recent is Array:
		recent = []
	recent.erase(level_id)
	recent.push_front(level_id)
	while recent.size() > RECENT_MAX:
		recent.pop_back()
	_save_json(RECENT_PATH, recent)


func play_replay(level_id: String) -> bool:
	var rep := load_replay(level_id)
	if rep.is_empty():
		return false
	var who := {"input": ReplayInput.new(rep.input), "name": str(rep.get("player", "Runner")), "color": rep.get("color", player_color())}
	play_level(rep.level, "replay", [who], rep)
	return true


# ---------------------------------------------------------------- friends' runs
# SHARE FILE writes a personal-best replay (plus its ghost frames) as a .ugr
# file; a friend imports it (button, or drop the file on the window) and can
# race it as a named ghost on the same course, or watch it.

const RIVAL_DIR := "user://rivals"
const RIVAL_INDEX := "user://rivals/index.json"


func share_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if d == "":
		d = OS.get_environment("HOME")
	return d.path_join("Ultimate Grapple")


func export_run_file(level_id: String) -> String:
	var rep := load_replay(level_id)
	if rep.is_empty():
		export_status.emit("No replay saved for this course", true)
		return ""
	if not rep.has("ghost"):
		rep["ghost"] = load_ghost(level_id)
	DirAccess.make_dir_recursive_absolute(share_dir())
	var base := "%s %s %s" % [str(rep.name), format_time(float(rep.time)).replace(":", "m"), str(rep.get("player", "Runner"))]
	var path := share_dir().path_join(base.validate_filename().replace(" ", "_") + ".ugr")
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		export_status.emit("Could not write %s" % path, true)
		return ""
	rep["kind"] = "run"
	f.store_var(rep)
	f.close()
	export_status.emit("Saved %s. Send it to a friend: they drop it on the game window (or IMPORT) to race your ghost." % path, true)
	return path


## Import a friend's .ugr. Returns "" on success, else what went wrong.
func import_rival(path: String) -> String:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Could not open %s" % path.get_file()
	var v = f.get_var()   # no objects: plain data only
	f.close()
	if not (v is Dictionary and v.get("level") is Dictionary and v.has("time")):
		return "%s is not an Ultimate Grapple run" % path.get_file()
	var frames: Array = v.get("ghost", []) if v.get("ghost") is Array else []
	if frames.size() < 3:
		frames = ghost_from_track(v.get("track", PackedVector2Array()))
	if frames.size() < 3:
		return "%s has no ghost in it" % path.get_file()
	v["ghost"] = frames
	var lid := str(v.get("level_id", v.level.get("id", "course")))
	var who := str(v.get("player", "Friend"))
	var id := ("%s__%s" % [lid, who]).validate_filename().replace(" ", "_")
	DirAccess.make_dir_recursive_absolute(RIVAL_DIR)
	var out := FileAccess.open_compressed(RIVAL_DIR + "/" + id + ".ugr", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if out == null:
		return "Could not store the run"
	out.store_var(v)
	out.close()
	var idx = _load_json(RIVAL_INDEX, [])
	if not idx is Array:
		idx = []
	idx = idx.filter(func(e): return str(e.get("id", "")) != id)
	idx.push_front({"id": id, "name": str(v.get("name", "Course")), "player": who, "time": float(v.time),
		"theme": str(v.get("theme", "")), "level_id": lid, "date": int(Time.get_unix_time_from_system())})
	_save_json(RIVAL_INDEX, idx)
	return ""


## Ghost frames rebuilt from a replay's per-tick track (older files without
## ghost frames): position, velocity, disc position every 4 ticks.
func ghost_from_track(track) -> Array:
	var out: Array = []
	if not track is PackedVector2Array:
		return out
	var ticks := int(track.size() / 4)
	for k in range(0, ticks, 4):
		var p: Vector2 = track[k * 4]
		var v: Vector2 = track[k * 4 + 1]
		var d: Vector2 = track[k * 4 + 2]
		var dv: Vector2 = track[k * 4 + 3]
		var held := dv == Vector2.ZERO and d.distance_to(p) < 60.0
		var flags := (1 if absf(v.y) < 1.0 else 0) | (8 if held else 0)
		out.append([p.x, p.y, v.x, v.y, 1 if v.x >= 0.0 else -1, flags, 0.0, 0.0, d.x, d.y, 0 if held else 1])
	return out


func list_rivals() -> Array:
	var idx = _load_json(RIVAL_INDEX, [])
	if not idx is Array:
		return []
	return idx.filter(func(e): return e is Dictionary and FileAccess.file_exists(RIVAL_DIR + "/" + str(e.get("id", "")) + ".ugr"))


func load_rival(id: String) -> Dictionary:
	var f := FileAccess.open_compressed(RIVAL_DIR + "/" + id.validate_filename() + ".ugr", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	return v if v is Dictionary and v.get("level") is Dictionary else {}


func delete_rival(id: String) -> void:
	DirAccess.remove_absolute(RIVAL_DIR + "/" + id.validate_filename() + ".ugr")
	var idx = _load_json(RIVAL_INDEX, [])
	if idx is Array:
		_save_json(RIVAL_INDEX, idx.filter(func(e): return str(e.get("id", "")) != id))


## Play the friend's course with their run as a named ghost.
func race_rival(id: String) -> bool:
	var v := load_rival(id)
	if v.is_empty():
		return false
	var c = v.get("color", Color(1.0, 0.6, 0.2))
	var rival := {"frames": v.ghost, "name": str(v.get("player", "Friend")), "time": float(v.time),
		"color": c if c is Color else Color(1.0, 0.6, 0.2)}
	var data: Dictionary = v.level.duplicate(true)
	play_level(data, "solo", [], {}, rival)
	return true


## Watch the friend's run (when it was recorded with this replay version).
func watch_rival(id: String) -> bool:
	var v := load_rival(id)
	if v.is_empty() or int(v.get("v", 0)) != REPLAY_VERSION or not v.has("input"):
		return false
	var who := {"input": ReplayInput.new(v.input), "name": str(v.get("player", "Friend")), "color": v.get("color", Color(1, 0.6, 0.2))}
	play_level(v.level, "replay", [who], v)
	return true


func _on_files_dropped(files: PackedStringArray) -> void:
	var msgs: Array = []
	for fp in files:
		if fp.get_extension().to_lower() in ["ugr", "rep"]:
			var err := import_rival(fp)
			msgs.append(err if err != "" else "Imported %s" % fp.get_file())
	if msgs.is_empty():
		return
	export_status.emit("\n".join(msgs), true)
	if current_scene and current_scene.has_method("show_page"):
		current_scene.show_page("replays")


# ---------------------------------------------------------------- match recordings
# Every couch / online round (see Level.build_match): course + every runner's
# 30 Hz frames. Kept newest first, MATCH_MAX of them.

const MATCH_DIR := "user://replays/matches"
const MATCH_INDEX := "user://replays/matches.json"
const MATCH_MAX := 40


func save_match(rec: Dictionary) -> void:
	if render_mode:
		return
	DirAccess.make_dir_recursive_absolute(MATCH_DIR)
	var id := "m%d" % Time.get_unix_time_from_system()
	var idx = _load_json(MATCH_INDEX, [])
	if not idx is Array:
		idx = []
	while _has_match_id(idx, id):
		id += "b"
	rec["id"] = id
	var f := FileAccess.open_compressed(MATCH_DIR + "/" + id + ".rep", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("could not save match recording")
		return
	f.store_var(rec)
	f.close()
	var names: Array = []
	for r in rec.runners:
		names.append(str(r.name))
	idx.push_front({"id": id, "name": rec.name, "theme": rec.theme, "mode": rec.mode, "date": rec.date,
		"winner": rec.winner, "players": names})
	while idx.size() > MATCH_MAX:
		var old: Dictionary = idx.pop_back()
		DirAccess.remove_absolute(MATCH_DIR + "/" + str(old.id) + ".rep")
	_save_json(MATCH_INDEX, idx)


func _has_match_id(idx: Array, id: String) -> bool:
	for e in idx:
		if str(e.get("id", "")) == id:
			return true
	return false


## Saved match recordings, newest first: [{id, name, theme, mode, date, winner, players}]
func list_matches() -> Array:
	var idx = _load_json(MATCH_INDEX, [])
	if not idx is Array:
		return []
	var out: Array = []
	for e in idx:
		if e is Dictionary and FileAccess.file_exists(MATCH_DIR + "/" + str(e.get("id", "")) + ".rep"):
			out.append(e)
	return out


func load_match(id: String) -> Dictionary:
	var path := MATCH_DIR + "/" + id.validate_filename() + ".rep"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v = f.get_var()
	if not (v is Dictionary and v.get("kind", "") == "match" and v.has("runners") and v.has("level")):
		return {}
	return v


func delete_match(id: String) -> void:
	DirAccess.remove_absolute(MATCH_DIR + "/" + id.validate_filename() + ".rep")
	var idx = _load_json(MATCH_INDEX, [])
	if idx is Array:
		idx = idx.filter(func(e): return str(e.get("id", "")) != id)
		_save_json(MATCH_INDEX, idx)


func play_match(id: String) -> bool:
	var rec := load_match(id)
	if rec.is_empty():
		return false
	Net.leave_if_solo()
	play_level(rec.level, "match", [], rec)
	return true


# ---------------------------------------------------------------- MP4 export
# Renders the replay in a second copy of the game with Godot's movie maker
# (--write-movie: fixed 60 fps, every frame, game audio), then converts the
# AVI to an H.264/AAC MP4 with ffmpeg into ~/Videos/Ultimate Grapple/.

var _export := {}   # {stage, pid, id, avi, mp4}


func is_exporting() -> bool:
	return not _export.is_empty()


func videos_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if d == "":
		d = OS.get_environment("HOME").path_join("Videos")
	return d.path_join("Ultimate Grapple")


func export_replay_mp4(level_id: String) -> void:
	if is_exporting():
		export_status.emit("Already exporting a replay...", false)
		return
	var rep := load_replay(level_id)
	if rep.is_empty():
		export_status.emit("No replay saved for this course", true)
		return
	DirAccess.make_dir_recursive_absolute(videos_dir())
	var render_dir := OS.get_user_data_dir().path_join("render")
	DirAccess.make_dir_recursive_absolute(render_dir)
	var base := "%s %s" % [str(rep.name), format_time(float(rep.time)).replace(":", "m")]
	base = base.validate_filename().replace(" ", "_")
	var avi := render_dir.path_join(level_id.validate_filename() + ".avi")
	var mp4 := videos_dir().path_join(base + ".mp4")
	# reuse how this game was launched (--main-pack for nix run, --path from source)
	var args := PackedStringArray()
	var cl := OS.get_cmdline_args()
	for i in cl.size():
		if cl[i] in ["--main-pack", "--path"] and i + 1 < cl.size():
			args.append(cl[i])
			args.append(cl[i + 1])
	if args.is_empty() and not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--write-movie", avi, "--fixed-fps", "60", "--resolution", "1920x1080", "--", "--render-replay=" + level_id])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		export_status.emit("Could not start the renderer", true)
		return
	_export = {"stage": "render", "pid": pid, "id": level_id, "avi": avi, "mp4": mp4}
	export_status.emit("Rendering replay (a window opens and closes by itself)...", false)


func _poll_export() -> void:
	if _export.is_empty() or OS.is_process_running(int(_export.pid)):
		return
	match str(_export.stage):
		"render":
			if not FileAccess.file_exists(_export.avi):
				export_status.emit("Rendering failed (no video written)", true)
				_export = {}
				return
			var ff := PackedStringArray(["-y", "-loglevel", "error", "-i", _export.avi,
				"-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
				"-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", _export.mp4])
			var pid := OS.create_process("ffmpeg", ff)
			if pid <= 0:
				export_status.emit("ffmpeg not found. The raw video is at %s" % _export.avi, true)
				_export = {}
				return
			_export.stage = "encode"
			_export.pid = pid
			export_status.emit("Encoding MP4...", false)
		"encode":
			if FileAccess.file_exists(_export.mp4):
				DirAccess.remove_absolute(_export.avi)
				export_status.emit("Saved %s" % _export.mp4, true)
			else:
				export_status.emit("Encoding failed. The raw video is at %s" % _export.avi, true)
			_export = {}


func start_random(seed_value: int, theme: String, difficulty: float, length: int) -> void:
	session = {"kind": "random", "theme": theme, "difficulty": difficulty, "length": length}
	play_level(generate_level(seed_value, theme, difficulty, length))


func start_pinned(index: int) -> void:
	var levels := list_pinned_levels()
	if levels.is_empty():
		start_random(randi(), "", 0.5, 12)
		return
	index = posmod(index, levels.size())
	session = {"kind": "pinned", "index": index}
	play_level(levels[index])


func next_level() -> void:
	match session.get("kind", "random"):
		"pinned":
			start_pinned(int(session.index) + 1)
		_:
			start_random(randi() % 1000000, session.get("theme", ""), session.get("difficulty", 0.5), session.get("length", 12))


# ---------------------------------------------------------------- couch (local split-screen)

const PlayerInput = preload("res://src/core/player_input.gd")

## {"players": [{device, name, color, wins}], "wins": int, "source": String,
##  "difficulty": float, "round": int, "winner": int, "results": {}, "next_at": float}
var couch := {}
var couch_champion := ""
var couch_last_players: Array = []


func start_couch(players: Array, wins: int, source: String, difficulty: float) -> void:
	couch = {"players": players, "wins": wins, "source": source, "difficulty": difficulty,
		"round": 0, "winner": -1, "set_winner": -1, "results": {}, "next_at": -1.0, "champion": ""}
	for p in players:
		p.wins = 0
	_couch_round()


func _couch_round() -> void:
	couch.winner = -1
	couch.results = {}
	couch.next_at = -1.0
	var data: Dictionary
	var pool := list_pinned_levels()
	if couch.source == "pinned" and not pool.is_empty():
		data = pool[int(couch.round) % pool.size()]
	else:
		data = generate_level(randi() % 1000000, "", couch.difficulty, 10)
	var locals := []
	for p in couch.players:
		locals.append({"input": PlayerInput.new(int(p.device)), "name": p.name, "color": player_palette(int(p.color))})
	var lvl := play_level(data, "couch", locals)
	lvl.start_countdown(3.0)
	Sfx.play("beep")


func couch_runner_finished(index: int, t: float) -> void:
	if couch.is_empty() or couch.results.has(index):
		return
	couch.results[index] = t
	var p: Dictionary = couch.players[index]
	var lvl = current_scene
	if couch.winner == -1:
		couch.winner = index
		p.wins = int(p.wins) + 1
		if int(p.wins) >= int(couch.wins):
			couch.set_winner = index
		couch.next_at = Time.get_ticks_msec() / 1000.0 + 6.0
		if lvl and lvl.has_method("couch_popup"):
			lvl.couch_popup("%s SANK IT FIRST!" % p.name, player_palette(int(p.color)) * 1.6)
			lvl.show_couch_winner_cam(index)
		Sfx.play("fanfare")
	if couch.results.size() >= couch.players.size():
		couch.next_at = minf(couch.next_at, Time.get_ticks_msec() / 1000.0 + 3.0)


func couch_waiting_text() -> String:
	if couch.is_empty() or couch.winner == -1:
		return ""
	var left := maxf(0.0, float(couch.next_at) - Time.get_ticks_msec() / 1000.0)
	var who: String = couch.players[couch.winner].name
	var lvl = current_scene
	if lvl and is_instance_valid(lvl) and lvl.get("cam_hold"):
		return "%s wins round %d  ·  watching the disc cam" % [who, int(couch.round) + 1]
	if couch.set_winner != -1:
		return "%s TAKES THE SET  ·  %d" % [who, int(ceil(left))]
	return "%s wins round %d  ·  next course in %d" % [who, int(couch.round) + 1, int(ceil(left))]


func couch_scoreboard() -> String:
	if couch.is_empty():
		return ""
	var lines := ["FIRST TO %d" % int(couch.wins)]
	for i in couch.players.size():
		var p: Dictionary = couch.players[i]
		var stars := ""
		for k in int(couch.wins):
			stars += "●" if k < int(p.wins) else "○"
		lines.append("%s %s" % [stars, p.name])
	return "\n".join(lines)


func end_couch() -> void:
	if not couch.is_empty():
		couch_last_players = couch.players
	couch = {}
	goto_menu("couch")


func _process(_dt: float) -> void:
	_poll_export()
	if couch.is_empty() or float(couch.get("next_at", -1.0)) < 0.0:
		return
	var lvl = current_scene
	if lvl and is_instance_valid(lvl) and lvl.has_method("holding_round") and lvl.holding_round():
		couch.next_at = maxf(float(couch.next_at), Time.get_ticks_msec() / 1000.0 + 1.0)
		return
	if Time.get_ticks_msec() / 1000.0 >= float(couch.next_at):
		if int(couch.set_winner) != -1:
			couch_champion = "%s WINS THE COUCH SET!" % couch.players[couch.set_winner].name
			couch_last_players = couch.players
			couch = {}
			goto_menu("couch")
		else:
			couch.round = int(couch.round) + 1
			_couch_round()


static func format_time(t: float) -> String:
	if t < 0.0 or is_inf(t):
		return "--:--.---"
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%02d:%06.3f" % [m, s]
