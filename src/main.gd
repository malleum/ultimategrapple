extends Node
## Root node. Hosts the current scene and a global overlay (FPS counter).

const PerfScript = preload("res://src/core/perf.gd")

var fps_label: Label
var show_fps := false
## --render-replay=<course id>: play that replay once (under --write-movie)
## and quit when it is over. Used by the MP4 export.
var render_id := ""
var render_end_t := -1.0
const RENDER_SIZE := Vector2i(1920, 1080)
var _toast_box: VBoxContainer


## A short note in the top-right corner for a few seconds (online news).
func toast(text: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.08, 0.92)
	sb.border_color = Color(0.4, 0.9, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	l.add_theme_font_size_override("font_size", 18)
	p.add_child(l)
	_toast_box.add_child(p)
	var tw := create_tween().bind_node(p)
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _ready() -> void:
	Game.main = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	fps_label = Label.new()
	fps_label.position = Vector2(8, 4)
	fps_label.add_theme_font_size_override("font_size", 16)
	fps_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	fps_label.visible = false
	overlay.add_child(fps_label)
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_toast_box)
	# --perf-log (nix run . -- --perf-log): frame timing log, see src/core/perf.gd
	if "--perf-log" in OS.get_cmdline_user_args() or "--perf-log" in OS.get_cmdline_args() or OS.get_environment("UG_PERF_LOG") != "":
		add_child(PerfScript.new())
	if Game.server_mode:
		Net.start_dedicated_server()
		var sp := Online.SERVICE_PORT
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--service-port="):
				sp = int(a.get_slice("=", 1))
		Online.start_server(sp)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--render-replay="):
			render_id = a.get_slice("=", 1)
	if render_id != "":
		Game.render_mode = true
		# Render at a fixed 1920x1080 whatever the window manager does to the
		# window (a tiling WM squeezed it into a split and the video lost its
		# top and bottom): the game draws into a fixed-size viewport, which is
		# what the movie writer records, and the window only shows it scaled.
		var w := get_window()
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		w.content_scale_size = RENDER_SIZE
		w.unresizable = true   # most tiling WMs float fixed-size windows
		w.size = RENDER_SIZE
		if not Game.play_replay(render_id):
			push_error("no replay for %s" % render_id)
			get_tree().quit(1)
		return
	if bool(Game.settings.get("online_services", true)):
		Online.connect_to(str(Game.settings.get("online_server", "joshammer.com")))
	Online.notice.connect(toast)
	Game.goto_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			show_fps = not show_fps
			fps_label.visible = show_fps
		elif event.physical_keycode == KEY_F11:
			Game.settings.fullscreen = not Game.settings.fullscreen
			Game.save_settings()


func _process(dt: float) -> void:
	if render_id != "":
		_render_watch(dt)
	if show_fps:
		fps_label.text = "%d FPS  |  %.2f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]


var _render_done_t := 0.0


## MP4 render: the video runs until the results card's disc cam has shown the
## disc going into the chains (it plays through once), then a beat more.
func _render_watch(dt: float) -> void:
	var lvl = Game.current_scene
	if lvl == null or not is_instance_valid(lvl) or lvl.runners.is_empty():
		return
	var r = lvl.runners[0]
	if r.done:
		_render_done_t += dt
		var hud = r.hud
		var cam_ok: bool = hud.results_cam != null and is_instance_valid(hud.results_cam)
		if cam_ok and hud.results_cam_played:
			if render_end_t < 0.0 or render_end_t > 0.8:
				render_end_t = 0.8
		elif _render_done_t > 2.0 and not cam_ok and render_end_t < 0.0:
			render_end_t = 2.5   # no disc cam (too short a clip): just the card
		elif _render_done_t > 60.0:
			get_tree().quit()   # never hang
			return
	elif r.inp.finished() and render_end_t < 0.0:
		# inputs ran out without a finish (shouldn't happen): don't hang
		render_end_t = 6.0
	if render_end_t >= 0.0:
		render_end_t -= dt
		if render_end_t < 0.0:
			print("render: stopping %.1f s after the finish" % _render_done_t)
			get_tree().quit()
