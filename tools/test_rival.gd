extends SceneTree
## Friends' runs: a PB replay is shared as a .ugr file, imported back as a
## friend's run, raced as a named ghost (moving along their path), and the
## results card says who won. A junk file is refused.
## godot --headless --fixed-fps 120 -s tools/test_rival.gd

const ID := "test_rival"

var lvl
var f := 0
var phase := "make"
var fails := 0
var started := false
var share_path := ""
var rid := ""


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Rival Test", "theme": "field", "spawn": [0, 0], "basket": [4000, 0],
		"kill_y": 6000, "bounds": [-2000, -3000, 9000, 9000],
		"solids": [{"r": [-2000, 0, 9000, 400], "k": "ground"}], "polys": [], "entities": [],
		"route": [[0, 0], [4000, 0]], "segments": [], "medals": {"par": 9, "gold": 9}}


func _game():
	return root.get_node("Game")


func _physics_process(_dt: float) -> bool:
	var G = _game()
	if not started:
		started = true
		G.main = root
		G.records.erase(ID)
	f += 1
	match phase:
		"make":
			# a friend's 3.0 s personal best: straight run to x=1500
			var frames: Array = []
			for k in 91:
				var x := k * 1500.0 / 90.0
				frames.append([x, 0.0, 500.0, 0.0, 1, 9, 0.0, 0.0, x, -30.0, 0])
			var rep := {"v": G.REPLAY_VERSION, "level_id": ID, "level": _level(), "name": "Rival Test", "theme": "field",
				"time": 3.0, "medal": "", "throws": 1, "deaths": 0, "penalty": 0.0, "player": "Pal", "color": Color(1, 0.5, 0.1),
				"seed": 1, "throw_type": 0, "nose": 0.0, "labels": {}, "date": 0, "input": {}, "track": PackedVector2Array(), "ghost": frames}
			G.save_replay(rep)
			share_path = G.export_run_file(ID)
			_check("share", share_path != "" and FileAccess.file_exists(share_path), "wrote %s" % share_path.get_file())
			G.delete_replay(ID)
			var err: String = G.import_rival(share_path)
			rid = "%s__Pal" % ID
			var listed := false
			for e in G.list_rivals():
				listed = listed or str(e.id) == rid
			_check("import", err == "" and listed, "imported, listed as %s %s" % [rid, err])
			var junk := "user://junk_test.ugr"
			var jf := FileAccess.open(junk, FileAccess.WRITE)
			jf.store_string("not a run")
			jf.close()
			var jerr: String = G.import_rival(junk)
			_check("junk", jerr != "", "junk refused: %s" % jerr)
			DirAccess.remove_absolute(junk)
			G.race_rival(rid)
			lvl = G.current_scene
			phase = "race"
			f = 0
		"race":
			var r = lvl.runners[0]
			if f == 5:
				Input.action_press("move_right")
			if f == 125:
				var g = r.rival_ghost
				_check("ghost", g != null and g.visible and g.position.x > 400.0 and g.position.x < 650.0 and g.visual.name_tag == "Pal",
					"Pal's ghost at x=%.0f after 1 s of racing" % (g.position.x if g else -1.0))
				Input.action_release("move_right")
				r._on_scored()   # finish in ~1 s: beats Pal's 3.0
			if f == 125 + 200:
				var txt := _find_text(lvl, "YOU BEAT PAL")
				_check("result", txt, "results card says YOU BEAT PAL")
				G.delete_rival(rid)
				DirAccess.remove_absolute(share_path)
				G.records.erase(ID)
				G.delete_replay(ID)
				G.save_ghost(ID, [])
				print("rival: %d failures" % fails)
				quit(0 if fails == 0 else 1)
				return true
	return false


func _find_text(n: Node, s: String) -> bool:
	if n is Label and (n as Label).text.begins_with(s):
		return true
	for c in n.get_children():
		if _find_text(c, s):
			return true
	return false
