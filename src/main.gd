extends Node
## Root node. Hosts the current scene and a global overlay (FPS counter).

var fps_label: Label
var show_fps := false
## --render-replay=<course id>: play that replay once (under --write-movie)
## and quit when it is over. Used by the MP4 export.
var render_id := ""
var render_end_t := -1.0


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
	if Game.server_mode:
		Net.start_dedicated_server()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--render-replay="):
			render_id = a.get_slice("=", 1)
	if render_id != "":
		Game.render_mode = true
		if not Game.play_replay(render_id):
			push_error("no replay for %s" % render_id)
			get_tree().quit(1)
		return
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


func _render_watch(dt: float) -> void:
	var lvl = Game.current_scene
	if lvl == null or not is_instance_valid(lvl) or lvl.runners.is_empty():
		return
	var r = lvl.runners[0]
	if r.done:
		# finished: hold for the results card (it pops in ~0.9s after the chains)
		if render_end_t < 0.0 or render_end_t > 4.5:
			render_end_t = 4.5
	elif r.inp.finished() and render_end_t < 0.0:
		# inputs ran out without a finish (shouldn't happen): don't hang
		render_end_t = 6.0
	if render_end_t >= 0.0:
		render_end_t -= dt
		if render_end_t < 0.0:
			get_tree().quit()
