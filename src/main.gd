extends Node
## Root node. Hosts the current scene and a global overlay (FPS counter).

var fps_label: Label
var show_fps := false


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
	Game.goto_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			show_fps = not show_fps
			fps_label.visible = show_fps
		elif event.physical_keycode == KEY_F11:
			Game.settings.fullscreen = not Game.settings.fullscreen
			Game.save_settings()


func _process(_dt: float) -> void:
	if show_fps:
		fps_label.text = "%d FPS  |  %.2f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
