extends SceneTree
## Grapple behaviour checks on a hand-built course:
##   hold      grabbing while falling / flying away keeps the rope (no false snap)
##   regrab    letting go and clicking again 3 ticks later still grabs (buffer)
##   through   a point behind a platform can be grabbed; the rope starts wrapped
##   zip_wrap  zipping to a point behind a platform goes around it and arrives
##   cursor    cursor right next to a point picks it even outside the aim cone
##   range     a point 650 px away is in range
##   double    one double jump in the air, not two
## godot --headless --fixed-fps 120 -s tools/test_grapple.gd

const P_OPEN := Vector2(0, -400)
const P_BEHIND := Vector2(1200, -700)    # above the slab
const P_FAR := Vector2(-1600, -420)

var lvl
var p
var aim := Vector2.ZERO
var tests: Array = []
var ti := -1
var f := 0
var fails := 0
var data := {}
var started := false


func _level() -> Dictionary:
	return {"version": 2, "id": "test_grapple", "name": "G", "theme": "field", "spawn": [0, 0], "basket": [6000, 0],
		"kill_y": 6000, "bounds": [-4000, -3000, 12000, 9000],
		"solids": [{"r": [-4000, 2000, 12000, 400], "k": "ground"}, {"r": [1050, -560, 300, 60], "k": "block"},
			{"r": [-1200, 600, 400, 60], "k": "block"}],
		"polys": [], "route": [], "medals": {"par": 9},
		"entities": [{"t": "grapple", "p": [P_OPEN.x, P_OPEN.y], "k": "static"},
			{"t": "grapple", "p": [P_BEHIND.x, P_BEHIND.y], "k": "static"},
			{"t": "grapple", "p": [P_FAR.x, P_FAR.y], "k": "static"}]}


func _check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		G.main = root
		lvl = G.play_level(_level())
		p = lvl.player
		lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
		for vx in [0.0, 500.0, 1100.0]:
			for vy in [0.0, 700.0, 1400.0]:
				tests.append(["hold", Vector2(260, -150), Vector2(vx, vy)])
		tests.append(["regrab", Vector2(-200, -150), Vector2.ZERO])
		tests.append(["through", Vector2(1180, -420), Vector2.ZERO])
		tests.append(["zip_wrap", Vector2(1180, -420), Vector2.ZERO])
		tests.append(["cursor", Vector2(-150, -150), Vector2.ZERO])
		tests.append(["range", Vector2(-1000, -150), Vector2.ZERO])
		tests.append(["double", Vector2(-2600, -900), Vector2.ZERO])
		_next()
		return false
	f += 1
	var t: Array = tests[ti]
	match t[0]:
		"hold":
			if f == 3:
				p.velocity = t[2]
				Input.action_press("grapple")
			if f == 90:
				_check("hold", p.state == 1, "v=%s state=%d" % [t[2], p.state])
				_next()
		"regrab":
			if f == 3:
				Input.action_press("grapple")
			if f == 20:
				Input.action_release("grapple")
			if f == 23:
				Input.action_press("grapple")
			if f == 40:
				_check("regrab", p.state == 1, "state=%d" % p.state)
				_next()
		"through":
			if f == 3:
				Input.action_press("grapple")
			if f == 5:
				_check("through", p.state == 1 and p.anchors.size() >= 2, "state=%d anchors=%d" % [p.state, p.anchors.size()])
			if f == 60:
				_check("through", p.state == 1, "still swinging: state=%d" % p.state)
				_next()
		"zip_wrap":
			if f == 3:
				Input.action_press("zip")
			if p.state != 2 and f > 4 and not data.has("end"):
				data["end"] = p.center().distance_to(P_BEHIND)
			if f == 300:
				var dd: float = data.get("end", p.center().distance_to(P_BEHIND))
				_check("zip_wrap", dd < 70.0, "ended %.0f px from the point" % dd)
				_next()
		"cursor":
			if f == 3:
				# aim far off to the left, cursor parked right next to the open point
				aim = P_OPEN + Vector2(-90, 60)
			if f == 6:
				var tgt = p.target.get("pos")
				_check("cursor", tgt == P_OPEN, "target=%s" % [tgt])
				_next()
		"double":
			# one extra jump in the air, then no more until landing
			if f == 30:
				Input.action_press("jump")
			if f == 32:
				Input.action_release("jump")
				data["vy1"] = p.velocity.y
			if f == 40:
				Input.action_press("jump")
			if f == 42:
				Input.action_release("jump")
				data["vy2"] = p.velocity.y
				_check("double", float(data.vy1) < -600.0 and float(data.vy2) > float(data.vy1) and not p.has_air_jump,
					"after 1st air jump vy=%.0f, 2nd press vy=%.0f (should not jump again)" % [data.vy1, data.vy2])
				_next()
		"range":
			if f == 6:
				var tgt2 = p.target.get("pos")
				_check("range", tgt2 == P_FAR, "dist %.0f target=%s" % [p.center().distance_to(P_FAR), tgt2])
				_next()
	return false


func _next() -> void:
	for a in ["grapple", "zip"]:
		Input.action_release(a)
	ti += 1
	if ti >= tests.size():
		print("grapple: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		return
	var t: Array = tests[ti]
	f = 0
	data = {}
	lvl.restart()
	p.respawn(t[1])
	match t[0]:
		"through", "zip_wrap":
			aim = P_BEHIND
		"range":
			aim = P_FAR
		_:
			aim = P_OPEN
