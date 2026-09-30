extends CanvasLayer
## In-game HUD: timer, medals, throw selector, meters, popups, off-screen
## indicators, results, pause and multiplayer scoreboard.

const UI = preload("res://src/ui/ui.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const Player = preload("res://src/player/player.gd")
const Disc = preload("res://src/disc/disc.gd")

var runner: Node = null
var level: Node:
	get: return runner.level if runner else null
var root: Control
var draw_layer: Control
var timer_label: Label
var sub_label: Label
var medal_label: Label
var type_label: Label
var desc_label: Label
var popups: Array = []
var snap_text := ""
var snap_color := Color.WHITE
var snap_t := 0.0
var results: Control = null
var pause_menu: Control = null
var scoreboard: Label
var countdown_until := 0.0
var level_name: Label
var help_label: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)

	draw_layer = Control.new()
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_layer.draw.connect(_draw_hud)
	root.add_child(draw_layer)

	timer_label = UI.label("00:00.000", 56, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.add_theme_font_override("font", UI.mono_font())
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-200, 14)
	timer_label.size = Vector2(400, 70)
	root.add_child(timer_label)

	sub_label = UI.label("", 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_label.position = Vector2(-300, 80)
	sub_label.size = Vector2(600, 30)
	root.add_child(sub_label)

	medal_label = UI.label("", 20, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	medal_label.add_theme_font_override("font", UI.mono_font())
	medal_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	medal_label.position = Vector2(-380, 18)
	medal_label.size = Vector2(360, 150)
	root.add_child(medal_label)

	level_name = UI.label("", 20, UI.DIM)
	level_name.position = Vector2(20, 18)
	root.add_child(level_name)

	scoreboard = UI.label("", 20, Color(1, 1, 1))
	scoreboard.add_theme_font_override("font", UI.mono_font())
	scoreboard.position = Vector2(20, 56)
	root.add_child(scoreboard)

	type_label = UI.label("", 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	type_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	type_label.position = Vector2(-300, -150)
	type_label.size = Vector2(600, 34)
	root.add_child(type_label)
	desc_label = UI.label("", 17, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	desc_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	desc_label.position = Vector2(-400, -118)
	desc_label.size = Vector2(800, 26)
	root.add_child(desc_label)

	help_label = UI.label("R restart   T recall (+3s)   Esc pause   P pin course", 15, Color(0.7, 0.75, 0.85, 0.6))
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.position = Vector2(20, -34)
	root.add_child(help_label)

	# vignette
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 0.8))); COLOR = vec4(0.0, 0.0, 0.0, v * 0.55); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	root.add_child(vig)
	root.move_child(vig, 0)


func on_restart() -> void:
	if results:
		results.queue_free()
		results = null
	popups.clear()
	snap_t = 0.0
	if level:
		var d: Dictionary = level.level_data
		level_name.text = "%s  ·  %s  ·  D%d" % [d.get("name", "Course"), level.th.get("name", ""), int(round(float(d.get("difficulty", 0.5)) * 10))]
	if level and level.mode == "multi":
		help_label.text = "R reset to lie   T recall (+3s)   Tab scores"


func popup(text: String, color: Color, dur := 1.2) -> void:
	popups.append({"text": text, "color": color, "t": 0.0, "dur": dur})
	if popups.size() > 5:
		popups.pop_front()


func snap_popup(text: String, color: Color) -> void:
	snap_text = text
	snap_color = color
	snap_t = 0.9


func _process(dt: float) -> void:
	if runner == null or runner.player == null:
		return
	var p = runner.player
	timer_label.text = Game.format_time(runner.total_time())
	var col := Color(1, 1, 1)
	if runner.done:
		col = UI.medal_color(level.medal_for(runner.finish_time))
	timer_label.add_theme_color_override("font_color", col)
	sub_label.text = "THROWS %d   ·   DEATHS %d%s" % [p.throws, runner.deaths, ("   ·   PENALTY +%.0fs" % runner.penalty) if runner.penalty > 0 else ""]
	_update_medals()
	var ty: Dictionary = ThrowTypes.get_type(p.throw_type)
	type_label.text = ty.name
	desc_label.text = ty.desc
	for pp in popups:
		pp.t += dt
	popups = popups.filter(func(x): return x.t < x.dur)
	snap_t = maxf(0.0, snap_t - dt)
	if level.mode == "multi":
		scoreboard.text = Net.scoreboard_text()
	elif level.mode == "couch":
		scoreboard.text = Game.couch_scoreboard()
	else:
		scoreboard.text = ""
	if countdown_until > 0.0:
		countdown_until = level.countdown
	if not get_tree().paused and not runner.done and Input.is_action_just_pressed("pin") and level.mode == "solo":
		level.pin_current()
	if runner.done and results and level.mode == "solo":
		if Input.is_action_just_pressed("next_level"):
			_next()
		elif Input.is_action_just_pressed("pin"):
			level.pin_current()
		elif Input.is_action_just_pressed("pause"):
			Game.goto_menu()
	draw_layer.queue_redraw()


func _input(event: InputEvent) -> void:
	if runner == null or runner.done:
		return
	var hit := false
	if event.is_action_pressed("pause") and runner.inp.uses_kbm():
		hit = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		hit = runner.inp.device == -2 or runner.inp.device == event.device
	if hit:
		get_viewport().set_input_as_handled()
		toggle_pause()


func _update_medals() -> void:
	var m: Dictionary = level.medals
	var lines := []
	var rec = Game.get_record(level.level_id)
	if m.has("par"):
		lines.append("PAR     %s" % Game.format_time(float(m.par)))
	for key in ["ace", "gold", "silver", "bronze"]:
		if m.has(key):
			lines.append("%-7s %s" % [key.to_upper(), Game.format_time(float(m[key]))])
	if rec:
		lines.append("BEST    %s" % Game.format_time(float(rec.time)))
	medal_label.text = "\n".join(lines)


# ------------------------------------------------------------------ drawing

func _world_to_screen(p: Vector2) -> Vector2:
	return runner.view.canvas_transform * p


func _draw_hud() -> void:
	if runner == null or runner.player == null:
		return
	var ci := draw_layer
	var vs := ci.size
	var p = runner.player
	var font := ThemeDB.fallback_font
	var th: Dictionary = level.th

	# speed lines
	var spd: float = p.velocity.length()
	if spd > 850.0:
		var k := clampf((spd - 850.0) / 900.0, 0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_msec() / 33)
		var cen := vs * 0.5
		for i in int(20 * k):
			var ang := rng.randf() * TAU
			var r0 := vs.length() * rng.randf_range(0.36, 0.45)
			var a := cen + Vector2(cos(ang), sin(ang)) * r0
			var b := cen + Vector2(cos(ang), sin(ang)) * (r0 + rng.randf_range(60, 180))
			ci.draw_line(a, b, Color(1, 1, 1, 0.12 * k), 2.0)

	# throw type strip
	var n := ThrowTypes.count()
	var slot := 64.0
	var start := Vector2(vs.x * 0.5 - n * slot * 0.5, vs.y - 96)
	for i in n:
		var ty: Dictionary = ThrowTypes.get_type(i)
		var r := Rect2(start + Vector2(i * slot + 4, 0), Vector2(slot - 8, 40))
		var sel: bool = i == p.throw_type
		var c: Color = _ldr(runner.disc.color) if sel else Color(0.5, 0.55, 0.65)
		ci.draw_rect(r, Color(0, 0, 0, 0.55))
		ci.draw_rect(r, c, false, 3.0 if sel else 1.5)
		ci.draw_string(font, r.position + Vector2(0, 27), ty.icon, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color(c, 1.0))
		ci.draw_string(font, r.position + Vector2(3, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.8))

	# nose gauge (left of strip)
	var gc := Vector2(start.x - 70, vs.y - 76)
	ci.draw_arc(gc, 34, PI + 0.3, TAU - 0.3, 24, Color(0.5, 0.55, 0.65), 2.0)
	var na: float = -PI * 0.5 - p.nose * 3.0
	ci.draw_line(gc, gc + Vector2(cos(-p.nose) * 34.0, sin(-p.nose) * 34.0), Color(2, 2, 2), 3.0)
	ci.draw_line(gc - Vector2(34, 0), gc + Vector2(34, 0), Color(0.5, 0.5, 0.6, 0.5), 1.0)
	ci.draw_string(font, gc + Vector2(-40, 26), "NOSE %+d°" % int(round(rad_to_deg(p.nose))), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(0.8, 0.85, 0.95))

	# ability pips (right of strip)
	var ax := start.x + n * slot + 24
	var ay := vs.y - 92
	_pip(ci, Vector2(ax, ay), "DASH", p.has_air_dash or p.on_floor, UI.NEON)
	_pip(ci, Vector2(ax, ay + 24), "PIVOT", p.has_disc and (p.on_floor or p.air_pivot_ready), UI.PINK)
	_pip(ci, Vector2(ax, ay + 48), "DISC", p.has_disc, runner.disc.color)

	# charge / snap meter
	if p.charging:
		var mw := 260.0
		var mp := Vector2(vs.x * 0.5 - mw * 0.5, vs.y - 196)
		ci.draw_rect(Rect2(mp, Vector2(mw, 10)), Color(0, 0, 0, 0.6))
		var pw: float = (p.charge_power() - 0.3) / 0.7
		var oc: float = p.overcharge()
		ci.draw_rect(Rect2(mp, Vector2(mw * pw, 10)), _ldr(runner.disc.color) if oc <= 0 else Color(1, 0.3, 0.25))
		if p.move_factor > 0.05:
			ci.draw_string(font, mp + Vector2(0, -6), "UNSTABLE %d%%" % int(p.move_factor * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.25))
		elif p.state == Player.PIVOT:
			ci.draw_string(font, mp + Vector2(0, -6), "PIVOT · CLEAN RELEASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _ldr(UI.PINK))
	if p.state == Player.PIVOT:
		var stall: float = p.pivot_t / (Player.AIR_PIVOT_MAX if p.pivot_air else Player.PIVOT_MAX)
		ci.draw_string(font, Vector2(vs.x * 0.5 - 100, vs.y * 0.5 + 90), "STALL " + "|".repeat(int(stall * 10)), HORIZONTAL_ALIGNMENT_CENTER, 200, 18, _ldr(UI.PINK))

	if snap_t > 0.0:
		var a := clampf(snap_t / 0.3, 0.0, 1.0)
		ci.draw_string(font, Vector2(vs.x * 0.5 - 200, vs.y - 180 - (0.9 - snap_t) * 30.0), snap_text, HORIZONTAL_ALIGNMENT_CENTER, 400, 30, Color(_ldr(snap_color), a))

	# popups
	var py := vs.y * 0.32
	for pp in popups:
		var a2: float = 1.0 - clampf((pp.t - pp.dur * 0.6) / (pp.dur * 0.4), 0.0, 1.0)
		var s := 1.0 + maxf(0.0, 0.2 - pp.t) * 2.0
		ci.draw_string(font, Vector2(vs.x * 0.5 - 400, py - pp.t * 20.0), pp.text, HORIZONTAL_ALIGNMENT_CENTER, 800, int(34 * s), Color(_ldr(pp.color), a2))
		py += 44

	# off-screen indicators
	_offscreen(ci, level.basket_pos + Vector2(0, -60), _ldr(th.get("basket", UI.GOLD)), "BASKET", vs)
	if not p.has_disc and runner.disc.state != Disc.SCORED:
		_offscreen(ci, runner.disc.global_position, _ldr(runner.disc.color), "DISC", vs)

	# countdown
	if level.countdown > 0.0:
		var cnum := int(ceil(level.countdown))
		ci.draw_string(font, Vector2(vs.x * 0.5 - 200, vs.y * 0.45), str(cnum), HORIZONTAL_ALIGNMENT_CENTER, 400, 160, Color(2, 2, 2))
	elif level.mode != "solo" and runner.running and runner.time < 0.8:
		ci.draw_string(font, Vector2(vs.x * 0.5 - 200, vs.y * 0.45), "GO!", HORIZONTAL_ALIGNMENT_CENTER, 400, 140, UI.NEON)
	if level.mode == "couch" and Game.couch_waiting_text() != "":
		ci.draw_string(font, Vector2(vs.x * 0.5 - 500, vs.y * 0.62), Game.couch_waiting_text(), HORIZONTAL_ALIGNMENT_CENTER, 1000, 30, UI.GOLD)
	if level.mode == "multi" and Net.waiting_text() != "":
		ci.draw_string(font, Vector2(vs.x * 0.5 - 500, vs.y * 0.62), Net.waiting_text(), HORIZONTAL_ALIGNMENT_CENTER, 1000, 30, UI.GOLD)


func _pip(ci: Control, pos: Vector2, text: String, on: bool, c: Color) -> void:
	var font := ThemeDB.fallback_font
	c = _ldr(c)
	if on:
		ci.draw_circle(pos + Vector2(6, -5), 6, c)
	else:
		ci.draw_arc(pos + Vector2(6, -5), 6, 0, TAU, 12, Color(0.4, 0.4, 0.5), 1.5)
	ci.draw_string(font, pos + Vector2(18, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.95) if on else Color(0.45, 0.45, 0.5))


static func _ldr(c: Color) -> Color:
	var m := maxf(1.0, maxf(c.r, maxf(c.g, c.b)))
	return Color(c.r / m, c.g / m, c.b / m, c.a)


func _offscreen(ci: Control, world_pos: Vector2, c: Color, text: String, vs: Vector2) -> void:
	var sp := _world_to_screen(world_pos)
	var margin := 50.0
	var inside := Rect2(Vector2(margin, margin), vs - Vector2(margin, margin) * 2.0)
	var dist: float = world_pos.distance_to(runner.player.center())
	if inside.has_point(sp):
		return
	var cen := vs * 0.5
	var d := sp - cen
	var scale_x := (vs.x * 0.5 - margin) / maxf(absf(d.x), 0.001)
	var scale_y := (vs.y * 0.5 - margin) / maxf(absf(d.y), 0.001)
	var edge := cen + d * minf(scale_x, scale_y)
	var dir := d.normalized()
	var tri := PackedVector2Array([edge + dir * 14.0, edge + dir.rotated(2.4) * 12.0, edge + dir.rotated(-2.4) * 12.0])
	ci.draw_colored_polygon(tri, c)
	var font := ThemeDB.fallback_font
	ci.draw_string(font, edge - dir * 30.0 + Vector2(-50, 6), "%s %dm" % [text, int(dist / 32.0)], HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color(c, 0.9))


# ------------------------------------------------------------------ results / pause

func show_results(t: float, medal: String, is_pb: bool) -> void:
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(level) or not runner.done:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results = PanelContainer.new()
	results.set_anchors_preset(Control.PRESET_CENTER)
	results.position = Vector2(-340, -250)
	results.custom_minimum_size = Vector2(680, 0)
	var v := UI.vbox(10)
	results.add_child(v)
	v.add_child(UI.label("CHAINS!", 64, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var tl := UI.label(Game.format_time(t), 72, UI.medal_color(medal), HORIZONTAL_ALIGNMENT_CENTER)
	tl.add_theme_font_override("font", UI.mono_font())
	v.add_child(tl)
	var mtxt := (medal.to_upper() + " MEDAL") if medal != "" else "NO MEDAL"
	v.add_child(UI.label(mtxt + ("   ·   NEW BEST!" if is_pb else ""), 30, UI.medal_color(medal), HORIZONTAL_ALIGNMENT_CENTER))
	if level.par_time() > 0.0:
		var dp: float = t - level.par_time()
		v.add_child(UI.label("%s%.2fs vs PAR" % ["+" if dp >= 0 else "−", absf(dp)], 24, Color(1.6, 0.6, 0.4) if dp > 0 else Color(0.5, 1.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	var nxt := ""
	for m in ["bronze", "silver", "gold", "ace"]:
		if level.medals.has(m) and t > float(level.medals[m]):
			nxt = "Next: %s at %s (-%.2fs)" % [m.to_upper(), Game.format_time(float(level.medals[m])), t - float(level.medals[m])]
	if nxt != "":
		v.add_child(UI.label(nxt, 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Throws %d   ·   Deaths %d   ·   Penalty %.0fs" % [runner.player.throws, runner.deaths, runner.penalty], 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UI.button("RETRY [R]", func(): level.restart()))
	h.add_child(UI.button("NEXT [N]", _next))
	if not Game.is_pinned(level.level_id):
		h.add_child(UI.button("PIN [P]", func(): level.pin_current()))
	h.add_child(UI.button("MENU", func(): Game.goto_menu()))
	v.add_child(h)
	root.add_child(results)


func _next() -> void:
	Game.next_level()


func toggle_pause() -> void:
	if level.mode == "multi":
		# no pausing in a race; open a small leave menu instead
		if pause_menu:
			pause_menu.queue_free()
			pause_menu = null
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			return
	var paused := pause_menu == null
	if level.mode != "multi":
		get_tree().paused = paused
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_menu = PanelContainer.new()
		pause_menu.set_anchors_preset(Control.PRESET_CENTER)
		pause_menu.position = Vector2(-200, -200)
		pause_menu.custom_minimum_size = Vector2(400, 0)
		var v := UI.vbox(12)
		pause_menu.add_child(v)
		v.add_child(UI.label("RACE MENU" if level.mode == "multi" else "PAUSED", 40, UI.NEON, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UI.button("RESUME", toggle_pause))
		if level.mode == "solo":
			v.add_child(UI.button("RESTART", func(): toggle_pause(); level.restart()))
			if not Game.is_pinned(level.level_id):
				v.add_child(UI.button("PIN COURSE", func(): level.pin_current()))
			v.add_child(UI.label("Seed %s" % str(level.level_data.get("seed", "?")), 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
			v.add_child(UI.button("QUIT TO MENU", func(): Game.goto_menu()))
		elif level.mode == "couch":
			v.add_child(UI.button("END COUCH SET", func(): Game.end_couch()))
		else:
			v.add_child(UI.button("LEAVE RACE", func(): Net.leave(); Game.goto_menu("multi")))
		root.add_child(pause_menu)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		pause_menu.queue_free()
		pause_menu = null
