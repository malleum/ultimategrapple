extends SceneTree
## Generator stress test: godot --headless -s tools/test_gen.gd
const Gen = preload("res://src/level/generator.gd")
const Themes = preload("res://src/core/theme_db.gd")
const Validator = preload("res://src/level/validator.gd")

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
		var errs := Validator.check(data)
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
	# shipped courses must pass the same checks (after load-time repair)
	var dir := DirAccess.open("res://levels")
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var lv = JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + fname))
		Validator.repair(lv)
		var lerrs := Validator.check(lv)
		if not lerrs.is_empty():
			fails += 1
			print("levels/%s: %s" % [fname, ", ".join(lerrs)])
	var sample := Gen.new().generate(42, "cyber", 0.6, 12)
	print("sample: ", sample.name, " medals ", sample.medals, " solids ", sample.solids.size(), " ents ", sample.entities.size(), " json bytes ", JSON.stringify(sample).length())
	quit(0 if fails == 0 else 1)


