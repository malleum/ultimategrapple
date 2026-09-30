extends SceneTree
## Generator stress test: godot --headless -s tools/test_gen.gd
const Gen = preload("res://src/level/generator.gd")
const Themes = preload("res://src/core/theme_db.gd")

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var fails := 0
	var seg_counts := {}
	var total_w := 0.0
	var n := 0
	for i in 300:
		var g := Gen.new()
		var th: String = Themes.ORDER[i % Themes.ORDER.size()]
		var d := (i % 11) / 10.0
		var data := g.generate(1000 + i, th, d, 6 + i % 20)
		n += 1
		for s in data.segments:
			seg_counts[s] = seg_counts.get(s, 0) + 1
		var errs := validate(data)
		# determinism
		var data2 := Gen.new().generate(1000 + i, th, d, 6 + i % 20)
		if JSON.stringify(data) != JSON.stringify(data2):
			errs.append("non-deterministic")
		total_w += data.bounds[2]
		if not errs.is_empty():
			fails += 1
			if fails < 12:
				print("seed %d %s d%.1f: %s" % [1000 + i, th, d, ", ".join(errs)])
	print("generated %d levels in %d ms, %d with issues, avg width %.0f tiles" % [n, Time.get_ticks_msec() - t0, fails, total_w / n / 32.0])
	var keys := seg_counts.keys()
	keys.sort()
	for k in keys:
		print("  %-14s %d" % [k, seg_counts[k]])
	var sample := Gen.new().generate(42, "cyber", 0.6, 12)
	print("sample: ", sample.name, " medals ", sample.medals, " solids ", sample.solids.size(), " ents ", sample.entities.size(), " json bytes ", JSON.stringify(sample).length())
	quit(0 if fails == 0 else 1)


func _rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


func validate(d: Dictionary) -> Array:
	var errs := []
	var spawn := Vector2(d.spawn[0], d.spawn[1])
	var basket := Vector2(d.basket[0], d.basket[1])
	var spawn_ok := false
	var basket_ok := false
	for s in d.solids:
		var r := _rect(s.r)
		if r.size.x <= 0 or r.size.y <= 0:
			errs.append("degenerate solid %s" % [s.r])
		if r.has_point(spawn + Vector2(0, 4)):
			spawn_ok = true
		if r.has_point(basket + Vector2(0, 4)):
			basket_ok = true
		if r.intersects(Rect2(spawn + Vector2(-10, -44), Vector2(20, 40))):
			errs.append("spawn inside solid")
		if r.intersects(Rect2(basket + Vector2(-30, -110), Vector2(60, 100))):
			errs.append("basket blocked by solid %s" % [s.r])
	if not spawn_ok:
		errs.append("no ground under spawn")
	if not basket_ok:
		errs.append("no ground under basket")
	if d.kill_y < basket.y:
		errs.append("kill_y above basket")
	for e in d.entities:
		if e.t == "grapple":
			var p := Vector2(e.p[0], e.p[1])
			for s in d.solids:
				if _rect(s.r).has_point(p):
					errs.append("grapple point inside solid (%s)" % [e.get("sky", false)])
					break
	return errs
