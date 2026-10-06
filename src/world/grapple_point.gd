extends Node2D
## Grapple anchor. Kinds: static, fragile (breaks after use, respawns),
## boost (extra speed on release), moving (oscillates along a path).

const Perf = preload("res://src/core/perf.gd")
const View = preload("res://src/world/view.gd")

var kind := "static"
var active := true
var base_pos := Vector2.ZERO
var move := Vector2.ZERO
var period := 3.0
var phase := 0.0
var color := Color(1.5, 1.2, 0.3)
var t := 0.0
var targeted := false
var attached := false
var break_t := -1.0
var respawn_t := -1.0
var sky := false
var level: Node = null
const FRAGILE_HOLD := 1.1     # seconds a fragile point holds once grabbed


func setup(data: Dictionary, th: Dictionary) -> void:
	kind = data.get("k", "static")
	base_pos = Vector2(data.p[0], data.p[1])
	position = base_pos
	sky = data.get("sky", false)
	if data.has("move"):
		move = Vector2(data.move[0], data.move[1])
		period = float(data.get("period", 3.0))
		phase = float(data.get("phase", 0.0))
	color = th.get("grapple", color)
	if kind == "fragile":
		color = th.get("hazard", Color(2, 0.3, 0.2)).lerp(color, 0.35)
	elif kind == "boost":
		color = th.get("basket", Color(2, 1.8, 0.3))


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("grapple_point.tick", _pt)


func _physics_process_timed(dt: float) -> void:
	# (level is the runner here)
	if level == null or level.level == null or level.level.world_clock_on():
		t += dt
	if kind == "moving":
		position = base_pos + move * (0.5 - 0.5 * cos((t / period + phase) * TAU))
	if break_t >= 0.0:
		break_t -= dt
		if break_t < 0.0:
			_shatter()
	if respawn_t >= 0.0:
		respawn_t -= dt
		if respawn_t < 0.0:
			active = true
	if View.sees_point(global_position, 120.0) or break_t >= 0.0:
		queue_redraw()


func reset() -> void:
	active = true
	break_t = -1.0
	respawn_t = -1.0
	attached = false
	t = 0.0
	if kind == "moving":
		position = base_pos + move * (0.5 - 0.5 * cos(phase * TAU))


func on_attach(_p) -> void:
	attached = true
	if kind == "fragile":
		break_t = FRAGILE_HOLD


func on_release(_p) -> void:
	attached = false
	if kind == "fragile" and active:
		_shatter()


func _shatter() -> void:
	if not active:
		return
	active = false
	break_t = -1.0
	respawn_t = 2.5
	if level:
		level.spawn_burst(global_position, color, 18)
		level.play_sfx("glass", global_position)
		if level.player:
			level.player.force_release(self)


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("grapple_point.draw", _pt)


func _draw_timed() -> void:
	if kind == "moving":
		# show path
		var a := base_pos - position
		var b := a + move
		draw_dashed_line(a, b, Color(color, 0.35), 2.0, 8.0)
	if not active:
		draw_arc(Vector2.ZERO, 10, 0, TAU, 16, Color(color, 0.2), 1.5)
		return
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	var r := 11.0
	draw_circle(Vector2.ZERO, r + 6.0, Color(color, 0.08 + 0.06 * pulse))
	draw_circle(Vector2.ZERO, r * 0.45, color)
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, color, 3.0, true)
	match kind:
		"fragile":
			var cr := Color(color, 0.9)
			draw_line(Vector2(-6, -8), Vector2(2, 0), cr, 1.5)
			draw_line(Vector2(2, 0), Vector2(-2, 9), cr, 1.5)
			if break_t >= 0.0:
				# countdown ring, flashing red in the last 0.35s so the break isn't a surprise
				var warn := break_t < 0.35 and fmod(t, 0.1) < 0.05
				draw_arc(Vector2.ZERO, r + 4.0, 0, TAU * (break_t / FRAGILE_HOLD), 24, Color(2.2, 0.3, 0.3) if warn else Color(2, 2, 2), 2.5)
		"boost":
			for i in 4:
				var ang := t * 3.0 + i * TAU / 4.0
				var p := Vector2(cos(ang), sin(ang)) * (r + 5.0)
				draw_line(p, p + Vector2(cos(ang + 1.2), sin(ang + 1.2)) * 6.0, color, 2.0)
		"moving":
			draw_arc(Vector2.ZERO, r + 4.0, t * 2.0, t * 2.0 + PI * 0.6, 12, color, 2.0)
			draw_arc(Vector2.ZERO, r + 4.0, t * 2.0 + PI, t * 2.0 + PI * 1.6, 12, color, 2.0)
	if targeted:
		var s := r + 10.0 + pulse * 3.0
		var cc := Color(2.4, 2.4, 2.4)
		for i in 4:
			var ang := i * TAU / 4.0 + PI / 4.0
			var p := Vector2(cos(ang), sin(ang)) * s
			draw_line(p, p * 0.7, cc, 2.5)
