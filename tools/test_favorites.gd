extends SceneTree
## Favorites + ghost clock:
##   pbghost   a recall in the PB run is recorded as the ghost standing still,
##             and the ghost plays on the run clock (penalties included)
##   fav       a finished run that is not a PB can still be kept as a favorite
##             (once), listed, played back by its key, and deleted
## godot --headless --fixed-fps 120 -s tools/test_favorites.gd

const ID := "test_favorites"

var lvl
var f := 0
var phase := "pb"
var fails := 0
var started := false
var d := {}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Fav Test", "theme": "field", "spawn": [0, 0], "basket": [6000, 0],
		"kill_y": 6000, "bounds": [-2000, -3000, 12000, 9000],
		"solids": [{"r": [-2000, 0, 12000, 400], "k": "ground"}], "polys": [], "entities": [],
		"route": [[0, 0], [6000, 0]], "segments": [], "medals": {"par": 9, "gold": 9}}


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		G.main = root
		G.records.erase(ID)
		G.save_ghost(ID, [])
		lvl = G.play_level(_level())
		return false
	f += 1
	var r = lvl.runners[0]
	match phase:
		"pb":
			# PB run: run 1 s, recall (+3 s), run 1 s more, finish
			if f == 5:
				Input.action_press("move_right")
			if f == 125:
				d["n0"] = r.rec_frames.size()
				r._on_recalled()
				d["n1"] = r.rec_frames.size()
			if f == 245:
				Input.action_release("move_right")
				r._on_scored()
				d["pb_time"] = r.finish_time
				d["frames"] = r.rec_frames.size()
				_check("hold", int(d.n1) - int(d.n0) == 90, "recall added %d still frames (3 s at 30 Hz)" % (int(d.n1) - int(d.n0)))
			if f == 260:
				lvl.restart()
				phase = "slow"
				f = 0
		"slow":
			# second run with the PB ghost: it follows the clock, so after a
			# recall of our own it jumps ahead with the timer
			if f == 5:
				Input.action_press("move_right")
			if f == 60:
				var g = r.pb_ghost
				_check("clock", g.visible and g.clock.is_valid() and absf(g.play_t - r.total_time()) < 0.05,
					"ghost at %.2fs, run clock %.2fs" % [g.play_t, r.total_time()])
				r._on_recalled()
			if f == 62:
				var g2 = r.pb_ghost
				_check("jump", absf(g2.play_t - r.total_time()) < 0.05 and r.total_time() > 3.4,
					"after our recall: ghost %.2fs, clock %.2fs" % [g2.play_t, r.total_time()])
			if f == 400:
				Input.action_release("move_right")
				r._on_scored()   # slower than the PB
			if f == 520:
				var rep: Dictionary = r.last_replay
				var is_pb: bool = absf(float(G.get_record(ID).time) - float(rep.get("time", -1.0))) < 0.0001
				var id: String = G.save_favorite(rep)
				var again: String = G.save_favorite(rep)
				var listed := false
				for e in G.list_favorites():
					listed = listed or str(e.id) == id
				var loaded: Dictionary = G.load_any_replay("fav:" + id)
				_check("fav", not is_pb and id != "" and again == id and listed and not loaded.is_empty() and str(loaded.key) == "fav:" + id,
					"non-PB run (%.2fs vs PB %.2fs) kept as %s, once, listed, loads" % [float(rep.get("time", 0)), float(d.pb_time), id])
				d["fav"] = id
				G.play_replay("fav:" + id)
				lvl = G.current_scene
				phase = "watch"
				f = 0
		"watch":
			if f == 5:
				_check("watch", lvl.mode == "replay" and str(lvl.replay.get("key", "")) == "fav:" + str(d.fav) and lvl.runners[0].pb_ghost.visible,
					"favorite (not the PB) plays back as a replay, with the PB ghost alongside")
				G.delete_favorite(str(d.fav))
				var gone := true
				for e in G.list_favorites():
					gone = gone and str(e.id) != str(d.fav)
				_check("delete", gone, "favorite deleted")
				G.records.erase(ID)
				G.save_ghost(ID, [])
				G.delete_replay(ID)
				G._splits.erase(ID)
				print("favorites: %d failures" % fails)
				quit(0 if fails == 0 else 1)
				return true
	return false
