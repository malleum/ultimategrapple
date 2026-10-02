extends SceneTree
## CPU-side frame cost per course, using the --perf-log sections. Runs each
## course for a few seconds with the runner sprinting right, then prints the
## script time per frame by section, worst first. Rendering itself needs a
## display: run under xvfb (or normally) to include draw-command recording.
##   godot --fixed-fps 120 -s tools/perf_scan.gd -- [n_courses] [seconds]

const Perf = preload("res://src/core/perf.gd")
const THEMES := ["field", "cyber", "canyon", "frost", "fantasy", "heaven", "foundry"]

var n := 14
var secs := 4.0
var i := -1
var f := 0
var lvl
var acc := {}
var frame_us: Array = []
var last_us := 0
var started := false
var results: Array = []
var worst := 0.0
var worst_what := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0 and a[0].is_valid_int(): n = int(a[0])
	if a.size() > 1 and a[1].is_valid_float(): secs = float(a[1])
	Perf.on = true


func _next() -> void:
	if i >= 0:
		_report()
	i += 1
	if i >= n:
		results.sort_custom(func(x, y): return x[0] > y[0])
		print("---- worst courses (script ms per frame)")
		for r in results:
			print("%6.2f ms  %s" % [r[0], r[1]])
		quit(0)
		return
	var G = root.get_node("Game")
	G.main = root
	var th: String = THEMES[i % THEMES.size()]
	var data: Dictionary = G.generate_level(500 + i, th, 0.3 + 0.1 * (i % 6), 8 + i % 6)
	lvl = G.play_level(data)
	acc.clear()
	frame_us.clear()
	worst = 0.0
	worst_what = ""
	f = 0
	Input.action_press("move_right")


func _report() -> void:
	var frames := maxi(f, 1)
	var keys := acc.keys()
	keys.sort_custom(func(a, b): return int(acc[a]) > int(acc[b]))
	var total := 0.0
	for k in acc:
		if not str(k).begins_with("burst"):
			total += int(acc[k])
	var parts: Array = []
	for k in keys.slice(0, 6):
		parts.append("%s %.3f" % [k, int(acc[k]) / 1000.0 / frames])
	var d: Dictionary = lvl.level_data
	var label := "%s #%s %s (%d entities) | worst frame %.1f ms (%s) | %s" % [d.theme, str(d.get("seed", "?")), str(d.get("name", "")), d.entities.size(), worst, worst_what, ", ".join(parts)]
	results.append([total / 1000.0 / frames, label])


func _process(_dt: float) -> bool:
	if not started:
		started = true
		_next()
		return false
	f += 1
	var fsum := 0.0
	var big := ""
	var bigv := 0
	for k in Perf._frame:
		acc[k] = int(acc.get(k, 0)) + int(Perf._frame[k])
		fsum += int(Perf._frame[k]) / 1000.0
		if int(Perf._frame[k]) > bigv:
			bigv = int(Perf._frame[k])
			big = str(k)
	if f > 30 and fsum > worst:
		worst = fsum
		worst_what = Perf._top(Perf._frame, 4)
	Perf._frame.clear()
	Perf._frame_n.clear()
	if f > int(secs * 120.0):
		_next()
	return false
