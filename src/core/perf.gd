extends Node
## Performance log, enabled with `--perf-log` (nix run . -- --perf-log).
##
## Writes to stdout and to user://logs/perf-<date>.log (the path is printed at
## start). Each line is plain text meant to be pasted back for diagnosis:
##   LEVEL   what was loaded: id, seed, theme, entity / node counts
##   SEC     once a second: fps, average / worst frame, 1% low, engine process,
##           physics and render times, draw calls, nodes, top script sections
##   SPIKE   any frame over SPIKE_MS (or 2.5x the running median): its time,
##           the script sections that ran in it, render time, what the runner
##           was doing
##   SUMMARY per level when it is left: fps, lows, worst frames, totals per
##           section
##
## Code marks hot spots with Perf.begin() / Perf.end("name", t0). Both are a
## single bool check when the log is off.

static var on := false
static var _frame := {}      # section -> usec in the current frame
static var _frame_n := {}    # section -> calls in the current frame

const SPIKE_MS := 25.0
const LOG_DIR := "user://logs"

var _file: FileAccess
var _last_us := 0
var _sec_t := 0.0
var _sec_frames: Array = []        # frame ms this second
var _sec_sections := {}            # section -> usec this second
var _lvl_frames: Array = []        # frame ms this level
var _lvl_sections := {}
var _lvl_name := ""
var _lvl_ref: WeakRef = null
var _spikes: Array = []            # [ms, line] worst of this level
var _median := 8.3
var _vp_rid: RID


static func begin() -> int:
	return Time.get_ticks_usec() if on else 0


static func end(section: String, t0: int) -> void:
	if not on:
		return
	_frame[section] = int(_frame.get(section, 0)) + Time.get_ticks_usec() - t0
	_frame_n[section] = int(_frame_n.get(section, 0)) + 1


func _ready() -> void:
	on = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100000   # first in every frame: closes the previous one
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var path := "%s/perf-%s.log" % [LOG_DIR, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_log("PERF log -> %s" % ProjectSettings.globalize_path(path))
	_log("SYSTEM %s | %s | %s | cpu %s x%d | renderer %s %s | window %s | physics %d Hz | vsync %s | max_fps %d" % [
		OS.get_name(), OS.get_distribution_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		DisplayServer.window_get_size(), Engine.physics_ticks_per_second,
		DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	_level_summary()
	if _file:
		_file.flush()


func _log(line: String) -> void:
	print(line)
	if _file:
		_file.store_line(line)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	# the frame that just ended
	var sections := _frame.duplicate()
	var counts := _frame_n.duplicate()
	_frame.clear()
	_frame_n.clear()
	_track_level()
	_sec_frames.append(ms)
	_lvl_frames.append(ms)
	for k in sections:
		_sec_sections[k] = int(_sec_sections.get(k, 0)) + int(sections[k])
		_lvl_sections[k] = int(_lvl_sections.get(k, 0)) + int(sections[k])
	_median = lerpf(_median, ms, 0.02)
	if ms > maxf(SPIKE_MS, _median * 2.5) and _lvl_frames.size() > 5:
		_spike(ms, sections, counts)
	_sec_t += ms / 1000.0
	if _sec_t >= 1.0:
		_second()
		_sec_t = 0.0


func _render_ms() -> Vector2:
	return Vector2(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid),
		RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))


static func _top(sections: Dictionary, n: int, scale := 1.0) -> String:
	var keys := sections.keys()
	keys.sort_custom(func(a, b): return int(sections[a]) > int(sections[b]))
	var parts: Array = []
	for k in keys.slice(0, n):
		parts.append("%s %.2f" % [k, int(sections[k]) / 1000.0 * scale])
	return ", ".join(parts) if not parts.is_empty() else "-"


## The Game autoload, looked up at runtime (this script is preloaded by
## scripts that compile before autoloads exist, e.g. -s tools).
func _game():
	return get_node_or_null("/root/Game")


func _context() -> String:
	var s = _game().current_scene if _game() else null
	if s == null or not is_instance_valid(s) or not s.has_method("remote_state") or s.runners.is_empty():
		return "scene %s" % (s.name if s and is_instance_valid(s) else "-")
	var r = s.runners[0]
	var p = r.player
	return "player %s v=%s state %d | disc state %d at %s | t=%.2f" % [
		p.global_position.round(), p.velocity.round(), p.state, r.disc.state, r.disc.global_position.round(), r.time]


func _spike(ms: float, sections: Dictionary, counts: Dictionary) -> void:
	var rt := _render_ms()
	var script_ms := 0.0
	for k in sections:
		script_ms += int(sections[k]) / 1000.0
	var line := "SPIKE %.1f ms (median %.1f) | process %.2f physics %.2f | render cpu %.2f gpu %.2f | script %.2f: %s | nodes %d | %s" % [
		ms, _median, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, rt.x, rt.y,
		script_ms, _top(sections, 6), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _context()]
	var calls: Array = []
	for k in counts:
		if int(counts[k]) > 1:
			calls.append("%s x%d" % [k, counts[k]])
	if not calls.is_empty():
		line += " | calls: " + ", ".join(calls.slice(0, 8))
	_log(line)
	_spikes.append([ms, line])
	_spikes.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if _spikes.size() > 5:
		_spikes.resize(5)


func _second() -> void:
	var fr: Array = _sec_frames.duplicate()
	_sec_frames.clear()
	if fr.is_empty():
		return
	var total := 0.0
	var worst := 0.0
	for x in fr:
		total += float(x)
		worst = maxf(worst, float(x))
	var rt := _render_ms()
	_log("SEC fps %d | frame avg %.1f worst %.1f low1%% %.0ffps | process %.2f physics %.2f render cpu %.2f gpu %.2f ms | draws %d objs %d prims %d | nodes %d orphans %d | phys2d active %d pairs %d | mem %.0fMB | script ms/s: %s" % [
		fr.size(), total / fr.size(), worst, _low_fps(fr, 0.01),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, rt.x, rt.y,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, _top(_sec_sections, 6)])
	_sec_sections.clear()


static func _low_fps(frames: Array, frac: float) -> float:
	if frames.is_empty():
		return 0.0
	var s := frames.duplicate()
	s.sort()
	var k := clampi(int(ceil(s.size() * (1.0 - frac))) - 1, 0, s.size() - 1)
	return 1000.0 / maxf(float(s[k]), 0.001)


func _track_level() -> void:
	var s = _game().current_scene if _game() else null
	var cur = _lvl_ref.get_ref() if _lvl_ref else null
	if s == cur:
		return
	_level_summary()
	_lvl_ref = weakref(s) if s else null
	_lvl_frames.clear()
	_lvl_sections.clear()
	_spikes.clear()
	if s == null or not is_instance_valid(s):
		_lvl_name = ""
		return
	if not s.has_method("remote_state"):
		_lvl_name = "menu"
		_log("SCENE menu")
		return
	var d: Dictionary = s.level_data
	_lvl_name = "%s (%s)" % [str(d.get("name", "?")), str(d.get("id", "?"))]
	var ents := {}
	for e in d.get("entities", []):
		var t := str(e.get("t", "?"))
		ents[t] = int(ents.get(t, 0)) + 1
	var spike_px := 0.0
	for e in d.get("entities", []):
		if str(e.get("t", "")) == "spikes":
			spike_px += maxf(float(e.r[2]), float(e.r[3]))
	_log("LEVEL %s | mode %s | seed %s theme %s difficulty %s version %s | solids %d polys %d | entities %s | spike strip length %d px" % [
		_lvl_name, s.mode, str(d.get("seed", "-")), str(d.get("theme", "-")), str(d.get("difficulty", "-")), str(d.get("version", "-")),
		d.get("solids", []).size(), d.get("polys", []).size(), ents, int(spike_px)])
	# node census a moment later (the level builds over its first frames)
	get_tree().create_timer(1.0).timeout.connect(_census.bind(weakref(s)))


func _census(ref: WeakRef) -> void:
	var s = ref.get_ref()
	if s == null:
		return
	var by := {}
	var redraw := 0
	var stack: Array = [s]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key := n.get_class()
		var scr = n.get_script()
		if scr and scr.resource_path != "":
			key = scr.resource_path.get_file().get_basename()
		by[key] = int(by.get(key, 0)) + 1
		stack.append_array(n.get_children())
	var keys := by.keys()
	keys.sort_custom(func(a, b): return int(by[a]) > int(by[b]))
	var parts: Array = []
	for k in keys.slice(0, 16):
		parts.append("%s %d" % [k, by[k]])
	_log("NODES %s: %s" % [_lvl_name, ", ".join(parts)])


func _level_summary() -> void:
	if _lvl_name == "" or _lvl_frames.size() < 30:
		return
	var total := 0.0
	for x in _lvl_frames:
		total += float(x)
	var secs := total / 1000.0
	_log("SUMMARY %s | %.1fs, %d frames, avg %.0f fps, 1%% low %.0f fps, 0.1%% low %.0f fps | script ms per second: %s" % [
		_lvl_name, secs, _lvl_frames.size(), _lvl_frames.size() / maxf(secs, 0.001),
		_low_fps(_lvl_frames, 0.01), _low_fps(_lvl_frames, 0.001), _top(_lvl_sections, 10, 1.0 / maxf(secs, 0.001))])
	for sp in _spikes:
		_log("  worst: " + str(sp[1]))
	if _file:
		_file.flush()
