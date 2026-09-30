extends SceneTree
## Random-input fuzzer: mashes actions with random aim across many courses.
## godot --headless --fixed-fps 120 -s tools/fuzz.gd -- [levels] [frames]

const ACTIONS := ["move_left", "move_right", "jump", "dash", "grapple", "zip", "throw", "snap", "pivot", "move_down", "move_up", "throw_next", "recall"]
var rng := RandomNumberGenerator.new()
var lvl
var frame := 0
var idx := 0
var n_levels := 20
var n_frames := 1500
var started := false
var stats := {"throws": 0, "deaths": 0, "swings": 0, "wraps": 0, "scored": 0, "max_speed": 0.0}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: n_levels = int(a[0])
	if a.size() > 1: n_frames = int(a[1])
	rng.seed = 12345


func _next() -> void:
	var Game = root.get_node("Game")
	Game.main = root
	if idx >= n_levels:
		print("fuzz done: ", stats)
		quit()
		return
	var themes := ["field", "cyber", "fantasy", "heaven", "foundry", "frost", "canyon"]
	lvl = Game.play_level(Game.generate_level(5000 + idx, themes[idx % 7], rng.randf(), 8 + idx % 10))
	frame = 0
	idx += 1


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_next()
		return false
	frame += 1
	var p = lvl.player
	if frame % 8 == 0:
		for a in ACTIONS:
			if rng.randf() < (0.6 if a == "move_right" else 0.15):
				Input.action_press(a)
			else:
				Input.action_release(a)
		# bias aim toward grapple points ahead
		if rng.randf() < 0.5 and not lvl.grapple_points.is_empty():
			var gp = lvl.grapple_points[rng.randi() % lvl.grapple_points.size()]
			p.aim_override = gp.global_position
		else:
			p.aim_override = p.center() + Vector2(rng.randf_range(-400, 900), rng.randf_range(-600, 300))
	if rng.randf() < 0.002:
		# teleport along the route to explore more segments
		var route: Array = lvl.level_data.route
		var pt = route[rng.randi() % route.size()]
		p.respawn(Vector2(pt[0], pt[1] - 4))
	if p.state == 1:
		stats.swings += 1
	stats.wraps = max(stats.wraps, p.anchors.size() - 1)
	stats.max_speed = maxf(stats.max_speed, p.velocity.length())
	if frame >= n_frames:
		var r = lvl.runners[0]
		stats.throws += p.throws
		stats.deaths += r.deaths
		if r.done:
			stats.scored += 1
		for a in ACTIONS:
			Input.action_release(a)
		_next()
	return false
