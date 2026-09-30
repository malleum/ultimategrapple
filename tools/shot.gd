extends SceneTree
## Screenshot helper (needs a display, e.g. xvfb-run).
## godot -s tools/shot.gd -- seed theme route_index out.png [menu]

var started := false
var frame := 0
var lvl
var args: PackedStringArray
var out := "shot.png"
var menu := false


func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	out = args[3] if args.size() > 3 else "shot.png"
	menu = args.size() > 4 and args[4] == "menu"


func _process(_dt: float) -> bool:
	var Game = root.get_node("Game")
	if not started:
		started = true
		Game.main = root
		if menu:
			Game.goto_menu(args[5] if args.size() > 5 else "title")
			return false
		var data: Dictionary = Game.generate_level(int(args[0]), args[1], 0.6, 12)
		lvl = Game.play_level(data)
		return false
	frame += 1
	if frame == 3 and lvl:
		var idx := int(args[2])
		var route: Array = lvl.level_data.route
		if idx >= 0 and idx < route.size():
			var p := Vector2(route[idx][0], route[idx][1] - 4)
			lvl.player.respawn(p)
			lvl.camera.position = p
		elif idx < 0:
			var bp: Vector2 = lvl.basket_pos
			lvl.player.respawn(bp + Vector2(-300, -10))
			lvl.camera.position = bp
		lvl.player.aim_override = lvl.player.center() + Vector2(300, -120)
	if frame == 8 and lvl:
		Input.action_press("move_right")
	if frame == 20 and lvl:
		Input.action_press("throw")
	if frame == 50:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		quit()
	return false
