extends PanelContainer
## COURSES page, in tabs: MAIN (the built-in courses), one tab per runner who
## saved courses online (up to Online.SHARE_MAX each, yours first), and your
## locally PINNED ones. Every course can be played; built-in and saved ones
## have leaderboards (BOARD: ranks, splits, race or watch the runs).

const UI = preload("res://src/ui/ui.gd")
const Themes = preload("res://src/core/theme_db.gd")

static var tab := "main"     # "main", "pinned" or a runner's online id (kept between visits)

var back_fn: Callable
var board_fn: Callable       # (course_list: Array, key: String) opens the boards
var tabs: HFlowContainer
var list: VBoxContainer
var status: Label
var _want := []              # ["play" | "board", cid] waiting for the course to download


func _ready() -> void:
	custom_minimum_size = Vector2(1180, 0)
	var v := UI.vbox(10)
	add_child(v)
	v.add_child(UI.label("COURSES", 48, UI.NEON))
	var info := UI.label("The main courses, the courses runners saved online (up to %d each: press SAVE COURSE on a results card) and the ones you pinned on this computer. Saved courses keep their exact layout and have leaderboards and runs to race." % Online.SHARE_MAX, 18, UI.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	tabs = HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 10)
	tabs.add_theme_constant_override("v_separation", 8)
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	status = UI.label("", 18, UI.PINK)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	v.add_child(UI.button("BACK", func(): back_fn.call(), 20))
	Online.catalog_received.connect(func(_l): _rebuild())
	Online.course_received.connect(_on_course)
	Online.state_changed.connect(func():
		if Online.is_online() and Online.catalog.is_empty():
			Online.request_catalog())
	Online.request_catalog()
	_rebuild()


func _rebuild() -> void:
	for c in tabs.get_children():
		c.queue_free()
	_tab_button("main", "MAIN")
	var mine_listed := false
	for p in Online.catalog:
		var me: bool = str(p.uid) == Online.uid
		mine_listed = mine_listed or me
		_tab_button(str(p.uid), "MY COURSES" if me else str(p.name).to_upper(), Game.player_palette(int(p.get("color", 0))))
	if not mine_listed and Online.uid != "":
		_tab_button(Online.uid, "MY COURSES")
	_tab_button("pinned", "PINNED")
	for c in list.get_children():
		c.queue_free()
	match tab:
		"main": _list_main()
		"pinned": _list_pinned()
		_: _list_runner(tab)


func _tab_button(id: String, text: String, col := Color(0.85, 1, 1)) -> void:
	var b := UI.button(("▸ " if tab == id else "") + text, func():
		tab = id
		_rebuild(), 20)
	b.add_theme_color_override("font_color", UI.GOLD if tab == id else col)
	tabs.add_child(b)


## name button (plays it), theme, difficulty, your best
func _row(name: String, d: Dictionary, theme_id: String, diff: float, best_id: String, play: Callable) -> HBoxContainer:
	var row := UI.hbox(14)
	var b := UI.button(name, play, 22)
	b.custom_minimum_size = Vector2(360, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	row.add_child(b)
	var th := Themes.get_theme(theme_id)
	var tl := UI.label(str(th.get("name", "")), 18, th.get("accent2", UI.DIM))
	tl.custom_minimum_size = Vector2(150, 0)
	row.add_child(tl)
	row.add_child(UI.label("D%d" % int(round(diff * 10)), 18, UI.DIM))
	var rec = Game.get_record(best_id)
	var bl := UI.label(("%s  %s" % [Game.format_time(float(rec.time)), UI.medal_name(str(rec.medal))]) if rec else "unplayed", 18,
		UI.medal_color(str(rec.medal)) if rec else UI.DIM)
	bl.custom_minimum_size = Vector2(200, 0)
	row.add_child(bl)
	return row


func _list_main() -> void:
	var levels := Game.list_pinned_levels()
	var board := _main_boards()
	var num := 0
	for i in levels.size():
		var d: Dictionary = levels[i]
		if not bool(d.get("_builtin", false)):
			continue
		var idx := i
		num += 1
		var row := _row("%d  %s" % [num, d.get("name", "Course")], d, str(d.get("theme", "")), float(d.get("difficulty", 0.5)), str(d.get("id", "")),
			func(): Game.start_pinned(idx))
		var key := Online.course_key(str(d.get("id", "")))
		if key != "":
			row.add_child(UI.button("BOARD", func(): board_fn.call(board, key), 18))
		list.add_child(row)


func _main_boards() -> Array:
	return load("res://src/ui/leaderboard_page.gd").builtin_list()


func _list_pinned() -> void:
	var levels := Game.list_pinned_levels()
	var any := false
	for i in levels.size():
		var d: Dictionary = levels[i]
		if bool(d.get("_builtin", false)):
			continue
		any = true
		var idx := i
		list.add_child(_row(str(d.get("name", "Course")), d, str(d.get("theme", "")), float(d.get("difficulty", 0.5)), str(d.get("id", "")),
			func(): Game.start_pinned(idx)))
	if not any:
		list.add_child(UI.label("Nothing pinned yet. Press P (or PIN on the results card) on a course you like to keep it on this computer.", 18, UI.DIM))


func _list_runner(who: String) -> void:
	var p: Dictionary = {}
	for e in Online.catalog:
		if str(e.uid) == who:
			p = e
	var me := who == Online.uid
	var cs: Array = p.get("courses", [])
	if not Online.is_online():
		list.add_child(UI.label(Online.link_text(), 18, UI.DIM))
		return
	if cs.is_empty():
		list.add_child(UI.label("No saved courses yet. Finish a course you like and press SAVE COURSE on the results card (up to %d)." % Online.SHARE_MAX if me
			else "Nothing saved.", 18, UI.DIM))
		return
	if me:
		list.add_child(UI.label("%d of %d saved. SAVE COURSE on a results card adds one (when full it asks which to replace)." % [cs.size(), Online.SHARE_MAX], 17, UI.DIM))
	var boards: Array = cs.map(func(c): return {"key": str(c.key), "name": str(c.name), "level": Online.cached_course(str(c.cid))})
	for c in cs:
		var cid := str(c.cid)
		var key := str(c.key)
		var row := _row(str(c.name), {}, str(c.get("theme", "")), float(c.get("diff", 0.5)), cid, func(): _fetch(cid, "play"))
		var top: Array = c.get("top", [])
		var n := int(c.get("runs", 0))
		var tl := UI.label("%d run%s" % [n, "" if n == 1 else "s"], 17, UI.DIM)
		tl.custom_minimum_size = Vector2(80, 0)
		row.add_child(tl)
		row.add_child(UI.button("BOARD", func():
			_want = ["board", cid, boards, key]
			Online.request_course(cid), 18))
		if me:
			row.add_child(UI.button("REMOVE", func():
				status.text = "Removed %s from your courses." % str(c.name)
				Online.unshare_course(cid), 18))
		list.add_child(row)
		# the podium: gold / silver / bronze
		if not top.is_empty():
			var pr := UI.hbox(22)
			var pad := Control.new()
			pad.custom_minimum_size = Vector2(30, 0)
			pr.add_child(pad)
			for i in top.size():
				pr.add_child(UI.label("%s  %s  %s" % [UI.podium(i + 1), str(top[i][0]), Game.format_time(float(top[i][1]))], 16, UI.podium_color(i + 1)))
			list.add_child(pr)


func _fetch(cid: String, what: String) -> void:
	_want = [what, cid]
	status.text = "Loading the course..."
	Online.request_course(cid)


func _on_course(cid: String, data: Dictionary) -> void:
	if _want.size() < 2 or str(_want[1]) != cid:
		return
	var what := str(_want[0])
	var w := _want
	_want = []
	if data.is_empty():
		status.text = "Couldn't get that course from the server."
		return
	if what == "play":
		Game.session = {"kind": "random"}
		Game.play_level(data)
	elif what == "board":
		var boards: Array = w[2]
		for b in boards:
			if str(b.key) == str(w[3]):
				b["level"] = data
		board_fn.call(boards, str(w[3]))
