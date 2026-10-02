extends SceneTree
## Screenshot: splits column (with a stored PB to compare against) and wind
## chips along the aim line. Needs a display (xvfb-run).
## godot --fixed-fps 120 -s tools/shot_hud.gd -- out.png

const ID := "shot_hud"

var lvl
var f := 0
var started := false
var out := "hud.png"
var aim := Vector2.ZERO


func _level() -> Dictionary:
	return {"version": 2, "id": ID, "name": "Windy Splits", "theme": "field", "spawn": [0, 0], "basket": [5200, 0],
		"kill_y": 6000, "bounds": [-2000, -3000, 12000, 9000],
		"solids": [{"r": [-2000, 0, 12000, 400], "k": "ground"}], "polys": [],
		"entities": [{"t": "wind", "r": [1500, -700, 420, 700], "force": [0, -3400]},
			{"t": "wind", "r": [2200, -520, 700, 260], "force": [1500, -150]}],
		"route": [[0, 0], [5000, 0]], "segments": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
		"medals": {"par": 9, "ace": 6, "gold": 9, "silver": 12, "bronze": 15}}


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		var a := OS.get_cmdline_user_args()
		if a.size() > 0:
			out = a[0]
		G.main = root
		G.records[ID] = {"time": 7.9, "throws": 2, "medal": "gold"}
		var e: Dictionary = G.get_splits(ID, 5)
		e.pb = [1.6, 3.1, 4.9, 6.4, 7.9]
		e.gold = [1.5, 1.4, 1.7, 1.4, 1.4]
		lvl = G.play_level(_level())
		lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
		return false
	f += 1
	var r = lvl.runners[0]
	aim = r.player.center() + Vector2(700, -260)
	if f == 5:
		Input.action_press("move_right")
	if OS.get_environment("DBG") != "" and f % 40 == 0:
		print(f, " x=", r.player.global_position.x, " charging=", r.player.charging, " has_disc=", r.player.has_disc)
	if r.player.global_position.x > 1150.0 and not r.player.charging and f < 400:
		Input.action_release("move_right")
		Input.action_press("throw")
	if f == 400 or (r.player.charging and r.player.charge_power() > 0.8 and not r.has_meta("shot")):
		r.set_meta("shot", true)
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " splits ", r.split_times)
		Input.action_release("throw")
		G.records.erase(ID)
		G._splits.erase(ID)
		quit(0)
		return true
	return false
