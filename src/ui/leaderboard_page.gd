extends PanelContainer
## LEADERBOARDS page: the online boards of the built-in courses. Tick any
## number of runs to compare their splits side by side, race them all as
## ghosts, or watch them run together.

const UI = preload("res://src/ui/ui.gd")
const Stats = preload("res://src/core/stats.gd")
const FETCH_TIMEOUT := 12.0

var back_fn: Callable
var name_fn: Callable     # opens the choose-your-name prompt
## The courses to show boards for: [{key, name, level}]. Empty: the built-ins.
var course_list: Array = []
var start_key := ""       # open this one first
var heading := "LEADERBOARDS"
var datas := {}           # course key -> level data
var names := {}           # course key -> course name
var keys: Array = []      # course keys in menu order
var course := ""
var entries: Array = []
var picked := {}          # uid -> true
var got := {}             # uid -> {info, frames}  (this course)
var pending := {}         # uid -> true while fetching
var action := ""          # "race" / "watch" once the fetch completes
var fetch_t := 0.0

var status: Label
var online_lbl: Label
var course_row: HFlowContainer
var board_box: VBoxContainer
var split_grid: GridContainer
var race_btn: Button
var watch_btn: Button


func _ready() -> void:
	custom_minimum_size = Vector2(1180, 0)
	var v := UI.vbox(10)
	add_child(v)
	v.add_child(UI.label(heading, 48, UI.NEON))
	v.add_child(UI.label("Best runs, kept on the online server (gold, silver and bronze: the top three). Tick runs to compare their splits, race them all as ghosts, or watch them together. Your PBs here are posted automatically (Settings).", 18, UI.DIM))
	online_lbl = UI.label("", 18, Color(0.5, 0.9, 1.0))
	online_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(online_lbl)
	course_row = HFlowContainer.new()
	v.add_child(course_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	board_box = UI.vbox(4)
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(board_box)
	v.add_child(UI.label("SPLITS OF THE TICKED RUNS", 20, UI.GOLD))
	var sscroll := ScrollContainer.new()
	sscroll.custom_minimum_size = Vector2(1120, 150)
	v.add_child(sscroll)
	split_grid = GridContainer.new()
	split_grid.add_theme_constant_override("h_separation", 22)
	sscroll.add_child(split_grid)
	status = UI.label("", 18, UI.PINK)
	v.add_child(status)
	var b := UI.hbox(16)
	race_btn = UI.button("RACE TICKED", func(): _fetch_then("race"), 22)
	watch_btn = UI.button("WATCH TICKED", func(): _fetch_then("watch"), 22)
	b.add_child(race_btn)
	b.add_child(watch_btn)
	b.add_child(UI.button("REFRESH", func():
		if Online.is_online():
			Online.request_board(course)
		elif bool(Game.settings.get("online_services", true)):
			Online.connect_to(str(Game.settings.get("online_server", "joshammer.com"))), 22))
	b.add_child(UI.button("BACK", func(): back_fn.call(), 20))
	v.add_child(b)

	if course_list.is_empty():
		course_list = builtin_list()
	for c in course_list:
		var kk := str(c.key)
		keys.append(kk)
		names[kk] = str(c.name)
		datas[kk] = c.get("level", {})
		course_row.add_child(UI.button(names[kk], func(): _select(kk), 18))

	Online.state_changed.connect(_on_state)
	Online.board_received.connect(_on_board)
	Online.run_received.connect(_on_run)
	_on_state()
	if not keys.is_empty():
		_select(start_key if keys.has(start_key) else keys[0])


## The built-in courses as a course list, in menu order.
static func builtin_list() -> Array:
	var levels := {}
	for d in Game.list_pinned_levels():
		if bool(d.get("_builtin", false)):
			levels[str(d.id)] = d
	var bc := Online.builtin_courses()
	var ks: Array = []
	for k in bc:
		if levels.has(str(bc[k])):
			ks.append(k)
	ks.sort_custom(func(a, c): return str(bc[a]) < str(bc[c]))
	var out: Array = []
	for k in ks:
		var d: Dictionary = levels[str(bc[k])]
		out.append({"key": k, "name": str(d.get("name", bc[k])), "level": d})
	return out


func _process(dt: float) -> void:
	if action == "":
		return
	fetch_t += dt
	if fetch_t > FETCH_TIMEOUT:
		status.text = "The server didn't send %d of the runs. Try again." % pending.size()
		action = ""
		pending.clear()


func _on_state() -> void:
	if Online.is_online():
		var names: Array = []
		for p in Online.presence:
			names.append(str(p.name))
		online_lbl.text = "Online as %s  ·  online now: %s" % [str(Game.settings.player_name), ", ".join(PackedStringArray(names))]
		if not Online.name_ok:
			online_lbl.text = "Online, but not on the leaderboards yet: %s" % Online.name_msg
		if course != "":
			Online.request_board(course)
	else:
		online_lbl.text = Online.link_text()
	_rebuild()


func _select(k: String) -> void:
	course = k
	if str(Game.return_to.get("page", "")) == "leaderboards":
		Game.return_to["key"] = k   # back from a race / watch: this course again
	entries = []
	picked.clear()
	got.clear()
	for c in course_row.get_children():
		if c is Button:
			c.modulate = Color(1, 1, 1) if c.text == _course_name(k) else Color(0.6, 0.65, 0.75)
	_rebuild()
	Online.request_board(k)


func _course_name(k: String) -> String:
	return str(names.get(k, k))


func _on_board(c: String, list: Array) -> void:
	if c != course:
		return
	entries = list
	var still := {}
	for e in entries:
		if picked.has(str(e.uid)):
			still[str(e.uid)] = true
	picked = still
	_rebuild()


## You see the boards once you've picked a name (and the server took it).
func _named() -> bool:
	return bool(Game.settings.get("name_chosen", false)) and (Online.name_ok or not Online.is_online())


func _rebuild() -> void:
	for c in board_box.get_children():
		c.queue_free()
	if not _named():
		board_box.add_child(UI.label("Choose a name to see the leaderboards and get your runs on them. Your runs so far are kept and show up under it.", 20, UI.DIM))
		if name_fn.is_valid():
			board_box.add_child(UI.button("CHOOSE NAME", name_fn, 22))
		entries = []
		picked.clear()
		_rebuild_splits()
		return
	if entries.is_empty():
		var why := ""
		if Online.is_online():
			why = "No runs yet on this course." if Online.courses.has(course) or course.begins_with("sc_") else \
				"The online server runs a different version of the game, so it has no board for this version of the course. Update both to the same version."
		board_box.add_child(UI.label(why, 20, UI.DIM))
	var rank := 1
	for e in entries:
		var uid := str(e.uid)
		var h := UI.hbox(14)
		var cb := CheckBox.new()
		cb.button_pressed = picked.has(uid)
		cb.toggled.connect(func(on):
			if on:
				picked[uid] = true
			else:
				picked.erase(uid)
			_rebuild_splits())
		h.add_child(cb)
		# gold / silver / bronze: the top three places
		var rl := UI.label("#%d" % rank, 20, UI.podium_color(rank))
		rl.custom_minimum_size = Vector2(56, 0)
		h.add_child(rl)
		var pl0 := UI.label(UI.podium(rank), 15, UI.podium_color(rank))
		pl0.custom_minimum_size = Vector2(70, 0)
		h.add_child(pl0)
		h.add_child(UI.label("●", 20, Game.player_palette(int(e.get("color", 0)))))
		var me := uid == Online.uid
		var nl := UI.label(str(e.name) + ("  (you)" if me else ""), 20, UI.NEON if me else Color(0.9, 0.97, 1))
		nl.custom_minimum_size = Vector2(250, 0)
		nl.clip_text = true
		h.add_child(nl)
		var tl := UI.label(Game.format_time(float(e.time)), 20, UI.GOLD)
		tl.custom_minimum_size = Vector2(150, 0)
		h.add_child(tl)
		h.add_child(UI.label("●", 18, UI.medal_color(str(e.get("medal", "")))))
		# how much they've played this course (an older server sends none)
		var played := "%s tries  ·  %s clears  ·  %s chrons" % [_n(e.get("att", 0)), _n(e.get("comp", 0)), Stats.chron_text(float(e.get("play", 0.0)))] \
			if e.has("att") else ""
		var pl := UI.label(played, 16, Color(0.75, 0.85, 1.0))
		pl.custom_minimum_size = Vector2(330, 0)
		h.add_child(pl)
		var dl := UI.label(Time.get_date_string_from_unix_time(int(e.get("date", 0))), 16, UI.DIM)
		h.add_child(dl)
		board_box.add_child(h)
		rank += 1
	_rebuild_splits()


## Cumulative split times of the ticked runs, one row each; the fastest in
## every column is gold, the rest show how far behind it they are.
func _rebuild_splits() -> void:
	for c in split_grid.get_children():
		c.queue_free()
	var rows: Array = []
	for e in entries:
		if picked.has(str(e.uid)) and e.get("splits") is Array and not (e.splits as Array).is_empty():
			rows.append(e)
	race_btn.disabled = picked.is_empty()
	watch_btn.disabled = picked.is_empty()
	if rows.is_empty():
		split_grid.columns = 1
		split_grid.add_child(UI.label("Tick runs above to compare their splits.", 17, UI.DIM))
		return
	var n := 0
	for e in rows:
		n = maxi(n, (e.splits as Array).size())
	split_grid.columns = n + 1
	split_grid.add_child(UI.label("", 16))
	for i in n:
		split_grid.add_child(UI.label("FINISH" if i == n - 1 else "SPLIT %d" % (i + 1), 15, UI.DIM))
	var best: Array = []
	for i in n:
		var b := INF
		for e in rows:
			if i < (e.splits as Array).size():
				b = minf(b, float(e.splits[i]))
		best.append(b)
	for e in rows:
		split_grid.add_child(UI.label(str(e.name), 17, Game.player_palette(int(e.get("color", 0)))))
		for i in n:
			if i >= (e.splits as Array).size():
				split_grid.add_child(UI.label("-", 16, UI.DIM))
				continue
			var t := float(e.splits[i])
			var lead := Game.centis(t) <= Game.centis(float(best[i]))
			var txt := Game.short_time(t) if lead else "%s  +%s" % [Game.short_time(t), Game.gap_text(t, float(best[i]))]
			split_grid.add_child(UI.label(txt, 16, UI.GOLD if lead else Color(1, 0.65, 0.5)))


func _fetch_then(what: String) -> void:
	if picked.is_empty() or not Online.is_online():
		status.text = "Tick some runs first." if Online.is_online() else "Not connected to the online server."
		return
	pending.clear()
	for uid in picked:
		if not got.has(uid):
			pending[uid] = true
			Online.request_run(course, uid)
	action = what
	fetch_t = 0.0
	status.text = "Fetching %d run(s)..." % pending.size()
	if pending.is_empty():
		_launch()


func _on_run(c: String, uid: String, info: Dictionary, data: Dictionary) -> void:
	if c != course or not pending.has(uid):
		return
	pending.erase(uid)
	if data.get("frames") is Array and (data.frames as Array).size() >= 3:
		got[uid] = {"info": info, "frames": data.frames}
	if pending.is_empty() and action != "":
		_launch()


func _launch() -> void:
	var what := action
	action = ""
	var runs: Array = []
	for uid in picked:
		if got.has(uid):
			runs.append(got[uid])
	if runs.is_empty():
		status.text = "Couldn't get those runs."
		return
	runs.sort_custom(func(a, b): return float(a.info.time) < float(b.info.time))
	var data: Dictionary = datas.get(course, {})
	if data.is_empty() and course.begins_with("sc_"):
		# a saved course we haven't downloaded yet: fetch it, then go
		var cid := course.get_slice(":", 0)
		var k := course
		status.text = "Fetching the course..."
		Online.course_received.connect(func(c, d):
			if c == cid and not d.is_empty() and is_inside_tree() and course == k:
				datas[k] = d
				action = what
				_launch(), CONNECT_ONE_SHOT)
		Online.request_course(cid)
		return
	if data.is_empty():
		return
	data = data.duplicate(true)
	data.erase("_builtin")
	if what == "race":
		var rv: Array = []
		for r in runs:
			rv.append({"frames": r.frames, "name": str(r.info.name), "time": float(r.info.time),
				"color": Game.player_palette(int(r.info.get("color", 0)))})
		var rival: Dictionary = rv[0]
		rival["more"] = rv.slice(1)
		rival["no_pb"] = true   # only the ticked runs, not your own PB ghost on top
		Game.play_level(data, "solo", [], {}, rival)
	else:
		var rs: Array = []
		for r in runs:
			rs.append({"name": str(r.info.name), "color": Game.player_palette(int(r.info.get("color", 0))),
				"frames": r.frames, "time": float(r.info.time), "throws": int(r.info.get("throws", 0))})
		Game.play_match_data({"kind": "match", "mode": "board", "level": data, "name": str(data.get("name", "Course")),
			"theme": str(data.get("theme", "")), "date": int(Time.get_unix_time_from_system()), "runners": rs,
			"winner": str(runs[0].info.name), "countdown": 3.0})


static func _n(v) -> String:
	return Stats._num(float(v))
