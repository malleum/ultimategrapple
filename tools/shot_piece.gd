extends SceneTree
## Screenshot of one generator segment (needs a display, e.g. xvfb-run):
## the camera on its first gate (or the basket with "finale:N").
## godot -s tools/shot_piece.gd -- piece theme out.png [zoom]

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
		var g := Gen.new()
		var piece := args[0]
		if piece.begins_with("finale:"):
			g.force_segments = ["run_gaps"]
			g.force_finale = int(piece.get_slice(":", 1))
		else:
			g.force_segments = [piece]
		lvl = G.play_level(g.generate(4242, args[1], 0.6, 1))
		return false
	frame += 1
	var r = lvl.runners[0]
	if frame == 3:
		var focus: Vector2 = lvl.basket_pos + Vector2(-200, -60)
		if not r.gates.is_empty():
			var dr: Rect2 = r.gates[0].door_rect
			focus = Vector2(dr.position.x - 120.0, dr.end.y - 40.0)
			if args[0] == "stacked":
				focus += Vector2(-200, -160)
		r.player.respawn(focus + Vector2(-260, 40))
		r.zoom_override = float(args[3]) if args.size() > 3 else 0.55
		r.follow_fn = func() -> Array: return [focus, Vector2.ZERO]
		r.camera.position = focus
	if frame == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(args[2])
		print("saved ", args[2])
		quit()
	return false
