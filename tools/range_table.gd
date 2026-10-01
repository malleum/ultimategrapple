extends SceneTree
## Exact range table using the real disc code on a flat floor.
## Conditions match a real throw: full power, PERFECT snap (spin 1.0 * type spin,
## speed x1.09, wobble 0.25*0.15), standing still (no movement penalty),
## nose 0, released from the hand (feet - 31.68px) + 16px along the aim.
## godot --headless --fixed-fps 120 -s tools/range_table.gd

const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const HAND_Y := -44.0 * 0.72
const PX_PER_M := 32.0

var runs := []
var frames := 0
var started := false


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		var floor_body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(400000, 400)
		cs.shape = r
		floor_body.position = Vector2(100000, 200)
		floor_body.add_child(cs)
		root.add_child(floor_body)
		for ti in ThrowTypes.count():
			var ty: Dictionary = ThrowTypes.get_type(ti)
			for deg in range(-10, 86):
				var d := Disc.new()
				root.add_child(d)
				var dir := Vector2.RIGHT.rotated(-deg_to_rad(deg))
				var from := Vector2(0, HAND_Y) + dir * 16.0
				var spin: float = 1.0 * ty.spin
				var vel: Vector2 = dir * float(ty.speed) * 1.0 * 1.09
				d.launch(from, vel, ti, spin, 0.0, 0.25 * 0.15)
				var e := {"d": d, "type": ty.id, "deg": deg, "touch": -1.0, "touch_t": -1.0, "rest": -1.0, "apex": 0.0, "skips": 0}
				d.impact.connect(func(kind, _s): _on_impact(e, kind))
				runs.append(e)
		return false
	frames += 1
	var all_done := true
	for e in runs:
		var d = e.d
		e.apex = minf(e.apex, d.global_position.y)
		if e.rest < 0.0:
			if d.state == Disc.REST:
				e.rest = d.global_position.x
			else:
				all_done = false
	if all_done or frames > 120 * 30:
		_report()
		return true
	return false


func _on_impact(e: Dictionary, kind: String) -> void:
	if kind == "skip":
		e.skips += 1
	if e.touch < 0.0 and kind in ["skip", "land", "roll", "wall"]:
		e.touch = e.d.global_position.x
		e.touch_t = frames / 120.0


func _report() -> void:
	var by := {}
	for e in runs:
		if not by.has(e.type):
			by[e.type] = []
		by[e.type].append(e)
	print("type       | best carry (first touch)     | best total (comes to rest)   | carry@0° total@0°")
	for ty in by:
		var arr: Array = by[ty]
		var bc = arr[0]
		var bt = arr[0]
		var a0 = null
		for e in arr:
			if e.touch > bc.touch:
				bc = e
			var tot: float = e.rest if e.rest >= 0.0 else e.d.global_position.x
			var btot: float = bt.rest if bt.rest >= 0.0 else bt.d.global_position.x
			if tot > btot:
				bt = e
			if e.deg == 0:
				a0 = e
		var bt_tot: float = bt.rest if bt.rest >= 0.0 else bt.d.global_position.x
		print("%-10s | %3d°  %6.1f m  (%4.2fs, apex %4.1f m) | %3d°  %6.1f m  (%d skips) | %6.1f m  %6.1f m" % [
			ty, bc.deg, bc.touch / PX_PER_M, bc.touch_t, -bc.apex / PX_PER_M,
			bt.deg, bt_tot / PX_PER_M, bt.skips,
			a0.touch / PX_PER_M, (a0.rest if a0.rest >= 0.0 else a0.d.global_position.x) / PX_PER_M])
	print("")
	print("best total with angle >= 0 (no downward throws):")
	for ty in by:
		var best = null
		var bv := -INF
		for e in by[ty]:
			if e.deg < 0:
				continue
			var tot: float = e.rest if e.rest >= 0.0 else e.d.global_position.x
			if tot > bv:
				bv = tot
				best = e
		print("  %-10s %3d°  %6.1f m  (carry %5.1f m, %d skips)" % [ty, best.deg, bv / PX_PER_M, best.touch / PX_PER_M, best.skips])
	print("")
	print("per-angle detail (every 5°): carry / total, metres")
	var header := "deg   "
	for ty in by:
		header += "%-16s" % ty
	print(header)
	for deg in range(-10, 86, 5):
		var line := "%3d°  " % deg
		for ty in by:
			for e in by[ty]:
				if e.deg == deg:
					var tot: float = e.rest if e.rest >= 0.0 else e.d.global_position.x
					line += "%5.1f / %-8.1f" % [e.touch / PX_PER_M, tot / PX_PER_M]
		print(line)
