extends CanvasLayer
## In-game HUD. Almost everything is custom-drawn for a punchy, animated,
## speedrun-arcade feel:
##   top-centre   timer slab + medal progress bar (ticks for every medal)
##   top-left     course card            top-right  medal ladder (coins)
##   bottom       throw cards with flight-path pictograms, nose gauge,
##                ability badges that pop when they refresh
##   bottom-left  speedometer, FLOW streak meter, key hints
##   centre       snap stamps, callout pills, countdown, off-screen markers
## Everything is laid out on a 1920x1080 design canvas and scaled to fit
## (split-screen views shrink it).

const Perf = preload("res://src/core/perf.gd")

const UI = preload("res://src/ui/ui.gd")
const DiscCam = preload("res://src/ui/disc_cam.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const Player = preload("res://src/player/player.gd")
const Disc = preload("res://src/disc/disc.gd")
const Bindings = preload("res://src/core/bindings.gd")

const MEDALS := ["ace", "gold", "silver", "bronze"]
## Shown as ACE / EAGLE / BIRDIE / PAR (see UI.MEDAL_NAMES): gold, silver
## and bronze are for leaderboard places.
const MEDAL_LETTER := {"ace": "A", "gold": "E", "silver": "B", "bronze": "P"}
const MEDAL_LDR := {"ace": Color(0.95, 0.45, 1.0), "gold": Color(0.3, 0.9, 1.0), "silver": Color(0.45, 1.0, 0.5), "bronze": Color(0.55, 0.65, 1.0), "": Color(0.55, 0.58, 0.65)}
const FLOW_COLORS := [Color(0.9, 0.95, 1.0), Color(0.35, 0.95, 1.0), Color(1.0, 0.4, 0.85), Color(1.0, 0.82, 0.3), Color(0.6, 1.0, 0.5)]
const FLOW_WINDOW := 4.0

# normalized flight-path pictograms per throw type (x 0..1 left->right, y 0..1 top->bottom)
const PICTO := [
	[Vector2(0, 0.75), Vector2(0.25, 0.45), Vector2(0.55, 0.32), Vector2(0.8, 0.38), Vector2(1, 0.6)],
	[Vector2(0, 0.55), Vector2(0.45, 0.48), Vector2(0.72, 0.5), Vector2(0.88, 0.68), Vector2(1, 0.95)],
	[Vector2(0, 0.92), Vector2(0.2, 0.35), Vector2(0.42, 0.08), Vector2(0.62, 0.18), Vector2(0.8, 0.6), Vector2(0.9, 0.96)],
	[Vector2(0, 0.55), Vector2(0.18, 0.42), Vector2(0.38, 0.88), Vector2(1, 0.88)],
	[Vector2(0.05, 0.85), Vector2(0.22, 0.3), Vector2(0.4, 0.15), Vector2(0.58, 0.35), Vector2(0.7, 0.88)],
	[Vector2(0, 0.25), Vector2(0.3, 0.42), Vector2(0.55, 0.95), Vector2(0.7, 0.68), Vector2(0.84, 0.95), Vector2(1, 0.86)],
]

var runner: Node = null
var level: Node:
	get: return runner.level if runner else null
var root: Control
var draw_layer: Control
var results: Control = null
var results_cam: Control = null     # the disc cam beside the results card
var results_cam_played := false     # ... has played through (into the chains) once
var key_glow := {}        # replay keystroke overlay: action -> 0..1 afterglow
var pause_menu: Control = null
var countdown_until := 0.0
var ui_scale := 1.0

var _font: Font
var _bold: Font
var _mono: Font
var t := 0.0
var popups: Array = []
var snap_text := ""
var snap_color := Color.WHITE
var snap_t := 0.0
var snap_detail := ""
var snap_score := 0.0
var sel_x := -1.0
var badge_pop := [0.0, 0.0, 0.0]
var badge_prev := [true, true, true]
var flow := 0
var flow_t := 0.0
var flow_pop := 0.0
var flow_best := 0
var flow_label := ""
var medal_flash := {}
var medal_prev := ""
var pb_mark := -1.0   # the PB this run is chasing (taken at the start, so a new PB doesn't move it)
var last_count := -1
var count_pop := 0.0
var go_t := -1.0
var speed_smooth := 0.0
var time_shown := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.9
	fv.spacing_glyph = 1
	_bold = fv
	var mv := FontVariation.new()
	mv.base_font = UI.mono_font()
	mv.variation_embolden = 0.4
	_mono = mv
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)
	# soft vignette
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.42, 0.9, length(d * vec2(1.0, 0.85))); COLOR = vec4(0.0, 0.0, 0.02, v * 0.5); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	root.add_child(vig)
	draw_layer = Control.new()
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_layer.draw.connect(_draw_hud)
	root.add_child(draw_layer)


func on_restart() -> void:
	if results:
		results.queue_free()
		results = null
	popups.clear()
	snap_t = 0.0
	flow = 0
	flow_t = 0.0
	medal_flash.clear()
	medal_prev = ""
	go_t = -1.0
	pb_mark = -1.0


# ================================================================== events

func popup(text: String, color: Color, dur := 1.2) -> void:
	for pp in popups:
		if pp.text == text:
			# same callout again: re-punch it instead of stacking duplicates
			pp.t = 0.0
			pp.dur = dur + 0.3
			return
	popups.append({"text": text, "color": _ldr(color), "t": 0.0, "dur": dur + 0.3})
	if popups.size() > 4:
		popups.pop_front()


func snap_popup(text: String, color: Color, detail := "", score := 0.0) -> void:
	snap_text = text.replace(" SNAP", "")
	snap_color = _ldr(color)
	snap_detail = detail
	snap_score = score
	snap_t = 1.0


## Style event: perfect snaps, sky catches, pivot launches, skips, boosts...
## Chains inside FLOW_WINDOW seconds build the FLOW multiplier.
func flow_event(label: String) -> void:
	flow = flow + 1 if flow_t > 0.0 else 1
	flow_t = FLOW_WINDOW
	flow_pop = 1.0
	flow_label = label
	flow_best = maxi(flow_best, flow)
	if flow >= 2 and runner:
		Sfx.play("tick", 0.5, 1.0 + minf(flow, 10) * 0.08)


# ================================================================== loop

func _process(dt: float) -> void:
	if runner == null or runner.player == null:
		return
	_fit_scale()
	t += dt
	var p = runner.player
	for pp in popups:
		pp.t += dt
	popups = popups.filter(func(x): return x.t < x.dur)
	snap_t = maxf(0.0, snap_t - dt)
	split_flash = maxf(0.0, split_flash - dt)
	flow_pop = maxf(0.0, flow_pop - dt * 3.0)
	if flow_t > 0.0 and not get_tree().paused:
		flow_t -= dt
		if flow_t <= 0.0:
			flow = 0
	count_pop = maxf(0.0, count_pop - dt * 2.5)
	speed_smooth = lerpf(speed_smooth, p.velocity.length(), 1.0 - exp(-10.0 * dt))
	time_shown = runner.total_time()
	# badge refresh pops
	var avail := [p.has_air_jump or p.on_floor, p.has_disc and (p.on_floor or p.air_pivot_ready), p.has_disc]
	for i in 3:
		if avail[i] and not badge_prev[i]:
			badge_pop[i] = 1.0
		badge_prev[i] = avail[i]
		badge_pop[i] = maxf(0.0, badge_pop[i] - dt * 3.0)
	# medal lost flash
	var cur := _current_medal(time_shown)
	if medal_prev != "" and cur != medal_prev and not runner.done:
		medal_flash[medal_prev] = 1.0
		Sfx.play("ui_hover", 0.5, 0.6)
	medal_prev = cur
	for k in medal_flash.keys():
		medal_flash[k] = maxf(0.0, medal_flash[k] - dt * 1.5)
	# countdown punch
	if level.countdown > 0.0:
		var c := int(ceil(level.countdown))
		if c != last_count:
			last_count = c
			count_pop = 1.0
			Sfx.play("beep")
	elif last_count > 0:
		last_count = -1
		go_t = 0.0
	if go_t >= 0.0:
		go_t += dt
		if go_t > 1.0:
			go_t = -1.0
	if countdown_until > 0.0:
		countdown_until = level.countdown
	if not get_tree().paused and not runner.done and Input.is_action_just_pressed("pin") and level.mode == "solo":
		level.pin_current()
	if runner.done and results and level.mode == "replay" and not Game.render_mode:
		if Input.is_action_just_pressed("pause"):
			Game.goto_menu("replays")
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
	if Game.render_mode:
		return
	if event.is_action_pressed("pause") and (runner.inp.uses_kbm() or level.mode == "replay"):
		hit = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		hit = runner.inp.device == -2 or runner.inp.device == event.device or level.mode == "replay"
	if hit:
		get_viewport().set_input_as_handled()
		toggle_pause()


func _current_medal(tm: float) -> String:
	for m in MEDALS:
		if level.medals.has(m) and Game.centis(tm) <= Game.centis(float(level.medals[m])):
			return m
	return ""


# ================================================================== layout helpers

func _world_to_screen(p: Vector2) -> Vector2:
	return (runner.view.canvas_transform * p) / ui_scale


## Split-screen views are smaller than the 1920x1080 design size: shrink the
## whole HUD so it keeps its proportions inside each player's view.
func _fit_scale() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := 1.0
	if runner and runner.container:
		s = clampf(minf(vp.x / 1920.0, vp.y / 1080.0), 0.5, 1.0)
		if vp.y < 600.0:
			s = maxf(s, 0.55)
	if absf(s - ui_scale) > 0.001 or root.size != vp / s:
		ui_scale = s
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2.ZERO
		root.size = vp / s
		root.scale = Vector2(s, s)


static func _ldr(c: Color) -> Color:
	var m := maxf(1.0, maxf(c.r, maxf(c.g, c.b)))
	return Color(c.r / m, c.g / m, c.b / m, c.a)


func _text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null, outline := 5) -> void:
	var f := font if font else _font
	if outline > 0:
		ci.draw_string_outline(f, pos, s, align, width, size, outline, Color(0.0, 0.0, 0.03, 0.75 * col.a))
	ci.draw_string(f, pos, s, align, width, size, col)


func _text_w(s: String, size: int, font: Font = null) -> float:
	var f := font if font else _font
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Slanted panel (parallelogram) with a highlight edge — the HUD's base shape.
func _slab(ci: CanvasItem, r: Rect2, skew := 14.0, fill := Color(0.03, 0.02, 0.08, 0.72), edge := Color(1, 1, 1, 0.18), accent := Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array([r.position + Vector2(skew, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(skew, 0), Vector2(r.position.x, r.end.y)])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_line(pts[0], pts[1], edge, 2.0, true)
	if accent.a > 0.0:
		var a2 := PackedVector2Array([pts[3], pts[3] + Vector2(skew * 0.35, -r.size.y * 0.35) * 0.0 + Vector2(0, 0), pts[2], pts[2]])
		ci.draw_line(pts[3], pts[2], accent, 3.0, true)


func _medal_coin(ci: CanvasItem, c: Vector2, r: float, medal: String, lit: bool, flash := 0.0) -> void:
	var col: Color = MEDAL_LDR.get(medal, MEDAL_LDR[""])
	var a := 1.0 if lit else 0.35
	if flash > 0.0:
		c += Vector2(sin(t * 60.0) * 4.0 * flash, 0)
		ci.draw_circle(c, r + 8.0 * flash, Color(1, 0.3, 0.3, 0.4 * flash))
	ci.draw_circle(c, r, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.9 * a))
	ci.draw_arc(c, r, 0, TAU, 28, Color(col, a), 2.5, true)
	ci.draw_arc(c, r - 4.0, 0, TAU, 28, Color(col, 0.45 * a), 1.0, true)
	if lit:
		ci.draw_arc(c, r - 1.5, -2.4, -1.2, 8, Color(1, 1, 1, 0.55), 2.0, true)
	_text(ci, c + Vector2(-r, r * 0.42), MEDAL_LETTER.get(medal, "·"), int(r * 1.15), Color(col.lightened(0.3), a), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, _bold, 0)


# ================================================================== drawing

func _draw_hud() -> void:
	var _pt := Perf.begin()
	_draw_hud_timed()
	if Perf.on:
		Perf.end("hud.draw", _pt)


func _draw_hud_timed() -> void:
	if runner == null or runner.player == null:
		return
	var ci := draw_layer
	var vs := ci.size
	var p = runner.player
	if cinema:
		# photo mode: only the in-the-moment bits (speed lines, popups, snaps)
		_draw_speedlines(ci, vs, p)
		_draw_popups(ci, vs)
		_draw_snap(ci, vs)
		return
	if Perf.on:
		var _ht := Perf.begin()
		_draw_speedlines(ci, vs, p)
		Perf.end("hud.speedlines", _ht)
	else:
		_draw_speedlines(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_timer(ci, vs)
		Perf.end("hud.timer", _ht)
	else:
		_draw_timer(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_course_card(ci, vs)
		Perf.end("hud.course_card", _ht)
	else:
		_draw_course_card(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_medal_ladder(ci, vs)
		Perf.end("hud.medal_ladder", _ht)
	else:
		_draw_medal_ladder(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_splits(ci, vs)
		Perf.end("hud.splits", _ht)
	else:
		_draw_splits(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_throw_cards(ci, vs, p)
		Perf.end("hud.throw_cards", _ht)
	else:
		_draw_throw_cards(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_nose(ci, vs, p)
		Perf.end("hud.nose", _ht)
	else:
		_draw_nose(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_badges(ci, vs, p)
		Perf.end("hud.badges", _ht)
	else:
		_draw_badges(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_charge(ci, vs, p)
		Perf.end("hud.charge", _ht)
	else:
		_draw_charge(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_speedo(ci, vs)
		Perf.end("hud.speedo", _ht)
	else:
		_draw_speedo(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_flow(ci, vs)
		Perf.end("hud.flow", _ht)
	else:
		_draw_flow(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_hints(ci, vs)
		Perf.end("hud.hints", _ht)
	else:
		_draw_hints(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_offscreen(ci, vs, p)
		Perf.end("hud.offscreen", _ht)
	else:
		_draw_offscreen(ci, vs, p)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_popups(ci, vs)
		Perf.end("hud.popups", _ht)
	else:
		_draw_popups(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_snap(ci, vs)
		Perf.end("hud.snap", _ht)
	else:
		_draw_snap(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_scoreboard(ci, vs)
		Perf.end("hud.scoreboard", _ht)
	else:
		_draw_scoreboard(ci, vs)
	if Perf.on:
		var _ht := Perf.begin()
		_draw_countdown(ci, vs)
		Perf.end("hud.countdown", _ht)
	else:
		_draw_countdown(ci, vs)
	if level.mode == "replay":
		_draw_keys(ci, vs)


func _draw_speedlines(ci: Control, vs: Vector2, p) -> void:
	var spd: float = speed_smooth
	if spd < 900.0:
		return
	var k := clampf((spd - 900.0) / 900.0, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_msec() / 40)
	var cen := vs * 0.5
	var dirv: Vector2 = p.velocity.normalized()
	for i in int(16 * k):
		var ang := rng.randf() * TAU
		var v := Vector2(cos(ang), sin(ang))
		if v.dot(dirv) > 0.3:
			continue  # lines stream from where you're heading, past the edges
		var r0 := vs.length() * rng.randf_range(0.38, 0.47)
		ci.draw_line(cen + v * r0, cen + v * (r0 + rng.randf_range(50, 150)), Color(1, 1, 1, 0.09 * k), 2.0)


func _draw_timer(ci: Control, vs: Vector2) -> void:
	var w := 470.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 10, w, 112)
	var cur := _current_medal(time_shown)
	var mcol: Color = MEDAL_LDR.get(cur, MEDAL_LDR[""])
	if runner.done:
		mcol = MEDAL_LDR.get(level.medal_for(runner.finish_time), MEDAL_LDR[""])
	_slab(ci, r, 18.0, Color(0.02, 0.015, 0.06, 0.78), Color(mcol, 0.55))
	# digits: MM:SS large + .cc small, monospaced (truncated like every other time)
	var tm := time_shown
	var cs := Game.centis(tm)
	var big := "%02d:%02d" % [cs / 6000, (cs / 100) % 60]
	var small := ".%02d" % (cs % 100)
	var bw := _text_w(big, 64, _mono)
	var sw := _text_w(small, 36, _mono)
	var x0 := vs.x * 0.5 - (bw + sw) * 0.5
	var tc: Color = Color(1, 1, 1) if not runner.done else mcol.lightened(0.2)
	if not runner.running and not runner.done:
		tc = Color(1, 1, 1, 0.55 + 0.35 * sin(t * 4.0))
	_text(ci, Vector2(x0, 70), big, 64, tc, HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 6)
	_text(ci, Vector2(x0 + bw, 70), small, 36, Color(tc, tc.a * 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 5)
	# medal progress bar
	var m: Dictionary = level.medals
	if m.has("bronze"):
		var bx := r.position.x + 34.0
		var bwid := r.size.x - 68.0
		var by := 88.0
		var top := float(m.bronze) * 1.08
		ci.draw_rect(Rect2(bx, by, bwid, 6), Color(1, 1, 1, 0.1))
		var frac := clampf(tm / top, 0.0, 1.0)
		ci.draw_rect(Rect2(bx, by, bwid * frac, 6), Color(mcol, 0.85))
		for key in MEDALS:
			if not m.has(key):
				continue
			var mt := float(m[key])
			var mx := bx + bwid * clampf(mt / top, 0.0, 1.0)
			var gone := Game.centis(tm) > Game.centis(mt)
			var col: Color = MEDAL_LDR[key]
			ci.draw_line(Vector2(mx, by - 4), Vector2(mx, by + 10), Color(col, 0.35 if gone else 1.0), 3.0)
			if key == cur and not runner.done:
				ci.draw_circle(Vector2(mx, by + 3), 5.0 + sin(t * 6.0) * 1.0, col)
		# your PB: a white tick + label under the bar
		if pb_mark < 0.0 and level.mode == "solo" and not runner.done:
			var rec = Game.get_record(level.level_id)
			pb_mark = float(rec.time) if rec else 0.0
		if pb_mark > 0.0 and level.mode == "solo":
			var pbx := bx + bwid * clampf(pb_mark / top, 0.0, 1.0)
			var pgone := Game.centis(tm) > Game.centis(pb_mark)
			ci.draw_line(Vector2(pbx, by - 7), Vector2(pbx, by + 13), Color(0.02, 0.0, 0.06, 0.8), 6.0)
			ci.draw_line(Vector2(pbx, by - 7), Vector2(pbx, by + 13), Color(0.55, 1.0, 0.75, 0.35 if pgone else 1.0), 3.0)
			_text(ci, Vector2(pbx - 30, by - 10), "PB", 11, Color(0.55, 1.0, 0.75, 0.4 if pgone else 0.95), HORIZONTAL_ALIGNMENT_CENTER, 60, _bold, 3)
		ci.draw_circle(Vector2(bx + bwid * frac, by + 3), 4.0, Color(1, 1, 1))
		# next medal countdown chip
		if cur != "" and not runner.done:
			var left := float(m[cur]) - tm
			var chip := "%s  %ss" % [UI.medal_name(cur), Game.short_time(left)]
			var cw := _text_w(chip, 15, _bold) + 26.0
			var cr := Rect2(vs.x * 0.5 - cw * 0.5, r.end.y + 4, cw, 24)
			_slab(ci, cr, 8.0, Color(mcol.r * 0.25, mcol.g * 0.25, mcol.b * 0.25, 0.85), Color(mcol, 0.7))
			_text(ci, cr.position + Vector2(0, 17), chip, 15, mcol.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER, cw, _bold, 0)
	# throws / deaths / penalty chips
	var stats := [["◎", str(runner.player.throws), Color(0.6, 0.9, 1.0)], ["✕", str(runner.deaths), Color(1.0, 0.55, 0.55)]]
	if runner.penalty > 0.0:
		stats.append(["+", "%.0fs" % runner.penalty, Color(1.0, 0.65, 0.3)])
	var sx := r.position.x + 4.0
	var sy := r.end.y + 4.0
	var sr := Rect2(sx, sy, 58.0 * stats.size() + 16.0, 24)
	_slab(ci, sr, 8.0, Color(0.02, 0.015, 0.06, 0.7), Color(1, 1, 1, 0.12))
	sx += 16.0
	for st in stats:
		_text(ci, Vector2(sx, sy + 17), st[0], 14, st[2], HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
		_text(ci, Vector2(sx + 16, sy + 17), st[1], 14, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
		sx += 58.0


func _draw_course_card(ci: Control, vs: Vector2) -> void:
	var d: Dictionary = level.level_data
	var name := str(d.get("name", "Course")).to_upper()
	var sub := "%s  ·  D%d" % [str(level.th.get("name", "")), int(round(float(d.get("difficulty", 0.5)) * 10))]
	if level.mode == "solo" and d.has("seed"):
		sub += "  ·  #%s" % str(d.seed)
	var w := maxf(_text_w(name, 22, _bold), _text_w(sub, 14)) + 54.0
	var r := Rect2(12, 12, w, 62)
	var acc: Color = _ldr(level.th.get("accent", UI.PINK))
	_slab(ci, r, 12.0, Color(0.02, 0.015, 0.06, 0.7), Color(acc, 0.6))
	ci.draw_rect(Rect2(r.position.x + 14, r.position.y + 12, 5, 38), acc)
	_text(ci, r.position + Vector2(28, 32), name, 22, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 4)
	_text(ci, r.position + Vector2(28, 52), sub, 14, Color(0.75, 0.8, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, null, 3)
	var rec = Game.get_record(level.level_id)
	if level.mode == "replay":
		var rl := "REPLAY  ·  %s's best  %s" % [str(level.replay.get("player", "Runner")), Game.format_time(float(level.replay.get("time", 0.0)))]
		var rr := Rect2(12, r.end.y + 6, _text_w(rl, 14, _bold) + 50, 26)
		_slab(ci, rr, 8.0, Color(0.02, 0.015, 0.06, 0.6), Color(1, 0.3, 0.4, 0.5))
		ci.draw_circle(rr.position + Vector2(20, 13), 6, Color(1, 0.25, 0.3, 0.6 + 0.4 * sin(t * 4.0)))
		_text(ci, rr.position + Vector2(34, 18), rl, 14, Color(1, 0.9, 0.92), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	elif rec and level.mode == "solo":
		var rm := str(rec.medal)
		var line := "BEST  " + Game.format_time(float(rec.time))
		var lr := Rect2(12, r.end.y + 6, _text_w(line, 14, _bold) + 50, 26)
		_slab(ci, lr, 8.0, Color(0.02, 0.015, 0.06, 0.6), Color(1, 1, 1, 0.1))
		ci.draw_circle(lr.position + Vector2(20, 13), 6, MEDAL_LDR.get(rm, MEDAL_LDR[""]))
		_text(ci, lr.position + Vector2(34, 18), line, 14, Color(0.9, 0.92, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	if level.mode == "solo":
		var vy: float = r.end.y + (38.0 if rec else 6.0)
		for rv in level.rival_list().slice(0, 6):
			var vline := "VS %s  %s" % [str(rv.name).to_upper(), Game.format_time(float(rv.time))]
			var vr := Rect2(12, vy, _text_w(vline, 14, _bold) + 50, 26)
			_slab(ci, vr, 8.0, Color(0.02, 0.015, 0.06, 0.6), Color(rv.color, 0.4))
			ci.draw_circle(vr.position + Vector2(20, 13), 6, rv.color)
			_text(ci, vr.position + Vector2(34, 18), vline, 14, Color(1.0, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
			vy += 30.0


func _draw_medal_ladder(ci: Control, vs: Vector2) -> void:
	var m: Dictionary = level.medals
	if not m.has("gold"):
		return
	var x := vs.x - 268.0
	var r := Rect2(x, 12, 256, 40 + 34 * 4)
	_slab(ci, r, 12.0, Color(0.02, 0.015, 0.06, 0.8), Color(1, 1, 1, 0.14))
	var tm: float = time_shown if not runner.done else runner.finish_time
	var y := 34.0
	for key in MEDALS:
		if not m.has(key):
			continue
		var mt := float(m[key])
		var lit: bool = Game.centis(tm) <= Game.centis(mt)
		var col: Color = MEDAL_LDR[key]
		_medal_coin(ci, Vector2(x + 34, y + 9), 13.0, key, lit, medal_flash.get(key, 0.0))
		_text(ci, Vector2(x + 56, y + 15), UI.medal_name(key), 14, Color(col, 1.0 if lit else 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
		_text(ci, Vector2(x + 132, y + 15), Game.format_time(mt), 15, Color(1, 1, 1, 0.9 if lit else 0.35), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 0)
		if not lit:
			ci.draw_line(Vector2(x + 130, y + 10), Vector2(x + 236, y + 10), Color(1, 0.4, 0.4, 0.5), 1.5)
		y += 34.0
	# your PB under the ladder, struck through once the clock is past it
	if pb_mark > 0.0 and level.mode == "solo":
		var plit: bool = Game.centis(tm) <= Game.centis(pb_mark)
		var pc := Color(0.55, 1.0, 0.75, 0.95 if plit else 0.4)
		var ptxt := "PB  " + Game.format_time(pb_mark)
		_text(ci, Vector2(x + 24, r.end.y - 9), ptxt, 12, pc, HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
		if not plit:
			ci.draw_line(Vector2(x + 22, r.end.y - 13), Vector2(x + 26 + _text_w(ptxt, 12, _bold), r.end.y - 13), Color(1, 0.4, 0.4, 0.5), 1.5)


# ---------------------------------------------------------------- splits

const SPLIT_GOLD := Color(1.0, 0.82, 0.25)
const SPLIT_AHEAD := Color(0.35, 1.0, 0.55)
const SPLIT_BEHIND := Color(1.0, 0.42, 0.4)
var cinema := false       # photo mode: hide the panels, keep speed lines + popups
var split_flash := 0.0    # seconds left showing the last split's delta under the timer
var split_last := -1


func on_split(i: int) -> void:
	split_last = i
	split_flash = 2.2


static func _short_time(t: float) -> String:
	return Game.short_time(t)


## shown difference a - b in seconds (hundredths, truncated values)
static func _shown_diff(a: float, b: float) -> float:
	return (Game.centis(a) - Game.centis(b)) / 100.0


func _split_color(i: int, d: float) -> Color:
	if i < runner.split_gold.size() and runner.split_gold[i]:
		return SPLIT_GOLD
	return SPLIT_AHEAD if d < 0.0 else SPLIT_BEHIND


## LiveSplit-style column under the medal ladder: one row per split with the
## PB time, turning into the delta (green ahead, red behind, gold = best
## segment ever) once crossed. Time trial modes only.
func _draw_splits(ci: Control, vs: Vector2) -> void:
	if not level.is_timetrial():
		return
	if level.mode == "replay" and runner._replay_is_pb():
		return   # the PB run against its own splits: nothing to compare
	var n: int = runner.split_count()
	if n == 0:
		return
	var pb: Array = runner.split_pb()
	var x := vs.x - 268.0
	var y0 := 12.0 + 40.0 + 34.0 * 4 + 10.0
	var row := 25.0
	var r := Rect2(x, y0, 256, 30 + row * n)
	_slab(ci, r, 12.0, Color(0.02, 0.015, 0.06, 0.72), Color(1, 1, 1, 0.1))
	_text(ci, Vector2(x + 18, y0 + 20), "SPLITS", 12, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	var done_n: int = runner.split_times.size()
	for i in n:
		var yy := y0 + 30.0 + row * i
		var cur: bool = i == done_n and not runner.done
		if cur:
			ci.draw_rect(Rect2(x + 8, yy - 2, 240, row - 2), Color(0.4, 0.8, 1.0, 0.12))
		var label := "FINISH" if i == n - 1 else "SPLIT %d" % (i + 1)
		_text(ci, Vector2(x + 18, yy + 16), label, 13, Color(1, 1, 1, 0.8 if cur else 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
		var has_pb := i < pb.size()
		if i < done_n:
			var tm: float = runner.split_times[i]
			if has_pb:
				var d: float = _shown_diff(tm, float(pb[i]))
				_text(ci, Vector2(x + 110, yy + 16), Game.delta_text(tm, float(pb[i])), 14, _split_color(i, d), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 0)
			_text(ci, Vector2(x + 172, yy + 16), _short_time(tm), 14, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 0)
		elif has_pb:
			_text(ci, Vector2(x + 172, yy + 16), _short_time(float(pb[i])), 14, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono, 0)
	# the split just crossed, big under the timer
	if split_flash > 0.0 and split_last >= 0 and split_last < done_n:
		var a := clampf(split_flash / 0.4, 0.0, 1.0)
		var tm2: float = runner.split_times[split_last]
		var txt := Game.format_time(tm2)
		var col := Color(1, 1, 1)
		if split_last < pb.size():
			var d2: float = _shown_diff(tm2, float(pb[split_last]))
			txt = Game.delta_text(tm2, float(pb[split_last]))
			col = _split_color(split_last, d2)
		elif split_last < runner.split_gold.size() and runner.split_gold[split_last]:
			col = SPLIT_GOLD
		var w := _text_w(txt, 26, _mono) + 40.0
		var rr := Rect2(vs.x * 0.5 - w * 0.5, 158, w, 38)
		_slab(ci, rr, 10.0, Color(0.02, 0.015, 0.06, 0.75 * a), Color(col, 0.5 * a))
		_text(ci, Vector2(rr.position.x, rr.position.y + 28), txt, 26, Color(col, a), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, _mono, 4)


func _draw_throw_cards(ci: Control, vs: Vector2, p) -> void:
	var n := ThrowTypes.count()
	var cw := 74.0
	var gap := 10.0
	var total := n * cw + (n - 1) * gap
	var x0 := vs.x * 0.5 - total * 0.5
	var y0 := vs.y - 104.0
	var dc: Color = _ldr(runner.disc.color)
	var target_x: float = x0 + p.throw_type * (cw + gap)
	sel_x = target_x if sel_x < 0.0 else lerpf(sel_x, target_x, 0.35)
	# sliding highlight under the selected card
	ci.draw_rect(Rect2(sel_x - 4, y0 - 14, cw + 8, 70), Color(dc, 0.16))
	for i in n:
		var sel: bool = i == p.throw_type
		var r := Rect2(x0 + i * (cw + gap), y0 - (10.0 if sel else 0.0), cw, 52)
		var fill := Color(0.03, 0.02, 0.08, 0.82) if sel else Color(0.03, 0.02, 0.08, 0.6)
		_slab(ci, r, 7.0, fill, Color(dc, 0.9) if sel else Color(1, 1, 1, 0.12))
		if sel:
			ci.draw_line(r.position + Vector2(0, r.size.y), r.end, dc, 3.0)
		var pc := dc if sel else Color(0.6, 0.65, 0.75, 0.7)
		var pts := PackedVector2Array()
		for v in PICTO[i]:
			pts.append(r.position + Vector2(10 + v.x * (cw - 20), 8 + v.y * 28))
		ci.draw_polyline(pts, Color(pc, 0.35), 5.0, true)
		ci.draw_polyline(pts, pc, 2.0, true)
		ci.draw_circle(pts[-1], 3.0, pc)
		var ty: Dictionary = ThrowTypes.get_type(i)
		_text(ci, r.position + Vector2(0, 48), ty.icon, 12, Color(1, 1, 1, 0.95 if sel else 0.45), HORIZONTAL_ALIGNMENT_CENTER, cw, _bold, 0)
		_text(ci, r.position + Vector2(6, 13), str(i + 1), 10, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	var ty2: Dictionary = ThrowTypes.get_type(p.throw_type)
	_text(ci, Vector2(vs.x * 0.5 - 300, y0 + 74), ty2.name, 20, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 600, _bold, 4)
	_text(ci, Vector2(vs.x * 0.5 - 400, y0 + 94), ty2.desc, 14, Color(0.75, 0.8, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 800, null, 3)


func _draw_nose(ci: Control, vs: Vector2, p) -> void:
	var n := ThrowTypes.count()
	var x := vs.x * 0.5 - (n * 84.0) * 0.5 - 92.0
	var c := Vector2(x, vs.y - 74.0)
	_slab(ci, Rect2(c.x - 58, c.y - 44, 116, 88), 10.0, Color(0.02, 0.015, 0.06, 0.6), Color(1, 1, 1, 0.1))
	# tick arc ±15°
	for k in range(-5, 6):
		var a := deg_to_rad(k * 3.0)
		var v := Vector2(cos(-a), sin(-a))
		var l := 6.0 if k % 5 == 0 else 3.0
		ci.draw_line(c + v * 34.0, c + v * (34.0 + l), Color(1, 1, 1, 0.4), 1.5)
	# disc in side view tilted by nose angle
	var dc: Color = _ldr(runner.disc.color)
	var ang: float = -p.nose
	var pts := PackedVector2Array()
	for i in 16:
		var a2 := TAU * i / 16.0
		pts.append(c + Vector2(cos(a2) * 22.0, sin(a2) * 6.0).rotated(ang))
	ci.draw_colored_polygon(pts, Color(dc.r * 0.4, dc.g * 0.4, dc.b * 0.4))
	pts.append(pts[0])
	ci.draw_polyline(pts, dc, 2.0, true)
	ci.draw_line(c + Vector2(22, 0).rotated(ang), c + Vector2(36, 0).rotated(ang), Color(1, 1, 1), 2.5)
	var deg := int(round(rad_to_deg(p.nose)))
	var label := "FLOAT" if deg > 3 else ("PUNCH" if deg < -3 else "FLAT")
	_text(ci, Vector2(c.x - 58, c.y + 36), "NOSE %+d°  %s" % [deg, label], 11, Color(0.85, 0.9, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 116, _bold, 0)


func _draw_badges(ci: Control, vs: Vector2, p) -> void:
	var n := ThrowTypes.count()
	var x := vs.x * 0.5 + (n * 84.0) * 0.5 + 40.0
	var y := vs.y - 74.0
	var avail := [p.has_air_jump or p.on_floor, p.has_disc and (p.on_floor or p.air_pivot_ready), p.has_disc]
	var cols := [Color(0.35, 0.95, 1.0), Color(1.0, 0.4, 0.85), _ldr(runner.disc.color)]
	var names := ["2× JUMP", "PIVOT", "DISC"]
	for i in 3:
		var c := Vector2(x + i * 54.0, y)
		var on: bool = avail[i]
		var pop: float = badge_pop[i]
		var rad := 19.0 + pop * 7.0
		var col: Color = cols[i]
		if pop > 0.0:
			ci.draw_arc(c, rad + 10.0 * (1.0 - pop), 0, TAU, 24, Color(col, pop), 2.0, true)
		ci.draw_circle(c, rad, Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.85) if on else Color(0.05, 0.05, 0.08, 0.6))
		ci.draw_arc(c, rad, 0, TAU, 24, Color(col, 1.0 if on else 0.25), 2.0, true)
		var ic := Color(col.lightened(0.3), 1.0) if on else Color(0.5, 0.5, 0.6, 0.5)
		match i:
			0:  # double up-chevron (double jump)
				for k in 2:
					var o := Vector2(0, 4 - k * 8)
					ci.draw_polyline(PackedVector2Array([c + o + Vector2(-7, 4), c + o + Vector2(0, -3), c + o + Vector2(7, 4)]), ic, 2.5, true)
			1:  # planted foot: circle + ground line
				ci.draw_arc(c + Vector2(0, -3), 6.0, 0, TAU, 14, ic, 2.5, true)
				ci.draw_line(c + Vector2(-9, 8), c + Vector2(9, 8), ic, 2.5)
			2:  # disc
				var dp := PackedVector2Array()
				for k in 12:
					var a := TAU * k / 12.0
					dp.append(c + Vector2(cos(a) * 10.0, sin(a) * 4.0))
				dp.append(dp[0])
				ci.draw_polyline(dp, ic, 2.5, true)
		_text(ci, Vector2(c.x - 30, y + 36), names[i], 11, Color(1, 1, 1, 0.8 if on else 0.3), HORIZONTAL_ALIGNMENT_CENTER, 60, _bold, 0)


func _draw_charge(ci: Control, vs: Vector2, p) -> void:
	if p.state == Player.PIVOT:
		var lim: float = Player.AIR_PIVOT_MAX if p.pivot_air else Player.PIVOT_MAX
		var stall: float = clampf(p.pivot_t / lim, 0.0, 1.0)
		var pr := Rect2(vs.x * 0.5 - 110, vs.y * 0.5 + 84, 220, 30)
		_slab(ci, pr, 8.0, Color(0.15, 0.03, 0.12, 0.8), Color(1.0, 0.4, 0.85, 0.7))
		ci.draw_rect(Rect2(pr.position.x + 14, pr.end.y - 7, (pr.size.x - 28) * (1.0 - stall), 3), Color(1.0, 0.4, 0.85))
		_text(ci, pr.position + Vector2(0, 20), "PIVOT  ·  STALL %d" % int(ceil((1.0 - stall) * 10.0)), 14, Color(1, 0.85, 0.95), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, _bold, 0)
	if not p.charging:
		return
	var w := 300.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y - 186, w, 34)
	var dc: Color = _ldr(runner.disc.color)
	var oc: float = p.overcharge()
	_slab(ci, r, 10.0, Color(0.02, 0.015, 0.06, 0.82), Color(dc, 0.5))
	var pw: float = (p.charge_power() - 0.3) / 0.7
	var segs := 14
	var sw := (w - 40.0) / segs
	for i in segs:
		var on := float(i) / segs < pw
		var col := dc if oc <= 0.0 else Color(1.0, 0.3 + 0.2 * sin(t * 30.0), 0.25)
		if i == segs - 1 and pw >= 0.999 and oc <= 0.0:
			col = Color(1, 1, 1)
		ci.draw_rect(Rect2(r.position.x + 20 + i * sw, r.position.y + 9, sw - 3, 9), col if on else Color(1, 1, 1, 0.08))
	var mf: float = p.move_factor + oc
	var tag := "STABLE"
	var tc := Color(0.5, 1.0, 0.65)
	if p.state == Player.PIVOT:
		tag = "CLEAN · PIVOT"
		tc = Color(1.0, 0.55, 0.9)
	elif mf > 0.75:
		tag = "WILD"
		tc = Color(1.0, 0.35, 0.3)
	elif mf > 0.25:
		tag = "WOBBLY"
		tc = Color(1.0, 0.75, 0.3)
	_text(ci, r.position + Vector2(20, 31), "POWER", 11, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	_text(ci, r.position + Vector2(0, 31), tag, 12, tc, HORIZONTAL_ALIGNMENT_RIGHT, w - 20, _bold, 0)


func _draw_speedo(ci: Control, vs: Vector2) -> void:
	var c := Vector2(92, vs.y - 116)
	var spd := speed_smooth
	var frac := clampf(spd / 1600.0, 0.0, 1.0)
	var a0 := PI * 0.8
	var a1 := PI * 2.2
	ci.draw_circle(c, 52, Color(0.02, 0.015, 0.06, 0.6))
	ci.draw_arc(c, 44, a0, a1, 40, Color(1, 1, 1, 0.12), 6.0, true)
	var run_frac := 440.0 / 1600.0
	var col := Color(0.4, 0.9, 1.0) if spd < 470.0 else (Color(1.0, 0.45, 0.85) if spd < 1000.0 else Color(1.0, 0.85, 0.3))
	if frac > 0.002:
		ci.draw_arc(c, 44, a0, a0 + (a1 - a0) * frac, 40, col, 6.0, true)
	var rm := a0 + (a1 - a0) * run_frac
	ci.draw_line(c + Vector2(cos(rm), sin(rm)) * 37, c + Vector2(cos(rm), sin(rm)) * 51, Color(1, 1, 1, 0.5), 2.0)
	_text(ci, c + Vector2(-50, 8), "%d" % int(spd / 32.0), 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 100, _mono, 4)
	_text(ci, c + Vector2(-50, 26), "m/s", 11, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 100, _bold, 0)


func _draw_flow(ci: Control, vs: Vector2) -> void:
	if flow <= 0:
		return
	var col: Color = FLOW_COLORS[mini(flow - 1, FLOW_COLORS.size() - 1)]
	if flow >= 5:
		col = Color.from_hsv(fmod(t * 0.5, 1.0), 0.55, 1.0)
	var x := 170.0
	var y := vs.y - 150.0
	var s := 1.0 + flow_pop * 0.35
	var r := Rect2(x, y, 210, 64)
	_slab(ci, r, 14.0, Color(col.r * 0.15, col.g * 0.15, col.b * 0.15, 0.75), Color(col, 0.8))
	_text(ci, Vector2(x + 22, y + 26), "FLOW", 14, Color(col, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	_text(ci, Vector2(x + 72, y + 42 + flow_pop * 4.0), "×%d" % flow, int(34 * s), col.lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 5)
	_text(ci, Vector2(x + 22, y + 46), flow_label, 11, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_LEFT, 60, _bold, 0)
	# decay bar
	ci.draw_rect(Rect2(x + 18, y + 54, (r.size.x - 36) * (flow_t / FLOW_WINDOW), 3), col)


func _draw_hints(ci: Control, vs: Vector2) -> void:
	var pad: bool = runner.inp.is_pad_aim()
	var hints: Array
	if Game.render_mode:
		return
	if level.mode == "replay":
		hints = [[Bindings.label("restart"), "watch again"], [Bindings.label("pause"), "replay menu"]]
	elif level.mode == "solo":
		hints = [[Bindings.label("restart", pad), "restart"], [Bindings.label("recall", pad), "recall +3s"], [Bindings.label("pause", pad), "pause"]]
		if not pad:
			hints.append([Bindings.label("pin"), "pin"])
	else:
		hints = [[Bindings.label("restart", pad), "reset"], [Bindings.label("recall", pad), "recall +3s"], [Bindings.label("pause", pad), "menu"]]
	hints = hints.filter(func(h): return h[0] != "")
	var x := 18.0
	var y := vs.y - 26.0
	for h in hints:
		var kw := _text_w(h[0], 11, _bold) + 14.0
		var kr := Rect2(x, y - 15, kw, 20)
		ci.draw_rect(kr, Color(1, 1, 1, 0.14))
		ci.draw_rect(Rect2(kr.position.x, kr.end.y - 3, kr.size.x, 3), Color(1, 1, 1, 0.1))
		_text(ci, kr.position + Vector2(0, 14), h[0], 11, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, kw, _bold, 0)
		_text(ci, Vector2(kr.end.x + 6, y), h[1], 12, Color(0.8, 0.85, 0.95, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, null, 2)
		x = kr.end.x + 12.0 + _text_w(h[1], 12) + 16.0


## Replay keystroke overlay: the runner's keys as caps that light up while
## held (with a short afterglow), labelled with the keys they actually used.
const KEY_ROWS := [
	[["move_up", 1.0, 1]],
	[["move_left", 1.0, 0], ["move_down", 1.0, 0], ["move_right", 1.0, 0]],
	[["jump", 3.0, 0]],
]
const ACT_ROWS := [
	[["recall", "RECALL"], ["pivot", "PIVOT"]],
	[["grapple", "SWING"], ["zip", "ZIP"]],
	[["throw", "THROW"], ["snap", "SNAP"]],
]


func _key_held(a: String) -> bool:
	var inp = runner.inp
	match a:
		"move_left": return inp.move.x < -0.3
		"move_right": return inp.move.x > 0.3
		"move_up": return inp.move.y < -0.3
		"move_down": return inp.move.y > 0.3 or inp.held("move_down")
	return inp.held(a)


func _draw_keys(ci: Control, vs: Vector2) -> void:
	var dt := get_process_delta_time()
	var pad: bool = runner.inp.is_pad_aim()
	var labels: Dictionary = level.replay.get("labels", {}).get("pad" if pad else "kbm", {})
	var acc: Color = _ldr(runner.player.color)
	var cap := Vector2(58, 46)
	var gap := 6.0
	var panel := Rect2(vs.x - 412, vs.y - 236, 396, 214)
	_slab(ci, panel, 10.0, Color(0.02, 0.015, 0.06, 0.72), Color(acc, 0.35))
	_text(ci, panel.position + Vector2(18, 24), "KEYS", 12, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 0)
	# movement cluster
	var ox := panel.position.x + 18.0
	var oy := panel.position.y + 34.0
	for ri in KEY_ROWS.size():
		var x := ox
		for k in KEY_ROWS[ri]:
			x += k[2] * (cap.x + gap)
			var w: float = cap.x * k[1] + gap * (k[1] - 1.0)
			_keycap(ci, Rect2(x, oy + ri * (cap.y + gap), w, cap.y), k[0], str(labels.get(k[0], "")), "", acc, dt)
			x += w + gap
	# action cluster
	var ax := ox + 3.0 * (cap.x + gap) + 14.0
	for ri in ACT_ROWS.size():
		for c2 in ACT_ROWS[ri].size():
			var k2: Array = ACT_ROWS[ri][c2]
			_keycap(ci, Rect2(ax + c2 * (cap.x + 12 + gap), oy + ri * (cap.y + gap), cap.x + 12, cap.y), k2[0], str(labels.get(k2[0], "")), k2[1], acc, dt)


func _keycap(ci: Control, r: Rect2, action: String, key: String, caption: String, acc: Color, dt: float) -> void:
	var held := _key_held(action)
	var g: float = key_glow.get(action, 0.0)
	g = 1.0 if held else maxf(0.0, g - dt * 6.0)
	key_glow[action] = g
	var base := Color(0.08, 0.08, 0.14, 0.9)
	var fill := base.lerp(Color(acc.r * 0.55, acc.g * 0.55, acc.b * 0.55, 0.95), g)
	var off := Vector2(0, 3.0 * g)   # pressed caps sink a little
	var rr := Rect2(r.position + off, r.size - Vector2(0, 3))
	ci.draw_rect(Rect2(r.position + Vector2(0, 3), r.size - Vector2(0, 3)), Color(0, 0, 0, 0.5))
	ci.draw_rect(rr, fill)
	ci.draw_rect(rr, Color(acc, 0.25 + 0.75 * g), false, 2.0)
	if g > 0.0:
		ci.draw_rect(rr.grow(3.0), Color(acc, 0.25 * g), false, 3.0)
	var label := key if key != "" else "—"
	var size := 15
	while size > 8 and _text_w(label, size, _bold) > rr.size.x - 8.0:
		size -= 1
	var tc := Color(1, 1, 1, 0.55 + 0.45 * g)
	var ky := rr.position.y + (rr.size.y * 0.5 + 5.0 if caption == "" else 22.0)
	_text(ci, Vector2(rr.position.x, ky), label, size, tc, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, _bold, 0)
	if caption != "":
		_text(ci, Vector2(rr.position.x, rr.position.y + 37.0), caption, 9, Color(1, 1, 1, 0.4 + 0.4 * g), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, null, 0)


func _draw_offscreen(ci: Control, vs: Vector2, p) -> void:
	_offscreen(ci, level.basket_pos + Vector2(0, -85), _ldr(level.th.get("basket", UI.GOLD)), "BASKET", vs, 0)
	if not p.has_disc and runner.disc.state != Disc.SCORED:
		_offscreen(ci, runner.disc.global_position, _ldr(runner.disc.color), "DISC", vs, 1)


func _offscreen(ci: Control, world_pos: Vector2, c: Color, text: String, vs: Vector2, icon: int) -> void:
	var sp := _world_to_screen(world_pos)
	var margin := 70.0
	var inside := Rect2(Vector2(margin, margin + 60), vs - Vector2(margin * 2.0, margin * 2.0 + 180))
	if inside.has_point(sp):
		return
	var dist: float = world_pos.distance_to(runner.player.center())
	var cen := vs * 0.5
	var d := sp - cen
	var sx := (inside.size.x * 0.5) / maxf(absf(d.x), 0.001)
	var sy := (inside.size.y * 0.5) / maxf(absf(d.y), 0.001)
	var edge := cen + d * minf(sx, sy)
	var dir := d.normalized()
	edge += dir * sin(t * 5.0) * 3.0
	ci.draw_circle(edge, 24, Color(0.02, 0.015, 0.06, 0.75))
	ci.draw_arc(edge, 24, 0, TAU, 28, Color(c, 0.8), 2.0, true)
	var tip := edge + dir * 34.0
	ci.draw_colored_polygon(PackedVector2Array([tip, edge + dir * 22.0 + dir.orthogonal() * 8.0, edge + dir * 22.0 - dir.orthogonal() * 8.0]), c)
	if icon == 0:
		# tiny basket
		ci.draw_line(edge + Vector2(0, -12), edge + Vector2(0, 10), c, 2.0)
		ci.draw_line(edge + Vector2(-9, -9), edge + Vector2(9, -9), c, 3.0)
		ci.draw_polyline(PackedVector2Array([edge + Vector2(-9, 1), edge + Vector2(-6, 6), edge + Vector2(6, 6), edge + Vector2(9, 1)]), c, 2.0)
	else:
		# same tilt / squash the disc has in the world right now
		var pz: Vector2 = runner.disc.pose()
		var ry := maxf(absf(pz.y) * 11.0, 3.0)
		var dp := PackedVector2Array()
		for k in 16:
			var a := TAU * k / 16.0
			dp.append(edge + Vector2(cos(a) * 11.0, sin(a) * ry).rotated(pz.x))
		ci.draw_colored_polygon(dp, c)
	_text(ci, edge + Vector2(-60, 44), "%s  %dm" % [text, int(dist / 32.0)], 13, Color(c, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 120, _bold, 4)


func _draw_popups(ci: Control, vs: Vector2) -> void:
	var y := vs.y * 0.3
	for pp in popups:
		var k: float = pp.t
		var enter := clampf(k / 0.18, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - enter, 3.0)
		var fade: float = 1.0 - clampf((k - (pp.dur - 0.35)) / 0.35, 0.0, 1.0)
		var s: float = lerpf(1.35, 1.0, e)
		var size := int(28 * s)
		var tw: float = _text_w(pp.text, size, _bold) + 48.0
		var x := vs.x * 0.5 - tw * 0.5 + (1.0 - e) * 80.0
		var col: Color = pp.color
		var r := Rect2(x, y - 30 - k * 10.0, tw, 42)
		_slab(ci, r, 12.0, Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.78 * fade), Color(col, 0.9 * fade))
		_text(ci, Vector2(r.position.x, r.position.y + 30), pp.text, size, Color(col.lightened(0.3), fade), HORIZONTAL_ALIGNMENT_CENTER, tw, _bold, 5)
		y += 52.0


func _draw_snap(ci: Control, vs: Vector2) -> void:
	if snap_t <= 0.0:
		return
	var k := 1.0 - snap_t
	var punch := 1.0 + maxf(0.0, 0.25 - k) * 2.4
	var fade := clampf(snap_t / 0.35, 0.0, 1.0)
	var c := Vector2(vs.x * 0.5, vs.y - 236)
	var big := snap_text == "PERFECT"
	if snap_text == "NO SNAP":
		# quiet note, not a shout: a missed snap is common and shouldn't nag
		var a2 := clampf(snap_t / 0.4, 0.0, 1.0)
		var note := "no snap" if snap_detail == "" else "late snap  ·  " + snap_detail
		_text(ci, Vector2(c.x - 150, c.y + 16), note, 15, Color(0.75, 0.78, 0.85, 0.7 * a2), HORIZONTAL_ALIGNMENT_CENTER, 300, _bold, 3)
		return
	var size := int((40 if big else 30) * punch)
	if big:
		# starburst: denser and longer the closer to frame-perfect
		var rays := 8 + int(snap_score * 10.0)
		for i in rays:
			var a := i * TAU / rays + t * 0.8
			var v := Vector2(cos(a), sin(a))
			var reach := 50.0 + 40.0 * snap_score + 30.0 * (1.0 - k)
			ci.draw_line(c + v * 46.0 * punch, c + v * reach * punch, Color(snap_color, 0.45 * fade), 3.0)
	var label := snap_text + (" SNAP" if snap_text != "NO SNAP" else "")
	var tw := _text_w(label, size, _bold)
	draw_layer.draw_set_transform(c, -0.07 if big else -0.04, Vector2.ONE)
	_slab(ci, Rect2(-tw * 0.5 - 22, -size * 0.85, tw + 44, size * 1.25), 12.0, Color(snap_color.r * 0.15, snap_color.g * 0.15, snap_color.b * 0.15, 0.8 * fade), Color(snap_color, fade))
	_text(ci, Vector2(-tw * 0.5, size * 0.2), label, size, Color(snap_color.lightened(0.35), fade), HORIZONTAL_ALIGNMENT_LEFT, -1, _bold, 6)
	if snap_detail != "":
		# exact timing + score, with a quality bar so near-misses are visible
		var dw := 180.0
		_text(ci, Vector2(-dw * 0.5, size * 0.2 + 24), snap_detail, 14, Color(1, 1, 1, 0.85 * fade), HORIZONTAL_ALIGNMENT_CENTER, dw, _bold, 3)
		ci.draw_rect(Rect2(-dw * 0.5, size * 0.2 + 32, dw, 4), Color(1, 1, 1, 0.15 * fade))
		ci.draw_rect(Rect2(-dw * 0.5, size * 0.2 + 32, dw * snap_score, 4), Color(snap_color.lightened(0.3), fade))
	draw_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_scoreboard(ci: Control, vs: Vector2) -> void:
	var txt := ""
	if level.mode == "multi":
		txt = Net.scoreboard_text()
	elif level.mode == "couch":
		txt = Game.couch_scoreboard()
	if txt == "":
		return
	var lines := txt.split("\n")
	var r := Rect2(12, 108, 300, 22 + 24 * lines.size())
	_slab(ci, r, 10.0, Color(0.02, 0.015, 0.06, 0.7), Color(1, 1, 1, 0.15))
	var y := r.position.y + 26
	for i in lines.size():
		_text(ci, Vector2(r.position.x + 18, y), lines[i], 15 if i > 0 else 13, Color(1, 0.85, 0.4) if i == 0 else Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, _mono if i > 0 else _bold, 0)
		y += 24
	_draw_place(ci, vs)
	var wt := ""
	if level.mode == "couch":
		wt = Game.couch_waiting_text()
	elif level.mode == "multi":
		wt = Net.waiting_text()
	if wt != "":
		var ww := _text_w(wt, 26, _bold) + 60
		var wr := Rect2(vs.x * 0.5 - ww * 0.5, vs.y * 0.6, ww, 50)
		_slab(ci, wr, 14.0, Color(0.15, 0.1, 0.02, 0.85), Color(1, 0.85, 0.3, 0.9))
		_text(ci, wr.position + Vector2(0, 34), wt, 26, Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, ww, _bold, 4)


## Versus: where you finished this round, [place, runners], or [0, n] if
## not finished (yet). Ranked by finish time.
func my_place() -> Vector2i:
	var results := {}
	var me = null
	var n := 0
	if level.mode == "couch":
		if Game.couch.is_empty():
			return Vector2i.ZERO
		results = Game.couch.results
		me = runner.index
		n = Game.couch.players.size()
	elif level.mode == "multi":
		results = level.net_results
		me = Net.my_id()
		n = Net.players.size()
	if me == null or not results.has(me):
		return Vector2i(0, n)
	var mine := float(results[me])
	var place := 1
	for k in results:
		if k != me and float(results[k]) < mine:
			place += 1
	return Vector2i(place, maxi(n, results.size()))


static func ordinal(n: int) -> String:
	var suf := "TH"
	if n % 100 < 11 or n % 100 > 13:
		suf = ["TH", "ST", "ND", "RD", "TH", "TH", "TH", "TH", "TH", "TH"][n % 10]
	return "%d%s" % [n, suf]


const PLACE_COLORS := [Color(1.0, 0.82, 0.25), Color(0.78, 0.84, 0.95), Color(0.9, 0.55, 0.3)]


## Big finishing place once you've sunk it in versus (1ST gold, 2ND silver...).
func _draw_place(ci: Control, vs: Vector2) -> void:
	if not runner.done:
		return
	var pl := my_place()
	if pl.x <= 0:
		return
	var col: Color = PLACE_COLORS[pl.x - 1] if pl.x <= 3 else Color(0.8, 0.82, 0.9)
	var big := ordinal(pl.x)
	var sub := "FIRST TO THE CHAINS" if pl.x == 1 else "TO THE CHAINS  ·  OF %d" % pl.y
	var w := maxf(_text_w(big, 72, _bold), _text_w(sub, 18, _bold)) + 80.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y * 0.2, w, 124)
	_slab(ci, r, 16.0, Color(0.02, 0.015, 0.06, 0.82), Color(col, 0.95))
	_text(ci, r.position + Vector2(0, 80), big, 72, col, HORIZONTAL_ALIGNMENT_CENTER, w, _bold, 6)
	_text(ci, r.position + Vector2(0, 110), sub, 18, Color(col, 0.85), HORIZONTAL_ALIGNMENT_CENTER, w, _bold, 3)


func _draw_countdown(ci: Control, vs: Vector2) -> void:
	var c := vs * Vector2(0.5, 0.42)
	if level.countdown > 0.0:
		var num := int(ceil(level.countdown))
		var s := 1.0 + count_pop * 0.6
		var frac: float = level.countdown - floor(level.countdown)
		ci.draw_circle(c, 110 * s, Color(0.02, 0.015, 0.06, 0.55))
		ci.draw_arc(c, 110 * s, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(1, 1, 1, 0.8), 6.0, true)
		_text(ci, c + Vector2(-150, 60 * s), str(num), int(170 * s), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 300, _bold, 8)
	elif go_t >= 0.0:
		var k := go_t
		var s2 := 1.0 + k * 0.8
		var a := 1.0 - k
		var col := Color(0.4, 1.0, 0.7, a)
		ci.draw_arc(c, 120 * s2, 0, TAU, 48, Color(col, a * 0.7), 8.0, true)
		_text(ci, c + Vector2(-200, 55 * s2), "GO!", int(150 * s2), col, HORIZONTAL_ALIGNMENT_CENTER, 400, _bold, 8)


# ================================================================== results / pause

class MedalBadge:
	extends Control
	var medal := ""
	var t := 0.0
	var colors: Dictionary = {}

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col: Color = colors.get(medal, Color(0.5, 0.5, 0.6))
		var pop := 1.0 + maxf(0.0, 0.35 - t) * 1.5
		var r := 54.0 * pop
		# ribbons
		draw_colored_polygon(PackedVector2Array([c + Vector2(-30, 20), c + Vector2(-10, 20), c + Vector2(-22, 92), c + Vector2(-34, 80), c + Vector2(-44, 90)]), col.darkened(0.35))
		draw_colored_polygon(PackedVector2Array([c + Vector2(10, 20), c + Vector2(30, 20), c + Vector2(44, 90), c + Vector2(34, 80), c + Vector2(22, 92)]), col.darkened(0.45))
		for i in 16:
			var a := i * TAU / 16.0 + t * 0.4
			draw_line(c + Vector2(cos(a), sin(a)) * (r + 8), c + Vector2(cos(a), sin(a)) * (r + 22), Color(col, 0.35), 3.0)
		draw_circle(c, r, col.darkened(0.55))
		draw_circle(c, r - 6, col.darkened(0.25))
		draw_arc(c, r, 0, TAU, 40, col.lightened(0.3), 4.0, true)
		draw_arc(c, r - 12, 0, TAU, 40, Color(1, 1, 1, 0.25), 2.0, true)
		draw_arc(c, r - 4, -2.5, -1.1, 12, Color(1, 1, 1, 0.6), 3.0, true)
		var letter: String = MEDAL_LETTER.get(medal, "–")
		var f := ThemeDB.fallback_font
		draw_string_outline(f, c + Vector2(-r, r * 0.38), letter, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.1), 6, Color(0, 0, 0, 0.5))
		draw_string(f, c + Vector2(-r, r * 0.38), letter, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.1), Color(1, 1, 1))


## ★ FAVORITE: keep this run in the replays menu's favorites (any run, PB
## or not). Shows ★ SAVED once it's in there.
func _fav_button(rep: Dictionary) -> Button:
	var b := UI.button("★ FAVORITE", func(): pass)
	var mark := func():
		b.text = "★ SAVED"
		b.disabled = true
	if Game.favorite_id_of(rep) != "":
		mark.call()
	b.pressed.connect(func():
		if Game.save_favorite(rep) != "":
			mark.call())
	return b


## SAVE COURSE: keep this course online in your courses (up to
## Online.SHARE_MAX; when full, pick one to replace). Everyone can play it
## and it gets a leaderboard; your run so far goes onto it.
func _save_course_button() -> Button:
	var b := UI.button("SAVE COURSE", func(): pass)
	var saved := func():
		b.text = "★ IN YOUR COURSES"
		b.disabled = true
	var lid: String = level.level_id
	for c in Online.my_courses():
		if str(c.cid) == lid:
			saved.call()
	var on_result := func(ok: bool, msg: String, cid: String):
		if not is_instance_valid(b):
			return
		if ok:
			saved.call()
			# keep playing it as the saved course: later runs count on its board
			level.level_data["id"] = cid
			level.level_id = cid
			popup("SAVED TO YOUR COURSES", Color(0.5, 2.0, 1.0), 2.0)
		else:
			b.text = "SAVE COURSE"
			popup(msg.to_upper(), Color(2.0, 0.6, 0.4), 2.5)
	b.pressed.connect(func():
		if not Online.share_result.is_connected(on_result):
			Online.share_result.connect(on_result)
		var mine := Online.my_courses()
		if mine.size() < Online.SHARE_MAX:
			b.text = "SAVING..."
			Online.share_course(level.level_data, -1)
		else:
			_replace_dialog(mine, b))
	Online.request_catalog()   # fresh list of mine for the check above / replacing
	return b


## Your courses are full: pick one to replace (or cancel).
func _replace_dialog(mine: Array, b: Button) -> void:
	var pop := PopupPanel.new()
	pop.theme = UI.theme()
	var v := UI.vbox(8)
	pop.add_child(v)
	v.add_child(UI.label("You have %d saved courses. Replace one:" % Online.SHARE_MAX, 20, UI.NEON))
	for i in mine.size():
		var slot := i
		v.add_child(UI.button("REPLACE  %s" % str(mine[i].name), func():
			b.text = "SAVING..."
			Online.share_course(level.level_data, slot)
			pop.queue_free(), 18))
	v.add_child(UI.button("CANCEL", func(): pop.queue_free(), 18))
	root.add_child(pop)
	pop.popup_centered()


## old_pb: the personal best this run beat (-1 for a first clear / no PB).
func show_results(tm: float, medal: String, is_pb: bool, old_pb := -1.0) -> void:
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(level) or not runner.done:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mcol: Color = MEDAL_LDR.get(medal, MEDAL_LDR[""])
	if results:
		results.queue_free()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.015, 0.06, 0.92)
	sb.border_color = mcol
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.set_corner_radius_all(6)
	sb.skew = Vector2(-0.06, 0)
	sb.shadow_color = Color(mcol, 0.35)
	sb.shadow_size = 24
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(720, 0)
	var v := UI.vbox(10)
	panel.add_child(v)
	var replaying: bool = level.mode == "replay"
	var head := "CHAINS!"
	if replaying:
		head = "REPLAY  ·  %s" % str(level.replay.get("player", "Runner"))
	v.add_child(UI.label(head, 30, Color(1, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER))
	var badge := MedalBadge.new()
	badge.medal = medal
	badge.colors = MEDAL_LDR
	badge.custom_minimum_size = Vector2(0, 200)
	v.add_child(badge)
	var mtxt := UI.medal_name(medal) if medal != "" else "OVER PAR — KEEP RUNNING"
	v.add_child(UI.label(mtxt, 26, mcol.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER))
	var tl := UI.label(Game.format_time(0.0), 68, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	tl.add_theme_font_override("font", _mono)
	v.add_child(tl)
	var tw := create_tween().bind_node(tl)
	tw.tween_method(func(x): tl.text = Game.format_time(x), 0.0, tm, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if is_pb:
		var pb := UI.label("★  NEW PERSONAL BEST  ★", 22, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(pb)
		# bound to the label: dies with the results card (a HUD-bound endless
		# tween outlives it and errors every frame -> the lag spike on later runs)
		var tw2 := create_tween().bind_node(pb).set_loops()
		tw2.tween_property(pb, "modulate:a", 0.45, 0.5)
		tw2.tween_property(pb, "modulate:a", 1.0, 0.5)
		if old_pb > 0.0:
			v.add_child(UI.label("−%ss  ·  old best %s" % [Game.gap_text(old_pb, tm), Game.format_time(old_pb)], 20,
				Color(0.5, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
		else:
			v.add_child(UI.label("first clear", 18, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var chips := UI.hbox(26)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UI.label("◎ %d throws" % runner.player.throws, 20, Color(0.6, 0.9, 1.0)))
	chips.add_child(UI.label("✕ %d deaths" % runner.deaths, 20, Color(1, 0.6, 0.6)))
	if runner.penalty > 0.0:
		chips.add_child(UI.label("+%.0fs penalty" % runner.penalty, 20, Color(1, 0.7, 0.3)))
	if flow_best >= 2:
		chips.add_child(UI.label("FLOW ×%d" % flow_best, 20, Color(1, 0.5, 0.9)))
	v.add_child(chips)
	# online leaderboard rank (built-in courses, filled in when the server answers)
	if level.mode == "solo" and Online.course_key(level.level_id) != "" and Online.is_online():
		var ol := UI.label("", 20, Color(0.5, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(ol)
		var ck := Online.course_key(level.level_id)
		var show_rank := func(course: String, rank: int, total: int, improved: bool):
			if course == ck and is_instance_valid(ol):
				if rank <= 0:
					ol.text = "Posted. Choose a name in the menu to show up on the leaderboard."
				else:
					# gold / silver / bronze are the top three places online
					var pod := UI.podium(rank)
					ol.text = ("%sONLINE  #%d OF %d" % [pod + "  ·  " if pod != "" else "", rank, total]) + ("" if improved else "  (your online best)")
					if pod != "":
						ol.add_theme_color_override("font_color", UI.podium_color(rank))
		var ls: Dictionary = Online.last_submit
		if str(ls.get("course", "")) == ck and Time.get_ticks_msec() - int(ls.get("ms", 0)) < 5000:
			show_rank.call(ck, int(ls.rank), int(ls.total), bool(ls.improved))
		else:
			Online.submitted.connect(show_rank, CONNECT_ONE_SHOT)
		if not is_pb:
			ol.text = "Leaderboards: Menu → LEADERBOARDS"
	var rivals: Array = level.rival_list()
	if rivals.size() == 1 and not replaying:
		var rt: float = level.rival.time
		var who := str(level.rival.name)
		var beat := Game.centis(tm) < Game.centis(rt)
		var vs_txt := ("YOU BEAT %s BY %ss" % [who.to_upper(), Game.gap_text(rt, tm)]) if beat else ("%s WAS %ss FASTER" % [who.to_upper(), Game.gap_text(tm, rt)])
		v.add_child(UI.label(vs_txt, 22, Color(0.5, 1, 0.7) if beat else Color(1, 0.6, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	elif rivals.size() > 1 and not replaying:
		var place := 1
		for rv in rivals:
			if float(rv.time) < tm:
				place += 1
		v.add_child(UI.label("%s OF %d AGAINST THE GHOSTS" % [ordinal(place), rivals.size() + 1], 22,
			Color(0.5, 1, 0.7) if place == 1 else Color(1, 0.8, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	for m in ["bronze", "silver", "gold", "ace"]:
		if level.medals.has(m) and Game.centis(tm) > Game.centis(float(level.medals[m])):
			v.add_child(UI.label("Next: %s at %s  (−%ss)" % [UI.medal_name(m), Game.format_time(float(level.medals[m])), Game.gap_text(tm, float(level.medals[m]))], 18, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
			break
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if replaying:
		if not Game.render_mode:
			h.add_child(UI.button("WATCH AGAIN  [R]", func(): level.restart_when_released()))
			h.add_child(_fav_button(level.replay))
			h.add_child(UI.button("EXPORT MP4", func(): Game.export_replay_mp4(Game.replay_key_for(level.replay))))
			h.add_child(UI.button("REPLAYS", func(): Game.goto_menu("replays")))
	else:
		h.add_child(UI.button("RETRY  [R]", func(): level.restart_when_released()))
		h.add_child(UI.button("NEXT  [N]", _next))
		if not Game.is_pinned(level.level_id):
			h.add_child(UI.button("PIN  [P]", func(): level.pin_current()))
		if Online.is_online() and not bool(level.level_data.get("_builtin", false)):
			h.add_child(_save_course_button())
		if not runner.last_replay.is_empty():
			# this run (PB or not), with your PB ghost alongside
			h.add_child(UI.button("REPLAY", func(): Game.play_replay_data(runner.last_replay)))
		elif Game.has_replay(level.level_id):
			h.add_child(UI.button("REPLAY", func(): Game.play_replay(level.level_id)))
		if not runner.last_replay.is_empty():
			h.add_child(_fav_button(runner.last_replay))
		h.add_child(UI.button("MENU", func(): Game.goto_menu()))
	v.add_child(h)
	if replaying and not Game.render_mode:
		var st := UI.label("", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(st)
		Game.export_status.connect(func(tx, _d): if is_instance_valid(st): st.text = tx)
	# A full-screen CenterContainer does the centring, whatever height the
	# panel ends up. The pop-in animates the holder: containers reset their
	# children's scale whenever they re-sort.
	results = CenterContainer.new()
	results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if runner.pov_clip.size() >= 60:
		# disc cam beside the card: the last seconds of the run from the disc
		var row := UI.hbox(24)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(panel)
		var cam_panel := PanelContainer.new()
		var sb2 := sb.duplicate() as StyleBoxFlat
		sb2.content_margin_left = 16
		sb2.content_margin_right = 16
		sb2.content_margin_top = 14
		sb2.content_margin_bottom = 14
		cam_panel.add_theme_stylebox_override("panel", sb2)
		cam_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cam := DiscCam.new()
		cam_panel.add_child(cam)
		cam.setup(level, runner.pov_frames(), runner.player.visual.color, runner.disc.color)
		results_cam = cam
		results_cam_played = false
		cam.played.connect(func(): results_cam_played = true)
		row.add_child(cam_panel)
		results.add_child(row)
	else:
		results.add_child(panel)
	root.add_child(results)
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.pivot_offset = root.size * 0.5
	results.scale = Vector2(0.9, 0.9)
	results.modulate.a = 0.0
	var tw3 := create_tween().bind_node(results).set_parallel(true)
	tw3.tween_property(results, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw3.tween_property(results, "modulate:a", 1.0, 0.2)


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
		pause_menu.custom_minimum_size = Vector2(420, 0)
		pause_menu.position = Vector2(root.size.x * 0.5 - 210, root.size.y * 0.5 - 220)
		var v := UI.vbox(12)
		pause_menu.add_child(v)
		v.add_child(UI.label("RACE MENU" if level.mode == "multi" else ("REPLAY" if level.mode == "replay" else "PAUSED"), 40, UI.NEON, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UI.button("RESUME", toggle_pause))
		if level.mode == "replay":
			v.add_child(UI.button("WATCH AGAIN", func(): toggle_pause(); level.restart_when_released()))
			v.add_child(UI.button("EXPORT MP4", func(): Game.export_replay_mp4(Game.replay_key_for(level.replay))))
			v.add_child(UI.button("REPLAYS", func(): Game.goto_menu("replays")))
		elif level.mode == "solo":
			v.add_child(UI.button("RESTART", func(): toggle_pause(); level.restart_when_released()))
			if not Game.is_pinned(level.level_id):
				v.add_child(UI.button("PIN COURSE", func(): level.pin_current()))
			v.add_child(UI.label("Seed %s" % str(level.level_data.get("seed", "?")), 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
			v.add_child(UI.button("QUIT TO MENU", func(): Game.goto_menu()))
		elif level.mode == "couch":
			v.add_child(UI.button("END COUCH SET", func(): Game.end_couch()))
		elif level.mode == "match":
			# watching a recording (a couch / online round, or leaderboard runs)
			v.add_child(UI.button("WATCH AGAIN", func(): Game.play_match_data(level.replay)))
			v.add_child(UI.button("BACK", func(): Game.goto_menu()))
		else:
			v.add_child(UI.button("LEAVE RACE", func(): Net.leave(); Game.goto_menu("multi")))
		root.add_child(pause_menu)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		pause_menu.queue_free()
		pause_menu = null
