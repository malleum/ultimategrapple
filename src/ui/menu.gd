extends Node2D
## Main menu: title, course select (pinned), random course builder,
## multiplayer lobby, controls, settings. Animated themed background.

const UI = preload("res://src/ui/ui.gd")
const Themes = preload("res://src/core/theme_db.gd")
const Background = preload("res://src/fx/background.gd")

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
	match p:
		"courses": _page_courses()
		"random": _page_random()
		"multi": _page_multi()
		"controls": _page_controls()
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
	col.add_child(UI.button("MULTIPLAYER", func(): show_page("multi"), 30))
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
		row.add_child(UI.label(("● " if p.get("ready", false) else "○ ") + str(p.name) + ("  (you)" if id == Net.my_id() else "") + ("  [host]" if id == 1 else ""), 22, Game.player_palette(int(p.color)) * 1.4))
		row.add_child(UI.label("wins %d" % int(p.wins), 18, UI.DIM))
		lobby_box.add_child(row)
	if Net.is_server():
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
	if Net.is_server():
		h2.add_child(UI.button("START SET", func(): Net.champion_text = ""; Net.start_set(), 24))
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
	var lines_l := [
		["A / D", "run  (carrying the disc is ~10% slower)"],
		["SPACE", "jump · wall-jump · jump off rope"],
		["S", "slide at speed (boost) · crouch · fast-fall"],
		["SHIFT", "dash (8-way). 1 air dash, refreshed by ground, grapple, sky catch"],
		["RMB (hold)", "grapple swing · W/S reel in/out · A/D pump"],
		["E (hold)", "zip: reel yourself to the grapple point"],
		["R", "instant restart"],
		["T", "recall disc to hand (+3s)"],
		["P", "pin this course permanently"],
	]
	var lines_r := [
		["LMB hold/release", "charge + throw toward the cursor"],
		["F  (on release)", "SNAP: press F the instant you let go of LMB.\n±35ms PERFECT (max spin, +9% speed) · ±90ms GOOD"],
		["1-6 / Q", "throw: backhand forehand hammer roller scoober thumber"],
		["WHEEL / Z X", "nose angle: up = float/stall, down = punch"],
		["CTRL (hold)", "PIVOT: plant & freeze, momentum stored. Throw clean,\nthen release CTRL within 0.3s for a PIVOT LAUNCH"],
		["moving throws", "sway + spray + less range. Scoober halves it"],
		["spin", "stability, skip shots off floors, wall kicks"],
		["catching", "grab the disc midair: refreshes dash + air pivot"],
		["goal", "get the disc into the basket. Fastest time wins"],
	]
	for l in lines_l:
		left.add_child(_ctrl_row(l[0], l[1]))
	for l in lines_r:
		right.add_child(_ctrl_row(l[0], l[1]))
	v.add_child(_back_button())


func _ctrl_row(k: String, d: String) -> Control:
	var h := UI.hbox(14)
	var kl := UI.label(k, 20, UI.PINK)
	kl.custom_minimum_size = Vector2(180, 0)
	h.add_child(kl)
	var dl := UI.label(d, 18, Color(0.9, 0.95, 1))
	h.add_child(dl)
	return h


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
	for key in ["fullscreen", "vsync", "show_ghost"]:
		var k2: String = key
		var cb := CheckBox.new()
		cb.text = k2.replace("_", " ").capitalize()
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
