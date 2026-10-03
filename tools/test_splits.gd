extends SceneTree
## Split times: a course is cut into splits along its route; crossing a line
## records the time; a finish stores the PB splits and best segments (the
## column keeps comparing against the PB it just beat); a faster
## second run shows negative deltas (gold where a segment beat its best).
## godot --headless --fixed-fps 120 -s tools/test_splits.gd

const ID := "test_splits"

var lvl
var f := 0
var run := 0
var fails := 0
var started := false
var first: Array = []


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Splits", "theme": "field", "spawn": [0, 0], "basket": [3200, 0],
		"kill_y": 6000, "bounds": [-2000, -3000, 9000, 9000],
		"solids": [{"r": [-2000, 0, 9000, 400], "k": "ground"}], "polys": [], "entities": [],
		"route": [[0, 0], [3000, 0]], "segments": ["a", "b", "c", "d", "e", "f", "g", "h"],
		"medals": {"par": 9, "gold": 9, "silver": 12, "bronze": 15}}


func _game():
	return root.get_node("Game")


func _physics_process(_dt: float) -> bool:
	var G = _game()
	if not started:
		started = true
		G.main = root
		G.records.erase(ID)
		G.get_splits(ID, 4).pb = []
		G.get_splits(ID, 4).gold = []
		lvl = G.play_level(_level())
		return false
	f += 1
	var r = lvl.runners[0]
	var p = r.player
	if f == 5:
		Input.action_press("move_right")
	# second run: skip ahead in the first segment -> faster splits 1.. on
	if run == 1 and f == 30:
		p.respawn(Vector2(600, -2))
	if p.global_position.x > 2700.0 and not r.done:
		Input.action_release("move_right")
		r._on_scored()
		if run == 0:
			first = r.split_times.duplicate()
			var e: Dictionary = G.get_splits(ID, 4)
			_check("first", lvl.split_xs.size() == 3 and first.size() == 4 and e.pb.size() == 4 and e.gold.size() == 4 and float(first[0]) > 0.5,
				"lines at %s, splits %s, PB stored %d, gold %d" % [lvl.split_xs, _fmt(first), e.pb.size(), e.gold.size()])
			run = 1
			f = 0
			lvl.restart()
			return false
		var second: Array = r.split_times
		var d0: float = float(second[0]) - float(first[0])
		var col: Color = r.hud._split_color(0, d0)
		_check("faster", second.size() == 4 and d0 < -0.3 and col == r.hud.SPLIT_GOLD and r.split_gold[0],
			"2nd run %s: first split %+.2fs, shown gold" % [_fmt(second), d0])
		var e2: Dictionary = G.get_splits(ID, 4)
		_check("pb", absf(float(e2.pb[3]) - float(second[3])) < 0.0001, "PB splits now the 2nd run (finish %.2f)" % float(e2.pb[3]))
		var shown: Array = r.split_pb()
		_check("shown", absf(float(shown[3]) - float(first[3])) < 0.0001,
			"results column still compares against the beaten PB (finish %.2f, delta %+.2fs)" % [float(shown[3]), float(second[3]) - float(shown[3])])
		# every time on screen: hundredths, truncated, differences of the shown values
		var ok_fmt: bool = G.format_time(15.9995) == "00:15.99" and G.format_time(16.0) == "00:16.00" \
			and G.format_time(75.678) == "01:15.67" and G.short_time(9.999) == "9.99" \
			and G.delta_text(15.9995, 17.0) == "−1.01" and G.delta_text(2.42, 2.16) == "+0.26" and G.gap_text(17.0, 15.9995) == "1.01"
		_check("format", ok_fmt, "15.9995 -> %s, 16.0 -> %s, delta %s" % [G.format_time(15.9995), G.format_time(16.0), G.delta_text(15.9995, 17.0)])
		var saved = JSON.parse_string(FileAccess.get_file_as_string(G.SPLITS_PATH))
		_check("saved", saved is Dictionary and saved.has(ID), "splits.json has the course")
		G.records.erase(ID)
		G._splits.erase(ID)
		G.save_splits()
		G.save_ghost(ID, [])
		G.delete_replay(ID)
		print("splits: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		return true
	if f > 120 * 15:
		_check("timeout", false, "never reached the end")
		quit(1)
		return true
	return false


func _fmt(a: Array) -> String:
	var s := []
	for x in a:
		s.append("%.2f" % float(x))
	return "[" + ", ".join(s) + "]"
