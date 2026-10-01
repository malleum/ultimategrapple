extends SceneTree
## Snap timing -> distance, using the real disc + shared launch math.
## Carry at each throw's best carry angle for a range of |snap - release| gaps,
## plus late snaps (snap after release) to show they match early ones.
## godot --headless --fixed-fps 120 -s tools/snap_table.gd
const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const HAND_Y := -44.0 * 0.72
const ANGLES := {"backhand": 16, "forehand": 20, "hammer": 34, "roller": 37, "scoober": 33, "thumber": 41}
# [label, gap ms (-1 = no snap), late?]
const MODES := [
	["0ms", 0.0, false], ["4ms", 4.0, false], ["8ms", 8.3, false], ["17ms", 16.7, false],
	["25ms", 25.0, false], ["35ms", 35.0, false], ["50ms", 50.0, false], ["70ms", 70.0, false],
	["90ms", 90.0, false], ["130ms", 130.0, false], ["none", -1.0, false],
	["8ms late", 8.3, true], ["33ms late", 33.0, true],
]
var runs := []
var f := 0
var started := false

func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		var fb := StaticBody2D.new(); var cs := CollisionShape2D.new(); var r := RectangleShape2D.new()
		r.size = Vector2(400000, 400); cs.shape = r; fb.position = Vector2(100000, 200); fb.add_child(cs); root.add_child(fb)
		for ti in ThrowTypes.count():
			var ty: Dictionary = ThrowTypes.get_type(ti)
			var deg: int = ANGLES[ty.id]
			for m in MODES:
				var d := Disc.new()
				root.add_child(d)
				var dir := Vector2.RIGHT.rotated(-deg_to_rad(deg))
				var score: float = 0.0 if m[1] < 0.0 else ThrowTypes.snap_score(int(m[1] * 1000.0))
				var launch_score := 0.0 if m[2] else score
				var lp := ThrowTypes.launch_params(ty, 1.0, launch_score, 0.0, 0.0)
				d.launch(Vector2(0, HAND_Y) + dir * 16.0, dir * float(lp.speed), ti, lp.spin, 0.0, lp.wobble, lp.quality)
				var e := {"d": d, "ty": ty, "dir": dir, "mode": m[0], "late": m[2], "delay": m[1] / 1000.0, "score": score, "touch": -1.0, "done_late": false}
				d.impact.connect(func(_k, _s): if e.touch < 0.0: e.touch = d.global_position.x)
				runs.append(e)
		return false
	f += 1
	var all_done := true
	for e in runs:
		var d = e.d
		if e.late and not e.done_late and d.age >= e.delay:
			e.done_late = true
			var cur := ThrowTypes.launch_params(e.ty, 1.0, 0.0, 0.0, 0.0)
			var lp := ThrowTypes.launch_params(e.ty, 1.0, e.score, 0.0, 0.0)
			d.apply_late_snap(lp.spin, e.dir * (float(lp.speed) - float(cur.speed)), lp.wobble, lp.quality)
		if e.touch < 0.0:
			all_done = false
	if all_done or f > 120 * 20:
		var head := "%-11s %-6s" % ["gap", "score"]
		for ty in ANGLES:
			head += "%10s" % ty
		print(head)
		for m in MODES:
			var line := ""
			for ty in ANGLES:
				for e in runs:
					if e.mode == m[0] and e.ty.id == ty:
						if line == "":
							line = "%-11s %-6s" % [m[0], "%.2f" % e.score]
						line += "%9.1fm" % (e.touch / 32.0)
			print(line)
		return true
	return false
