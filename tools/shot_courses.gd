extends SceneTree
## Screenshot of the COURSES page against a local services server with a few
## saved courses (needs a display, e.g. xvfb-run).
## godot -s tools/shot_courses.gd -- out.png [board]

const PORT := 24792
var OnlineScript
var srv
var c1
var f := 0
var phase := 0
var args: PackedStringArray
var Gen


func _process(_dt: float) -> bool:
	var G = root.get_node("Game")
	f += 1
	match phase:
		0:
			args = OS.get_cmdline_user_args()
			OnlineScript = load("res://src/net/online.gd")
			Gen = load("res://src/level/generator.gd")
			G.main = root
			G.settings["name_chosen"] = true   # in memory only: no name prompt over the shot
			srv = OnlineScript.new()
			srv.name = "ShotSrv"
			srv.server_dir = "user://shot_courses_server"
			root.add_child(srv)
			srv.start_server(PORT)
			c1 = root.get_node("Online")
			c1.auto_sync = false
			c1.name_override = "Malleum"
			c1.connect_to("127.0.0.1:%d" % PORT)
			phase = 1
		1:
			if c1.is_online():
				for i in 4:
					c1.share_course(Gen.new().generate(800 + i, ["field", "cyber", "frost", "canyon"][i], 0.3 + i * 0.15, 8), -1)
				phase = 2
				f = 0
		2:
			if f == 60:
				for cid in srv._shared.get(c1.uid, []).map(func(e): return str(e.cid)).slice(0, 2):
					c1.submit_run(cid, 21.37 + randf() * 5.0, 2, "gold", [[0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0], [1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0], [2, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0]], [7.0, 14.0, 21.0])
			if f == 90:
				load("res://src/ui/courses_page.gd").tab = c1.uid
				G.goto_menu("courses")
			if f == 150:
				root.get_viewport().get_texture().get_image().save_png(args[0])
				print("saved ", args[0])
				var d := DirAccess.open("user://shot_courses_server")
				quit()
	return false
