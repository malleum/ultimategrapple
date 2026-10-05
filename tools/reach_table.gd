extends SceneTree
## How far a runner jumps off a ledge (jump + double jump, landing back at the
## same height), carrying the disc or empty-handed, from a run or a slide.
## Sizes the generator's chase gaps (Gen.CHASE_GAP_*).
## godot --headless --fixed-fps 120 -s tools/reach_table.gd

const EDGE := 0.0

var lvl
var r
var f := 0
var trial := -1
var trials: Array = []
var phase := ""
var best := {}
var started := false
var jumped_at := 0
var air_done := false
var took_off := false


func _level() -> Dictionary:
	return {"version": 3, "id": "reach", "name": "Reach", "theme": "field", "spawn": [-3000, 0], "basket": [-20000, 0],
		"kill_y": 4000, "bounds": [-24000, -3000, 30000, 9000],
		"solids": [{"r": [-4600, 0, 4600, 400], "k": "ground"}, {"r": [-21000, 0, 2000, 400], "k": "ground"}],
		"polys": [], "entities": [], "route": [], "segments": [], "medals": {"par": 9}}


func _initialize() -> void:
	for carry in [true, false]:
		for slide in [false, true]:
			for press in [-40.0, -24.0, -12.0, -4.0, 4.0, 12.0]:
				for dj in [0.0, -60.0, -200.0, -400.0]:
					trials.append({"carry": carry, "slide": slide, "press": press, "dj": dj})


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		G.main = root
		lvl = G.play_level(_level())
		return false
	if r == null:
		r = lvl.runners[0]
	f += 1
	if phase == "":
		_next()
		return false
	var p = r.player
	var tr: Dictionary = trials[trial]
	if phase == "run":
		if not tr.carry and p.has_disc and f > 2:
			p.has_disc = false
			r.disc.launch(Vector2(-20000, -40), Vector2.ZERO, 0, 1.0, 0.0, 0.0)
		if tr.slide and p.global_position.x > EDGE - 260.0 and not p.sliding:
			Input.action_press("move_down")
		if p.global_position.x >= EDGE + float(tr.press):
			Input.action_press("jump")
			jumped_at = f
			phase = "air"
	elif phase == "air":
		if p.global_position.y < -2.0:
			took_off = true
		if f == jumped_at + 3:
			Input.action_release("move_down")
		# second press once the first jump has slowed to this
		if Input.is_action_pressed("jump") and p.velocity.y > float(tr.dj) and f > jumped_at + 6 and p.has_air_jump:
			Input.action_release("jump")
		elif not Input.is_action_pressed("jump") and p.has_air_jump and f > jumped_at + 6:
			Input.action_press("jump")
		if took_off and p.global_position.y > 0.5 and p.velocity.y > 0.0:
			var key := "%s %s" % ["carry" if tr.carry else "empty", "slide" if tr.slide else "run"]
			var x: float = p.global_position.x - EDGE
			if x > float(best.get(key, -1.0)):
				best[key] = x
				best[key + " cfg"] = tr
			phase = ""
	if f > 2400:
		phase = ""
	return false


func _next() -> void:
	Input.action_release("jump")
	Input.action_release("move_down")
	Input.action_release("move_right")
	trial += 1
	if trial >= trials.size():
		for k in ["carry run", "carry slide", "empty run", "empty slide"]:
			print("%-12s %6.0f px  (%4.1f tiles)  %s" % [k, best.get(k, 0.0), float(best.get(k, 0.0)) / 32.0, best.get(k + " cfg", {})])
		quit()
		return
	lvl.restart()
	r.player.global_position = Vector2(-3000, 0)
	r.player.reset_physics_interpolation()
	took_off = false
	f = 0
	Input.action_press("move_right")
	phase = "run"
