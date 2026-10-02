extends SceneTree
## Movement feel checks on a hand-built course:
##   speed      top run speed empty-handed / carrying the disc
##   mantle     jump at a wall whose top is just above reach (and press jump
##              again against it): you end up on top, never wall-jumped away
##   hop        tapping jump gives a lower jump than holding it, without a
##              one-frame chop in upward speed
##   corner     jumping straight up with your head clipping a ceiling corner
##              slides past it
## godot --headless --fixed-fps 120 -s tools/test_moves.gd

const Player = preload("res://src/player/player.gd")

var lvl
var p
var tests := ["speed_empty", "speed_carry", "mantle", "hop_tap", "hop_hold", "corner"]
var ti := -1
var f := 0
var fails := 0
var d := {}
var started := false


func _level() -> Dictionary:
	return {"version": 2, "id": "test_moves", "name": "M", "theme": "field", "spawn": [0, 0], "basket": [9000, 0],
		"kill_y": 6000, "bounds": [-4000, -3000, 16000, 9000],
		"solids": [{"r": [-4000, 0, 16000, 400], "k": "ground"},
			{"r": [3300, -175, 200, 175], "k": "block"},        # wall just out of plain-jump reach
			{"r": [5000, -120, 200, 40], "k": "block"}],        # ceiling corner, bottom 80 px up
		"polys": [], "route": [], "medals": {"par": 9}, "entities": []}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-12s %s" % ["OK  " if ok else "FAIL", name, detail])


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		lvl = root.get_node("Game").play_level(_level())
		p = lvl.player
		_next()
		return false
	f += 1
	match tests[ti]:
		"speed_empty", "speed_carry":
			if f == 2:
				p.has_disc = tests[ti] == "speed_carry"
				Input.action_press("move_right")
			if f == 240:
				var want: float = Player.RUN_SPEED * (Player.CARRY_SPEED_MULT if p.has_disc else 1.0)
				_check(tests[ti], absf(p.velocity.x - want) < 2.0, "%.0f px/s (expected %.0f)" % [p.velocity.x, want])
				_next()
		"mantle":
			if f == 2:
				Input.action_press("move_right")
			if f == 4:
				Input.action_press("jump")
			if f == 40:
				Input.action_release("jump")
			if f == 44:
				Input.action_press("jump")   # the press that used to wall-jump you away
			if f == 48:
				Input.action_release("jump")
			d["min_x"] = minf(d.get("min_x", INF), p.global_position.x) if f > 44 else d.get("min_x", INF)
			if p.on_floor and p.global_position.y < -170.0 and p.global_position.x > 3300.0:
				d["on_top"] = true
			if f == 140:
				var on_top: bool = d.get("on_top", false)
				_check("mantle", on_top and float(d.min_x) > 3200.0, "on top=%s pos=(%.0f, %.0f), furthest back after 2nd press x=%.0f" % [on_top, p.global_position.x, p.global_position.y, d.min_x])
				_next()
		"hop_tap", "hop_hold":
			if f == 12:
				Input.action_press("jump")
			if f == (16 if tests[ti] == "hop_tap" else 200):
				Input.action_release("jump")
			if f > 12:
				d["top"] = minf(d.get("top", 0.0), p.global_position.y)
				if d.has("vy") and p.velocity.y < 0.0:
					d["chop"] = maxf(d.get("chop", 0.0), p.velocity.y - float(d.vy))
				d["vy"] = p.velocity.y
			if f == 120:
				var h: float = -float(d.top)
				lvl.set_meta(tests[ti], h)
				lvl.set_meta(tests[ti] + "_chop", float(d.get("chop", 0.0)))
				if tests[ti] == "hop_hold":
					var tap: float = lvl.get_meta("hop_tap")
					var chop: float = lvl.get_meta("hop_tap_chop")
					_check("hop", tap < h * 0.7 and chop < 60.0,
						"tap %.0f px vs hold %.0f px; letting go: biggest 1-tick loss of rising speed %.0f px/s" % [tap, h, chop])
				_next()
		"corner":
			if f == 2:
				Input.action_press("jump")
			d["top"] = minf(d.get("top", 0.0), p.global_position.y)
			if f == 90:
				Input.action_release("jump")
				_check("corner", float(d.top) < -100.0, "head clipped the corner by 6 px, feet still rose to %.0f px (it would stop at 36)" % -float(d.top))
				_next()
	return false


func _next() -> void:
	for a in ["move_right", "move_left", "jump"]:
		Input.action_release(a)
	ti += 1
	if ti >= tests.size():
		print("moves: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		return
	f = 0
	d = {}
	lvl.restart()
	var x := 0.0
	match tests[ti]:
		"mantle":
			x = 3300.0 - 40.0
		"corner":
			x = 5000.0 - 4.0     # body is 20 wide: right edge 6 px under the block
	p.respawn(Vector2(x, -2))
	p.has_disc = true
