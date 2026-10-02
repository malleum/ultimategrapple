extends SceneTree
## Match recordings: a couch round is saved when the level closes, shows up in
## Game.list_matches(), and plays back with every runner following their
## recorded path; left/right switches who the camera follows; the end card
## appears; delete removes it.
## godot --headless --fixed-fps 120 -s tools/test_match.gd

const PI_ = preload("res://src/core/player_input.gd")

var lvl
var f := 0
var phase := "race"
var fails := 0
var started := false
var n_before := 0
var rec_a: Array = []
var mid := ""
var max_off := 0.0


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _level() -> Dictionary:
	return {"version": 2, "id": "test_match", "name": "Match Test", "theme": "field", "spawn": [0, 0], "basket": [9000, 0],
		"kill_y": 6000, "bounds": [-4000, -3000, 16000, 9000],
		"solids": [{"r": [-4000, 0, 16000, 400], "k": "ground"}, {"r": [600, -60, 200, 60], "k": "block"}],
		"polys": [], "route": [], "medals": {"par": 9}, "entities": []}


func _game():
	return root.get_node("Game")


func _physics_process(_dt: float) -> bool:
	var G = _game()
	if not started:
		started = true
		G.main = root
		n_before = G.list_matches().size()
		var locals := [{"input": PI_.new(PI_.KBM), "name": "Ann", "color": Color(0, 1, 1)},
			{"input": PI_.new(7), "name": "Bo", "color": Color(1, 0, 1)}]
		lvl = G.play_level(_level(), "couch", locals)
		lvl.start_countdown(0.05)
		return false
	f += 1
	match phase:
		"race":
			var a = lvl.runners[0]
			if f == 20:
				Input.action_press("move_right")
			if f == 120:
				Input.action_press("jump")
			if f == 130:
				Input.action_release("jump")
			if f == 400:
				Input.action_release("move_right")
				a._on_scored()
			if f == 420:
				rec_a = a.rec_frames.duplicate()
				G.goto_menu()
				phase = "saved"
				f = 0
		"saved":
			if f == 3:
				var list: Array = G.list_matches()
				var ok: bool = list.size() == mini(n_before + 1, G.MATCH_MAX) and str(list[0].winner) == "Ann"
				mid = str(list[0].id) if not list.is_empty() else ""
				var rec: Dictionary = G.load_match(mid)
				var nr: int = rec.get("runners", []).size()
				_check("saved", ok and nr == 2 and rec_a.size() > 80, "listed %d (was %d), winner %s, %d runners, Ann %d frames" % [list.size(), n_before, list[0].winner if not list.is_empty() else "-", nr, rec_a.size()])
				G.play_match(mid)
				lvl = G.current_scene
				phase = "watch"
				f = 0
		"watch":
			var mp = lvl.match_playback
			if mp == null:
				_check("watch", false, "no match playback")
				return _finish()
			if mp.t > 0.2 and mp.t < mp.length - 0.2:
				var k := int(mp.t * 30.0)
				if k < rec_a.size() - 1:
					var want := Vector2(rec_a[k][0], rec_a[k][1]).lerp(Vector2(rec_a[k + 1][0], rec_a[k + 1][1]), mp.t * 30.0 - k)
					max_off = maxf(max_off, (mp.puppets[0].visual.position as Vector2).distance_to(want))
			if mp.t > 1.5 and not mp.has_meta("switched"):
				mp.set_meta("switched", true)
				var before: int = mp.follow
				Input.action_press("move_right")
				mp.set_meta("before", before)
			if mp.has_meta("switched") and not mp.has_meta("checked"):
				Input.action_release("move_right")
				if mp.follow != int(mp.get_meta("before")):
					mp.set_meta("checked", true)
					var cam_target: Vector2 = mp._follow_state()[0]
					_check("switch", mp.puppets[mp.follow].name == "Bo", "camera now follows %s at %s" % [mp.puppets[mp.follow].name, cam_target.round()])
			if mp.card != null:
				_check("playback", max_off < 1.0 and mp.has_meta("checked"), "Ann's puppet stayed within %.2f px of her recorded path; end card up" % max_off)
				G.delete_match(mid)
				_check("delete", G.load_match(mid).is_empty(), "recording deleted")
				return _finish()
			if f > 120 * 20:
				_check("playback", false, "no end card after 20 s")
				return _finish()
	return false


func _finish() -> bool:
	print("match: %d failures" % fails)
	quit(0 if fails == 0 else 1)
	return true
