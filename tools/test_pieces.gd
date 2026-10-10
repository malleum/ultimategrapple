extends SceneTree
## Plays the movement pieces with a scripted runner: each case builds a
## course of one segment (open-green finale), drives the real player through
## it with a simple per-piece policy, and checks it reaches the segment's end
## with no deaths (or, for carry cases that the piece is meant to stop, that
## it doesn't). Empty-handed is the common case (throw it ahead, chase it).
##   tailwind_gap  the wind carries a full-speed jump over; carrying it doesn't
##   pad_climb, pit_launch, slide_chute, vent_shaft, drop_shaft, drop_well,
##   switchback, lift_shaft: the intended way through works, several seeds
##   glass_floor   a throw down through the pane, drop into the lane below
##   ring_ledges   a straight throw at the ring builds the ledge (checked
##                 after it lands; the runner then climbs the zig-zag)
## godot --headless --fixed-fps 120 -s tools/test_pieces.gd [-- piece]

const Gen = preload("res://src/level/generator.gd")
const T := 32.0
const ACTS := ["move_left", "move_right", "move_down", "jump"]

var cases: Array = []
var ci := -1
var c: Dictionary = {}
var lvl
var r
var p
var f := 0
var fails := 0
var started := false
var st := {}
var goal := Vector2.ZERO
var x0 := 0.0
var seg_y := 0.0


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-26s %s" % ["OK  " if ok else "FAIL", name, detail])


func _initialize() -> void:
	var only := ""
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		only = a[0]
	var seeds := [11, 23, 37]
	if OS.get_environment("SEED") != "":
		seeds = [int(OS.get_environment("SEED"))]
	for sd in seeds:
		cases.append({"piece": "tailwind_gap", "seed": sd, "carry": false, "pass": true})
		for pc in ["pad_climb", "pit_launch", "slide_chute", "vent_shaft", "drop_shaft", "drop_well", "switchback", "lift_shaft", "glass_floor", "ring_ledges"]:
			cases.append({"piece": pc, "seed": sd, "carry": false, "pass": true})
	cases.append({"piece": "tailwind_gap", "seed": 11, "carry": true, "pass": false})
	if only != "":
		cases = cases.filter(func(e): return e.piece == only)


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		root.get_node("Game").main = root
		_next()
		return false
	f += 1
	if c.is_empty():
		return false
	_drive()
	if OS.get_environment("TRACE") != "" and f % int(OS.get_environment("TRACE")) == 0:
		var lz: Array = _movers().map(func(m): return [(m.position / T).snapped(Vector2(0.1, 0.1)), (m.base_pos / T).snapped(Vector2(0.1, 0.1)), m.move / T])
		print("  t%.2f pos %s v %s floor %s st %s m %s" % [f / 120.0, (p.global_position / T).snapped(Vector2(0.1, 0.1)), p.velocity.round(), p.on_floor, st.keys().filter(func(k): return k != "ents"), [(r.disc.global_position / T).snapped(Vector2(0.1, 0.1)), r.disc.state, p.has_disc]])
	if r.deaths == 0:
		st["last"] = p.global_position
		st["lastv"] = p.velocity
	var reached: bool = p.global_position.x >= goal.x - T and absf(p.global_position.y - goal.y) < 2.0 * T and p.on_floor
	var died: bool = r.deaths > 0
	var timeout := f > int(c.get("limit", 12.0) * 120.0)
	if reached or died or timeout:
		var ok: bool = (reached and not died) == bool(c.pass)
		var what := "reached in %.2fs" % (f / 120.0) if reached and not died else ("died at %s (v %s)" % [(st.last / T).round(), st.lastv.round()] if died else "stuck at %s" % [(p.global_position / T).round()])
		_check("%s s%d %s" % [c.piece, c.seed, "carry" if c.carry else "empty"], ok, what + ("" if c.pass else "  (meant to stop it)"))
		_next()
	return false


func _release() -> void:
	for a in ACTS:
		Input.action_release(a)


func _hold(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)


func _next() -> void:
	_release()
	ci += 1
	if ci >= cases.size():
		print("pieces: %d failures" % fails)
		quit(0 if fails == 0 else 1)
		c = {}
		return
	c = cases[ci]
	var g := Gen.new()
	g.force_segments = [c.piece]
	g.force_finale = 0
	var data := g.generate(int(c.seed), "field", 0.6, 1)
	lvl = root.get_node("Game").play_level(data)
	r = lvl.runners[0]
	p = r.player
	goal = Vector2(float(data.basket[0]) - 22.0 * T, float(data.basket[1]))
	x0 = 8.0 * T
	seg_y = 0.0
	st = {"ents": data.entities}
	f = 0
	if c.piece in ["glass_floor", "ring_ledges"]:
		c["limit"] = 14.0
	if not c.carry and not c.piece in ["glass_floor", "ring_ledges"]:
		# thrown on ahead: it waits past the segment
		p.has_disc = false
		r.disc.launch(goal + Vector2(10.0 * T, -40.0), Vector2.ZERO, 0, 1.0, 0.0, 0.0)


## Hop a floor spike strip just ahead (on the floor we're on).
func _spike_hop(dir: float) -> void:
	if not p.on_floor:
		return
	var px: float = p.global_position.x
	var py: float = p.global_position.y
	for e in st.ents:
		if str(e.t) != "spikes" or str(e.get("dir", "")) != "up":
			continue
		var top := float(e.r[1]) + float(e.r[3])
		if absf(top - py) > 8.0:
			continue
		var near_x := float(e.r[0]) if dir > 0.0 else float(e.r[0]) + float(e.r[2])
		var ahead := (near_x - px) * dir
		if ahead > 0.0 and ahead < 2.2 * T:
			st["hop"] = f
			Input.action_press("jump")
			return


## Per-piece policy: Input presses only (what a player could do).
func _drive() -> void:
	var px: float = p.global_position.x
	var py: float = p.global_position.y
	if st.has("hop") and f - int(st.hop) == 14 and c.piece in ["drop_well", "switchback"]:
		Input.action_release("jump")
	match c.piece:
		"tailwind_gap":
			_hold("move_right", true)
			var edge := _gap_edge()
			if not st.has("j1") and p.on_floor and px > edge - 1.2 * T:
				st["j1"] = f
				_hold("jump", true)
			elif st.has("j1") and not st.has("j2") and p.velocity.y > -40.0 and f - int(st.j1) > 6:
				st["j2"] = f
				_hold("jump", false)
			elif st.has("j2") and f - int(st.j2) == 2:
				_hold("jump", true)
		"pad_climb", "pit_launch":
			_hold("move_right", true)
		"slide_chute":
			_hold("move_right", true)
			var tun := _tunnel()
			_hold("move_down", px > tun.x - 3.0 * T and px < tun.y + T)
			# the kicker: jump off its lip
			if px > tun.y + 2.0 * T and p.on_floor and not st.has("kick") and px > tun.y + 5.0 * T:
				st["kick"] = true
				_hold("jump", true)
		"vent_shaft":
			# into the shaft, rise up the middle, out right at the top
			var mid := x0 + 9.0 * T
			var high: bool = py < goal.y + 1.5 * T
			if px < mid - 2.0 * T or high:
				_hold("move_right", true)
				_hold("move_left", false)
			else:
				_steer(mid)
			_hold("jump", px > x0 + 6.0 * T)
		"drop_shaft":
			# off the edge, then steer for the middle of the shaft on the way down
			var mid := x0 + 10.5 * T
			if p.on_floor or py > goal.y - 3.0 * T:
				_hold("move_right", true)
				_hold("move_left", false)
			else:
				var want := clampf((mid - px) * 5.0, -350.0, 350.0)
				_hold("move_right", p.velocity.x < want - 60.0)
				_hold("move_left", p.velocity.x > want + 60.0)
		"drop_well", "switchback":
			# floor index from the entry floor: even floors run right, odd left
			var up: bool = c.piece == "switchback"
			var fl := int(round(absf(py) / (6.0 * T)))
			var right := fl % 2 == 0
			var w_lo := x0 - 2.0 * T
			_hold("move_right", right)
			_hold("move_left", not right)
			if not st.has("jt"):
				_spike_hop(1.0 if right else -1.0)
			if up and p.on_floor:
				# under the gap to the next floor: jump, then double jump
				var hole_x: float = st.get("hole_e", -1.0) if right else st.get("hole_w", -1.0)
				if hole_x < 0.0:
					_find_holes()
					hole_x = st.get("hole_e", -1.0) if right else st.get("hole_w", -1.0)
				if fl < int(st.get("floors", 0)) and absf(px - hole_x) < 1.5 * T:
					st["jt"] = f
					_hold("jump", true)
			if up and st.has("jt"):
				var dt := f - int(st.jt)
				if dt == 20:
					_hold("jump", false)
				elif dt == 24:
					_hold("jump", true)
				elif dt == 50:
					_hold("jump", false)
					st.erase("jt")
		"lift_shaft":
			_lift()
		"glass_floor":
			var pane := _ent_rect("glass")
			if not st.has("thrown") and p.on_floor and absf(p.velocity.x) < 1.0 and px > pane.position.x - 2.0 * T:
				# throw it down at the pane, then follow it through
				st["thrown"] = f
				_throw_at(pane.get_center() + Vector2(T, 10), 1200.0, false)
			_hold("move_right", (st.has("thrown") and f - int(st.thrown) > 30) or px < pane.position.x - 1.5 * T)
		"ring_ledges":
			var ring := _ring()
			if not st.has("thrown"):
				st["thrown"] = true
				_throw_at(ring, 1500.0)
			if f == 240 and not r.gates[0].triggered:
				_check("ring_ledges s%d ring" % c.seed, false, "a straight throw at the ring didn't build the ledge")
			_climb_zigzag()


func _ent_rect(kind: String) -> Rect2:
	for e in st.ents:
		if str(e.t) == kind:
			return Rect2(float(e.r[0]), float(e.r[1]), float(e.r[2]), float(e.r[3]))
	return Rect2()


func _ring() -> Vector2:
	for e in st.ents:
		if str(e.t) == "gate" and e.has("ring"):
			return Vector2(float(e.ring[0]), float(e.ring[1]))
	return Vector2.ZERO


## A throw from the hand straight at a point (no snap needed: a clean release).
func _throw_at(target: Vector2, speed: float, lob := true) -> void:
	var from: Vector2 = p.hand()
	p.has_disc = false
	# aim above it by the drop over the flight (forehand: ~720 px/s^2, less some lift)
	var t := from.distance_to(target) / speed
	var aim := target + Vector2(0, -0.5 * 500.0 * t * t if lob else 0.0)
	r.disc.launch(from, (aim - from).normalized() * speed, 1, 1.0, 0.0, 0.0, 1.0)


## Ring ledges: on the ledge if it's there, else up the zig-zag.
func _climb_zigzag() -> void:
	var px: float = p.global_position.x
	var py: float = p.global_position.y
	var dr: Rect2 = r.gates[0].door_rect
	var wall_x := dr.end.x
	if r.gates[0].triggered:
		# from the side: up onto the ledge, then from it up onto the top
		var on_ledge: bool = p.on_floor and absf(py - dr.position.y) < 6.0
		if st.has("jt"):
			on_ledge = bool(st.jt_ledge)     # the jump we're in
		var on_top: bool = p.on_floor and py < dr.position.y - 2.0 * T
		if on_top:
			_hold("move_right", true)
			_hold("move_left", false)
			return
		var from_x := dr.position.x - 2.0 * T if not on_ledge else dr.end.x - 2.5 * T
		var land_x := dr.get_center().x if not on_ledge else wall_x + 3.0 * T
		var land_y := dr.position.y if not on_ledge else goal.y
		if p.on_floor and not st.has("jt"):
			if absf(px - from_x) > 10.0 or absf(p.velocity.x) > 60.0:
				_steer(from_x)
				return
			st["jt"] = f
			st["jt_ledge"] = on_ledge
		if st.has("jt"):
			var k := f - int(st.jt)
			_hold("jump", k < 20 or (k > 24 and k < 50))
			if py < land_y + (1.5 * T if on_ledge else -0.3 * T) or (k > 30 and not on_ledge and py < dr.position.y):
				_steer(land_x)
			else:
				_hold("move_right", false)
				_hold("move_left", false)
			if k > 70 or (k > 10 and p.on_floor):
				st.erase("jt")
		return
	_hold("move_right", px < wall_x - 16.0 * T)


func _gap_edge() -> float:
	for e in st.ents:
		if str(e.t) == "wind":
			return float(e.r[0]) + 2.0 * T
	return INF


func _tunnel() -> Vector2:
	for e in st.ents:
		if str(e.t) == "spikes" and str(e.get("dir", "")) == "down":
			return Vector2(float(e.r[0]), float(e.r[0]) + float(e.r[2]))
	return Vector2(INF, INF)


## Switchback gaps: the oneway steps mark them.
func _find_holes() -> void:
	var steps: Array = []
	for s in lvl.level_data.solids:
		if str(s.k) == "oneway":
			steps.append(Vector2(float(s.r[0]) + 48.0, float(s.r[1])))
	st["floors"] = steps.size()
	var xs := steps.map(func(v): return v.x)
	if xs.is_empty():
		return
	st["hole_e"] = xs.max()
	st["hole_w"] = xs.min()


## Air steering toward x: aim for a speed proportional to the distance.
func _steer(tx: float) -> void:
	var want := clampf((tx - p.global_position.x) * 6.0, -600.0, 600.0)
	_hold("move_right", p.velocity.x < want - 40.0)
	_hold("move_left", p.velocity.x > want + 40.0)


func _movers() -> Array:
	var out: Array = []
	for n in lvl.world.get_children():
		if n.get("move") is Vector2 and n.get("period") != null and n.has_meta("rect"):
			out.append(n)
	out.sort_custom(func(a, b): return a.base_pos.y > b.base_pos.y)
	return out


## Lift shaft: start the clock, step onto the first lift at the bottom of its
## run, ride it up, hop across onto the next as it bottoms out, and so on.
func _lift() -> void:
	var ms := _movers()
	var stage: int = st.get("stage", 0)
	if f < 4:
		_hold("move_left", true)
		return
	_hold("move_left", false)
	if stage >= ms.size():
		_hold("move_right", true)
		return
	var m = ms[stage]
	var mr: Rect2 = m.get_meta("rect")
	var cx := mr.get_center().x
	var px: float = p.global_position.x
	var low: float = (m.position.y - m.base_pos.y) > -6.0       # near the bottom of its run
	var riding: bool = p.on_floor and absf(p.global_position.y - mr.position.y) < 6.0 and absf(px - cx) < mr.size.x * 0.5
	if riding:
		_hold("move_right", false)
		_hold("move_left", false)
		_hold("jump", false)
		# at the top: on to the next one (it's at the bottom of its run now)
		if (m.position.y - m.base_pos.y) < m.move.y + 6.0:
			st["stage"] = stage + 1
			st["hop"] = f
		return
	if st.has("hop") and f - int(st.hop) < 40:
		# hop across to the next lift
		_steer(cx)
		_hold("jump", f - int(st.hop) < 10)
		return
	# first lift: wait beside it, jump on from the side as it bottoms out
	if stage == 0 and p.on_floor:
		var wait_x := mr.position.x - 1.4 * T
		if absf(px - wait_x) > 8.0 and not st.has("board"):
			_hold("move_right", px < wait_x)
			_hold("move_left", px > wait_x)
			return
		if (m.position.y - m.base_pos.y) > -3.0 and not st.has("board"):
			st["board"] = f
		_hold("move_right", false)
		_hold("move_left", false)
	if st.has("board") and not riding:
		var k := f - int(st.board)
		_hold("jump", k < 12)
		_steer(cx)
		if k > 90:
			st.erase("board")
