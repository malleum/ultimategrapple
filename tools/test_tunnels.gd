extends SceneTree
## Drives the real player through every spike-ceiling tunnel in the shipped
## courses plus a batch of generated ones, and checks the outcome:
##   slide        run in, hold down              -> through, alive
##   slide_let_go slide in, release down inside  -> stays low, through, alive
##   slide_jump   slide in, press jump inside    -> jump held back, alive
##   stand        run in without crouching       -> dies (the hazard is real)
## godot --headless --fixed-fps 120 -s tools/test_tunnels.gd

const Gen = preload("res://src/level/generator.gd")
const Player = preload("res://src/player/player.gd")

const CASES := ["slide", "slide_let_go", "slide_jump", "stand"]
const MAX_FRAMES := 480

var jobs: Array = []     # [{data, x0, x1, floor_y}]
var job_i := -1
var case_i := 0
var frame := 0
var lvl = null
var fails := 0
var runs := 0
var started := false


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_collect()
		_next()
		return false
	if lvl == null or not is_instance_valid(lvl) or lvl.player == null:
		return false
	frame += 1
	var p = lvl.player
	var j: Dictionary = jobs[job_i]
	var c: String = CASES[case_i]
	if frame == 2:
		p.global_position = Vector2(j.x0 - 7 * Gen.T, j.floor_y)
		p.velocity = Vector2.ZERO
		lvl.runners[0].deaths = 0
		Input.action_press("move_right")
	var to_entry: float = j.x0 - p.global_position.x
	if c != "stand" and frame > 2 and to_entry < 70.0 and not Input.is_action_pressed("move_down") and p.global_position.x < j.x0:
		Input.action_press("move_down")
	var inside: bool = p.global_position.x > j.x0 + 40.0 and p.global_position.x < j.x1 - 10.0
	if inside and c == "slide_let_go":
		Input.action_release("move_down")
	if inside and c == "slide_jump" and frame % 20 == 0:
		Input.action_press("jump")
	elif c == "slide_jump":
		Input.action_release("jump")
	var deaths: int = lvl.runners[0].deaths
	var through: bool = p.global_position.x > j.x1 + 20.0
	if deaths > 0 or through or frame > MAX_FRAMES:
		var ok: bool = (deaths > 0) if c == "stand" else (deaths == 0 and through)
		runs += 1
		if not ok:
			fails += 1
			print("FAIL %s [%s] tunnel x=%d..%d: deaths=%d through=%s player=(%.0f, %.0f) frames=%d" % [
				j.name, c, j.x0, j.x1, deaths, through, p.global_position.x, p.global_position.y, frame])
		for a in ["move_right", "move_down", "jump"]:
			Input.action_release(a)
		case_i += 1
		if case_i >= CASES.size():
			case_i = 0
			_next()
		else:
			_restart()
	return false


func _collect() -> void:
	var Game = root.get_node("Game")
	Game.main = root
	var levels: Array = []
	for fname in DirAccess.open("res://levels").get_files():
		if fname.ends_with(".json"):
			levels.append(JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + fname)))
	var seed_v := 500
	var found := 0
	while found < 6:
		seed_v += 1
		var g: Dictionary = Game.generate_level(seed_v, "", (seed_v % 11) / 10.0, 14)
		if g.segments.has("slide_tunnel"):
			levels.append(g)
			found += 1
	for data in levels:
		for e in data.entities:
			if str(e.t) != "spikes" or str(e.get("dir", "")) != "down":
				continue
			# only tunnels: spikes whose floor is within standing height
			var r := Rect2(e.r[0], e.r[1], e.r[2], e.r[3])
			var fl := INF
			for s in data.solids:
				var sr := Rect2(s.r[0], s.r[1], s.r[2], s.r[3])
				if sr.position.y >= r.end.y and sr.position.x <= r.position.x and sr.end.x >= r.end.x:
					fl = minf(fl, sr.position.y)
			if fl - r.position.y <= Player.STAND.y + 16.0:
				jobs.append({"data": data, "name": str(data.get("name", data.get("id"))), "x0": r.position.x, "x1": r.end.x, "floor_y": fl})


func _next() -> void:
	job_i += 1
	if job_i >= jobs.size():
		print("tunnels: %d runs over %d tunnels, %d failures" % [runs, jobs.size(), fails])
		quit(0 if fails == 0 and jobs.size() > 0 else 1)
		return
	_restart()


func _restart() -> void:
	var Game = root.get_node("Game")
	lvl = Game.play_level(jobs[job_i].data.duplicate(true))
	frame = 0
