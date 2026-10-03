extends SceneTree
## Rollers on slopes: a roller set rolling at the top of a downhill slope
## speeds up and runs to the bottom; one set down slowly on the slope sets off
## by itself; on the flat it still rolls out and stops.
## godot --headless --fixed-fps 120 -s tools/test_roll.gd

const ROLLER := 3
const TOP := Vector2(0, 0)
const BOTTOM := Vector2(2000, 700)   # ~19 degree slope

var lvl
var f := 0
var phase := 0
var fails := 0
var started := false
var d := {}


func _level() -> Dictionary:
	return {"version": 2, "id": "test_roll", "name": "R", "theme": "field", "spawn": [-300, 0], "basket": [9000, 700],
		"kill_y": 6000, "bounds": [-4000, -3000, 16000, 9000],
		"solids": [{"r": [-4000, 0, 4000, 400], "k": "ground"}, {"r": [2000, 700, 9000, 400], "k": "ground"}],
		"polys": [{"pts": [TOP.x, TOP.y, BOTTOM.x, BOTTOM.y, BOTTOM.x, BOTTOM.y + 400, TOP.x, TOP.y + 400], "k": "ground"}],
		"route": [], "medals": {"par": 9}, "entities": []}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		lvl = root.get_node("Game").play_level(_level())
		_launch(Vector2(40, -30), Vector2(320, 60))
		return false
	f += 1
	var disc = lvl.runners[0].disc
	match phase:
		0:
			# rolling start at the top of the slope
			if f == 30:
				d["v0"] = disc.velocity.length()
			if f == 150:
				var v: float = disc.velocity.length()
				_check("speedup", disc.state == 2 and v > float(d.v0) + 300.0, "rolling downhill: %.0f -> %.0f px/s" % [d.v0, v])
			if f == 360:
				_check("bottom", disc.global_position.x > BOTTOM.x, "ran off the bottom of the slope to x=%.0f" % disc.global_position.x)
				_launch(Vector2(600, 210 - 30), Vector2(40, 40))
				phase = 1
				f = 0
		1:
			# set down slowly mid-slope: sets off on its own
			if f == 240:
				_check("setoff", disc.global_position.x > 1000.0, "set down at x=600, rolled to x=%.0f (state %d)" % [disc.global_position.x, disc.state])
				_launch(Vector2(-2000, -30), Vector2(600, 60))
				phase = 2
				f = 0
		2:
			# flat ground: rolls out and stops
			if f == 480:
				_check("flat", disc.state == 4 and disc.global_position.x < -1000.0, "flat roll stopped at x=%.0f (state %d)" % [disc.global_position.x, disc.state])
				print("roll: %d failures" % fails)
				quit(0 if fails == 0 else 1)
				return true
	return false


func _launch(at: Vector2, vel: Vector2) -> void:
	var r = lvl.runners[0]
	r.player.has_disc = false
	r.player.respawn(Vector2(-3000, 0))
	r.disc.launch(at, vel, ROLLER, 1.0, 0.0, 0.0)
