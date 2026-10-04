extends SceneTree
## Local stats: a scripted run counts its attempt, time (chrons), distance,
## jumps, the double jump, the throw (by type), snap and the clear, per course
## too; a restart mid-run counts; stats survive a save + reload.
## godot --headless --fixed-fps 120 -s tools/test_stats.gd

const ID := "test_stats"
const FILE := "user://test_stats.json"

var Stats   # loaded at runtime
var lvl
var f := 0
var phase := "run"
var fails := 0
var started := false
var aim := Vector2.ZERO


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Stats Test", "theme": "field", "spawn": [0, 0], "basket": [6000, 0],
		"kill_y": 6000, "bounds": [-2000, -3000, 12000, 9000],
		"solids": [{"r": [-2000, 0, 12000, 400], "k": "ground"}], "polys": [], "entities": [],
		"route": [[0, 0], [6000, 0]], "segments": [], "medals": {"par": 30, "gold": 30}}


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		Stats = load("res://src/core/stats.gd")
		Stats.enabled = true
		DirAccess.remove_absolute(FILE)
		Stats.use_file(FILE)
		G.main = root
		G.records.erase(ID)
		lvl = G.play_level(_level())
		lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
		return false
	f += 1
	var r = lvl.runners[0]
	aim = r.player.center() + Vector2(600, -200)
	match phase:
		"run":
			if f == 5:
				Input.action_press("move_right")
			if f == 60:
				Input.action_press("jump")
			if f == 90:
				Input.action_release("jump")
			if f == 96:
				Input.action_press("jump")   # double jump
			if f == 100:
				Input.action_release("jump")
			if f == 200:
				Input.action_press("throw")
			if f == 260:
				Input.action_press("snap")
				Input.action_release("throw")
			if f == 262:
				Input.action_release("snap")
			if f == 420:
				lvl.restart()   # a restart mid-run
				phase = "second"
				f = 0
		"second":
			if f == 10:
				Input.action_press("jump")   # starts attempt #2
			if f == 14:
				Input.action_release("jump")
			if f == 120:
				Input.action_release("move_right")
				r._on_scored()
			if f == 130:
				var e: Dictionary = Stats.level(ID)
				var detail := "attempts %d, restarts %d, clears %d, jumps %d, airjumps %d, throws %d (backhand %d), snaps %d, run %.0f px, play %.2f s, course att %d comp %d" % [
					Stats.get_n("attempts"), Stats.get_n("restarts"), Stats.get_n("completions"), Stats.get_n("jumps"), Stats.get_n("airjumps"),
					Stats.get_n("throws"), Stats.get_n("throw_backhand"), Stats.get_n("snap_perfect") + Stats.get_n("snap_good") + Stats.get_n("snap_none"),
					Stats.get_n("run_px"), Stats.get_n("play_s"), e.att, e.comp]
				var ok: bool = Stats.get_n("attempts") == 2 and Stats.get_n("restarts") == 1 and Stats.get_n("completions") == 1 \
					and Stats.get_n("jumps") >= 2 and Stats.get_n("airjumps") == 1 and Stats.get_n("throws") == 1 and Stats.get_n("throw_backhand") == 1 \
					and Stats.get_n("snap_perfect") + Stats.get_n("snap_good") + Stats.get_n("snap_none") == 1 \
					and Stats.get_n("run_px") > 1000.0 and Stats.get_n("play_s") > 4.0 and int(e.att) == 2 and int(e.comp) == 1
				_check("counts", ok, detail)
				_check("chrons", Stats.chron_text(864.0 * 3.4567) == "3.45" and Stats.chron_text(Stats.get_n("play_s")) == "0.00", "864 s = 1 chron, truncated to hundredths")
				var before: float = Stats.get_n("jumps")
				Stats.save()
				Stats.use_file(FILE)   # reload from disk
				_check("saved", Stats.get_n("jumps") == before and int(Stats.level(ID).comp) == 1, "reloaded: jumps %d, course clears %d" % [Stats.get_n("jumps"), Stats.level(ID).comp])
				var secs: Array = Stats.sections()
				_check("page", secs.size() >= 6, "%d stat sections for the STATS page" % secs.size())
				Stats.enabled = false
				Stats.use_file(Stats.PATH)   # nothing more gets written to the test file
				DirAccess.remove_absolute(FILE)
				G.records.erase(ID)
				G.save_ghost(ID, [])
				G.delete_replay(ID)
				G._splits.erase(ID)
				print("stats: %d failures" % fails)
				quit(0 if fails == 0 else 1)
				return true
	return false
