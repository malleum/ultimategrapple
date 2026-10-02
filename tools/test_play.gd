extends SceneTree
## Headless gameplay smoke test: builds levels, drives the player with scripted
## input (run, jump, slide, dash, grapple, throw with snap, pivot) and reports.
## godot --headless --fixed-fps 120 -s tools/test_play.gd

const Disc = preload("res://src/disc/disc.gd")

var lvl
var frame := 0
var script_steps := []
var log_lines := []
var level_idx := 0
var seeds := [7, 42, 1234, 99, 555]


var started := false


func _initialize() -> void:
	pass


func _next_level() -> void:
	if level_idx >= seeds.size():
		if level_idx == seeds.size():
			_couch_test()
			level_idx += 1
			return
		for l in log_lines:
			print(l)
		quit()
		return
	var Game = root.get_node("Game")
	Game.main = root
	var data: Dictionary = Game.generate_level(seeds[level_idx], "", 0.6, 10)
	lvl = Game.play_level(data)
	frame = 0
	level_idx += 1


func _couch_test() -> void:
	var Game = root.get_node("Game")
	const PI_ = preload("res://src/core/player_input.gd")
	var data: Dictionary
	var has_gate := false
	var sd := 70
	while not has_gate:
		sd += 1
		data = Game.generate_level(sd, "field", 0.5, 8)
		for e in data.entities:
			if e.t == "gate":
				has_gate = true
	var locals := [{"input": PI_.new(PI_.KBM), "name": "A", "color": Color(0, 1, 1)}, {"input": PI_.new(0), "name": "B", "color": Color(1, 0, 1)}]
	lvl = Game.play_level(data, "couch", locals)
	var r0 = lvl.runners[0]
	var r1 = lvl.runners[1]
	var msg := "couch: runners=%d views=%s,%s layers p0=%d p1=%d gates=%d/%d grapple=%d/%d" % [lvl.runners.size(), r0.view.get_class(), r1.view.get_class(), r0.player.collision_mask, r1.player.collision_mask, r0.gates.size(), r1.gates.size(), r0.grapple_points.size(), r1.grapple_points.size()]
	if has_gate and r0.gates.size() > 0:
		r0.gates[0].trigger()
		msg += " | after P1 opens gate: p1 gate=%s p2 gate=%s" % [r0.gates[0].triggered, r1.gates[0].triggered]
	log_lines.append(msg)
	frame = 400


func _press(a: String) -> void:
	Input.action_press(a)


func _release(a: String) -> void:
	Input.action_release(a)


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_next_level()
		return false
	frame += 1
	if lvl == null or not is_instance_valid(lvl) or lvl.player == null:
		return false
	var p = lvl.player
	match frame:
		5:
			_press("move_right")
		60:
			_press("jump")
		80:
			_release("jump")
		100:
			_press("move_down")  # slide
		140:
			_release("move_down")
		150:
			_press("jump")  # double jump
		152:
			_release("jump")
		170:
			# grapple toward the nearest point ahead if any
			var best = null
			for gp in lvl.grapple_points:
				if gp.global_position.x > p.global_position.x and (best == null or gp.global_position.distance_to(p.center()) < best.global_position.distance_to(p.center())):
					best = gp
			if best:
				p.aim_override = best.global_position
			_press("grapple")
		230:
			_release("grapple")
			p.aim_override = p.center() + Vector2(600, -200)
		240:
			_press("pivot")
			_press("throw")
		290:
			_press("snap")
			_release("throw")
		291:
			_release("snap")
		300:
			_release("pivot")
		420:
			_release("move_right")
			var d = lvl.disc
			log_lines.append("level %s (%s, %d segs): player x=%.0f y=%.0f state=%d throws=%d disc_state=%d disc_x=%.0f spin=%.2f deaths=%d time=%.2f snap=%s" % [
				lvl.level_data.name, lvl.level_data.theme, lvl.level_data.segments.size(), p.global_position.x, p.global_position.y, p.state, p.throws, d.state, d.global_position.x, d.spin, lvl.runners[0].deaths, lvl.runners[0].total_time(), p.last_snap_quality])
		430:
			# teleport disc into the basket region to verify scoring
			var d2 = lvl.disc
			# the blind scripted run may have died: clear that so a pending
			# respawn doesn't snatch the disc back before it scores
			lvl.runners[0].respawn_t = -1.0
			if p.state == 4:
				p.respawn(lvl.spawn)
			p.recall()
			p.aim_override = lvl.basket_pos + Vector2(0, -80)
			p.has_disc = false
			d2.launch(lvl.basket_pos + Vector2(-60, -80), Vector2(300, 0), 0, 1.0, 0.0, 0.0)
		520:
			log_lines.append("   scored=%s done=%s finish=%.2f" % [str(lvl.disc.state == Disc.SCORED), str(lvl.done), lvl.runners[0].finish_time])
			_next_level()
	return false
