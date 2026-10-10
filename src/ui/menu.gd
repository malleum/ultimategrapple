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
	Online.name_needed.connect(func(msg): _name_prompt(msg))
	# saved-course sources in the couch / lobby pickers come from the catalog
	Online.catalog_received.connect(func(_l):
		if page in ["multi", "lan"]:
			_build_lobby()
		elif page == "couch":
			show_page("couch"))
	show_page(start_page)
	if not bool(Game.settings.get("name_chosen", false)):
		_name_prompt("")
	if Game.updater:
		if not Game.updater.info.is_empty():
			_update_prompt(Game.updater.info)
		Game.updater.available.connect(_update_prompt)


# ------------------------------------------------------------------ update

static var _update_dismissed := false


## A newer release is out: offer to download it, swap it in and restart.
func _update_prompt(info: Dictionary) -> void:
	if _update_dismissed or page != "title":
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.theme = UI.theme()
	layer.add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var v := UI.vbox(14)
	v.custom_minimum_size = Vector2(640, 0)
	panel.add_child(v)
	v.add_child(UI.label("UPDATE AVAILABLE", 40, UI.NEON))
	var what := UI.label("A newer version of Ultimate Grapple is out (built %s%s). Download it now? The game restarts on the new version; your runs and settings stay." % [
		str(info.get("date", "")), (": " + str(info.title)) if str(info.get("title", "")) != "" else ""], 18, UI.DIM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(what)
	var st := UI.label("", 18, UI.PINK)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(st)
	var h := UI.hbox(12)
	v.add_child(h)
	var ok := UI.button("UPDATE NOW", func(): pass, 24)
	var later := UI.button("LATER", func():
		_update_dismissed = true
		shade.queue_free(), 22)
	ok.pressed.connect(func():
		ok.disabled = true
		later.disabled = true
		Game.updater.install())
	h.add_child(ok)
	h.add_child(later)
	Game.updater.progress.connect(func(text: String, done: bool, good: bool):
		if not is_instance_valid(st):
			return
		st.text = text
		if done and not good:
			later.disabled = false
			later.text = "CLOSE")


func _exit_tree() -> void:
	Net.stop_discovery()


# ------------------------------------------------------------------ name

const NAME_A := ["Neon", "Swift", "Quiet", "Lucky", "Rapid", "Sly", "Bold", "Silver", "Wild", "Crimson", "Lunar", "Frost"]
const NAME_B := ["Heron", "Comet", "Falcon", "Otter", "Disc", "Fox", "Lynx", "Raven", "Gecko", "Kite", "Pike", "Wren"]
var _name_box: Control = null


## Choose your name: on first start, and whenever the online server says the
## name is the default or taken. Until then you're off the leaderboards.
func _name_prompt(msg: String) -> void:
	if _name_box and is_instance_valid(_name_box):
		_name_box.queue_free()
	var cur := str(Game.settings.player_name).strip_edges()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.theme = UI.theme()
	layer.add_child(shade)
	_name_box = shade
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var v := UI.vbox(14)
	v.custom_minimum_size = Vector2(620, 0)
	panel.add_child(v)
	v.add_child(UI.label("CHOOSE YOUR NAME", 40, UI.NEON))
	var info := UI.label("It's how you show up online and on the leaderboards. A name is yours once you use it: nobody else can take it.", 18, UI.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var ne := LineEdit.new()
	ne.max_length = 16
	ne.custom_minimum_size = Vector2(0, 52)
	ne.add_theme_font_size_override("font_size", 28)
	ne.text = cur if Online.name_problem(cur) == "" else "%s %s" % [NAME_A.pick_random(), NAME_B.pick_random()]
	v.add_child(ne)
	var err := UI.label(msg, 18, UI.PINK)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(err)
	var h := UI.hbox(12)
	v.add_child(h)
	var ok := func():
		var n := ne.text.strip_edges()
		var why := Online.name_problem(n)
		if why != "":
			err.text = why
			return
		Game.settings.player_name = n
		Game.settings["name_chosen"] = true
		Game.save_settings()
		Online.update_profile()   # the server checks it's free (prompts again if not)
		shade.queue_free()
		if page in ["title", "leaderboards", "multi"]:
			show_page(page)
	h.add_child(UI.button("RANDOM", func(): ne.text = "%s %s" % [NAME_A.pick_random(), NAME_B.pick_random()], 22))
	h.add_child(UI.button("OK", ok, 26))
	ne.text_submitted.connect(func(_t): ok.call())
	ne.grab_focus.call_deferred()
	ne.select_all.call_deferred()


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
	# where "MENU" from a course / replay brings you back to (the boards keep
	# their own entry, with the course you were on)
	if p != "leaderboards":
		Game.return_to = {"page": p}
	match p:
		"couch": _page_couch()
		"courses": _page_courses()
		"random": _page_random()
		"elo": _page_elo()
		"multi", "lan": _page_multi()
		"controls": _page_controls()
		"replays": _page_replays()
		"leaderboards":
			var rt: Dictionary = Game.return_to
			if str(rt.get("page", "")) == "leaderboards":
				_open_boards(rt.get("list", []), str(rt.get("key", "")), str(rt.get("back", "title")))
			else:
				_page_leaderboards()
		"stats": _page_stats()
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
	col.add_child(UI.button("RANDOM", func(): show_page("random"), 30))
	col.add_child(UI.button("ELO RUN", func(): show_page("elo"), 30))
	col.add_child(UI.button("LEADERBOARDS", func(): _page_leaderboards(), 30))   # the main boards (not the last list)
	col.add_child(UI.button("REPLAYS", func(): show_page("replays"), 30))
	col.add_child(UI.button("STATS", func(): show_page("stats"), 30))
	col.add_child(UI.button("MULTIPLAYER", func(): show_page("multi"), 30))
	col.add_child(UI.button("SETTINGS", func(): show_page("settings"), 30))
	v.add_child(UI.label("F3 fps · F11 fullscreen", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	# quit, out of the way in the top-right corner
	var q := UI.button("QUIT", func(): get_tree().quit(), 20)
	page_root.add_child(q)
	q.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)


# ------------------------------------------------------------------ courses

const CoursesPage = preload("res://src/ui/courses_page.gd")


func _page_courses() -> void:
	var c := _clear()
	var cp := CoursesPage.new()
	cp.back_fn = func(): show_page("title")
	cp.board_fn = func(list: Array, key: String): _open_boards(list, key)
	c.add_child(cp)


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
	h.add_child(UI.button("QUICK RANDOM", func(): Game.start_random(randi() % 1000000, "", 0.5, 12), 30))
	h.add_child(_back_button())
	v.add_child(h)
	v.add_child(UI.label("Tip: same seed + settings = same course. Press P in-game to pin it.", 16, UI.DIM))


# ------------------------------------------------------------------ elo run

func _page_elo() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	c.add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	v.add_child(UI.label("ELO RUN", 48, UI.NEON))
	var rl := UI.label("Rating …", 34, Color(1, 0.85, 0.35))
	v.add_child(rl)
	var il := UI.label("", 20, UI.DIM)
	v.add_child(il)
	var rules := UI.label("One run per seed, ever. Restart, quit or a crash is a DNF and the seed is gone. " + \
		"Seeds others have played come with the best, median and worst ghost. Your rating moves against the average time on each seed.", 17, UI.DIM)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rules)
	var status := UI.label("", 20, Color(0.5, 0.9, 1.0))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	var h := UI.hbox()
	var play := UI.button("PLAY NEXT GAME", func(): pass, 30)
	play.pressed.connect(func():
		play.disabled = true
		status.text = "Getting your seed…"
		Elo.next_game(func(ok: bool, d: Dictionary):
			if ok:
				Game.start_elo(d)
			elif is_instance_valid(status):
				play.disabled = false
				status.text = str(d.get("message", "No answer"))))
	h.add_child(play)
	h.add_child(_back_button())
	v.add_child(h)
	v.add_child(UI.label("LADDER", 26, UI.NEON))
	var ladder := UI.vbox(2)
	v.add_child(ladder)
	var lt := UI.label("Loading…", 18, UI.DIM)
	ladder.add_child(lt)
	if Elo.is_open():
		status.text = "An unfinished game was forfeited."
	Elo.recover()
	Elo.fetch_rating(func(ok: bool, d: Dictionary):
		if not is_instance_valid(rl):
			return
		if not ok:
			rl.text = "Rating unavailable"
			status.text = str(d.get("message", ""))
			return
		var gp := int(d.get("games_played", 0))
		var rated := int(d.get("rated_games", 0))
		rl.text = ("Rating %d" % int(round(float(d.get("rating", 1000))))) + ("  (provisional)" if bool(d.get("provisional", true)) else "") + \
			("   ·   ladder #%d" % int(d.ladder_rank) if int(d.get("ladder_rank", 0)) > 0 else "")
		il.text = "Next: game %d  ·  set %d, seed %d of 3  ·  %d rated, %d pending" % [gp + 1, Elo.set_of(gp + 1), Elo.set_position(gp + 1), rated, int(d.get("pending_games", 0))])
	Elo.fetch_ladder(10, func(ok: bool, d: Dictionary):
		if not is_instance_valid(lt):
			return
		var list: Array = d.get("entries", []) if ok and d.get("entries") is Array else []
		if list.is_empty():
			lt.text = "No rated players yet." if ok else "Ladder unavailable"
			return
		lt.queue_free()
		for e in list:
			var mine := str(e.get("uid", "")) == Elo.uid
			ladder.add_child(UI.label("%2d.  %-18s %5d   (%d games)" % [int(e.get("rank", 0)), str(e.get("name", "?")).substr(0, 18),
				int(round(float(e.get("rating", 0)))), int(e.get("rated_games", 0))], 18, Color(1, 0.85, 0.35) if mine else Color(0.9, 0.97, 1))))


# ------------------------------------------------------------------ multiplayer

func _page_multi() -> void:
	var c := _clear()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 720)
	c.add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	v.add_child(UI.label("MULTIPLAYER", 48, UI.NEON))
	v.add_child(_multi_tabs())
	if Net.champion_text != "":
		v.add_child(UI.label(Net.champion_text, 32, UI.GOLD))
	var who := UI.hbox()
	who.add_child(UI.label("Name", 22))
	var ne := LineEdit.new()
	ne.text = str(Game.settings.player_name)
	ne.custom_minimum_size = Vector2(240, 0)
	ne.max_length = 16
	ne.text_changed.connect(func(tx):
		Game.settings.player_name = tx
		Game.settings["name_chosen"] = Online.name_problem(tx) == ""
		Game.save_settings())
	ne.focus_exited.connect(func(): Online.update_profile())
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
	# ONLINE: straight onto the public server the first time it's opened
	if page == "multi" and not Net.in_lobby and Net.peer == null and not _auto_joined:
		_auto_joined = true
		Net.join(_online_address())


static var _auto_joined := false


func _online_address() -> String:
	var a := str(Game.settings.online_server).strip_edges()
	return a if a != "" else Net.ONLINE_SERVER


## ONLINE (public server) · COUCH (split-screen) · LAN (host / join nearby)
func _multi_tabs() -> HBoxContainer:
	var tabs := UI.hbox(12)
	for tb in [["multi", "ONLINE"], ["couch", "COUCH VERSUS"], ["lan", "LAN"]]:
		var id: String = tb[0]
		var b := UI.button(("▸ " if page == id else "") + str(tb[1]), func(): show_page(id), 20)
		if page == id:
			b.add_theme_color_override("font_color", UI.GOLD)
		tabs.add_child(b)
	return tabs


func _build_lobby() -> void:
	if lobby_box == null or not is_instance_valid(lobby_box):
		return
	for ch in lobby_box.get_children():
		ch.queue_free()
	if not Net.in_lobby and page == "multi":
		var on := UI.hbox()
		var srv := LineEdit.new()
		srv.text = str(Game.settings.online_server)
		srv.placeholder_text = Net.ONLINE_SERVER
		srv.custom_minimum_size = Vector2(320, 0)
		srv.text_changed.connect(func(tx): Game.settings.online_server = tx.strip_edges(); Game.save_settings())
		on.add_child(UI.button("PLAY ONLINE", func(): Net.join(_online_address()), 26))
		on.add_child(srv)
		lobby_box.add_child(on)
		lobby_box.add_child(UI.label("Joins the public server. No port forwarding needed. The first player in picks the settings and starts.", 16, UI.DIM))
		return
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
		lobby_box.add_child(UI.label("Dedicated server:  nix run . -- --server [--port=24680 --wins=3 --source=random|pinned]  ·  any number of players", 16, UI.DIM))
		return
	Net.stop_discovery()
	lobby_box.add_child(UI.label("LOBBY  ·  %d runner%s  ·  first to %d wins  ·  %s" % [Net.players.size(), "" if Net.players.size() == 1 else "s", int(Net.settings.wins), Net.source_text()], 24, UI.GOLD))
	# any number of runners: chips that wrap, scrolling once there are lots
	var pscroll := ScrollContainer.new()
	pscroll.custom_minimum_size = Vector2(0, mini(60 + 44 * int(ceil(Net.players.size() / 3.0)), 260))
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_box.add_child(pscroll)
	var chips := HFlowContainer.new()
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("h_separation", 26)
	pscroll.add_child(chips)
	var ids := Net.players.keys()
	ids.sort_custom(func(a, b): return int(Net.players[a].get("order", 0)) < int(Net.players[b].get("order", 0)))
	for id in ids:
		var p: Dictionary = Net.players[id]
		var chip := UI.label(("● " if p.get("ready", false) else "○ ") + str(p.name) + (" (you)" if id == Net.my_id() else "") + (" ★" if int(id) == Net.leader_id() else "") + ("  ·  %d" % int(p.wins) if int(p.wins) > 0 else ""),
			20, Game.player_palette(int(p.color)) * 1.4)
		chip.custom_minimum_size = Vector2(320, 0)
		chips.add_child(chip)
	if Net.is_leader():
		var s := UI.hbox()
		s.add_child(UI.label("First to", 20))
		var sb := SpinBox.new()
		sb.min_value = 1
		sb.max_value = 15
		sb.value = int(Net.settings.wins)
		sb.value_changed.connect(func(x): Net.update_settings({"wins": int(x)}))
		s.add_child(sb)
		var cur := str(Net.settings.source)
		if cur == "saved":
			cur = "saved::" + str(Net.settings.get("pool_name", ""))
		s.add_child(_source_picker(cur, func(key: String):
			if key.begins_with("saved:"):
				Net.use_saved_courses(key.get_slice(":", 1), key.get_slice(":", 2))
			else:
				Net.update_settings({"source": key})))
		s.add_child(UI.label("Difficulty", 20))
		var ds := UI.slider(0, 1, float(Net.settings.difficulty), 0.1, func(x): Net.update_settings({"difficulty": x}))
		ds.custom_minimum_size = Vector2(160, 28)
		s.add_child(ds)
		lobby_box.add_child(s)
		if Net.pool_status != "":
			lobby_box.add_child(UI.label(Net.pool_status, 16, UI.PINK))
	var h2 := UI.hbox()
	h2.add_child(UI.button("READY", func(): Net.toggle_ready(), 24))
	if Net.is_leader():
		h2.add_child(UI.button("START SET", func(): Net.champion_text = ""; Net.request_start(), 24))
	else:
		lobby_box.add_child(UI.label("Waiting for the leader to start (or everyone READY).", 16, UI.DIM))
	h2.add_child(UI.button("LEAVE", func(): Net.leave(); _build_lobby(), 24))
	lobby_box.add_child(h2)


## Which courses a set is raced on: random, the main courses, or the courses
## one runner saved online (keys "random", "pinned", "saved:<uid>:<name>").
## `current` matches a saved entry by "saved:<uid>:" or "saved::<name>".
func _source_picker(current: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	var keys: Array = ["random", "pinned"]
	ob.add_item("Random courses")
	ob.add_item("Main courses")
	for p in Online.catalog:
		var n := (p.get("courses", []) as Array).size()
		if n == 0:
			continue
		var who := "My" if str(p.uid) == Online.uid else "%s's" % str(p.name)
		ob.add_item("%s saved courses (%d)" % [who, n])
		keys.append("saved:%s:%s" % [str(p.uid), str(p.name)])
	var sel := 0
	for i in keys.size():
		var k: String = keys[i]
		if k == current or (current.begins_with("saved:") and k.begins_with("saved:") and
				((current.get_slice(":", 1) != "" and k.get_slice(":", 1) == current.get_slice(":", 1)) or (current.get_slice(":", 1) == "" and k.get_slice(":", 2) == current.get_slice(":", 2)))):
			sel = i
	ob.selected = sel
	ob.item_selected.connect(func(i): on_pick.call(keys[i]))
	if Online.catalog.is_empty():
		Online.request_catalog()   # the saved-course entries show on the next rebuild
	return ob


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
	panel.custom_minimum_size = Vector2(1100, 640)
	c.add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	v.add_child(UI.label("MULTIPLAYER", 48, UI.NEON))
	v.add_child(_multi_tabs())
	if Game.couch_champion != "":
		v.add_child(UI.label(Game.couch_champion, 32, UI.GOLD))
	v.add_child(UI.label("Split-screen race, up to %d players. Everyone has their own gates, glass and grapple points.\nPress A on a controller (or SPACE on the keyboard) to join. B / BACKSPACE to leave. X / C to change color." % Game.COUCH_MAX, 18, UI.DIM))
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
	s.add_child(_source_picker(couch_source, func(key: String): couch_source = key))
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
	for i in maxi(4, mini(couch_players.size() + 1, Game.COUCH_MAX)):
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
	if _couch_index(device) >= 0 or couch_players.size() >= Game.COUCH_MAX:
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
	if couch_source.begins_with("saved:"):
		# a runner's saved courses: fetch them first
		var who := couch_source.get_slice(":", 1)
		var cids: Array = []
		for p in Online.catalog:
			if str(p.uid) == who:
				cids = (p.get("courses", []) as Array).map(func(c): return str(c.cid))
		Online.fetch_courses(cids, func(levels: Array):
			if levels.is_empty():
				Game.start_couch(players, couch_wins, "random", couch_diff)
			else:
				Game.start_couch(players, couch_wins, "saved", couch_diff, levels))
		return
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
	h.add_child(UI.button("BACK", func(): show_page("settings"), 20))
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
	v.add_child(UI.label("Favorites first (★ FAVORITE on any results card keeps that run, PB or not), then your personal-best run on each course, most recently played first. Watch with the keystroke overlay, or export an MP4 to send to friends. Couch and online rounds are below.", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var rows := UI.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	# favorites: runs kept on purpose, plus starred matches
	var favs := Game.list_favorites()
	var fav_matches := Game.list_matches().filter(func(e): return bool(e.get("fav", false)))
	rows.add_child(UI.label("★ FAVORITES", 28, UI.GOLD))
	if favs.is_empty() and fav_matches.is_empty():
		rows.add_child(UI.label("Press ★ FAVORITE on a results card (PB or not), or ★ a replay or match below, to keep it here.", 18, UI.DIM))
	for e in favs:
		var fid: String = str(e.id)
		var key := "fav:" + fid
		var fh := UI.hbox(14)
		fh.add_child(UI.label("★", 22, UI.medal_color(str(e.get("medal", "")))))
		var fn := UI.label(str(e.get("name", "Course")), 22)
		fn.custom_minimum_size = Vector2(360, 0)
		fn.clip_text = true
		fh.add_child(fn)
		var fp := UI.label(str(e.get("player", "")), 18, UI.DIM)
		fp.custom_minimum_size = Vector2(190, 0)
		fp.clip_text = true
		fh.add_child(fp)
		var ft := UI.label(Game.format_time(float(e.get("time", 0.0))), 22, UI.GOLD)
		ft.custom_minimum_size = Vector2(150, 0)
		fh.add_child(ft)
		if bool(e.get("old", false)):
			fh.add_child(UI.label("older game version: can't play back", 17, UI.DIM))
		else:
			fh.add_child(UI.button("WATCH", func(): Game.play_replay(key), 20))
			fh.add_child(UI.button("EXPORT MP4", func(): Game.export_replay_mp4(key), 20))
			fh.add_child(_send_button("run", "%s %s" % [str(e.get("name", "Course")), Game.format_time(float(e.get("time", 0.0)))], func(): return Game.run_for_sending(key)))
		fh.add_child(UI.button("DELETE", func(): Game.delete_favorite(fid); show_page("replays"), 20))
		rows.add_child(fh)
	for e in fav_matches:
		rows.add_child(_match_row(e))
	rows.add_child(UI.label("PERSONAL BESTS", 28, UI.NEON))
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
		h.add_child(_send_button("run", "%s %s" % [str(e.get("name", id)), Game.format_time(float(e.get("time", 0.0)))], func(): return Game.run_for_sending(id)))
		var pb_rep := {"level_id": id, "date": e.get("date", 0), "time": e.get("time", 0.0)}
		if Game.favorite_id_of(pb_rep) == "":
			h.add_child(UI.button("★", func():
				Game.save_favorite(Game.load_replay(id))
				show_page("replays"), 20))
		rows.add_child(h)
	# friends' runs (imported .ugr files)
	var rivals := Game.list_rivals()
	rows.add_child(UI.label("FRIENDS' RUNS", 28, UI.NEON))
	if rivals.is_empty():
		rows.add_child(UI.label("SHARE FILE saves your run as a .ugr in %s. Import a friend's (or drop it on the window) to race their ghost on that course." % Game.share_dir(), 18, UI.DIM))
	for e in rivals:
		var rid: String = str(e.get("id", ""))
		var rh := UI.hbox(14)
		rh.add_child(UI.label("◆", 22, Color(1, 0.6, 0.3)))
		var rn := UI.label(str(e.get("name", "Course")), 22)
		rn.custom_minimum_size = Vector2(330, 0)
		rn.clip_text = true
		rh.add_child(rn)
		var rp := UI.label(str(e.get("player", "Friend")), 18, UI.DIM)
		rp.custom_minimum_size = Vector2(170, 0)
		rp.clip_text = true
		rh.add_child(rp)
		var rt := UI.label(Game.format_time(float(e.get("time", 0.0))), 22, UI.GOLD)
		rt.custom_minimum_size = Vector2(150, 0)
		rh.add_child(rt)
		rh.add_child(UI.button("RACE", func(): Game.race_rival(rid), 20))
		rh.add_child(UI.button("WATCH", func():
			if not Game.watch_rival(rid):
				_on_export_status("That run was made with another version of the game: race it as a ghost instead.", true), 20))
		rh.add_child(UI.button("REMOVE", func(): Game.delete_rival(rid); show_page("replays"), 20))
		rows.add_child(rh)
	# couch + online rounds
	var matches := Game.list_matches()
	rows.add_child(UI.label("MATCHES", 28, UI.NEON))
	if matches.is_empty():
		rows.add_child(UI.label("Every couch and online round you play is recorded here (the last %d)." % Game.MATCH_MAX, 18, UI.DIM))
	for e in matches:
		if not bool(e.get("fav", false)):
			rows.add_child(_match_row(e))
	replay_status = UI.label("", 18, UI.PINK)
	replay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(replay_status)
	var b := UI.hbox(16)
	b.add_child(UI.button("IMPORT FRIEND'S RUN", _import_dialog, 20))
	b.add_child(UI.button("OPEN SHARE FOLDER", func():
		DirAccess.make_dir_recursive_absolute(Game.share_dir())
		OS.shell_open(Game.share_dir()), 20))
	b.add_child(UI.button("OPEN VIDEOS FOLDER", func():
		DirAccess.make_dir_recursive_absolute(Game.videos_dir())
		OS.shell_open(Game.videos_dir()), 20))
	b.add_child(_back_button())
	v.add_child(b)
	if not Game.export_status.is_connected(_on_export_status):
		Game.export_status.connect(_on_export_status)
	if not Online.send_result.is_connected(_on_send_result):
		Online.send_result.connect(_on_send_result)


## One match recording row; ★ / ☆ stars it (starred ones are kept for good
## and listed under favorites).
func _match_row(e: Dictionary) -> Control:
	var mid: String = str(e.get("id", ""))
	var fav := bool(e.get("fav", false))
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
	mh.add_child(UI.button("MP4", func(): Game.export_replay_mp4("match:" + mid), 20))
	mh.add_child(_send_button("match", str(e.get("name", "Course")), func(): return Game.load_match(mid)))
	mh.add_child(UI.button("★ UNSTAR" if fav else "★", func(): Game.set_match_favorite(mid, not fav); show_page("replays"), 20))
	mh.add_child(UI.button("DELETE", func(): Game.delete_match(mid); show_page("replays"), 20))
	return mh


# ------------------------------------------------------------------ leaderboards

const LeaderboardPage = preload("res://src/ui/leaderboard_page.gd")


const StatsPage = preload("res://src/ui/stats_page.gd")


func _page_stats() -> void:
	var c := _clear()
	var sp := StatsPage.new()
	sp.back_fn = func(): show_page("title")
	c.add_child(sp)


func _page_leaderboards() -> void:
	_open_boards([], "", "title")


## The boards of these courses ([] = the built-ins), opened on `key`.
func _open_boards(list: Array, key: String, back := "courses") -> void:
	page = "leaderboards"
	Game.return_to = {"page": "leaderboards", "list": list, "key": key, "back": back}
	var c := _clear()
	var lp := LeaderboardPage.new()
	lp.course_list = list
	lp.start_key = key
	lp.back_fn = func(): show_page(back)
	lp.name_fn = func(): _name_prompt("")
	c.add_child(lp)


## SEND: pick someone online and relay this replay / match through the server.
func _send_button(kind: String, title: String, data_fn: Callable) -> Button:
	return UI.button("SEND", func(): _send_dialog(kind, title, data_fn), 20)


func _send_dialog(kind: String, title: String, data_fn: Callable) -> void:
	if not Online.is_online():
		_on_export_status("Not connected to the online server (Settings → online services).", true)
		return
	var others: Array = Online.presence.filter(func(p): return str(p.uid) != Online.uid)
	if others.is_empty():
		_on_export_status("Nobody else is online right now.", true)
		return
	var pop := PopupPanel.new()
	var v := UI.vbox(8)
	pop.add_child(v)
	v.add_child(UI.label("Send %s to:" % title, 20, UI.NEON))
	for p in others:
		var who: Dictionary = p
		var b := UI.button(str(who.name), func():
			var d: Dictionary = data_fn.call()
			if d.is_empty():
				_on_export_status("Couldn't load that recording.", true)
			else:
				_on_export_status("Sending to %s..." % who.name, false)
				Online.send_to(str(who.uid), kind, title, d)
			pop.queue_free(), 20)
		b.add_theme_color_override("font_color", Game.player_palette(int(who.get("color", 0))))
		v.add_child(b)
	v.add_child(UI.button("CANCEL", func(): pop.queue_free(), 18))
	add_child(pop)
	pop.popup_centered()


func _on_send_result(ok: bool, text: String) -> void:
	_on_export_status(text, true)


func _import_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.ugr ; Ultimate Grapple runs"])
	fd.use_native_dialog = true
	DirAccess.make_dir_recursive_absolute(Game.share_dir())
	fd.current_dir = Game.share_dir()
	fd.title = "Import a friend's run"
	fd.file_selected.connect(func(path):
		var err := Game.import_rival(path)
		show_page("replays")
		_on_export_status(err if err != "" else "Imported %s" % path.get_file(), true)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.7)


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
	for key in ["master_volume", "music_volume", "sfx_volume", "screen_shake", "rumble"]:
		var k: String = key
		v.add_child(UI.label(k.replace("_", " ").capitalize(), 20))
		v.add_child(UI.slider(0, 1, float(Game.settings[k]), 0.05, func(x): Game.settings[k] = x; Game.save_settings()))
	var names := {"disc_cam_lock": "Disc cam: lock to the disc (world turns)",
		"check_updates": "Check for a new version on start (downloaded release builds)",
		"online_services": "Online services: leaderboards, who's online, sending runs",
		"share_records": "Post my PBs on the built-in courses to the online leaderboard"}
	for key in ["fullscreen", "vsync", "show_ghost", "disc_cam_lock", "online_services", "share_records", "check_updates"]:
		var k2: String = key
		var cb := CheckBox.new()
		cb.text = names.get(k2, k2.replace("_", " ").capitalize())
		cb.button_pressed = bool(Game.settings[k2])
		cb.toggled.connect(func(on):
			Game.settings[k2] = on
			Game.save_settings()
			if k2 == "online_services":
				if on:
					Online.connect_to(str(Game.settings.online_server))
				else:
					Online.disconnect_services()
			elif k2 == "share_records" and on:
				Online.sync_local_records())
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
	var sh := UI.hbox(16)
	sh.add_child(UI.button("CONTROLS", func(): show_page("controls"), 22))
	sh.add_child(_back_button())
	v.add_child(sh)
