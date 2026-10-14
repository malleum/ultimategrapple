extends SceneTree
## Screenshot of a whole generator segment, zoomed to fit (needs a display,
## e.g. xvfb-run), for reviewing new pieces.
## godot --path . --resolution 1600x900 -s tools/shot_segment.gd -- piece theme out.png [seed] [difficulty]

const Gen = preload("res://src/level/generator.gd")

var started := false
var frame := 0
var lvl
var args: PackedStringArray


func _process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		args = OS.get_cmdline_user_args()
		G.main = root
		# xvfb (no window manager) hands out odd window sizes, and a saved
		# fullscreen / maximized setting can override them
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		root.size = Vector2i(1600, 900)
		var g := Gen.new()
		g.force_segments = [args[0]]
		if OS.get_environment("FINALE") != "":
			g.force_finale = int(OS.get_environment("FINALE"))
		var sd := int(args[3]) if args.size() > 3 else 4242
		var df := float(args[4]) if args.size() > 4 else 0.6
		lvl = G.play_level(g.generate(sd, args[1], df, 1))
		return false
	frame += 1
	var r = lvl.runners[0]
	if frame == 3:
		# the segment's box: every solid and entity right of the start pad,
		# left of the finale's basket
		var box := Rect2()
		var has := false
		var x0 := 8.0 * Gen.T
		var x1: float = lvl.basket_pos.x + (8.0 if OS.get_environment("FINALE") != "" else -6.0) * Gen.T
		for s in lvl.level_data.solids:
			var rr := Rect2(s.r[0], s.r[1], s.r[2], mini(int(s.r[3]), 12 * Gen.T))
			if rr.end.x <= x0 or rr.position.x >= x1:
				continue
			rr = Rect2(Vector2(maxf(rr.position.x, x0), rr.position.y), Vector2(minf(rr.end.x, x1) - maxf(rr.position.x, x0), rr.size.y))
			box = rr if not has else box.merge(rr)
			has = true
		var vs: Vector2 = root.get_viewport().get_visible_rect().size
		var focus := box.get_center()
		var zoom := minf(vs.x / (box.size.x + 300.0), vs.y / (box.size.y + 300.0))
		r.player.respawn(Vector2(x0 - 64.0, 0))
		r.zoom_override = clampf(zoom, 0.12, 1.0)
		r.follow_fn = func() -> Array: return [focus + Vector2(0, 22), Vector2.ZERO]
		r.camera.position = focus
		print("segments %s box %s zoom %.2f" % [lvl.level_data.segments, box, zoom])
	if frame == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(args[2])
		print("saved ", args[2])
		quit()
	return false
