extends SceneTree
## How much the snap matters: carry/total per snap outcome at each throw's best angles.
## godot --headless --fixed-fps 120 -s tools/snap_table.gd
const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const HAND_Y := -44.0 * 0.72
# best carry angle, best total angle (from tools/range_table.gd)
const ANGLES := {"backhand": [16, 14], "forehand": [20, 14], "hammer": [34, 6], "roller": [37, 2], "scoober": [33, 6], "thumber": [41, 7]}
# name, launch quality, late delay (s) and late quality
const MODES := [
	["perfect", "PERFECT", -1.0, ""],
	["perfect-late", "NONE", 0.033, "PERFECT"],
	["good", "GOOD", -1.0, ""],
	["good-late", "NONE", 0.083, "GOOD"],
	["none", "NONE", -1.0, ""],
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
			for which in 2:
				var deg: int = ANGLES[ty.id][which]
				for m in MODES:
					var d := Disc.new()
					root.add_child(d)
					var dir := Vector2.RIGHT.rotated(-deg_to_rad(deg))
					var lp := ThrowTypes.launch_params(ty, 1.0, m[1], 0.0, 0.0)
					d.launch(Vector2(0, HAND_Y) + dir * 16.0, dir * float(lp.speed), ti, lp.spin, 0.0, lp.wobble, lp.quality)
					var e := {"d": d, "ty": ty, "dir": dir, "type": ty.id, "which": which, "mode": m[0], "late": m[2], "late_q": m[3], "touch": -1.0, "rest": -1.0, "done_late": false}
					d.impact.connect(func(k, _s): if e.touch < 0.0: e.touch = d.global_position.x)
					runs.append(e)
		return false
	f += 1
	var all_done := true
	for e in runs:
		var d = e.d
		if e.late > 0.0 and not e.done_late and d.age >= e.late:
			e.done_late = true
			var none := ThrowTypes.launch_params(e.ty, 1.0, "NONE", 0.0, 0.0)
			var lq := ThrowTypes.launch_params(e.ty, 1.0, e.late_q, 0.0, 0.0)
			d.apply_late_snap(lq.spin, e.dir * (float(lq.speed) - float(none.speed)), lq.wobble, lq.quality)
		if e.rest < 0.0:
			if d.state == Disc.REST:
				e.rest = d.global_position.x
			else:
				all_done = false
	if all_done or f > 120 * 30:
		for ty in ANGLES:
			for which in 2:
				var line := "%-9s %-6s %3d° " % [ty, "carry" if which == 0 else "total", ANGLES[ty][which]]
				for e in runs:
					if e.type == ty and e.which == which:
						var v: float = e.touch if which == 0 else (e.rest if e.rest >= 0.0 else e.d.global_position.x)
						line += "| %s %6.1fm " % [e.mode, v / 32.0]
				print(line)
		print("")
		print("perfect / none ratio (carry, total):")
		for ty in ANGLES:
			var vals := {}
			for e in runs:
				if e.type == ty:
					vals["%s%d" % [e.mode, e.which]] = e.touch if e.which == 0 else (e.rest if e.rest >= 0.0 else e.d.global_position.x)
			print("  %-9s carry x%.2f   total x%.2f   (good: carry x%.2f)" % [ty, vals.perfect0 / vals.none0, vals.perfect1 / vals.none1, vals.good0 / vals.none0])
		return true
	return false
