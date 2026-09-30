extends StaticBody2D
## One piece of level geometry (rect or polygon) that draws itself in the theme style.

var kind := "ground"
var rect := Rect2()
var poly := PackedVector2Array()
var th: Dictionary = {}
var seed_v := 0
var fill_top_only := false


func setup(p_kind: String, p_rect: Rect2, p_theme: Dictionary, p_poly := PackedVector2Array()) -> void:
	kind = p_kind
	th = p_theme
	collision_layer = 1
	collision_mask = 0
	seed_v = int(p_rect.position.x * 7 + p_rect.position.y * 13)
	if p_poly.size() >= 3:
		poly = p_poly
		var cp := CollisionPolygon2D.new()
		cp.polygon = poly
		add_child(cp)
		set_meta("poly", poly)
		rect = Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
	else:
		rect = p_rect
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		if kind == "oneway":
			sh.size = Vector2(rect.size.x, 16)
			cs.position = rect.position + Vector2(rect.size.x * 0.5, 8)
			cs.one_way_collision = true
			cs.one_way_collision_margin = 8.0
		else:
			sh.size = rect.size
			cs.position = rect.get_center()
		cs.shape = sh
		add_child(cs)
		set_meta("rect", rect)
	if kind == "grip":
		set_meta("grip", true)
	if kind == "ice":
		set_meta("ice", true)


func _col(key: String) -> Color:
	return th.get(key, Color.MAGENTA)


func _draw() -> void:
	if poly.size() >= 3:
		_draw_poly()
		return
	match kind:
		"oneway":
			_draw_oneway()
		"grip":
			_draw_grip()
		_:
			_draw_block()


func _vgrad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _draw_block() -> void:
	var r := rect
	var is_ground := kind == "ground" or kind == "ice"
	var base := _col("ground") if is_ground else _col("block")
	var dark := _col("ground_dark") if is_ground else _col("block_dark")
	var edge := _col("edge")
	var style: String = th.get("bg_style", "")
	var depth := minf(r.size.y, 520.0)
	_vgrad_rect(Rect2(r.position, Vector2(r.size.x, depth)), base, dark)
	if r.size.y > depth:
		draw_rect(Rect2(r.position + Vector2(0, depth), Vector2(r.size.x, r.size.y - depth)), dark)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var detail := _col("detail")
	var pat_h := minf(depth, 360.0)
	match style:
		"field":
			# turf with mowing stripes and yard lines
			var x := r.position.x
			var i := 0
			while x < r.end.x:
				var w := minf(64.0, r.end.x - x)
				if i % 2 == 0:
					_vgrad_rect(Rect2(x, r.position.y, w, pat_h), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.0))
				if int(x) % 320 == 0:
					draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.position.y + 90), Color(1, 1, 1, 0.5), 3.0)
				x += 64.0
				i += 1
			draw_rect(Rect2(r.position, Vector2(r.size.x, 7)), Color(0.35, 0.8, 0.3))
			for k in int(r.size.x / 9.0):
				var gx := r.position.x + k * 9.0 + rng.randf() * 4.0
				draw_line(Vector2(gx, r.position.y), Vector2(gx + rng.randf_range(-3, 3), r.position.y - rng.randf_range(3, 8)), Color(0.4, 0.9, 0.35), 2.0)
		"city":
			var cols := int(r.size.x / 24.0)
			var rows := int(pat_h / 30.0)
			for cx in cols:
				for cy in range(1, rows):
					if rng.randf() < 0.1:
						var lit := detail if rng.randf() < 0.5 else _col("accent2")
						draw_rect(Rect2(r.position.x + 6 + cx * 24, r.position.y + cy * 30, 8, 3), Color(lit, 0.3 * (1.0 - cy / float(rows))))
			draw_line(r.position + Vector2(0, 14), Vector2(r.end.x, r.position.y + 14), Color(detail, 0.4), 1.5)
		"forest":
			var row := 0
			var y := r.position.y + 8
			while y < r.position.y + pat_h:
				var off := 0.0 if row % 2 == 0 else 24.0
				var x2 := r.position.x - off
				while x2 < r.end.x:
					var br := Rect2(maxf(x2, r.position.x), y, minf(46.0, r.end.x - maxf(x2, r.position.x)), 22)
					if br.size.x > 4:
						draw_rect(br, Color(0, 0, 0, 0.18), false, 1.5)
					x2 += 48.0
				y += 24
				row += 1
			for k in int(r.size.x / 14.0):
				var mx := r.position.x + k * 14.0 + rng.randf() * 6.0
				var ml := rng.randf_range(4, 22)
				draw_line(Vector2(mx, r.position.y), Vector2(mx, r.position.y + ml), Color(0.25, 0.6, 0.2, 0.9), 4.0)
			for k in int(r.size.x / 90.0):
				var rp := Vector2(r.position.x + rng.randf() * r.size.x, r.position.y + rng.randf_range(40, pat_h))
				draw_circle(rp, 3.0, Color(detail, 0.6))
		"heaven":
			for k in int(r.size.x / 70.0) + 1:
				var vx := r.position.x + k * 70.0 + 35.0
				if vx < r.end.x:
					draw_line(Vector2(vx, r.position.y + 20), Vector2(vx + rng.randf_range(-30, 30), r.position.y + pat_h), Color(detail, 0.12), 2.0)
			draw_line(r.position + Vector2(0, 10), Vector2(r.end.x, r.position.y + 10), Color(_col("accent"), 0.5), 2.0)
		"factory":
			var sx := r.position.x
			while sx < r.end.x - 8:
				draw_circle(Vector2(sx + 8, r.position.y + 10), 2.5, Color(0.6, 0.55, 0.5))
				sx += 32.0
			if kind == "block" and r.size.y <= 96:
				var hx := r.position.x
				while hx < r.end.x:
					var q := PackedVector2Array([Vector2(hx, r.end.y), Vector2(hx + 12, r.end.y), Vector2(hx + 24, r.end.y - 10), Vector2(hx + 12, r.end.y - 10)])
					draw_colored_polygon(q, Color(1.0, 0.75, 0.0, 0.6))
					hx += 24.0
		"mountains":
			var cap := PackedVector2Array()
			cap.append(Vector2(r.position.x, r.position.y + 2))
			var sxx := r.position.x
			while sxx <= r.end.x:
				cap.append(Vector2(sxx, r.position.y + 8 + sin(sxx * 0.05 + seed_v) * 4.0))
				sxx += 12.0
			cap.append(Vector2(r.end.x, r.position.y + 2))
			cap.append(Vector2(r.end.x, r.position.y - 4))
			cap.append(Vector2(r.position.x, r.position.y - 4))
			draw_colored_polygon(cap, Color(0.95, 0.98, 1.0))
			if kind == "block":
				for k in int(r.size.x / 18.0):
					var ix := r.position.x + 6 + k * 18.0
					var il := rng.randf_range(6, 22)
					draw_colored_polygon(PackedVector2Array([Vector2(ix - 3, r.end.y), Vector2(ix + 3, r.end.y), Vector2(ix, r.end.y + il)]), Color(0.8, 0.95, 1.2, 0.8))
	if kind == "ice":
		_vgrad_rect(Rect2(r.position, Vector2(r.size.x, 40)), Color(0.75, 0.95, 1.0, 0.45), Color(0.75, 0.95, 1.0, 0.0))
		for k in int(r.size.x / 40.0):
			var gx2 := r.position.x + k * 40.0 + 10.0
			draw_line(Vector2(gx2, r.position.y + 6), Vector2(gx2 + 14, r.position.y + 2), Color(2, 2, 2, 0.6), 1.5)
	# glowing edges
	var ew := 3.0
	draw_line(r.position, Vector2(r.end.x, r.position.y), edge, ew)
	var side_len := minf(r.size.y, 260.0)
	var side_c := Color(edge, 0.7)
	draw_line(r.position, r.position + Vector2(0, side_len), side_c, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + side_len), side_c, 2.0)
	if r.size.y < 600.0:
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(edge, 0.5), 2.0)


func _draw_oneway() -> void:
	var r := Rect2(rect.position, Vector2(rect.size.x, 12))
	var c := _col("oneway")
	draw_rect(r, Color(c.r * 0.3, c.g * 0.3, c.b * 0.3, 0.9))
	draw_line(r.position, Vector2(r.end.x, r.position.y), c, 3.0)
	var x := r.position.x + 6
	while x < r.end.x - 4:
		draw_line(Vector2(x, r.position.y + 3), Vector2(x + 6, r.end.y), Color(c, 0.5), 2.0)
		x += 14.0


func _draw_grip() -> void:
	var r := rect
	var c := _col("grapple")
	draw_rect(r, Color(c.r * 0.15, c.g * 0.15, c.b * 0.15))
	var x := r.position.x + 8
	while x < r.end.x:
		draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y - 10), c, 3.0)
		draw_circle(Vector2(x, r.end.y - 2), 3.0, c)
		x += 22.0
	draw_line(Vector2(r.position.x, r.end.y), r.end, c, 3.0)
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(c, 0.4), 2.0)


func _draw_poly() -> void:
	var base := _col("ground")
	var dark := _col("ground_dark")
	var cols := PackedColorArray()
	for v in poly:
		cols.append(base.lerp(dark, clampf((v.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
	draw_polygon(poly, cols)
	var edge := _col("edge")
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(edge, 0.6), 2.0)
	# emphasise walkable slope
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := (b - a).orthogonal().normalized()
		if absf(a.x - b.x) > 1.0 and absf(a.y - b.y) > 1.0:
			draw_line(a, b, edge, 3.0)
			var k := 0.1
			while k < 1.0:
				var p := a.lerp(b, k)
				draw_line(p, p + (b - a).normalized() * 10.0 + n * 3.0, Color(_col("accent"), 0.7), 2.0)
				k += 0.15
