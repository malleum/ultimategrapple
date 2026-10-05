extends SceneTree
## Which throws open each throw puzzle? Builds a course of one generator
## segment, then throws every type at many angles / powers / noses from the
## floor in front of each gate's door (standing, perfect snap) and counts the
## throws that set the gate off. A puzzle should open to its throw (roller
## plates: roller only; lob walls: hammer, maybe a stalled lob) and stay shut
## to the rest.
## godot --headless --fixed-fps 120 -s tools/piece_check.gd [-- piece seeds]

const Gen = preload("res://src/level/generator.gd")
const Solid = preload("res://src/world/solid.gd")
const Gate = preload("res://src/world/gate.gd")
const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const HAND_Y := -44.0 * 0.72
const MAX_T := 6.0


class FakeLevel:
	extends Node
	var kill_y := 100000.0
	var has_basket := false
	var basket_pos := Vector2.ZERO


var pieces: Array = ["roll_lane", "lob_wall", "stacked", "disc_gate"]
var seeds := 3
var queue: Array = []      # [{piece, seed, gate index}]
var world: Node2D
var fake: FakeLevel
var gates: Array = []
var gate: Node = null
var runs: Array = []
var type_i := 0
var frames := 0
var hits := {}
var speeds := {}
var tried := {}
var examples := {}
var job := {}
var started := false


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		var args := OS.get_cmdline_user_args()
		if args.size() >= 1:
			pieces = [args[0]]
		if args.size() >= 2:
			seeds = int(args[1])
		for p in pieces:
			for sd in seeds:
				queue.append({"piece": p, "seed": 7000 + sd * 31})
		_next_job()
		return false
	frames += 1
	var live := 0
	for e in runs:
		if e.done:
			continue
		var d = e.d
		if gate.hit_by(d.global_position, d.state == Disc.ROLL) and not e.hit:
			e.hit = true
			e["spd"] = d.velocity.length()
		if e.hit or d.state == Disc.REST or frames > MAX_T * 120 or d.global_position.y > fake.kill_y:
			e.done = true
			if e.hit:
				var ty: String = ThrowTypes.get_type(type_i).id
				hits[ty] = int(hits.get(ty, 0)) + 1
				var sp: Array = speeds.get(ty, [])
				sp.append(int(e.spd))
				speeds[ty] = sp
				if not examples.has(ty):
					examples[ty] = "x-%0.1f tiles %d° p%.2f nose %+d°" % [e.back, e.deg, e.pow, e.nose]
			d.queue_free()
		else:
			live += 1
	if live == 0:
		type_i += 1
		if type_i >= ThrowTypes.count():
			_report_job()
			if not _next_job():
				quit()
				return true
		else:
			_launch_batch()
	return false


func _next_job() -> bool:
	if world:
		world.queue_free()
	if queue.is_empty():
		return false
	job = queue.pop_front()
	var g := Gen.new()
	g.force_segments = [job.piece]
	var data := g.generate(int(job.seed), "field", 0.6, 1)
	world = Node2D.new()
	root.add_child(world)
	fake = FakeLevel.new()
	fake.kill_y = float(data.kill_y)
	world.add_child(fake)
	for s in data.solids:
		var r: Array = s.r
		var n := Solid.new()
		n.setup(str(s.k), Rect2(r[0], r[1], r[2], maxf(r[3], 8)), {})
		world.add_child(n)
	for pp in data.polys:
		var pts := PackedVector2Array()
		var arr: Array = pp.pts
		for i in range(0, arr.size(), 2):
			pts.append(Vector2(arr[i], arr[i + 1]))
		var n2 := Solid.new()
		n2.setup(str(pp.k), Rect2(), {}, pts)
		world.add_child(n2)
	gates = []
	for e in data.entities:
		if str(e.t) == "gate":
			var gt := Gate.new()
			gt.setup(e, {})
			world.add_child(gt)
			gt.set_physics_layer(Solid.FENCE_LAYER if gt.fence else 1)
			gates.append(gt)
	# one job per gate in the course
	if not job.has("gate"):
		for i in range(1, gates.size()):
			queue.push_front({"piece": job.piece, "seed": job.seed, "gate": i})
		job["gate"] = 0
	gate = gates[int(job.gate)]
	hits = {}
	speeds = {}
	examples = {}
	tried = {}
	type_i = 0
	_launch_batch.call_deferred()
	return true


## Where a runner can stand in front of the door: the floor under it, from
## 1.2 to 15 tiles before it (wherever there is floor, inside any tunnel).
func _stands() -> Array:
	var out: Array = []
	var dr: Rect2 = gate.door_rect
	var floor_y := dr.end.y
	var space := world.get_world_2d().direct_space_state
	var back := 1.2
	while back <= 15.0:
		var x := dr.position.x - back * 32.0
		var q := PhysicsRayQueryParameters2D.create(Vector2(x, floor_y - 40.0), Vector2(x, floor_y + 20.0), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(float(hit.position.y) - floor_y) < 18.0:
			out.append({"x": x, "y": float(hit.position.y), "back": back})
		back += 1.6
	return out


func _launch_batch() -> void:
	frames = 0
	runs = []
	var ty: Dictionary = ThrowTypes.get_type(type_i)
	for st in _stands():
		for deg in range(-10, 89, 4):
			for pw in [0.6, 0.8, 1.0]:
				for nose_deg in [0, 15]:
					var d := Disc.new()
					d.level = fake
					world.add_child(d)
					var dir := Vector2.RIGHT.rotated(-deg_to_rad(deg))
					var from := Vector2(st.x, st.y + HAND_Y) + dir * 16.0
					var lp := ThrowTypes.launch_params(ty, pw, 1.0, 0.0, 0.0)
					d.launch(from, dir * float(lp.speed), type_i, lp.spin, deg_to_rad(nose_deg), lp.wobble, lp.quality)
					runs.append({"d": d, "hit": false, "done": false, "back": st.back, "deg": deg, "pow": pw, "nose": nose_deg})
	tried[ty.id] = runs.size()


func _report_job() -> void:
	var parts: Array = []
	for i in ThrowTypes.count():
		var id: String = ThrowTypes.get_type(i).id
		parts.append("%s %d/%d" % [id, int(hits.get(id, 0)), int(tried.get(id, 0))])
	print("%-10s seed %d gate %d (%s): %s" % [job.piece, int(job.seed), int(job.gate), "plate" if gate.plate.size.x > 0 else ("fence" if gate.fence else "ring"), ", ".join(PackedStringArray(parts))])
	for k in examples:
		var sp: Array = speeds.get(k, [])
		sp.sort()
		print("    e.g. %-8s %s   speed at the gate %d..%d (median %d)" % [k, examples[k], sp[0], sp[-1], sp[sp.size() / 2]])
