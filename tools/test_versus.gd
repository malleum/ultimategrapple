extends SceneTree
## Versus rules on a hand-built course:
##   freeze    couch: recalling the disc freezes you 3 s (no time penalty);
##             holding right during it doesn't move you; the clock keeps going
##   oob       couch: disc out of bounds freezes you 2 s
##   solo      solo: recall still adds +3 s and doesn't freeze
##   tackle    couch: sliding into the other runner knocks them away + stuns
##   clash     couch: two discs meeting mid-air bounce apart and lose spin
##   netclash  online handler: a reported hit knocks our disc
##   hit_head  couch: a fast disc to the head knocks the runner down
##   hit_arm   couch: a disc to the arm makes them drop theirs
##   hit_leg   couch: a disc to the legs trips them into a slide
##   hit_slow  couch: a slow disc just bounces off
##   couchcam  couch: the round winner's disc cam shows in the corner;
##             clicking it goes full screen and holds the next course until
##             it has played through
## godot --headless --fixed-fps 120 -s tools/test_versus.gd

const PI_ = preload("res://src/core/player_input.gd")
const Disc = preload("res://src/disc/disc.gd")

var lvl
var tests := ["freeze", "oob", "tackle", "clash", "netclash", "hit_head", "hit_arm", "hit_leg", "hit_slow", "couchcam", "solo"]
var ti := -1
var f := 0
var fails := 0
var d := {}
var started := false


const CAM_HOLD := 1.2   # DiscCam.HOLD (it can't be preloaded here: it uses the Game autoload)


func _level() -> Dictionary:
	return {"version": 2, "id": "test_versus", "name": "V", "theme": "field", "spawn": [0, 0], "basket": [9000, 0],
		"kill_y": 6000, "bounds": [-4000, -3000, 16000, 9000],
		"solids": [{"r": [-4000, 0, 16000, 400], "k": "ground"}],
		"polys": [], "route": [], "medals": {"par": 9}, "entities": []}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-9s %s" % ["OK  " if ok else "FAIL", name, detail])


func _game():
	return root.get_node("Game")


func _start(mode: String) -> void:
	var G = _game()
	G.main = root
	if mode == "couch":
		var locals := [{"input": PI_.new(PI_.KBM), "name": "A", "color": Color(0, 1, 1)},
			{"input": PI_.new(7), "name": "B", "color": Color(1, 0, 1)}]
		lvl = G.play_level(_level(), "couch", locals)
		lvl.start_countdown(0.02)
	else:
		lvl = G.play_level(_level(), mode)


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_next()
		return false
	f += 1
	var a = lvl.runners[0]
	match tests[ti]:
		"freeze":
			if f == 10:
				a.player.has_disc = false
				a.disc.launch(Vector2(300, -200), Vector2(400, -200), 0, 1.0, 0.0, 0.0)
			if f == 20:
				d["x0"] = a.player.global_position.x
				d["t0"] = a.total_time()
				Input.action_press("move_right")
				Input.action_press("recall")
			if f == 22:
				Input.action_release("recall")
			if f == 20 + 350:   # 2.9 s later: still frozen
				d["x1"] = a.player.global_position.x
			if f == 20 + 420:   # 3.5 s later: free and running
				var still: bool = absf(float(d.x1) - float(d.x0)) < 0.5
				var moved: bool = a.player.global_position.x > float(d.x0) + 50.0
				var clock: float = a.total_time() - float(d.t0)
				_check("freeze", still and moved and a.penalty == 0.0 and clock > 3.4,
					"held right through it: moved %.1f px while frozen, %.0f px after; clock +%.2fs, penalty %.1f" % [float(d.x1) - float(d.x0), a.player.global_position.x - float(d.x0), clock, a.penalty])
				_next()
		"oob":
			if f == 10:
				a.player.has_disc = false
				a.disc.launch(Vector2(300, -200), Vector2(400, -200), 0, 1.0, 0.0, 0.0)
			if f == 20:
				a._on_disc_oob()
				d["frozen"] = a.player.frozen_t
			if f == 30:
				_check("oob", absf(float(d.frozen) - 2.0) < 0.01 and a.player.has_disc and a.penalty == 0.0,
					"frozen %.2fs, disc back in hand=%s, penalty %.1f" % [d.frozen, a.player.has_disc, a.penalty])
				_next()
		"solo":
			if f == 10:
				a.player.has_disc = false
				a.disc.launch(Vector2(300, -200), Vector2(400, -200), 0, 1.0, 0.0, 0.0)
			if f == 20:
				Input.action_press("recall")
			if f == 22:
				Input.action_release("recall")
			if f == 30:
				_check("solo", a.penalty == 3.0 and a.player.frozen_t <= 0.0, "penalty +%.1fs, frozen=%s" % [a.penalty, a.player.frozen_t > 0.0])
				_next()
		"tackle":
			var b = lvl.runners[1]
			if f == 5:
				a.player.respawn(Vector2(-260, -2))
				b.player.respawn(Vector2(0, -2))
				Input.action_press("move_right")
			if f == 25:
				Input.action_press("move_down")   # slide into B
			d["bvx"] = maxf(d.get("bvx", 0.0), b.player.velocity.x)
			d["bstun"] = maxf(d.get("bstun", 0.0), b.player.stun_t)
			if f == 120:
				_check("tackle", float(d.bvx) > 400.0 and float(d.bstun) > 0.5,
					"B knocked to %.0f px/s, stunned %.2fs (A slid at %.0f)" % [d.bvx, d.bstun, a.player.velocity.x])
				_next()
		"clash":
			var b2 = lvl.runners[1]
			if f == 5:
				for r in [a, b2]:
					r.player.has_disc = false
				a.disc.launch(Vector2(-300, -300), Vector2(900, 0), 0, 1.0, 0.0, 0.0)
				b2.disc.launch(Vector2(300, -300), Vector2(-900, 0), 0, 1.0, 0.0, 0.0)
				d["spin"] = a.disc.spin
			if f == 60:
				_check("clash", a.disc.velocity.x < 0.0 and b2.disc.velocity.x > 0.0 and a.disc.spin < float(d.spin) * 0.7,
					"after meeting: A disc vx %.0f (was +900), B disc vx %.0f (was -900), A spin %.2f -> %.2f" % [a.disc.velocity.x, b2.disc.velocity.x, d.spin, a.disc.spin])
				_next()
		"hit_head", "hit_arm", "hit_leg", "hit_slow":
			var b3 = lvl.runners[1]
			var up: float = {"hit_head": 42.0, "hit_arm": 24.0, "hit_leg": 14.0, "hit_slow": 24.0}[tests[ti]]
			var slow: bool = tests[ti] == "hit_slow"
			if f == 3:
				a.player.respawn(Vector2(-400, -2))
				b3.player.respawn(Vector2(0, -2))
			if f == 5:
				a.player.has_disc = false
				a.disc.launch(Vector2(-40.0 if slow else -130.0, -2.0 - up), Vector2(220.0 if slow else 1000.0, 0.0), 0, 1.0, 0.0, 0.0)
			d["down"] = maxf(d.get("down", 0.0), b3.player.down_t)
			d["stumble"] = maxf(d.get("stumble", 0.0), b3.player.stumble_t)
			d["slid"] = d.get("slid", false) or b3.player.sliding
			d["stun"] = maxf(d.get("stun", 0.0), b3.player.stun_t)
			if f == 50:
				var dvx: float = a.disc.velocity.x
				match tests[ti]:
					"hit_head":
						_check("hit_head", float(d.down) > 0.9 and dvx < 500.0, "down %.2fs, disc vx after %.0f" % [d.down, dvx])
					"hit_arm":
						_check("hit_arm", not b3.player.has_disc and b3.disc.state == Disc.FLIGHT and float(d.down) == 0.0,
							"B has disc=%s, B disc state %d, down %.2f" % [b3.player.has_disc, b3.disc.state, d.down])
					"hit_leg":
						_check("hit_leg", float(d.stumble) > 0.7 and d.slid and float(d.down) == 0.0, "stumble %.2fs, slid=%s" % [d.stumble, d.slid])
					"hit_slow":
						_check("hit_slow", float(d.stun) == 0.0 and b3.player.has_disc and dvx < 150.0, "stun %.2f, still holding=%s, disc vx %.0f" % [d.stun, b3.player.has_disc, dvx])
				_next()
		"couchcam":
			var b4 = lvl.runners[1]
			if f == 5:
				a.player.respawn(Vector2(-300, -2))
				Input.action_press("move_right")
			if f == 200:
				Input.action_release("move_right")
				a._on_scored()   # A sinks it
				if _game().couch.is_empty():   # no couch set running in this test
					lvl.show_couch_winner_cam(0)
					# finishing place, from a stand-in couch set (restored before any draw)
					_game().couch = {"results": {0: 5.0, 1: 3.0}, "players": [{}, {}, {}]}
					var pl: Vector2i = a.hud.my_place()
					_game().couch = {}
					_check("place", pl == Vector2i(2, 3) and a.hud.ordinal(2) == "2ND" and a.hud.ordinal(11) == "11TH" and a.hud.ordinal(23) == "23RD",
						"A finished %s of %d" % [a.hud.ordinal(pl.x), pl.y])
			if f == 200 + 160:
				var rc = lvl.round_cam
				var cam = rc.get_child(0) if rc and is_instance_valid(rc) else null
				var ok: bool = cam != null and cam.frames.size() > 150 and a.player.visibility_layer & 1 == 0 \
					and b4.player.visibility_layer & 1 == 0
				_check("couchcam", ok, "winner cam up: %s, %d frames, live bodies hidden from it" % [cam != null, cam.frames.size() if cam else 0])
				# click it: full screen, next course held until it has played
				d["small_w"] = cam.sv.size.x
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				rc.gui_input.emit(ev)
			if f == 200 + 162:
				var rc2 = lvl.round_cam
				var cam2 = rc2.get_child(0)
				_check("camfull", lvl.cam_hold and lvl.holding_round() and cam2.sv.size.x > int(d.small_w) * 1.5 and cam2.t < 30.0,
					"clicked: view %d px wide (was %d), restarted at tick %.0f, next course held" % [cam2.sv.size.x, d.small_w, cam2.t])
				cam2.t = float(cam2.frames.size() - 1)   # skip to its end
			if f == 200 + 162 + int(CAM_HOLD * 120.0) + 12:
				var rc3 = lvl.round_cam
				_check("camfull", not lvl.cam_hold, "hold released once the clip played through")
				rc3.queue_free()
			if f == 200 + 162 + int(CAM_HOLD * 120.0) + 17:
				_check("couchcam", a.player.visibility_layer == 1 and b4.player.visibility_layer == 1, "layers back after the cam closes (A %d, B %d)" % [a.player.visibility_layer, b4.player.visibility_layer])
				_next()
		"netclash":
			if f == 5:
				a.player.has_disc = false
				a.disc.launch(Vector2(0, -300), Vector2(800, 0), 0, 1.0, 0.0, 0.0)
			if f == 6:
				# the other player's client reports their disc hit ours. Their view
				# lags: they saw ours 60 px back, theirs 25 px ahead of that
				var seen: Vector2 = a.disc.global_position - Vector2(60, 0)
				_game().get_node("/root/Net").net_clash(seen, seen + Vector2(25, 0), Vector2(-800, 0))
				d["vx"] = a.disc.velocity.x
			if f == 8:
				_check("netclash", float(d.vx) < 0.0, "our disc vx after the reported hit: %.0f (was +800)" % d.vx)
				_next()
	return false


func _next() -> void:
	for act in ["move_right", "move_left", "move_down", "recall", "jump"]:
		Input.action_release(act)
	ti += 1
	if ti >= tests.size():
		print("versus: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		return
	f = 0
	d = {}
	match tests[ti]:
		"solo":
			_start("solo")
		"netclash":
			_start("multi")
			lvl.start_countdown(0.02)
		_:
			_start("couch")
