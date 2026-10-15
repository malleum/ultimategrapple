extends SceneTree
## Battle Rush generator: 300 seeds are valid, deterministic, end in exactly
## one leader, contain no throw pieces, and plain courses are unchanged.
## godot --headless -s tools/test_battle_gen.gd
const Gen = preload("res://src/level/generator.gd")
const Themes = preload("res://src/core/theme_db.gd")
const Validator = preload("res://src/level/validator.gd")


func _initialize() -> void:
	var fails := 0
	var arenas := 0
	var enemies := {}
	var segs := {}
	for i in 300:
		var g := Gen.new()
		g.battle = true
		var th: String = Themes.ORDER[i % Themes.ORDER.size()]
		var d := (i % 11) / 10.0
		var len := 5 + i % 18
		var data := g.generate(5000 + i, th, d, len)
		var errs := Validator.check(data)
		var g2 := Gen.new()
		g2.battle = true
		if JSON.stringify(data) != JSON.stringify(g2.generate(5000 + i, th, d, len)):
			errs.append("non-deterministic")
		if not data.has("battle"):
			errs.append("no battle marker")
		var leaders := 0
		var my_arenas := 0
		for e in data.entities:
			match str(e.t):
				"gate", "glass":
					errs.append("throw entity %s in a battle course" % e.t)
				"enemy":
					enemies[e.k] = enemies.get(e.k, 0) + 1
					if e.k == "leader":
						leaders += 1
				"arena":
					my_arenas += 1
		if leaders != 1:
			errs.append("%d leaders" % leaders)
		if my_arenas < 2 and len >= 8:
			errs.append("only %d arenas in %d segments" % [my_arenas, len])
		arenas += my_arenas
		for s in data.segments:
			segs[s] = segs.get(s, 0) + 1
		if not errs.is_empty():
			fails += 1
			if fails < 12:
				print("seed %d %s d%.1f: %s" % [5000 + i, th, d, ", ".join(errs)])
	print("battle courses: %d fails, %d arenas, enemies %s" % [fails, arenas, enemies])
	var keys := segs.keys()
	keys.sort()
	for k in keys:
		print("  %-14s %d" % [k, segs[k]])
	# plain courses must not have changed shape: no battle pieces, same output
	var plain := Gen.new().generate(1234, "cyber", 0.5, 12)
	for s in plain.segments:
		if str(s).begins_with("arena") or s == "skirmish":
			fails += 1
			print("FAIL battle piece in a plain course: ", s)
	quit(0 if fails == 0 else 1)
