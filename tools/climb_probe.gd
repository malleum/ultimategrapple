extends SceneTree
## How high can a runner get up ONE wall (no other wall nearby) by bouncing
## off it: wall jump, steer back, wall jump again (double jump once)? Prints
## the best height per policy for a grippy wall and a slick one.
## godot --headless --fixed-fps 120 -s tools/climb_probe.gd

var lvl
var p
var f := 0
var started := false
var trials: Array = []
var ti := -1
var best := 0.0
var tr := {}
var last_wj := -100
var used_dj := false
var touches := 0


func _level(slick: bool) -> Dictionary:
	return {"version": 2, "id": "climb_probe", "name": "C", "theme": "field", "spawn": [0, 0], "basket": [9000, 0],
		"kill_y": 6000, "bounds": [-4000, -6000, 16000, 12000],
		"solids": [{"r": [-4000, 0, 16000, 400], "k": "ground"},
			{"r": [1000, -4000, 64, 4000], "k": "slick" if slick else "block"}],
		"polys": [], "route": [], "medals": {"par": 9}, "entities": []}


func _initialize() -> void:
	for slick in [false, true]:
		for back in [0, 6, 12, 20, 30]:          # frames after a wall jump before steering back
			for dj_at in [-1, 0, 1, 2]:          # which bounce gets the double jump (-1 never)
				trials.append({"slick": slick, "back": back, "dj": dj_at})


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		_next()
		return false
	f += 1
	var h: float = -p.global_position.y / 32.0
	best = maxf(best, h)
	var wd: int = p.wall_dir
	if f < 4:
		Input.action_press("move_right")
		return false
	# run in and jump just before the wall
	if p.on_floor and p.global_position.x > 1000 - 90 and f - last_wj > 20:
		Input.action_press("jump")
		last_wj = f
	elif wd != 0 and f - last_wj > 3:
		# touching the wall in the air: wall jump (fresh press)
		Input.action_release("jump")
		tr["press"] = f + 1
		last_wj = f
		touches += 1
	if tr.has("press") and f == int(tr.press):
		Input.action_press("jump")
	var since := f - last_wj
	Input.action_release("move_right")
	Input.action_release("move_left")
	if since >= int(trials[ti].back) or p.on_floor:
		Input.action_press("move_right")
	# double jump on the chosen bounce, near the top of it
	if not used_dj and touches == int(trials[ti].dj) + 1 and int(trials[ti].dj) >= 0 and p.velocity.y > -60.0 and not p.on_floor and since > 6:
		Input.action_release("jump")
		tr["press"] = f + 1
		used_dj = true
	if f > 600 or (f > 60 and p.on_floor and touches > 0):
		print("%-6s back %2d dj %2d  best %.1f tiles  bounces %d" % ["slick" if trials[ti].slick else "grippy", trials[ti].back, trials[ti].dj, best, touches])
		_next()
	return false


func _next() -> void:
	for a in ["move_right", "move_left", "jump"]:
		Input.action_release(a)
	ti += 1
	if ti >= trials.size():
		quit(0)
		return
	lvl = root.get_node("Game").play_level(_level(trials[ti].slick))
	p = lvl.player
	p.has_disc = false
	f = 0
	best = 0.0
	tr = {}
	last_wj = -100
	used_dj = false
	touches = 0
