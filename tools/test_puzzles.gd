extends SceneTree
## Throw puzzles in real courses (generator segments, real runner):
##   chase     a chase gap can't be jumped with the disc in hand, and can
##             once the disc is thrown across
##   fence     the roller lane's fence stops the runner; a backhand along the
##             floor doesn't set the plate off, a roller does, then the fence
##             is open
##   slick     wall-jumping up a lob wall's slick face gets nowhere
##   sunken    a roller rolled off the lip of a sunken basket scores
##   clock     saws stand still at their start until the run starts, and are
##             back there after a restart; a RETRY while a key is held waits
##             for it to be let go
## godot --headless --fixed-fps 120 -s tools/test_puzzles.gd

const Gen = preload("res://src/level/generator.gd")
const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")

var G
var lvl
var r
var f := 0
var phase := "chase_load"
var fails := 0
var started := false
var aim := Vector2.ZERO
var m := {}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _course(segs: Array, finale := -1) -> Dictionary:
	var g := Gen.new()
	g.force_segments = segs
	g.force_finale = finale
	return g.generate(4242, "field", 0.6, 1)


func _play(data: Dictionary) -> void:
	_release_all()
	lvl = G.play_level(data)
	r = null
	f = 0


func _release_all() -> void:
	for a in ["move_right", "move_left", "jump", "move_down", "throw"]:
		Input.action_release(a)


func _slicks() -> Array:
	var out: Array = []
	for s in lvl.level_data.solids:
		if str(s.k) == "slick":
			out.append(Rect2(s.r[0], s.r[1], s.r[2], s.r[3]))
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


func _put(p: Vector2) -> void:
	r.player.respawn(p)
	r.player.velocity = Vector2.ZERO
	r.player.reset_physics_interpolation()


func _launch(from: Vector2, vel: Vector2, type_id: String) -> void:
	var ti := 0
	for i in ThrowTypes.count():
		if ThrowTypes.get_type(i).id == type_id:
			ti = i
	r.player.has_disc = false
	r.disc.launch(from, vel, ti, 1.0, 0.0, 0.1, 1.0)


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		G = root.get_node("Game")
		G.main = root
	f += 1
	if lvl and r == null and is_instance_valid(lvl) and not lvl.runners.is_empty():
		r = lvl.runners[0]
		r.inp.mouse_world_fn = func() -> Vector2: return aim
	if r:
		aim = r.player.center() + Vector2(600, -100)
	match phase:
		"chase_load":
			_play(_course(["chase_gap"]))
			phase = "chase_carry"
		"chase_carry":
			# run at it carrying the disc: jump at the edge, double jump at the top
			var sl := _slicks()
			if f == 3:
				m["x0"] = sl[0].end.x
				m["x1"] = sl[1].position.x
				m["y"] = sl[0].position.y
				_put(Vector2(float(m.x0) - 640.0, float(m.y)))
				Input.action_press("move_right")
			if f > 3 and not m.has("jumped") and r.player.global_position.x > float(m.x0) - 6.0:
				m["jumped"] = f
				Input.action_press("jump")
			if m.has("jumped") and f == int(m.jumped) + 20:
				Input.action_release("jump")
			if m.has("jumped") and f == int(m.jumped) + 26:
				Input.action_press("jump")
			if m.has("jumped") and f == int(m.jumped) + 200:
				var p: Vector2 = r.player.global_position
				var crossed: bool = p.x > float(m.x1) and absf(p.y - float(m.y)) < 140.0 and r.player.state != r.player.DEAD
				_check("carry", not crossed and r.player.has_disc, "carrying: gap %.1f tiles, ended at x %+.0f px past the far edge (y %+.0f): %s" % [
					(float(m.x1) - float(m.x0)) / 32.0, p.x - float(m.x1), p.y - float(m.y), "fell" if not crossed else "MADE IT"])
				_release_all()
				m.erase("jumped")
				phase = "chase_empty"
				f = 0
		"chase_empty":
			# throw the disc across first, then the same jump empty-handed
			if f == 3:
				lvl.restart()
			if f == 5:
				_put(Vector2(float(m.x0) - 640.0, float(m.y)))
				_launch(r.player.hand(), Vector2(900, -420), "backhand")
				Input.action_press("move_right")
			if f > 5 and not m.has("jumped") and r.player.global_position.x > float(m.x0) - 6.0:
				m["jumped"] = f
				Input.action_press("jump")
			if m.has("jumped") and f == int(m.jumped) + 20:
				Input.action_release("jump")
			if m.has("jumped") and f == int(m.jumped) + 26:
				Input.action_press("jump")
			if m.has("jumped") and f == int(m.jumped) + 200:
				var p2: Vector2 = r.player.global_position
				var made: bool = p2.x > float(m.x1) and absf(p2.y - float(m.y)) < 140.0
				_check("chase", made, "empty-handed after throwing it across: landed %+.0f px past the far edge" % (p2.x - float(m.x1)))
				_release_all()
				phase = "fence_load"
		"fence_load":
			_play(_course(["roll_lane"]))
			phase = "fence_walk"
		"fence_walk":
			if f == 3:
				var gt = r.gates[0]
				m["door"] = gt.door_rect
				_put(Vector2(gt.door_rect.position.x - 200.0, gt.door_rect.end.y))
				Input.action_press("move_right")
			if f == 120:
				var dr: Rect2 = m.door
				_check("fence", r.player.global_position.x < dr.position.x and not r.gates[0].triggered, "walked into the fence: stopped %.0f px before it" % (dr.position.x - r.player.global_position.x))
				_release_all()
				# a backhand skimmed along the floor through the fence: not a roll
				_launch(r.player.hand(), Vector2(900, 60), "backhand")
			if f == 400:
				m["bh"] = r.gates[0].triggered
				r.player.has_disc = true
				r.disc.hold()
				_launch(r.player.hand(), Vector2(700, 80), "roller")
			if f == 700:
				_check("plate", not bool(m.bh) and r.gates[0].triggered, "backhand opened it: %s; roller opened it: %s" % [m.bh, r.gates[0].triggered])
				Input.action_press("move_right")
			if f == 820:
				var dr2: Rect2 = m.door
				_check("open", r.player.global_position.x > dr2.end.x + 20.0, "walked through the open fence: %+.0f px past it" % (r.player.global_position.x - dr2.end.x))
				_release_all()
				phase = "slick_load"
		"slick_load":
			_play(_course(["lob_wall"]))
			phase = "slick_climb"
		"slick_climb":
			if f == 3:
				var gt2 = r.gates[0]
				m["floor"] = gt2.door_rect.end.y
				m["top"] = float(m.floor)
				_put(Vector2(gt2.door_rect.position.x - 60.0, gt2.door_rect.end.y))
				Input.action_press("move_right")
			if f > 3 and f < 600:
				# mash jump against the wall
				if f % 14 == 0:
					Input.action_press("jump")
				elif f % 14 == 6:
					Input.action_release("jump")
				m["top"] = minf(float(m.top), r.player.global_position.y)
			if f == 600:
				var climbed: float = (float(m.floor) - float(m.top)) / 32.0
				_check("slick", climbed < 9.5 and not r.gates[0].triggered, "best height wall-jumping at the slick wall: %.1f tiles (wall %d+)" % [climbed, Gen.WALL_TALL])
				_release_all()
				phase = "sunk_load"
		"sunk_load":
			_play(_course(["run_gaps"], 5))
			phase = "sunk_roll"
		"sunk_roll":
			if f == 3:
				var bp: Vector2 = lvl.basket_pos
				# the lip is 2.5 tiles before the pole, 3 tiles higher
				_put(Vector2(bp.x - 420.0, bp.y - 96.0))
			if f == 10:
				_launch(r.player.hand(), Vector2(700, 60), "roller")
			if f == 400:
				_check("sunken", r.disc.state == Disc.SCORED and r.done, "roller off the lip: disc state %d, finished %s" % [r.disc.state, r.done])
				phase = "clock_load"
		"clock_load":
			_play(_course(["saws"]))
			phase = "clock"
		"clock":
			var saws: Array = []
			for c in lvl.world.get_children():
				if c.has_meta("saw"):
					saws.append(c)
			if f == 5:
				m["p0"] = saws.map(func(z): return z.position)
			if f == 200:
				var still: bool = saws.map(func(z): return z.position) == m.p0
				m["still"] = still
				Input.action_press("move_right")
			if f == 320:
				var moved: bool = saws.map(func(z): return z.position) != m.p0
				Input.action_press("jump")   # held through the RETRY
				lvl.restart_when_released()
				m["moved"] = moved
			if f == 330:
				m["waited"] = r.running
				Input.action_release("jump")
				Input.action_release("move_right")
			if f == 340:
				var back: bool = saws.map(func(z): return z.position) == m.p0
				_check("clock", bool(m.still) and bool(m.moved) and back and bool(m.waited) and not r.running and saws.size() > 0,
					"%d saws: still before the start %s, moving once running %s, RETRY waited for the key %s, back at the start %s" % [saws.size(), m.still, m.moved, m.waited, back])
				print("puzzles: %d failures" % fails)
				quit(0 if fails == 0 else 1)
				return true
	return false
