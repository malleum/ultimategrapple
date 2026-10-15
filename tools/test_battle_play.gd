extends SceneTree
## Battle Rush gameplay on a hand-built course:
##   sword / axe / pike / bow   damage and speed of each weapon on a dummy
##   block + grace              a held block negates a hit; respawn grace
##   enemy_hit                  a patrolling grunt kills; you come back away from it
##   arena                      locks behind you, exit shut until clear, reset on death
##   leader                     killing the leader finishes the run and saves a PB
## godot --headless --fixed-fps 120 -s tools/test_battle_play.gd

const Enemy = preload("res://src/world/enemy.gd")
const Weapons = preload("res://src/combat/weapons.gd")
const Arena = preload("res://src/world/arena.gd")

var lvl
var run
var p
var tests := ["sword", "axe", "pike", "bow", "block", "enemy_hit", "arena", "leader"]
var ti := -1
var f := 0
var fails := 0
var d := {}
var started := false
var dummy


func _level() -> Dictionary:
	return {"version": 8, "id": "test_battle", "name": "B", "theme": "field", "spawn": [0, 0], "basket": [8200, 0],
		"kill_y": 6000, "bounds": [-4000, -3000, 16000, 9000], "battle": {"weapon": "sword"},
		"solids": [{"r": [-4000, 0, 16000, 400], "k": "ground"}],
		"polys": [], "route": [], "medals": {"par": 30, "gold": 30, "silver": 40, "bronze": 60},
		"entities": [
			{"t": "enemy", "k": "grunt", "p": [2000, 0], "x0": 1600, "x1": 2400, "a": -1},
			{"t": "arena", "id": 1, "r": [4032, -512, 1600, 512], "entry": [4000, -512, 32, 512], "exit": [5632, -512, 32, 512], "spawn": [3900, 0], "leader": false},
			{"t": "enemy", "k": "grunt", "p": [5000, 0], "x0": 4800, "x1": 5200, "a": 1},
			{"t": "enemy", "k": "archer", "p": [5300, 0], "x0": 5300, "x1": 5300, "a": 1},
			{"t": "arena", "id": 2, "r": [7032, -512, 1600, 512], "entry": [7000, -512, 32, 512], "exit": [], "spawn": [6900, 0], "leader": true},
			{"t": "enemy", "k": "leader", "p": [8200, 0], "x0": 7600, "x1": 8500, "a": 2}]}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-12s %s" % ["OK  " if ok else "FAIL", name, detail])


## A harmless target: it never moves, attacks or recovers from a hit.
func _dummy(kind: String, x: float) -> Node:
	var e := Enemy.new()
	e.level = lvl
	e.setup({"k": kind, "p": [x, 0], "x0": x, "x1": x, "a": -1}, lvl.th)
	e.cfg = e.cfg.duplicate(true)
	e.cfg["stagger"] = 1e9
	lvl.world.add_child(e)
	lvl.enemies.append(e)
	e.state = Enemy.STAGGER
	e.st = 1e9
	e.face = -1.0
	return e


func _clear_dummy() -> void:
	if dummy != null and is_instance_valid(dummy):
		lvl.enemies.erase(dummy)
		dummy.queue_free()
	dummy = null


func _tap(action: String, at: int, hold := 3) -> void:
	if f == at:
		Input.action_press(action)
	if f == at + hold:
		Input.action_release(action)


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		lvl = root.get_node("Game").play_level(_level())
		run = lvl.runners[0]
		p = lvl.player
		_next()
		return false
	f += 1
	match tests[ti]:
		"sword":
			_tap("throw", 5)
			_tap("throw", 60)
			if f == 40:
				d["hp1"] = dummy.hp
			if f == 120:
				_check("sword", is_equal_approx(float(d.hp1), 1.0) and not dummy.alive(), "grunt hp 3: after one swing %.1f, dead after two (%s)" % [d.hp1, not dummy.alive()])
				_next()
		"axe":
			_tap("throw", 5)
			if f == 30:
				d["alive_early"] = dummy.alive()
			if f == 110:
				_check("axe", d.alive_early and not dummy.alive(), "heavy: still standing mid wind-up (%s), dead from one swing (%s)" % [d.alive_early, not dummy.alive()])
				_next()
		"pike":
			if f == 5:
				Input.action_press("throw")
			if f == 8:
				Input.action_release("throw")
			if f == 60:
				d["still_hp"] = dummy.hp
				dummy.hp = 3.0
				dummy.state = Enemy.STAGGER
				dummy.position.x = -2000.0
				dummy.home.x = -2000.0
				dummy.x0 = -2000.0
				dummy.x1 = -2000.0
				p.respawn(Vector2(-3000.0, 0.0))
				p.aim_override = Vector2(2000.0, -22.0)
				Input.action_press("move_right")
				d["run"] = true
			if f > 60 and d.get("run", false) and not d.has("thrust"):
				if dummy.position.x - p.global_position.x < 220.0:
					Input.action_press("throw")
					d["thrust"] = f
					d["speed"] = p.velocity.length()
			if d.has("thrust") and f == int(d.thrust) + 3:
				Input.action_release("throw")
			if f == 200:
				_check("pike", is_equal_approx(float(d.still_hp), 2.0) and not dummy.alive(),
					"standing thrust leaves hp %.1f (dmg 1.0); at %.0f px/s the thrust kills (%s)" % [d.still_hp, d.get("speed", 0.0), not dummy.alive()])
				_next()
		"bow":
			if f == 5:
				Input.action_press("throw")
			if f == 5 + 90:
				Input.action_release("throw")
			if f == 260:
				_check("bow", not dummy.alive(), "full draw arrow downed an archer 700 px away (alive=%s)" % dummy.alive())
				_next()
		"block":
			if f == 3:
				p.facing = 1.0
				Input.action_press("snap")
			if f == 6:
				Input.action_release("snap")
			if f == 12:
				var held: bool = p.is_blocking()
				var hit_front: bool = p.battle_hit(Vector2(p.global_position.x + 80, 0), "melee")
				_check("block", held and not hit_front and p.state != p.DEAD, "blocking=%s, front hit hurt=%s" % [held, hit_front])
				var hit_back: bool = p.battle_hit(Vector2(p.global_position.x - 80, 0), "melee")
				_check("block_back", hit_back and p.state == p.DEAD, "a hit from behind kills (%s)" % hit_back)
			if f == 14:
				_next()
				d["grace"] = true
		"enemy_hit":
			var g = lvl.enemies[0]
			if f == 2:
				Input.action_press("move_right")
			if f > 2 and p.global_position.x >= 1650.0 and not d.has("stopped"):
				d["stopped"] = true
				Input.action_release("move_right")
			if p.state == p.DEAD and not d.has("died_at"):
				d["died_at"] = p.global_position.x
				d["enemy_x"] = g.position.x
			if d.has("died_at") and run.respawn_t < 0.0 and p.state != p.DEAD and not d.has("back"):
				d["back"] = p.global_position.x
				d["inv"] = p.inv_t
				d["t_back"] = f
			if d.has("back") and f > int(d.t_back) + 2:
				_check("enemy_hit", float(d.back) < float(d.enemy_x) - 340.0 and float(d.inv) > 0.5 and run.deaths == 1,
					"died at x=%.0f next to the grunt (x=%.0f); back at x=%.0f with %.1fs grace, deaths %d" % [d.died_at, d.enemy_x, d.back, d.inv, run.deaths])
				_next()
			if f == 1500:
				_check("enemy_hit", false, "never died to the patrolling grunt (x=%.0f, grunt x=%.0f state %d)" % [p.global_position.x, g.position.x, g.state])
				_next()
		"arena":
			var ar = lvl.arenas[0]
			var ph: int = d.get("ph", 0)
			if ph == 0:
				if f == 2:
					Input.action_press("move_right")
				if ar.state == Arena.LOCKED:
					d["ph"] = 1
					d["t"] = f
			elif ph == 1 and f == int(d.t) + 240:
				_check("arena_lock", p.global_position.x < 5632.0 and ar.exit_body.process_mode != Node.PROCESS_MODE_DISABLED, "locked in, stopped at x=%.0f before the door at 5632" % p.global_position.x)
				Input.action_release("move_right")
				p.die("enemy")
				d["ph"] = 2
				d["t"] = f
			elif ph == 2 and f == int(d.t) + 220:
				var back_ok: bool = ar.state == Arena.IDLE and lvl.enemies[1].alive() and lvl.enemies[1].hp == float(Weapons.ENEMIES.grunt.hp) and p.global_position.x < 4000.0
				_check("arena_reset", back_ok, "after dying the fight is reset (state %d) and you are back at the entrance x=%.0f" % [ar.state, p.global_position.x])
				Input.action_press("move_right")
				d["ph"] = 3
			elif ph == 3 and ar.state == Arena.LOCKED:
				d["ph"] = 4
				d["t"] = f
			elif ph == 4 and f == int(d.t) + 60:
				for e in lvl.enemies:
					if e.arena_id == 1:
						e.take_hit(99.0, e.position.x - 30.0, 0.0, true, 0.0)
				d["ph"] = 5
				d["t"] = f
			elif ph == 5 and f == int(d.t) + 360:
				_check("arena_clear", ar.state == Arena.CLEARED and p.global_position.x > 5700.0, "cleared (state %d), walked out through the exit to x=%.0f" % [ar.state, p.global_position.x])
				_next()
			if f > 4000:
				_check("arena", false, "timeout (phase %d state %d x=%.0f)" % [ph, ar.state, p.global_position.x])
				_next()
		"leader":
			if f == 2:
				Input.action_press("move_right")
			if lvl.arenas[1].state == Arena.LOCKED and not d.has("locked"):
				d["locked"] = f
				Input.action_release("move_right")
				for e in lvl.enemies:
					if e.kind == "leader":
						d["leader"] = e
			if d.has("locked") and f == int(d.locked) + 30:
				d.leader.take_hit(99.0, d.leader.position.x - 30.0, 0.0, true, 0.0)
			if d.has("locked") and f == int(d.locked) + 150:
				var rec = root.get_node("Game").get_record(lvl.level_id)
				_check("leader", run.done and lvl.battle_over and rec != null and run.kills >= 1, "leader slain: run done=%s, PB saved=%s, kills %d, time %.2f" % [run.done, rec != null, run.kills, run.finish_time])
				_next()
			if f > 2500:
				_check("leader", false, "timeout")
				_next()
	return false


func _next() -> void:
	for a in ["move_right", "move_left", "jump", "throw", "snap"]:
		Input.action_release(a)
	_clear_dummy()
	ti += 1
	if ti >= tests.size():
		print("battle play: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		return
	f = 0
	d = {}
	lvl.restart()
	p.weapon = "sword"
	p.aim_override = null
	match tests[ti]:
		"sword", "axe", "pike", "bow":
			p.weapon = tests[ti]
			p.respawn(Vector2(-3000, 0))
			p.facing = 1.0
			p.aim_override = Vector2(-3000 + 600, -22)
			match tests[ti]:
				"bow":
					dummy = _dummy("archer", -3000.0 + 700.0)
					p.aim_override = Vector2(-3000 + 700, -22 - 30)
				"pike":
					dummy = _dummy("grunt", -3000.0 + 60.0)
					p.aim_override = Vector2(-3000 + 600, -22)
				_:
					dummy = _dummy("grunt", -3000.0 + 52.0)
			p.inv_t = 0.0
		"block":
			p.respawn(Vector2(-3000, 0))
			p.inv_t = 0.0
		"enemy_hit":
			p.respawn(Vector2(1200, 0))
			p.inv_t = 0.0
			p.aim_override = Vector2(5000, -22)
		"arena":
			p.respawn(Vector2(3000, 0))
			p.inv_t = 0.0
		"leader":
			p.respawn(Vector2(6000, 0))
			p.inv_t = 0.0
