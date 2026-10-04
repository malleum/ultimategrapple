extends PanelContainer
## STATS page: everything this install has counted (src/core/stats.gd), time
## in chrons (1 chron = 1% of a day = 14 min 24 s), and the most played courses.

const UI = preload("res://src/ui/ui.gd")
const Stats = preload("res://src/core/stats.gd")

var back_fn: Callable


func _ready() -> void:
	custom_minimum_size = Vector2(1180, 0)
	var v := UI.vbox(10)
	add_child(v)
	var head := UI.hbox(24)
	v.add_child(head)
	head.add_child(UI.label("STATS", 48, UI.NEON))
	var big := UI.label("%s CHRONS PLAYED" % Stats.chron_text(Stats.get_n("play_s")), 34, UI.GOLD)
	head.add_child(big)
	v.add_child(UI.label("1 chron = 1% of a day = 14 min 24 s. Counted on this computer for your own runs (not replays or other couch players).", 16, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1120, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := UI.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# counters, three sections per row
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 40)
	flow.add_theme_constant_override("v_separation", 18)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(flow)
	for sec in Stats.sections():
		var box := UI.vbox(4)
		box.custom_minimum_size = Vector2(340, 0)
		box.add_child(UI.label(str(sec[0]), 22, UI.PINK))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		for row in sec[1]:
			var l := UI.label(str(row[0]), 17, Color(0.8, 0.86, 0.95))
			l.custom_minimum_size = Vector2(190, 0)
			grid.add_child(l)
			grid.add_child(UI.label(str(row[1]), 17, Color(1, 1, 1)))
		box.add_child(grid)
		flow.add_child(box)

	# most played courses
	body.add_child(UI.label("MOST PLAYED COURSES", 22, UI.PINK))
	var lv: Dictionary = Stats.data.get("lv", {})
	var ids := lv.keys()
	ids.sort_custom(func(a, b): return float(lv[a].get("play", 0.0)) > float(lv[b].get("play", 0.0)))
	var table := GridContainer.new()
	table.columns = 6
	table.add_theme_constant_override("h_separation", 28)
	body.add_child(table)
	for h in ["COURSE", "TRIES", "CLEARS", "CHRONS", "DEATHS", "BEST"]:
		table.add_child(UI.label(h, 15, UI.DIM))
	if ids.is_empty():
		body.add_child(UI.label("Play a course and it shows up here.", 18, UI.DIM))
	for id in ids.slice(0, 15):
		var e: Dictionary = lv[id]
		var nm := UI.label(str(e.get("name", id)), 18)
		nm.custom_minimum_size = Vector2(340, 0)
		nm.clip_text = true
		table.add_child(nm)
		table.add_child(UI.label(Stats._num(float(e.get("att", 0))), 18))
		table.add_child(UI.label(Stats._num(float(e.get("comp", 0))), 18))
		table.add_child(UI.label(Stats.chron_text(float(e.get("play", 0.0))), 18, UI.GOLD))
		table.add_child(UI.label(Stats._num(float(e.get("deaths", 0))), 18))
		var rec = Game.get_record(str(id))
		table.add_child(UI.label(Game.format_time(float(rec.time)) if rec else "-", 18, UI.NEON))
	v.add_child(UI.button("BACK", func(): back_fn.call(), 20))
