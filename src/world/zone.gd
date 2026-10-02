extends Area2D
## Generic trigger zone: spikes/kill (hazard), wind, booster, bounce pad,
## laser (timed beam) and saw (moving circle). Bodies that implement
## trigger_enter(kind, node)/trigger_exit(kind, node) react to it.

const Perf = preload("res://src/core/perf.gd")
const View = preload("res://src/world/view.gd")

var kind := "hazard"          # hazard | kill | wind | booster | pad | laser | saw
var th: Dictionary = {}
var rect := Rect2()
var dir_name := "up"
var force := Vector2.ZERO
var dir: Variant = 1           # booster: int ; pad: Vector2
var power := 1400.0
var t := 0.0
# laser
var a := Vector2.ZERO
var b := Vector2.ZERO
var on_time := 1.0
var off_time := 1.0
var phase := 0.0
var lit := true
# saw / moving
var base_pos := Vector2.ZERO
var move := Vector2.ZERO
var period := 2.0
var radius := 26.0
var level: Node = null
var _bodies: Array = []
var _particles_seed := 0


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	collision_layer = 1 << 3
	collision_mask = (1 << 1) | (1 << 2)
	monitorable = false
	var t_name: String = data.t
	var cs := CollisionShape2D.new()
	match t_name:
		"spikes":
			kind = "hazard"
			dir_name = data.get("dir", "up")
			rect = _r(data.r)
			var sh := RectangleShape2D.new()
			sh.size = rect.size - Vector2(6, 6).min(rect.size * 0.5)
			cs.shape = sh
			cs.position = rect.get_center()
		"kill":
			kind = "kill"
			rect = _r(data.r)
			var sh := RectangleShape2D.new()
			sh.size = rect.size
			cs.shape = sh
			cs.position = rect.get_center()
		"wind":
			kind = "wind"
			rect = _r(data.r)
			force = Vector2(data.force[0], data.force[1])
			var sh := RectangleShape2D.new()
			sh.size = rect.size
			cs.shape = sh
			cs.position = rect.get_center()
		"booster":
			kind = "booster"
			rect = _r(data.r)
			dir = int(data.get("dir", 1))
			var sh := RectangleShape2D.new()
			sh.size = rect.size + Vector2(0, 20)
			cs.shape = sh
			cs.position = rect.get_center() + Vector2(0, -6)
		"pad":
			kind = "pad"
			var p := Vector2(data.p[0], data.p[1])
			rect = Rect2(p - Vector2(28, 14), Vector2(56, 14))
			dir = Vector2(data.dir[0], data.dir[1]).normalized()
			power = float(data.get("power", 1400))
			var sh := RectangleShape2D.new()
			sh.size = Vector2(52, 16)
			cs.shape = sh
			cs.position = p + Vector2(0, -8)
		"laser":
			kind = "hazard"
			a = Vector2(data.a[0], data.a[1])
			b = Vector2(data.b[0], data.b[1])
			on_time = float(data.get("on", 1.0))
			off_time = float(data.get("off", 1.0))
			phase = float(data.get("phase", 0.0))
			var sh := SegmentShape2D.new()
			sh.a = a
			sh.b = b
			cs.shape = sh
			set_meta("laser", true)
		"saw":
			kind = "hazard"
			base_pos = Vector2(data.p[0], data.p[1])
			move = Vector2(data.move[0], data.move[1])
			period = float(data.get("period", 2.0))
			phase = float(data.get("phase", 0.0))
			radius = float(data.get("radius", 26))
			var sh := CircleShape2D.new()
			sh.radius = radius - 4.0
			cs.shape = sh
			position = base_pos
			set_meta("saw", true)
	add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	_particles_seed = int(rect.position.x + a.x + base_pos.x)


func _r(arr: Array) -> Rect2:
	return Rect2(arr[0], arr[1], arr[2], arr[3])


func _on_enter(body: Node) -> void:
	_bodies.append(body)
	if kind == "hazard" and has_meta("laser") and not lit:
		return
	if body.has_method("trigger_enter"):
		body.trigger_enter(kind, self)
		if kind == "pad" and level:
			level.play_sfx("pad", body.global_position)


func _on_exit(body: Node) -> void:
	_bodies.erase(body)
	if body.has_method("trigger_exit"):
		body.trigger_exit(kind, self)


func reset() -> void:
	t = 0.0


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("zone." + kind + ".tick", _pt)


func _physics_process_timed(dt: float) -> void:
	t += dt
	if has_meta("laser"):
		var cyc := on_time + off_time
		var local := fposmod(t + phase * cyc, cyc)
		var now_lit := local < on_time
		if now_lit and not lit:
			for body in _bodies:
				if is_instance_valid(body) and body.has_method("trigger_enter"):
					body.trigger_enter("hazard", self)
		lit = now_lit
	elif has_meta("saw"):
		position = base_pos + move * (0.5 - 0.5 * cos((t / period + phase) * TAU))
	# plain spike strips are static: drawn once. The rest animate, but only
	# need re-recording while a camera can see them.
	if _static:
		return
	if View.sees(_bounds()):
		queue_redraw()


var _static_cached := -1
var _static: bool:
	get:
		if _static_cached < 0:
			_static_cached = 1 if kind == "hazard" and not has_meta("laser") and not has_meta("saw") else 0
		return _static_cached == 1


func _bounds() -> Rect2:
	if has_meta("laser"):
		return Rect2(a, Vector2.ZERO).expand(b).grow(40.0)
	if has_meta("saw"):
		return Rect2(global_position - Vector2(radius, radius), Vector2(radius, radius) * 2.0).grow(20.0)
	# kill fog / wind / boosters draw around their rect
	return Rect2(rect.position - Vector2(0, 300), rect.size + Vector2(0, 330))


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("zone." + kind + ".draw", _pt)


func _draw_timed() -> void:
	var hz: Color = th.get("hazard", Color(2, 0.2, 0.2))
	match kind:
		"hazard":
			if has_meta("laser"):
				_draw_laser(hz)
			elif has_meta("saw"):
				_draw_saw(hz)
			else:
				_draw_spikes(hz)
		"kill":
			# abyss: dark falloff with a faint ember shimmer instead of a hard line
			var fog := Rect2(rect.position - Vector2(0, 260), Vector2(rect.size.x, 290))
			var pts := PackedVector2Array([fog.position, Vector2(fog.end.x, fog.position.y), fog.end, Vector2(fog.position.x, fog.end.y)])
			var hzd := Color(hz.r * 0.25, hz.g * 0.08, hz.b * 0.12, 0.0)
			draw_polygon(pts, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.0, 0.0, 0.02, 0.92), Color(0.0, 0.0, 0.02, 0.92)]))
			var glow := Rect2(rect.position - Vector2(0, 70), Vector2(rect.size.x, 70))
			var gp := PackedVector2Array([glow.position, Vector2(glow.end.x, glow.position.y), glow.end, Vector2(glow.position.x, glow.end.y)])
			draw_polygon(gp, PackedColorArray([hzd, hzd, Color(hzd, 0.35), Color(hzd, 0.35)]))
			var rng := RandomNumberGenerator.new()
			rng.seed = _particles_seed
			for i in int(rect.size.x / 60.0):
				var ex := rect.position.x + rng.randf() * rect.size.x
				var ph := fmod(t * rng.randf_range(0.2, 0.5) + rng.randf(), 1.0)
				var ey := rect.position.y - ph * 160.0
				draw_circle(Vector2(ex + sin(t + i) * 6.0, ey), 1.6, Color(minf(hz.r, 1.2), minf(hz.g, 1.0) * 0.6, minf(hz.b, 1.0) * 0.4, 0.6 * (1.0 - ph)))
		"wind":
			_draw_wind()
		"booster":
			var c: Color = th.get("accent2", Color(0.3, 1.5, 2.0))
			draw_rect(rect, Color(c, 0.35))
			var off := fmod(t * 300.0, 40.0)
			var x := rect.position.x + off
			while x < rect.end.x - 12:
				var y := rect.position.y + rect.size.y * 0.5
				var s := 10.0 * float(dir)
				draw_polyline(PackedVector2Array([Vector2(x, y - 6), Vector2(x + s, y), Vector2(x, y + 6)]), c, 3.0)
				x += 40.0
		"pad":
			var c2: Color = th.get("accent", Color(2, 0.6, 1.5))
			var p := rect.get_center() + Vector2(0, 7)
			draw_rect(Rect2(p - Vector2(28, 10), Vector2(56, 10)), Color(c2.r * 0.3, c2.g * 0.3, c2.b * 0.3))
			var squish := 1.0 + 0.15 * sin(t * 10.0)
			draw_line(p + Vector2(-26, -10 * squish), p + Vector2(26, -10 * squish), c2, 5.0)
			var d2: Vector2 = dir
			for i in 3:
				var q := p + Vector2(0, -24 - i * 14 - fmod(t * 40.0, 14.0)) + d2 * 6.0 * i
				draw_line(q, q - d2.rotated(0.6) * 8.0, Color(c2, 0.8 - i * 0.2), 2.5)
				draw_line(q, q - d2.rotated(-0.6) * 8.0, Color(c2, 0.8 - i * 0.2), 2.5)


func _draw_spikes(hz: Color) -> void:
	var r := rect
	var n: int
	var base_c := Color(hz.r * 0.35, hz.g * 0.35, hz.b * 0.35)
	# the whole strip as one zigzag: one fill (fan-free triangle list) and one
	# outline, instead of two draw commands per spike
	var tris := PackedVector2Array()
	var edge := PackedVector2Array()
	match dir_name:
		"up", "down":
			n = maxi(1, int(r.size.x / 16.0))
			var w := r.size.x / n
			var base_y := r.end.y if dir_name == "up" else r.position.y
			var tip_y := r.position.y if dir_name == "up" else r.end.y
			for i in n:
				var x0 := r.position.x + i * w
				var p0 := Vector2(x0, base_y)
				var p1 := Vector2(x0 + w * 0.5, tip_y)
				var p2 := Vector2(x0 + w, base_y)
				tris.append_array([p0, p1, p2])
				edge.append_array([p0, p1, p1, p2])
			edge.append_array([Vector2(r.position.x, base_y), Vector2(r.end.x, base_y)])
		_:
			n = maxi(1, int(r.size.y / 16.0))
			var h := r.size.y / n
			var base_x := r.end.x if dir_name == "left" else r.position.x
			var tip_x := r.position.x if dir_name == "left" else r.end.x
			for i in n:
				var y0 := r.position.y + i * h
				var p0 := Vector2(base_x, y0)
				var p1 := Vector2(tip_x, y0 + h * 0.5)
				var p2 := Vector2(base_x, y0 + h)
				tris.append_array([p0, p1, p2])
				edge.append_array([p0, p1, p1, p2])
			edge.append_array([Vector2(base_x, r.position.y), Vector2(base_x, r.end.y)])
	var cols := PackedColorArray()
	cols.resize(tris.size())
	cols.fill(base_c)
	var idx := PackedInt32Array()
	idx.resize(tris.size())
	for i in tris.size():
		idx[i] = i
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, tris, cols)
	draw_multiline(edge, hz, 1.5)


func _draw_laser(hz: Color) -> void:
	draw_circle(a, 7.0, Color(0.3, 0.3, 0.35))
	draw_circle(b, 7.0, Color(0.3, 0.3, 0.35))
	var cyc := on_time + off_time
	var local := fposmod(t + phase * cyc, cyc)
	if lit:
		var flick := 0.8 + 0.2 * sin(t * 60.0)
		draw_line(a, b, Color(hz, 0.25), 14.0)
		draw_line(a, b, Color(hz.r * 1.5, hz.g * 1.5, hz.b * 1.5) * flick, 4.0)
		draw_line(a, b, Color(3, 3, 3), 1.5)
	else:
		# warning telegraph in the last 0.3s before firing
		var until := cyc - local
		if until < 0.3:
			draw_dashed_line(a, b, Color(hz, 0.7), 2.0, 6.0)
		draw_circle(a, 3.5, Color(hz, 0.6))


func _draw_saw(hz: Color) -> void:
	var rot := t * 14.0
	var pts := PackedVector2Array()
	var teeth := 12
	for i in teeth * 2:
		var ang := rot + i * PI / teeth
		var rr := radius if i % 2 == 0 else radius * 0.78
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, Color(0.55, 0.55, 0.6))
	pts.append(pts[0])
	draw_polyline(pts, hz, 2.0)
	draw_circle(Vector2.ZERO, radius * 0.25, Color(0.2, 0.2, 0.22))
	draw_arc(Vector2.ZERO, radius * 0.25, 0, TAU, 12, hz, 1.5)
	# track
	var ta := -(position - base_pos)
	draw_dashed_line(ta, ta + move, Color(hz, 0.25), 2.0, 10.0)


func _draw_wind() -> void:
	var c: Color = th.get("accent2", Color(0.5, 1.5, 2.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = _particles_seed
	var dirv := force.normalized()
	var span := rect.size.y if absf(dirv.y) > 0.5 else rect.size.x
	for i in 26:
		var bx := rng.randf() * rect.size.x
		var by := rng.randf() * rect.size.y
		var speed := rng.randf_range(0.6, 1.2)
		var off := fmod(t * 520.0 * speed + rng.randf() * span, span)
		var p := rect.position + Vector2(bx, by)
		if absf(dirv.y) > 0.5:
			p.y = rect.position.y + fposmod(by + off * signf(dirv.y), rect.size.y)
		else:
			p.x = rect.position.x + fposmod(bx + off * signf(dirv.x), rect.size.x)
		draw_line(p, p + dirv * 26.0, Color(c, 0.45), 2.0)
	# fan housing at the source side
	if dirv.y < -0.5:
		var fy := rect.end.y - 8
		draw_rect(Rect2(rect.position.x, fy, rect.size.x, 8), Color(0.25, 0.25, 0.3))
		var fx := rect.position.x + 10
		while fx < rect.end.x - 10:
			draw_line(Vector2(fx, fy), Vector2(fx + 8 * sin(t * 30.0), fy + 8), c, 2.0)
			fx += 20.0
