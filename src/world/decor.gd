extends Node2D
## Theme decoration prop (no collision). Origin = ground contact point.

var kind := "cone"
var th: Dictionary = {}
var s := 1.0
var v := 0
var t := 0.0
var animated := false


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	kind = data.get("k", "cone")
	s = float(data.get("s", 1.0))
	v = int(data.get("v", 0))
	position = Vector2(data.p[0], data.p[1])
	z_index = -2
	animated = kind in ["flag", "antenna", "holo", "vent", "neon_sign", "crystal", "chain", "cloud_puff", "ice_crystal"]
	t = v * 0.37
	set_physics_process(animated)


func _physics_process(dt: float) -> void:
	t += dt
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var acc: Color = th.get("accent", Color(2, 0.5, 1.5))
	var acc2: Color = th.get("accent2", Color(0.5, 1.5, 2))
	var dark: Color = th.get("block_dark", Color(0.1, 0.1, 0.1))
	match kind:
		"cone":
			var c := Color(1.0, 0.45, 0.05)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(2, -26), Vector2(-2, -26)]), c)
			draw_line(Vector2(-6, -10), Vector2(6, -10), Color(1, 1, 1), 3.0)
			draw_rect(Rect2(-13, -2, 26, 3), c.darkened(0.3))
		"flag":
			draw_line(Vector2(0, 0), Vector2(0, -70), Color(0.9, 0.9, 0.9), 2.5)
			var wv := sin(t * 5.0) * 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(0, -70), Vector2(30, -64 + wv), Vector2(0, -54)]), acc2 if v % 2 == 0 else acc)
		"bench":
			draw_rect(Rect2(-30, -16, 60, 5), Color(0.55, 0.35, 0.2))
			draw_line(Vector2(-24, -11), Vector2(-24, 0), Color(0.4, 0.4, 0.4), 3.0)
			draw_line(Vector2(24, -11), Vector2(24, 0), Color(0.4, 0.4, 0.4), 3.0)
		"tree":
			if th.get("bg_style", "") == "forest":
				draw_line(Vector2(0, 0), Vector2(4, -60), Color(0.25, 0.18, 0.15), 8.0)
				draw_line(Vector2(3, -40), Vector2(-18, -58), Color(0.25, 0.18, 0.15), 4.0)
				draw_circle(Vector2(4, -74), 24, Color(0.12, 0.3, 0.2))
				draw_circle(Vector2(-16, -64), 14, Color(0.14, 0.34, 0.22))
				for i in 5:
					var a := i * 1.3 + v
					draw_circle(Vector2(4, -74) + Vector2(cos(a), sin(a)) * 16.0, 2.0, Color(th.get("detail", Color(1.3, 1.1, 0.4)), 0.9))
			else:
				draw_line(Vector2(0, 0), Vector2(0, -50), Color(0.35, 0.22, 0.12), 7.0)
				draw_circle(Vector2(0, -62), 22, Color(0.2, 0.55, 0.22))
				draw_circle(Vector2(-12, -52), 14, Color(0.18, 0.5, 0.2))
				draw_circle(Vector2(12, -54), 15, Color(0.22, 0.6, 0.25))
		"yardline":
			var num := str(((v % 5) + 1) * 10)
			draw_string(ThemeDB.fallback_font, Vector2(-14, 40), num, HORIZONTAL_ALIGNMENT_CENTER, 28, 26, Color(1, 1, 1, 0.55))
		"neon_sign":
			draw_line(Vector2(0, 0), Vector2(0, -60), Color(0.3, 0.3, 0.35), 3.0)
			var flick := 1.0 if fmod(t * 7.0 + v, 11.0) > 0.4 else 0.25
			var col := (acc if v % 2 == 0 else acc2) * flick
			var r := Rect2(-26, -100, 52, 40)
			draw_rect(r, Color(0.02, 0.0, 0.05, 0.9))
			draw_rect(r, col, false, 2.5)
			for i in 3:
				var yy := r.position.y + 10 + i * 10
				draw_line(Vector2(r.position.x + 8, yy), Vector2(r.position.x + 12 + ((v * (i + 3)) % 30), yy), col, 3.0)
		"antenna":
			draw_line(Vector2(0, 0), Vector2(0, -90), Color(0.35, 0.35, 0.4), 2.5)
			draw_line(Vector2(-10, -70), Vector2(10, -70), Color(0.35, 0.35, 0.4), 2.0)
			draw_line(Vector2(-6, -80), Vector2(6, -80), Color(0.35, 0.35, 0.4), 2.0)
			if fmod(t, 1.4) < 0.5:
				draw_circle(Vector2(0, -92), 3.5, Color(3, 0.3, 0.3))
		"vent":
			draw_rect(Rect2(-16, -20, 32, 20), Color(0.18, 0.18, 0.22))
			for i in 3:
				var ph := fmod(t * 0.8 + i * 0.33, 1.0)
				draw_circle(Vector2(sin(t + i) * 4.0, -24 - ph * 50.0), 5 + ph * 8, Color(0.7, 0.7, 0.8, 0.25 * (1.0 - ph)))
		"holo":
			var hy := -50 + sin(t * 2.0) * 5.0
			var ang := t * 1.5
			var pts := PackedVector2Array()
			for i in 4:
				pts.append(Vector2(cos(ang + i * PI / 2.0) * 14.0, hy + sin(ang + i * PI / 2.0) * 5.0 + (-12 if i % 2 == 0 else 12) * 0.0))
			draw_polyline(PackedVector2Array([Vector2(0, hy - 18), pts[0], Vector2(0, hy + 18), pts[2], Vector2(0, hy - 18)]), Color(acc2, 0.8), 2.0)
			draw_line(Vector2(-8, 0), Vector2(8, 0), acc2, 3.0)
		"mushroom":
			draw_line(Vector2(0, 0), Vector2(0, -22), Color(0.85, 0.8, 0.7), 6.0)
			var cap := PackedVector2Array()
			for i in 13:
				var a := PI + i * PI / 12.0
				cap.append(Vector2(cos(a) * 20, -22 + sin(a) * 14))
			draw_colored_polygon(cap, Color(0.6, 0.15, 0.4))
			draw_circle(Vector2(-7, -28), 2.5, Color(1.8, 1.4, 0.6))
			draw_circle(Vector2(6, -31), 2.0, Color(1.8, 1.4, 0.6))
		"crystal":
			var glow := 0.7 + 0.3 * sin(t * 2.0 + v)
			var cc := acc2 * glow
			draw_colored_polygon(PackedVector2Array([Vector2(-8, 0), Vector2(-4, -34), Vector2(2, -40), Vector2(6, 0)]), Color(cc, 0.6))
			draw_colored_polygon(PackedVector2Array([Vector2(4, 0), Vector2(12, -22), Vector2(16, 0)]), Color(cc, 0.5))
		"ruin_pillar":
			draw_rect(Rect2(-12, -70 - (v % 3) * 12, 24, 70 + (v % 3) * 12), Color(0.45, 0.42, 0.4))
			draw_rect(Rect2(-16, -8, 32, 8), Color(0.35, 0.33, 0.32))
			draw_line(Vector2(-12, -40), Vector2(12, -52), Color(0.25, 0.6, 0.2), 3.0)
		"pillar":
			draw_rect(Rect2(-10, -90, 20, 90), Color(0.97, 0.97, 1.0))
			draw_rect(Rect2(-15, -96, 30, 8), th.get("basket", Color(2, 1.7, 0.3)))
			for i in 3:
				draw_line(Vector2(-5 + i * 5, -86), Vector2(-5 + i * 5, -4), Color(0.8, 0.82, 0.95), 1.5)
		"cloud_puff":
			var off := sin(t * 0.7 + v) * 4.0
			for i in 4:
				draw_circle(Vector2(-24 + i * 16, -16 + off - (i % 2) * 8), 16 - (i % 2) * 2, Color(1, 1, 1, 0.8))
		"statue":
			draw_rect(Rect2(-12, -12, 24, 12), Color(0.85, 0.87, 0.95))
			draw_line(Vector2(0, -12), Vector2(0, -50), Color(0.95, 0.95, 1.0), 6.0)
			draw_circle(Vector2(0, -58), 7, Color(0.95, 0.95, 1.0))
			draw_arc(Vector2(-4, -42), 20, PI * 0.9, PI * 1.5, 10, Color(1.5, 1.5, 1.8), 3.0)
			draw_arc(Vector2(4, -42), 20, -PI * 0.5, PI * 0.1, 10, Color(1.5, 1.5, 1.8), 3.0)
			draw_arc(Vector2(0, -70), 8, 0, TAU, 16, th.get("basket", Color(2, 1.7, 0.3)), 1.5)
		"arch":
			draw_arc(Vector2(0, -40), 36, PI, TAU, 20, Color(0.95, 0.95, 1.0), 8.0)
			draw_line(Vector2(-36, -40), Vector2(-36, 0), Color(0.95, 0.95, 1.0), 8.0)
			draw_line(Vector2(36, -40), Vector2(36, 0), Color(0.95, 0.95, 1.0), 8.0)
			draw_arc(Vector2(0, -40), 36, PI, TAU, 20, Color(acc2, 0.6), 2.0)
		"barrel":
			draw_rect(Rect2(-14, -36, 28, 36), Color(0.45, 0.2, 0.1))
			draw_line(Vector2(-14, -26), Vector2(14, -26), Color(0.25, 0.25, 0.25), 3.0)
			draw_line(Vector2(-14, -10), Vector2(14, -10), Color(0.25, 0.25, 0.25), 3.0)
			if v % 3 == 0:
				draw_colored_polygon(PackedVector2Array([Vector2(-6, -20), Vector2(0, -30), Vector2(6, -20), Vector2(0, -14)]), Color(1.8, 1.2, 0.1))
		"pipe":
			draw_rect(Rect2(-8, -80, 16, 80), Color(0.35, 0.33, 0.33))
			draw_rect(Rect2(-12, -84, 24, 8), Color(0.45, 0.42, 0.4))
			draw_circle(Vector2(0, -60), 3, Color(2.4, 0.8, 0.1))
		"crate":
			draw_rect(Rect2(-18, -36, 36, 36), Color(0.4, 0.3, 0.18))
			draw_rect(Rect2(-18, -36, 36, 36), Color(0.25, 0.18, 0.1), false, 2.5)
			draw_line(Vector2(-18, -36), Vector2(18, 0), Color(0.25, 0.18, 0.1), 2.5)
		"chain":
			var sw := sin(t * 1.5 + v) * 6.0
			for i in 8:
				var p := Vector2(sw * i / 8.0, -160 + i * 14)
				draw_arc(p, 5, 0, TAU, 8, Color(0.5, 0.5, 0.55), 2.0)
			draw_line(Vector2(-6 + sw, -48), Vector2(6 + sw, -48), Color(0.6, 0.6, 0.65), 4.0)
		"pine":
			draw_line(Vector2(0, 0), Vector2(0, -16), Color(0.3, 0.2, 0.15), 6.0)
			for i in 3:
				var w := 26.0 - i * 6.0
				var y0 := -12.0 - i * 20.0
				draw_colored_polygon(PackedVector2Array([Vector2(-w, y0), Vector2(w, y0), Vector2(0, y0 - 32)]), Color(0.1, 0.3, 0.28))
				draw_line(Vector2(-w * 0.6, y0 - 10), Vector2(w * 0.3, y0 - 14), Color(0.9, 0.95, 1.0), 3.0)
		"ice_crystal":
			var g := 0.8 + 0.2 * sin(t * 1.5 + v)
			draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(0, -44), Vector2(6, 0)]), Color(0.7 * g, 1.2 * g, 1.8 * g, 0.7))
			draw_colored_polygon(PackedVector2Array([Vector2(2, 0), Vector2(14, -26), Vector2(12, 0)]), Color(0.7, 1.1, 1.6, 0.5))
		"rock":
			draw_colored_polygon(PackedVector2Array([Vector2(-22, 0), Vector2(-16, -16), Vector2(0, -22), Vector2(18, -12), Vector2(22, 0)]), Color(0.4, 0.45, 0.5))
			draw_line(Vector2(-16, -16), Vector2(0, -22), Color(0.95, 0.98, 1.0), 4.0)
		"snowman":
			draw_circle(Vector2(0, -14), 14, Color(0.95, 0.97, 1.0))
			draw_circle(Vector2(0, -36), 10, Color(0.95, 0.97, 1.0))
			draw_line(Vector2(2, -37), Vector2(12, -35), Color(1.5, 0.6, 0.1), 3.0)
			draw_line(Vector2(-6, -46), Vector2(6, -46), Color(0.1, 0.1, 0.1), 3.0)
		_:
			draw_circle(Vector2(0, -8), 8, dark)
