extends SceneTree
## Cheese hunt: can a runner get past a piece WITHOUT doing it? Each case
## builds a one-piece course, parks the disc past the end (empty-handed: no
## throw ever opens a gate or breaks glass) and runs a sweep of input
## policies through it with the real player:
##   hop    run, jump at x, double jump after n frames, keep running
##   climb  run, jump at x, wall-jump every wall touched, steer straight
##          back into it (one grippy wall climbs forever), double jump once
##   rand   random holds, mostly right, random jump presses
## A policy that reaches the piece's exit is a cheese when it never passed
## through any of the piece's `musts` (Gen.musts: inside the shaft, the
## tunnel behind the door...), or for pieces with none (the gate is the only
## way, grapple gaps) whenever it gets there at all.
##   godot --headless --fixed-fps 120 -s tools/test_cheese.gd [-- piece [seed]]
## Env FAST=1: fewer policies.

const Gen = preload("res://src/level/generator.gd")
const T := 32.0
const ACTS := ["move_left", "move_right", "move_down", "jump"]

## Pieces checked. "any": reaching the end at all is a cheese (no disc, no
## grapple: the bot can't do the piece's thing). Others use Gen.musts.
const PIECES := {
	"drop_shaft": "musts", "drop_well": "musts", "switchback": "musts", "vent_shaft": "musts",
	"lift_shaft": "musts", "throw_lane": "musts", "roll_lane": "musts", "lob_skylight": "musts",
	"glass_floor": "musts", "pit_launch": "musts", "pad_climb": "musts", "slide_chute": "musts",
	"ring_ledges": "any", "disc_gate": "any", "glass": "any", "disc_bridge": "any",
	"swing_chain": "any", "grip_ceiling": "any", "wrap_block": "any", "crosswind": "any",
	"stacked": "musts", "lasers": "musts",
	# Battle Rush: the enemies stand still (harmless), so only the doors are tested:
	# reaching past the exit door without killing anything is a cheese
	"arena_flat": "arena", "arena_tier": "arena", "arena_shield": "arena",
}
const Enemy = preload("res://src/world/enemy.gd")

var cases: Array = []
var ci := -1
var c: Dictionary = {}
var data: Dictionary
var musts: Array = []
var mode := ""
var pols: Array = []
var pi := -1
var pol: Dictionary = {}
var lvl
var r
var p
var f := 0
var st := {}
var goal := Vector2.ZERO
var x0 := 0.0
var started := false
var cheeses := 0
var case_cheese: Array = []
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var only := a[0] if a.size() > 0 else ""
	var seeds := [11, 23, 37, 4242]
	if a.size() > 1:
		seeds = [int(a[1])]
	for pc in PIECES:
		if only != "" and pc != only:
			continue
		for sd in seeds:
			cases.append({"piece": pc, "seed": sd})


func _policies() -> Array:
	var out: Array = []
	var fast := OS.get_environment("FAST") != ""
	var step := 2.0 if fast else 1.0
	var jx := 0.0
	while jx < 60.0:
		for dj in ([12, 30] if fast else [10, 20, 32, -1]):
			out.append({"k": "hop", "jx": jx, "dj": dj})
		jx += step
	jx = 0.0
	while jx < 60.0:
		out.append({"k": "climb", "jx": jx})
		jx += step * 2.0
	for i in (20 if fast else 60):
		out.append({"k": "rand", "seed": i})
	return out


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		_next_case()
		return false
	if c.is_empty():
		return false
	f += 1
	_drive()
	if OS.get_environment("TRACE") != "" and pi == int(OS.get_environment("TRACE")) and f % 6 == 0:
		print("  %s t%.2f pos %s v %s floor %s wall %d" % [_desc(pol), f / 120.0, (p.global_position / T).snapped(Vector2(0.1, 0.1)), p.velocity.round(), p.on_floor, p.wall_dir])
	var pos: Vector2 = p.global_position
	for m in musts:
		if (m as Rect2).grow(4.0).has_point(pos + Vector2(0, -20)):
			st["must"] = true
	var reached: bool = pos.x >= goal.x - T and absf(pos.y - goal.y) < 2.0 * T and p.on_floor
	var died: bool = r.deaths > 0
	if pos.x > float(st.get("best", -INF)) + 8.0:
		st["best"] = pos.x
		st["best_f"] = f
	var stuck := f - int(st.get("best_f", 0)) > 360
	if reached or died or stuck or f > 1500:
		if reached and not died and (mode == "any" or mode == "arena" or not st.has("must")):
			case_cheese.append("%s (%.1fs)" % [_desc(pol), f / 120.0])
		_next_pol()
	return false


func _desc(q: Dictionary) -> String:
	match q.k:
		"hop": return "hop at +%.0f, dj %d" % [q.jx, q.dj]
		"climb": return "wall climb from +%.0f" % q.jx
	return "random #%d" % q.seed


func _drive() -> void:
	var px: float = p.global_position.x - x0
	for a in ACTS:
		Input.action_release(a)
	match pol.k:
		"hop":
			Input.action_press("move_right")
			if not st.has("j") and p.on_floor and px >= float(pol.jx) * T:
				st["j"] = f
			if st.has("j"):
				var k := f - int(st.j)
				if k < 18:
					Input.action_press("jump")
				elif int(pol.dj) >= 0 and k > int(pol.dj) and k < int(pol.dj) + 20 and k > 20:
					Input.action_press("jump")
		"climb":
			var wd: int = p.wall_dir
			if not st.has("j") and p.on_floor and px >= float(pol.jx) * T:
				st["j"] = f
				st["press"] = f
			if st.has("j") and not p.on_floor and wd != 0 and f - int(st.get("wj", -100)) > 4:
				st["wj"] = f
				st["press"] = f + 1      # a fresh press
				st["side"] = wd
				st["touches"] = int(st.get("touches", 0)) + 1
			var side: int = st.get("side", 1)
			if side > 0:
				Input.action_press("move_right")
			else:
				Input.action_press("move_left")
			# off the top of the wall (no more contact for a while): carry on right
			if st.has("wj") and f - int(st.wj) > 40:
				st["side"] = 1
			var pr := int(st.get("press", -100))
			if f >= pr and f < pr + 14:
				Input.action_press("jump")
			if not st.has("dj") and st.has("wj") and not p.on_floor and p.velocity.y > -40.0 and f - int(st.wj) > 8:
				st["dj"] = true
				st["press"] = f + 1
		_:
			if f % int(st.get("every", 1)) == 0 or not st.has("dir"):
				st["every"] = rng.randi_range(6, 24)
				st["dir"] = 1 if rng.randf() < 0.75 else (-1 if rng.randf() < 0.5 else 0)
				st["jmp"] = rng.randf() < 0.45
				st["down"] = rng.randf() < 0.1
			if int(st.dir) > 0:
				Input.action_press("move_right")
			elif int(st.dir) < 0:
				Input.action_press("move_left")
			if bool(st.jmp):
				Input.action_press("jump")
			if bool(st.down):
				Input.action_press("move_down")


func _next_case() -> void:
	if ci >= 0:
		var n := case_cheese.size()
		if n > 0:
			cheeses += 1
		print("%s %-14s s%-5d %s" % ["CHEESE" if n > 0 else "OK    ", c.piece, c.seed,
			("%d/%d policies, e.g. %s" % [n, pols.size(), ", ".join(case_cheese.slice(0, 3))]) if n > 0 else ""])
	ci += 1
	if ci >= cases.size():
		print("cheese: %d of %d cases" % [cheeses, cases.size()])
		quit(0 if cheeses == 0 else 1)
		c = {}
		return
	c = cases[ci]
	mode = PIECES[c.piece]
	var g := Gen.new()
	g.force_segments = [c.piece]
	g.force_finale = 0
	g.battle = mode == "arena"
	data = g.generate(int(c.seed), "field", 0.7, 1)
	musts = g.musts.duplicate()
	pols = _policies()
	pi = -1
	case_cheese = []
	_next_pol()


func _next_pol() -> void:
	for a in ACTS:
		Input.action_release(a)
	pi += 1
	if pi >= pols.size():
		_next_case()
		return
	pol = pols[pi]
	if pol.k == "rand":
		rng.seed = int(pol.seed) * 7919 + int(c.seed)
	lvl = root.get_node("Game").play_level(data.duplicate(true))
	r = lvl.runners[0]
	p = r.player
	goal = Vector2(float(data.basket[0]) - 22.0 * T, float(data.basket[1]))
	x0 = 8.0 * T
	st = {}
	f = 0
	if mode == "arena":
		for e in data.entities:
			if str(e.t) == "arena" and not (e.exit as Array).is_empty():
				goal = Vector2(float(e.exit[0] + e.exit[2]) + 3.0 * T, float(e.exit[1] + e.exit[3]))
		for en in lvl.enemies:
			en.cfg = en.cfg.duplicate(true)
			en.cfg["stagger"] = 1e9
			en.state = Enemy.STAGGER
			en.st = 1e9
		return
	p.has_disc = false
	r.disc.launch(goal + Vector2(10.0 * T, -40.0), Vector2.ZERO, 0, 1.0, 0.0, 0.0)
