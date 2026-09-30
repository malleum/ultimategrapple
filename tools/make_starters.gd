extends SceneTree
## Writes a starter set of pinned courses into res://levels (one per theme,
## rising difficulty). godot --headless -s tools/make_starters.gd
const Gen = preload("res://src/level/generator.gd")
const Themes = preload("res://src/core/theme_db.gd")

func _initialize() -> void:
	var specs := [
		[101, "field", 0.2, 8, "01 First Pull"],
		[202, "heaven", 0.35, 10, "02 Halo Relay"],
		[303, "fantasy", 0.45, 11, "03 Elder Hollow"],
		[404, "canyon", 0.5, 12, "04 Sundown Mesa"],
		[505, "cyber", 0.6, 12, "05 Neon Kernel"],
		[606, "frost", 0.65, 13, "06 Frost Peak"],
		[707, "foundry", 0.8, 14, "07 Crucible"],
	]
	DirAccess.make_dir_recursive_absolute("res://levels")
	for s in specs:
		var d: Dictionary = Gen.new().generate(s[0], s[1], s[2], s[3])
		d["name"] = s[4].substr(3)
		d["id"] = "starter_" + s[4].substr(0, 2) + "_" + s[1]
		d["pinned"] = true
		var f := FileAccess.open("res://levels/%s.json" % d.id, FileAccess.WRITE)
		f.store_string(JSON.stringify(d, "\t"))
		print("wrote ", d.id, "  par ", d.medals.par)
	quit()
