extends Node2D
## Main menu: title, course select (pinned), random course builder,
## multiplayer lobby, controls, settings. Animated themed background.

const UI = preload("res://src/ui/ui.gd")
const Themes = preload("res://src/core/theme_db.gd")
const Background = preload("res://src/fx/background.gd")
const Bindings = preload("res://src/core/bindings.gd")

var start_page := "title"
var camera: Camera2D
var layer: CanvasLayer
var page_root: Control
var t := 0.0
var bg_theme := "cyber"

# random page state
var r_seed := 0
var r_theme := ""
var r_diff := 0.5
var r_len := 12
var seed_edit: LineEdit
var lobby_box: VBoxContainer
var server_list: VBoxContainer
var status_label: Label
var page := ""
var couch_players: Array = []   # [{device, name, color}]
var couch_box: VBoxContainer
var couch_wins := 3
var couch_source := "random"
var couch_diff := 0.5
# rebind page state
var bind_device := "kbm"
var capture := {}                 # {action, slot} while waiting for an input
var bind_status := ""
var bind_scroll := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var themes := Themes.ORDER
	bg_theme = themes[randi() % themes.size()]
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.make_current()
	var bg := Background.new()
	add_child(bg)
	bg.setup(Themes.get_theme(bg_theme), camera)
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	page_root = Control.new()
	page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_root.theme = UI.theme()
	layer.add_child(page_root)
	r_seed = randi() % 1000000
	Music.play_theme(bg_theme)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.status_changed.connect(_on_status)
	Net.servers_changed.connect(_refresh_servers)
	show_page(start_page)


func _exit_tree() -> void:
	Net.stop_discovery()


func _process(dt: float) -> void:
	t += dt
	camera.position = Vector2(t * 60.0, sin(t * 0.2) * 80.0 - 200.0)


func _clear() -> Control:
	for c in page_root.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(center)
	return center


func show_page(p: String) -> void:
	Net.stop_discovery()
	page = p
	match p:
		"couch": _page_couch()
		"courses": _page_courses()
		"random": _page_random()
		"multi": _page_multi()
		"controls": _page_controls()
		"replays": _page_replays()
		"bindings": _page_bindings()
		"settings": _page_settings()
		_: _page_title()


func _back_button() -> Button:
	return UI.button("BACK", func(): show_page("title"), 20)


# ------------------------------------------------------------------ title

func _page_title() -> void:
	var c := _clear()
	var v := UI.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	v.add_child(UI.title("ULTIMATE GRAPPLE", 104))
	v.add_child(UI.label("grapple · throw · chains", 26, Color(2.0, 0.5, 1.6), HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)
	var col := UI.vbox(10)
	col.custom_minimum_size = Vector2(420, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(col)
	col.add_child(UI.button("COURSES", func(): show_page("courses"), 30))
	col.add_child(UI.button("RANDOM COURSE", func(): show_page("random"), 30))
	col.add_child(UI.button("QUICK RANDOM", func(): Game.start_random(randi() % 1000000, "", 0.5, 12), 30))
	col.add_child(UI.button("REPLAYS", func(): show_page("replays"), 30))
	col.add_child(UI.button("COUCH VERSUS", func(): show_page("couch"), 30))
	col.add_child(UI.button("ONLINE / LAN", func(): show_page("multi"), 30))
	col.add_child(UI.button("CONTROLS", func(): show_page("controls"), 24))
	col.add_child(UI.button("SETTINGS", func(): show_page("settings"), 24))
	col.add_child(UI.button("QUIT", func(): get_tree().quit(), 24))
	v.add_child(UI.label("F3 fps · F11 fullscreen", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))


# ------------------------------------------------------------------ courses

func _page_courses() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 760)
	c.add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	v.add_child(UI.label("COURSES", 48, UI.NEON))
	var levels := Game.list_pinned_levels()
	if levels.is_empty():
		v.add_child(UI.label("No pinned courses yet.\nPlay random courses and press P (or PIN on the results screen) to keep the ones you like.\nPinned courses are saved to user://pinned and, when running from source, to levels/ in the repo.", 20, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in levels.size():
		var d: Dictionary = levels[i]
		var th := Themes.get_theme(d.get("theme", "cyber"))
		var rec = Game.get_record(str(d.get("id", "")))
		var row := UI.hbox(16)
		var idx := i
		var b := UI.button("%02d  %s" % [i + 1, d.get("name", "Course")], func(): Game.start_pinned(idx), 24)
		b.custom_minimum_size = Vector2(440, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		row.add_child(UI.label(th.name, 20, th.accent2))
		row.add_child(UI.label("D%d" % int(round(float(d.get("difficulty", 0.5)) * 10)), 20, UI.DIM))
		if rec:
			var ml := UI.label("%s  %s" % [Game.format_time(float(rec.time)), str(rec.medal).to_upper()], 20, UI.medal_color(str(rec.medal)))
			ml.add_theme_font_override("font", UI.mono_font())
			row.add_child(ml)
		else:
			row.add_child(UI.label("unplayed", 20, UI.DIM))
		list.add_child(row)
	v.add_child(_back_button())


# ------------------------------------------------------------------ random

func _page_random() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	c.add_child(panel)
	var v := UI.vbox(16)
	panel.add_child(v)
	v.add_child(UI.label("RANDOM COURSE", 48, UI.NEON))
	var sh := UI.hbox()
	sh.add_child(UI.label("Seed", 22))
	seed_edit = LineEdit.new()
	seed_edit.text = str(r_seed)
	seed_edit.custom_minimum_size = Vector2(240, 0)
	seed_edit.text_changed.connect(func(tx): r_seed = int(tx) if tx.is_valid_int() else tx.hash() % 1000000)
	sh.add_child(seed_edit)
	sh.add_child(UI.button("🎲 REROLL", func(): r_seed = randi() % 1000000; seed_edit.text = str(r_seed), 20))
	v.add_child(sh)
	var th_row := UI.hbox()
	th_row.add_child(UI.label("Theme", 22))
	var ob := OptionButton.new()
	ob.add_item("Random")
	for id in Themes.ORDER:
		ob.add_item(Themes.THEMES[id].name)
	ob.selected = 0 if r_theme == "" else Themes.ORDER.find(r_theme) + 1
	ob.item_selected.connect(func(i): r_theme = "" if i == 0 else Themes.ORDER[i - 1])
	th_row.add_child(ob)
	v.add_child(th_row)
	var dl := UI.label("Difficulty  %d" % int(r_diff * 10), 22)
	v.add_child(dl)
	v.add_child(UI.slider(0, 1, r_diff, 0.1, func(x): r_diff = x; dl.text = "Difficulty  %d" % int(round(x * 10))))
	var ll := UI.label("Length  %d segments" % r_len, 22)
	v.add_child(ll)
	v.add_child(UI.slider(4, 30, r_len, 1, func(x): r_len = int(x); ll.text = "Length  %d segments" % int(x)))
	var h := UI.hbox()
	h.add_child(UI.button("PLAY", func(): Game.start_random(r_seed, r_theme, r_diff, r_len), 30))
	h.add_child(_back_button())
	v.add_child(h)
	v.add_child(UI.label("Tip: same seed + settings = same course. Press P in-game to pin it.", 16, UI.DIM))


# ------------------------------------------------------------------ multiplayer

func _page_multi() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 720)
	c.add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	v.add_child(UI.label("MULTIPLAYER", 48, UI.NEON))
	if Net.champion_text != "":
		v.add_child(UI.label(Net.champion_text, 32, UI.GOLD))
	var who := UI.hbox()
	who.add_child(UI.label("Name", 22))
	var ne := LineEdit.new()
	ne.text = str(Game.settings.player_name)
	ne.custom_minimum_size = Vector2(240, 0)
	ne.max_length = 16
	ne.text_changed.connect(func(tx): Game.settings.player_name = tx; Game.save_settings())
	who.add_child(ne)
	var colb := UI.button("COLOR", func(): pass, 20)
	colb.add_theme_color_override("font_color", Game.player_color())
	colb.pressed.connect(func():
		Game.settings.player_color = (int(Game.settings.player_color) + 1) % 8
		Game.save_settings()
		colb.add_theme_color_override("font_color", Game.player_color()))
	who.add_child(colb)
	v.add_child(who)
	status_label = UI.label(Net.status, 18, UI.DIM)
	v.add_child(status_label)
	lobby_box = UI.vbox(10)
	lobby_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lobby_box)
	_build_lobby()
	v.add_child(_back_button())


func _build_lobby() -> void:
	if lobby_box == null or not is_instance_valid(lobby_box):
		return
	for ch in lobby_box.get_children():
		ch.queue_free()
	if not Net.in_lobby:
		Net.start_discovery()
		var on := UI.hbox()
		var srv := LineEdit.new()
		srv.text = str(Game.settings.online_server)
		srv.placeholder_text = Net.ONLINE_SERVER
		srv.custom_minimum_size = Vector2(320, 0)
		srv.text_changed.connect(func(tx): Game.settings.online_server = tx.strip_edges(); Game.save_settings())
		on.add_child(UI.button("PLAY ONLINE", func(): Net.join(srv.text.strip_edges() if srv.text.strip_edges() != "" else Net.ONLINE_SERVER), 26))
		on.add_child(srv)
		lobby_box.add_child(on)
		lobby_box.add_child(UI.label("Joins the public server. No port forwarding needed. The first player in picks the settings and starts.", 16, UI.DIM))
		var h := UI.hbox()
		h.add_child(UI.button("HOST GAME", func(): Net.host(), 26))
		var ip := LineEdit.new()
		ip.placeholder_text = "ip[:port]"
		ip.text = "127.0.0.1"
		ip.custom_minimum_size = Vector2(260, 0)
		h.add_child(ip)
		h.add_child(UI.button("JOIN", func(): Net.join(ip.text), 26))
		lobby_box.add_child(h)
		lobby_box.add_child(UI.label("LAN servers", 22, UI.PINK))
		server_list = UI.vbox(6)
		lobby_box.add_child(server_list)
		_refresh_servers()
		lobby_box.add_child(UI.label("Dedicated server:  nix run . -- --server [--port=24680 --wins=3 --source=random|pinned]", 16, UI.DIM))
		return
	Net.stop_discovery()
	lobby_box.add_child(UI.label("LOBBY  ·  first to %d wins" % int(Net.settings.wins), 26, UI.GOLD))
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var row := UI.hbox()
		row.add_child(UI.label(("● " if p.get("ready", false) else "○ ") + str(p.name) + ("  (you)" if id == Net.my_id() else "") + ("  [leader]" if int(id) == Net.leader_id() else ""), 22, Game.player_palette(int(p.color)) * 1.4))
		row.add_child(UI.label("wins %d" % int(p.wins), 18, UI.DIM))
		lobby_box.add_child(row)
	if Net.is_leader():
		var s := UI.hbox()
		s.add_child(UI.label("First to", 20))
		var sb := SpinBox.new()
		sb.min_value = 1
		sb.max_value = 15
		sb.value = int(Net.settings.wins)
		sb.value_changed.connect(func(x): Net.update_settings({"wins": int(x)}))
		s.add_child(sb)
		var src := OptionButton.new()
		src.add_item("Random courses")
		src.add_item("Pinned courses")
		src.selected = 1 if Net.settings.source == "pinned" else 0
		src.item_selected.connect(func(i): Net.update_settings({"source": "pinned" if i == 1 else "random"}))
		s.add_child(src)
		s.add_child(UI.label("Difficulty", 20))
		var ds := UI.slider(0, 1, float(Net.settings.difficulty), 0.1, func(x): Net.update_settings({"difficulty": x}))
		ds.custom_minimum_size = Vector2(160, 28)
		s.add_child(ds)
		lobby_box.add_child(s)
	var h2 := UI.hbox()
	h2.add_child(UI.button("READY", func(): Net.toggle_ready(), 24))
	if Net.is_leader():
		h2.add_child(UI.button("START SET", func(): Net.champion_text = ""; Net.request_start(), 24))
	else:
		lobby_box.add_child(UI.label("Waiting for the leader to start (or everyone READY).", 16, UI.DIM))
	h2.add_child(UI.button("LEAVE", func(): Net.leave(); _build_lobby(), 24))
	lobby_box.add_child(h2)


func _refresh_servers() -> void:
	if server_list == null or not is_instance_valid(server_list):
		return
	for ch in server_list.get_children():
		ch.queue_free()
	if Net.servers.is_empty():
		server_list.add_child(UI.label("(searching...)", 18, UI.DIM))
	for key in Net.servers:
		var s: Dictionary = Net.servers[key]
		var addr: String = key
		server_list.add_child(UI.button("%s  ·  %d players  ·  %s" % [s.name, s.count, key], func(): Net.join(addr), 20))


func _on_lobby_changed() -> void:
	if is_inside_tree():
		_build_lobby()


func _on_status(tx: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = tx


# ------------------------------------------------------------------ couch

func _page_couch() -> void:
	if couch_players.is_empty() and not Game.couch_last_players.is_empty():
		for p in Game.couch_last_players:
			couch_players.append({"device": int(p.device), "name": p.name, "color": int(p.color)})
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 640)
	c.add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	v.add_child(UI.label("COUCH VERSUS", 48, UI.NEON))
	if Game.couch_champion != "":
		v.add_child(UI.label(Game.couch_champion, 32, UI.GOLD))
	v.add_child(UI.label("Split-screen race, up to 4 players. Everyone has their own gates, glass and grapple points.\nPress A on a controller (or SPACE on the keyboard) to join. B / BACKSPACE to leave. X / C to change color.", 18, UI.DIM))
	couch_box = UI.vbox(8)
	couch_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(couch_box)
	_refresh_couch()
	var s := UI.hbox()
	s.add_child(UI.label("First to", 20))
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 15
	sb.value = couch_wins
	sb.value_changed.connect(func(x): couch_wins = int(x))
	s.add_child(sb)
	var src := OptionButton.new()
	src.add_item("Random courses")
	src.add_item("Pinned courses")
	src.selected = 1 if couch_source == "pinned" else 0
	src.item_selected.connect(func(i): couch_source = "pinned" if i == 1 else "random")
	s.add_child(src)
	s.add_child(UI.label("Difficulty", 20))
	var ds := UI.slider(0, 1, couch_diff, 0.1, func(x): couch_diff = x)
	ds.custom_minimum_size = Vector2(180, 28)
	s.add_child(ds)
	v.add_child(s)
	var h := UI.hbox()
	h.add_child(UI.button("START (START / ENTER)", _start_couch, 26))
	h.add_child(_back_button())
	v.add_child(h)


func _refresh_couch() -> void:
	if couch_box == null or not is_instance_valid(couch_box):
		return
	for ch in couch_box.get_children():
		ch.queue_free()
	for i in 4:
		if i < couch_players.size():
			var p: Dictionary = couch_players[i]
			var dev := "Keyboard + Mouse" if int(p.device) < 0 else "%s (#%d)" % [Input.get_joy_name(int(p.device)), int(p.device)]
			couch_box.add_child(UI.label("P%d  %s   ·   %s" % [i + 1, p.name, dev], 26, Game.player_palette(int(p.color)) * 1.4))
		else:
			couch_box.add_child(UI.label("P%d  — press A / SPACE to join —" % (i + 1), 22, Color(0.5, 0.55, 0.65)))
	var pads := Input.get_connected_joypads()
	couch_box.add_child(UI.label("%d controller(s) connected" % pads.size(), 16, UI.DIM))


func _couch_index(device: int) -> int:
	for i in couch_players.size():
		if int(couch_players[i].device) == device:
			return i
	return -1


func _couch_join(device: int) -> void:
	if _couch_index(device) >= 0 or couch_players.size() >= 4:
		return
	var used := []
	for p in couch_players:
		used.append(int(p.color))
	var col := 0
	while used.has(col):
		col += 1
	var nm: String = str(Game.settings.player_name) if device < 0 else "P%d" % (couch_players.size() + 1)
	couch_players.append({"device": device, "name": nm, "color": col})
	Sfx.play("ui_click")
	_refresh_couch()


func _couch_leave(device: int) -> void:
	var i := _couch_index(device)
	if i >= 0:
		couch_players.remove_at(i)
		_refresh_couch()


func _couch_color(device: int) -> void:
	var i := _couch_index(device)
	if i >= 0:
		couch_players[i].color = (int(couch_players[i].color) + 1) % 8
		_refresh_couch()


func _start_couch() -> void:
	if couch_players.is_empty():
		return
	Game.couch_champion = ""
	var players := []
	for p in couch_players:
		players.append({"device": p.device, "name": p.name, "color": p.color, "wins": 0})
	Game.start_couch(players, couch_wins, couch_source, couch_diff)


func _input(event: InputEvent) -> void:
	if page == "bindings" and not capture.is_empty():
		_capture_input(event)
		return
	if page != "couch":
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _couch_join(event.device)
			JOY_BUTTON_B: _couch_leave(event.device)
			JOY_BUTTON_X: _couch_color(event.device)
			JOY_BUTTON_START:
				if _couch_index(event.device) >= 0:
					_start_couch()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit:
			return
		match event.physical_keycode:
			KEY_SPACE:
				_couch_join(-1)
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE: _couch_leave(-1)
			KEY_C: _couch_color(-1)
			KEY_ENTER, KEY_KP_ENTER:
				_start_couch()
				get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ controls

func _page_controls() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1240, 0)
	c.add_child(panel)
	var v := UI.vbox(6)
	panel.add_child(v)
	v.add_child(UI.label("CONTROLS & TECH", 44, UI.NEON))
	var cols := UI.hbox(40)
	v.add_child(cols)
	var left := UI.vbox(4)
	var right := UI.vbox(4)
	cols.add_child(left)
	cols.add_child(right)
	var K := func(a): return Bindings.labels(a)
	var lines_l := [
		[K.call("move_left") + " · " + K.call("move_right"), "run  (carrying the disc is ~38% slower)"],
		[K.call("jump"), "jump · double jump in the air · wall-jump · jump off rope"],
		[K.call("move_down"), "slide at speed (boost) · crouch · fast-fall"],
		[K.call("grapple"), "grapple swing (hold) · up/down reel · run keys pump"],
		[K.call("zip"), "zip (hold): reel yourself to the grapple point"],
		[K.call("restart"), "instant restart"],
		[K.call("recall"), "recall disc to hand (+3s)"],
		[K.call("pin"), "pin this course permanently"],
	]
	var lines_r := [
		[K.call("throw"), "hold to charge, release to throw toward the cursor"],
		[K.call("snap"), "SNAP: press the instant you release the throw.\n±35ms PERFECT · ±90ms GOOD · tighter = further"],
		[K.call("throw_next") + " · 1-6", "throw: backhand forehand hammer roller scoober thumber"],
		[K.call("nose_up") + " · " + K.call("nose_down"), "nose angle: up = float/stall, down = punch"],
		[K.call("pivot"), "PIVOT (hold): plant & freeze, momentum stored. Throw,\nthen let go within 0.3s for a PIVOT LAUNCH"],
		["moving throws", "sway + spray + less range. Scoober halves it"],
		["catching", "grab the disc midair: refreshes double jump + air pivot"],
		["controller", "LS move · RS aim · %s jump · %s swing · %s zip\n%s throw · %s snap · %s pivot · %s recall" % [
			Bindings.label("jump", true), Bindings.label("grapple", true), Bindings.label("zip", true),
			Bindings.label("throw", true), Bindings.label("snap", true), Bindings.label("pivot", true), Bindings.label("recall", true)]],
	]
	for l in lines_l:
		left.add_child(_ctrl_row(l[0], l[1]))
	for l in lines_r:
		right.add_child(_ctrl_row(l[0], l[1]))
	var h := UI.hbox(16)
	h.add_child(UI.button("REBIND CONTROLS", func(): capture = {}; bind_status = ""; show_page("bindings"), 22))
	h.add_child(_back_button())
	v.add_child(h)


func _ctrl_row(k: String, d: String) -> Control:
	var h := UI.hbox(14)
	var kl := UI.label(k, 18, UI.PINK)
	kl.custom_minimum_size = Vector2(200, 0)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(kl)
	var dl := UI.label(d, 18, Color(0.9, 0.95, 1))
	h.add_child(dl)
	return h


# ------------------------------------------------------------------ replays

var replay_status: Label


func _page_replays() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 0)
	c.add_child(panel)
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label("REPLAYS", 48, UI.NEON))
	v.add_child(UI.label("Your personal-best run on each course, most recently played first. Watch it with the keystroke overlay, or export an MP4 to send to friends. Couch and online rounds are below.", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var rows := UI.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var list := Game.list_replays()
	if list.is_empty():
		rows.add_child(UI.label("No replays yet. Finish a course and every new personal best is saved here.", 20, UI.DIM))
	for e in list:
		var id: String = e.id
		var h := UI.hbox(14)
		var dot := UI.label("●", 22, UI.medal_color(str(e.get("medal", ""))))
		h.add_child(dot)
		var nm := UI.label(str(e.get("name", id)), 22)
		nm.custom_minimum_size = Vector2(360, 0)
		nm.clip_text = true
		h.add_child(nm)
		var th: Dictionary = Themes.get_theme(str(e.get("theme", "")))
		var tl := UI.label(str(th.get("name", "")), 18, UI.DIM)
		tl.custom_minimum_size = Vector2(190, 0)
		h.add_child(tl)
		var tm := UI.label(Game.format_time(float(e.get("time", 0.0))), 22, UI.GOLD)
		tm.custom_minimum_size = Vector2(150, 0)
		h.add_child(tm)
		h.add_child(UI.button("WATCH", func(): Game.play_replay(id), 20))
		h.add_child(UI.button("EXPORT MP4", func(): Game.export_replay_mp4(id), 20))
		rows.add_child(h)
	# couch + online rounds
	var matches := Game.list_matches()
	rows.add_child(UI.label("MATCHES", 28, UI.NEON))
	if matches.is_empty():
		rows.add_child(UI.label("Every couch and online round you play is recorded here (the last %d)." % Game.MATCH_MAX, 18, UI.DIM))
	for e in matches:
		var mid: String = str(e.get("id", ""))
		var mh := UI.hbox(14)
		mh.add_child(UI.label("⚑", 22, UI.GOLD))
		var mn := UI.label(str(e.get("name", "Course")), 22)
		mn.custom_minimum_size = Vector2(300, 0)
		mn.clip_text = true
		mh.add_child(mn)
		var who: Array = e.get("players", [])
		var pl := UI.label("%s  ·  %s" % ["COUCH" if e.get("mode", "") == "couch" else "ONLINE", ", ".join(PackedStringArray(who.map(func(x): return str(x))))], 17, UI.DIM)
		pl.custom_minimum_size = Vector2(330, 0)
		pl.clip_text = true
		mh.add_child(pl)
		var wl := UI.label(("won by " + str(e.winner)) if str(e.get("winner", "")) != "" else "no finish", 17, UI.GOLD)
		wl.custom_minimum_size = Vector2(190, 0)
		wl.clip_text = true
		mh.add_child(wl)
		mh.add_child(UI.button("WATCH", func(): Game.play_match(mid), 20))
		mh.add_child(UI.button("DELETE", func(): Game.delete_match(mid); show_page("replays"), 20))
		rows.add_child(mh)
	replay_status = UI.label("", 18, UI.PINK)
	replay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(replay_status)
	var b := UI.hbox(16)
	b.add_child(UI.button("OPEN VIDEOS FOLDER", func():
		DirAccess.make_dir_recursive_absolute(Game.videos_dir())
		OS.shell_open(Game.videos_dir()), 20))
	b.add_child(_back_button())
	v.add_child(b)
	if not Game.export_status.is_connected(_on_export_status):
		Game.export_status.connect(_on_export_status)


func _on_export_status(tx: String, _done: bool) -> void:
	if replay_status and is_instance_valid(replay_status):
		replay_status.text = tx


# ------------------------------------------------------------------ rebinding

func _page_bindings() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 0)
	c.add_child(panel)
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label("REBIND CONTROLS", 44, UI.NEON))
	var tabs := UI.hbox(12)
	v.add_child(tabs)
	for dv in [["kbm", "KEYBOARD + MOUSE"], ["pad", "CONTROLLER"]]:
		var d: String = dv[0]
		var tb := UI.button(("▸ " if bind_device == d else "") + dv[1], func(): bind_device = d; capture = {}; bind_status = ""; bind_scroll = 0.0; show_page("bindings"), 20)
		if bind_device == d:
			tb.add_theme_color_override("font_color", UI.GOLD)
		tabs.add_child(tb)
	var hint := "Click a slot, then press a key, mouse button (LMB/RMB/MMB, MOUSE 4/5 side buttons) or wheel. ESC cancels."
	if bind_device == "pad":
		hint = "Click a slot, then press a controller button or pull a trigger. ESC cancels. START is reserved for pause."
	v.add_child(UI.label(hint, 17, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1040, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var rows := UI.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var actions: Array = Bindings.PAD_ACTIONS if bind_device == "pad" else Bindings.KBM_ACTIONS
	var slots: int = Bindings.PAD_SLOTS if bind_device == "pad" else Bindings.KBM_SLOTS
	var map: Dictionary = Bindings.pad if bind_device == "pad" else Bindings.kbm
	for entry in actions:
		var action: String = entry[0]
		var h := UI.hbox(10)
		var l := UI.label(entry[1], 20)
		l.custom_minimum_size = Vector2(380, 0)
		h.add_child(l)
		var codes: Array = map.get(action, [])
		for slot in slots:
			var sl: int = slot
			var waiting: bool = capture.get("action", "") == action and int(capture.get("slot", -1)) == sl
			var txt := "· · ·"
			if waiting:
				txt = "press…"
			elif sl < codes.size():
				txt = Bindings.code_label(codes[sl])
			var b := UI.button(txt, func(): _start_capture(action, mini(sl, codes.size()), scroll), 20)
			b.custom_minimum_size = Vector2(240, 0)
			if waiting:
				b.add_theme_color_override("font_color", UI.GOLD)
			elif sl >= codes.size():
				b.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
			h.add_child(b)
		var clr := UI.button("✕", func(): _clear_binding(action, scroll), 18)
		clr.tooltip_text = "Unbind"
		h.add_child(clr)
		rows.add_child(h)
	var st := UI.label(bind_status, 18, UI.PINK)
	st.custom_minimum_size = Vector2(0, 26)
	v.add_child(st)
	var bottom := UI.hbox(16)
	bottom.add_child(UI.button("RESET TO DEFAULTS", func(): Bindings.reset(bind_device); Game.save_bindings(); bind_status = "Defaults restored."; show_page("bindings"), 20))
	bottom.add_child(UI.button("BACK", func(): capture = {}; show_page("controls"), 20))
	v.add_child(bottom)
	_restore_scroll(scroll)


## Keep the list where it was across rebuilds (needs the layout pass first).
func _restore_scroll(scroll: ScrollContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(bind_scroll)


func _start_capture(action: String, slot: int, scroll: ScrollContainer) -> void:
	bind_scroll = scroll.scroll_vertical
	capture = {"action": action, "slot": slot}
	bind_status = ""
	show_page("bindings")


func _clear_binding(action: String, scroll: ScrollContainer) -> void:
	bind_scroll = scroll.scroll_vertical
	var map: Dictionary = Bindings.pad if bind_device == "pad" else Bindings.kbm
	while not map.get(action, []).is_empty():
		Bindings.unbind(bind_device, action, 0)
	Game.save_bindings()
	bind_status = "Unbound."
	show_page("bindings")


func _capture_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		capture = {}
		bind_status = "Cancelled."
		get_viewport().set_input_as_handled()
		show_page("bindings")
		return
	var ok := false
	if bind_device == "pad":
		ok = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START:
			ok = false
	else:
		ok = event is InputEventKey or event is InputEventMouseButton
	if not ok:
		# swallow everything else so the GUI doesn't react mid-capture
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	var code := Bindings.code_for_event(event)
	get_viewport().set_input_as_handled()
	if code == "":
		return
	var action: String = capture.action
	var taken := Bindings.bind(bind_device, action, int(capture.slot), code)
	Game.save_bindings()
	capture = {}
	bind_status = "%s → %s" % [Bindings.code_label(code), _action_name(action)]
	if taken != "":
		bind_status += "   (removed from %s)" % _action_name(taken)
	Sfx.play("ui_click", 0.8)
	# rebuild after this event finishes so the press/release doesn't hit the new buttons
	call_deferred("show_page", "bindings")


func _action_name(action: String) -> String:
	for e in Bindings.KBM_ACTIONS:
		if e[0] == action:
			return e[1]
	return action


# ------------------------------------------------------------------ settings

func _page_settings() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	c.add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	v.add_child(UI.label("SETTINGS", 44, UI.NEON))
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake"]:
		var k: String = key
		v.add_child(UI.label(k.replace("_", " ").capitalize(), 20))
		v.add_child(UI.slider(0, 1, float(Game.settings[k]), 0.05, func(x): Game.settings[k] = x; Game.save_settings()))
	var names := {"disc_cam_lock": "Disc cam: lock to the disc (world turns)"}
	for key in ["fullscreen", "vsync", "show_ghost", "disc_cam_lock"]:
		var k2: String = key
		var cb := CheckBox.new()
		cb.text = names.get(k2, k2.replace("_", " ").capitalize())
		cb.button_pressed = bool(Game.settings[k2])
		cb.toggled.connect(func(on): Game.settings[k2] = on; Game.save_settings())
		v.add_child(cb)
	var fh := UI.hbox()
	fh.add_child(UI.label("Max FPS", 20))
	var fo := OptionButton.new()
	var caps := [0, 60, 120, 144, 165, 240, 360]
	for cap in caps:
		fo.add_item("Unlimited" if cap == 0 else str(cap))
	fo.selected = maxi(0, caps.find(int(Game.settings.max_fps)))
	fo.item_selected.connect(func(i): Game.settings.max_fps = caps[i]; Game.save_settings())
	fh.add_child(fo)
	v.add_child(fh)
	v.add_child(_back_button())
