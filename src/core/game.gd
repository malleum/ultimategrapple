extends Node
## Global game state: settings, save data, input map, scene flow.

const LevelGen = preload("res://src/level/generator.gd")
const LevelScript = preload("res://src/level/level.gd")
const MenuScript = preload("res://src/ui/menu.gd")

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"
const PINNED_USER_DIR := "user://pinned"
const GHOST_DIR := "user://ghosts"
const GENERATOR_VERSION := 1

signal settings_changed

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
}

## level_id -> {time: float, throws: int, medal: String}
var records := {}

var server_mode := false  # headless dedicated server

## What "NEXT" does after a finish: {"kind": "random", ...} or {"kind": "pinned", "index": i}
var session := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load_settings()
	_load_records()
	DirAccess.make_dir_recursive_absolute(PINNED_USER_DIR)
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var args := OS.get_cmdline_user_args()
	server_mode = args.has("--server")
	apply_settings()


# ---------------------------------------------------------------- input map

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev: InputEvent
		if k is String and k.begins_with("mouse"):
			ev = InputEventMouseButton.new()
			ev.button_index = {"mouse_left": MOUSE_BUTTON_LEFT, "mouse_right": MOUSE_BUTTON_RIGHT,
				"mouse_middle": MOUSE_BUTTON_MIDDLE, "mouse_x1": MOUSE_BUTTON_XBUTTON1,
				"mouse_x2": MOUSE_BUTTON_XBUTTON2}[k]
		else:
			ev = InputEventKey.new()
			ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("jump", [KEY_SPACE])
	_key("dash", [KEY_SHIFT])
	_key("grapple", ["mouse_right"])
	_key("zip", [KEY_E, "mouse_x2"])
	_key("throw", ["mouse_left"])
	_key("snap", [KEY_F, "mouse_x1"])
	_key("pivot", [KEY_CTRL])
	_key("throw_next", [KEY_Q])
	_key("throw_1", [KEY_1])
	_key("throw_2", [KEY_2])
	_key("throw_3", [KEY_3])
	_key("throw_4", [KEY_4])
	_key("throw_5", [KEY_5])
	_key("throw_6", [KEY_6])
	_key("nose_up", [KEY_X])
	_key("nose_down", [KEY_Z])
	_key("recall", [KEY_T])
	_key("restart", [KEY_R])
	_key("pause", [KEY_ESCAPE])
	_key("pin", [KEY_P])
	_key("next_level", [KEY_N])
	_key("scoreboard", [KEY_TAB])


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
func play_level(data: Dictionary, mode: String = "solo", local_players: Array = []) -> Node:
	var lvl := LevelScript.new()
	lvl.level_data = data
	lvl.mode = mode
	lvl.local_players = local_players
	change_scene(lvl)
	return lvl


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
		Sfx.play("fanfare")
	if couch.results.size() >= couch.players.size():
		couch.next_at = minf(couch.next_at, Time.get_ticks_msec() / 1000.0 + 3.0)


func couch_waiting_text() -> String:
	if couch.is_empty() or couch.winner == -1:
		return ""
	var left := maxf(0.0, float(couch.next_at) - Time.get_ticks_msec() / 1000.0)
	var who: String = couch.players[couch.winner].name
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
	if couch.is_empty() or float(couch.get("next_at", -1.0)) < 0.0:
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
