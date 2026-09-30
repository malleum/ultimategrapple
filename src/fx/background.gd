extends Node2D
## Themed sky (shader), 3 procedural parallax layers and ambient screen particles.

const SKY_SHADER := """
shader_type canvas_item;
uniform vec4 top_col : source_color;
uniform vec4 bot_col : source_color;
uniform vec4 acc_col : source_color;
uniform int style = 0;
uniform float time_s = 0.0;
uniform vec2 cam = vec2(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; } return v; }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 par = uv + cam * vec2(0.00002, 0.00004);
	float y = clamp(uv.y + cam.y * 0.00008, 0.0, 1.0);
	vec3 col = mix(top_col.rgb, bot_col.rgb, smoothstep(0.0, 1.0, y));
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 sp = vec2(par.x, par.y * aspect);
	if (style == 1 || style == 2 || style == 5) {
		vec2 g = floor(sp * 260.0);
		float s = hash(g);
		float tw = 0.6 + 0.4 * sin(time_s * 2.0 + s * 50.0);
		if (s > 0.996) col += vec3(1.0) * tw * (1.0 - y) * 0.9;
	}
	if (style == 1) {
		float d = length((sp - vec2(0.72, 0.18 * aspect)) * vec2(1.0, 1.0));
		col += acc_col.rgb * 0.25 * smoothstep(0.16, 0.0, d);
		col = mix(col, vec3(0.9, 0.3, 0.8), smoothstep(0.1, 0.095, d) * 0.6);
		col += vec3(0.4, 0.05, 0.3) * smoothstep(0.5, 1.0, y) * 0.5;
	}
	if (style == 2) {
		float d = length(sp - vec2(0.25, 0.15 * aspect));
		col += vec3(0.9, 0.9, 1.0) * smoothstep(0.06, 0.05, d) * 0.8 + vec3(0.3, 0.3, 0.5) * smoothstep(0.3, 0.0, d) * 0.3;
		col += vec3(0.2, 0.35, 0.3) * fbm(sp * 3.0 + time_s * 0.02) * y * 0.4;
	}
	if (style == 0 || style == 3) {
		float c = fbm(vec2(sp.x * 2.5 + time_s * 0.01, sp.y * 6.0));
		float mask = smoothstep(0.55, 0.8, c) * (1.0 - smoothstep(0.2, 0.7, y));
		col = mix(col, vec3(1.0), mask * (style == 3 ? 0.8 : 0.55));
		float d = length(sp - vec2(0.8, 0.12 * aspect));
		col += vec3(1.0, 0.95, 0.8) * smoothstep(0.35, 0.0, d) * 0.35;
		if (style == 3) {
			col += vec3(1.0, 0.6, 0.9) * smoothstep(0.6, 1.0, y) * 0.2;
		}
	}
	if (style == 4) {
		float smoke = fbm(vec2(sp.x * 3.0 - time_s * 0.03, sp.y * 4.0 + time_s * 0.05));
		col = mix(col, vec3(0.08, 0.05, 0.04), smoke * 0.55);
		col += vec3(1.0, 0.35, 0.05) * smoothstep(0.5, 1.0, y) * 0.3;
	}
	if (style == 5) {
		float band = sin(sp.x * 6.0 + fbm(sp * 2.0 + time_s * 0.05) * 5.0 + time_s * 0.2);
		float a = smoothstep(0.6, 1.0, band) * smoothstep(0.55, 0.1, y) * smoothstep(0.0, 0.15, y);
		col += mix(vec3(0.1, 1.2, 0.6), vec3(0.8, 0.2, 1.2), sp.x) * a * 0.5;
	}
	if (style == 6) {
		vec2 sun = vec2(0.3, 0.62 * aspect);
		float d = length(sp - sun);
		col += vec3(1.0, 0.7, 0.3) * smoothstep(0.5, 0.0, d) * 0.45;
		float disk = smoothstep(0.075, 0.07, d);
		float bands = step(0.5, fract((sp.y - sun.y) * 60.0)) * step(sun.y + 0.01, sp.y);
		col = mix(col, vec3(1.0, 0.85, 0.5), disk * (1.0 - bands * 0.8));
		float c2 = fbm(vec2(sp.x * 3.0 + time_s * 0.015, sp.y * 12.0));
		col = mix(col, vec3(0.95, 0.5, 0.45), smoothstep(0.6, 0.8, c2) * (1.0 - smoothstep(0.2, 0.55, y)) * 0.5);
	}
	COLOR = vec4(col, 1.0);
}
"""

const STYLE_IDS := {"field": 0, "city": 1, "forest": 2, "heaven": 3, "factory": 4, "mountains": 5, "canyon": 6}
const REPEAT := 4096.0

var th: Dictionary = {}
var style := "city"
var sky_mat: ShaderMaterial
var camera: Camera2D
var t := 0.0


func setup(p_theme: Dictionary, cam: Camera2D) -> void:
	th = p_theme
	style = th.get("bg_style", "city")
	camera = cam
	z_index = -100
	# sky
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	sky_mat.set_shader_parameter("top_col", th.sky_top)
	sky_mat.set_shader_parameter("bot_col", th.sky_bottom)
	sky_mat.set_shader_parameter("acc_col", th.accent)
	sky_mat.set_shader_parameter("style", STYLE_IDS.get(style, 0))
	rect.material = sky_mat
	sky_layer.add_child(rect)
	# parallax layers
	for i in 3:
		var px := Parallax2D.new()
		var sc: float = [0.12, 0.3, 0.55][i]
		px.scroll_scale = Vector2(sc, sc * 0.35)
		px.repeat_size = Vector2(REPEAT, 0)
		px.repeat_times = 3
		px.z_index = -90 + i * 10
		px.ignore_camera_scroll = false
		var layer := BgLayer.new()
		layer.depth = i
		layer.style = style
		layer.th = th
		px.add_child(layer)
		add_child(px)
	_add_particles()


func _process(dt: float) -> void:
	t += dt
	if sky_mat:
		sky_mat.set_shader_parameter("time_s", t)
		if camera:
			sky_mat.set_shader_parameter("cam", camera.get_screen_center_position())


func _add_particles() -> void:
	var kind: String = th.get("particles", "")
	if kind == "":
		return
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var p := CPUParticles2D.new()
	p.position = Vector2(960, -40)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1400, 10)
	p.amount = 120
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.gravity = Vector2.ZERO
	var acc: Color = th.accent
	match kind:
		"rain":
			p.amount = 260
			p.lifetime = 1.2
			p.preprocess = 1.2
			p.direction = Vector2(-0.15, 1)
			p.spread = 2.0
			p.initial_velocity_min = 1200
			p.initial_velocity_max = 1500
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
			p.color = Color(0.6, 0.8, 1.4, 0.35)
			p.texture = _streak_tex(2, 26)
		"snow":
			p.amount = 160
			p.lifetime = 7.0
			p.preprocess = 7.0
			p.direction = Vector2(-0.3, 1)
			p.spread = 25.0
			p.initial_velocity_min = 80
			p.initial_velocity_max = 190
			p.scale_amount_min = 2.0
			p.scale_amount_max = 5.0
			p.color = Color(1, 1, 1, 0.8)
		"embers":
			p.position = Vector2(960, 1120)
			p.direction = Vector2(0.2, -1)
			p.spread = 30.0
			p.initial_velocity_min = 60
			p.initial_velocity_max = 200
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.color = Color(2.5, 0.8, 0.1, 0.9)
			p.lifetime = 6.0
			p.preprocess = 6.0
		"dust":
			p.position = Vector2(-60, 540)
			p.emission_rect_extents = Vector2(10, 600)
			p.direction = Vector2(1, 0.05)
			p.spread = 8.0
			p.initial_velocity_min = 300
			p.initial_velocity_max = 700
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.5
			p.amount = 90
			p.lifetime = 4.0
			p.preprocess = 4.0
			p.color = Color(1.0, 0.8, 0.6, 0.35)
		"fireflies", "sparkle", "pollen":
			p.emission_rect_extents = Vector2(1100, 600)
			p.position = Vector2(960, 540)
			p.direction = Vector2(0, -1)
			p.spread = 180.0
			p.initial_velocity_min = 8
			p.initial_velocity_max = 40
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.amount = 60
			var cc := Color(1.8, 1.6, 0.4, 0.9) if kind == "fireflies" else (Color(2, 2, 2.4, 0.8) if kind == "sparkle" else Color(1, 1, 0.8, 0.6))
			p.color = cc
			var ramp := Gradient.new()
			ramp.set_color(0, Color(1, 1, 1, 0))
			ramp.add_point(0.3, Color(1, 1, 1, 1))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
			p.color_ramp = ramp
	layer.add_child(p)


func _streak_tex(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, float(y) / h))
	return ImageTexture.create_from_image(img)


class BgLayer:
	extends Node2D
	var depth := 0
	var style := ""
	var th: Dictionary = {}

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + depth * 77 + style.hash()
		var sky_b: Color = th.sky_bottom
		var sky_t: Color = th.sky_top
		var base: Color = sky_b.lerp(sky_t, 0.4).darkened(0.25 + depth * 0.22)
		if style == "city":
			base = sky_b.lerp(sky_t, 0.3 + depth * 0.2).lightened(0.06 - depth * 0.03)
		if style == "heaven":
			base = sky_b.lerp(Color(1, 1, 1), 0.3 - depth * 0.08)
		var W := 4096.0
		var ground_y := 300.0 - depth * 60.0
		match style:
			"city":
				var x := 0.0
				while x < W:
					var bw := rng.randf_range(80, 220) * (1.0 + depth * 0.3)
					var bh := rng.randf_range(300, 900) * (1.2 - depth * 0.25)
					var r := Rect2(x, ground_y - bh, bw, bh + 3000)
					draw_rect(r, base)
					var win: Color = th.accent2 if rng.randf() < 0.5 else th.accent
					win = Color(minf(win.r, 1.0), minf(win.g, 1.0), minf(win.b, 1.0)) * (0.25 + depth * 0.12)
					for wy in range(int(r.position.y) + 20, int(ground_y), 26):
						for wx in range(int(r.position.x) + 10, int(r.end.x) - 10, 22):
							if rng.randf() < 0.12:
								draw_rect(Rect2(wx, wy, 6, 9), Color(win, 0.8))
					if depth == 2 and rng.randf() < 0.4:
						var sc: Color = th.accent if rng.randf() < 0.5 else th.accent2
						draw_rect(Rect2(r.position.x + 10, r.position.y + 40, bw - 20, 30), Color(sc, 0.5), false, 3.0)
					if rng.randf() < 0.3:
						draw_line(Vector2(x + bw * 0.5, r.position.y), Vector2(x + bw * 0.5, r.position.y - 60), base, 3.0)
						draw_circle(Vector2(x + bw * 0.5, r.position.y - 60), 3, Color(3, 0.2, 0.2))
					x += bw + rng.randf_range(0, 40)
			"field":
				if depth == 0:
					_hills(rng, ground_y + 60, 160, Color(0.45, 0.65, 0.75), W)
				elif depth == 1:
					_hills(rng, ground_y + 120, 90, Color(0.3, 0.55, 0.35), W)
					var sx := 400.0
					while sx < W:
						# stadium light tower
						draw_line(Vector2(sx, ground_y + 100), Vector2(sx, ground_y - 300), Color(0.5, 0.55, 0.6), 6.0)
						draw_rect(Rect2(sx - 40, ground_y - 340, 80, 40), Color(0.6, 0.6, 0.65))
						for k in 4:
							draw_circle(Vector2(sx - 28 + k * 19, ground_y - 320), 7, Color(2.0, 2.0, 1.6))
						sx += rng.randf_range(1200, 1800)
				else:
					var tx := 0.0
					while tx < W:
						var r2 := rng.randf_range(40, 90)
						draw_circle(Vector2(tx, ground_y + 160), r2, Color(0.15, 0.4, 0.2))
						tx += r2 * 1.2
					draw_rect(Rect2(0, ground_y + 160, W, 3000), Color(0.15, 0.4, 0.2))
			"forest":
				if depth == 0:
					_mountains(rng, ground_y, 500, base, W)
				else:
					var tx2 := 0.0
					while tx2 < W:
						var h := rng.randf_range(500, 1000) * (0.7 + depth * 0.2)
						var tw := rng.randf_range(40, 90) * (0.6 + depth * 0.3)
						draw_rect(Rect2(tx2, ground_y - h, tw, h + 3000), base)
						draw_circle(Vector2(tx2 + tw * 0.5, ground_y - h), tw * 2.2, base)
						draw_circle(Vector2(tx2 + tw * 0.5 - tw * 1.5, ground_y - h + 60), tw * 1.6, base)
						if depth == 2:
							for k in 3:
								var vx := tx2 + rng.randf_range(-100, 100)
								draw_line(Vector2(vx, ground_y - h), Vector2(vx, ground_y - h + rng.randf_range(100, 400)), Color(0.2, 0.5, 0.2, 0.5), 3.0)
						tx2 += tw + rng.randf_range(150, 400)
			"heaven":
				var cx := 0.0
				while cx < W:
					var cr := rng.randf_range(80, 200) * (1.0 + depth * 0.3)
					var cy := ground_y + rng.randf_range(-200, 100)
					for k in 5:
						draw_circle(Vector2(cx + k * cr * 0.6, cy - (k % 2) * cr * 0.4), cr * (0.7 + 0.1 * (k % 3)), Color(0.9, 0.93, 1.0, 0.3 + depth * 0.12))
					if depth >= 1 and rng.randf() < 0.5:
						var ph := rng.randf_range(200, 500)
						draw_rect(Rect2(cx + cr, cy - ph, 40, ph), Color(0.98, 0.98, 1.0, 0.7))
						draw_rect(Rect2(cx + cr - 10, cy - ph - 14, 60, 14), Color(th.basket, 0.6))
					cx += cr * 3.5 + rng.randf_range(100, 400)
				draw_rect(Rect2(0, ground_y + 200, W, 3000), Color(0.9, 0.92, 1.0, 0.35))
			"factory":
				var fx := 0.0
				while fx < W:
					var fw := rng.randf_range(120, 300)
					var fh := rng.randf_range(200, 600) * (1.0 + depth * 0.2)
					draw_rect(Rect2(fx, ground_y - fh, fw, fh + 3000), base)
					if rng.randf() < 0.6:
						var stx := fx + rng.randf_range(10, fw - 40)
						var sth := rng.randf_range(200, 500)
						draw_rect(Rect2(stx, ground_y - fh - sth, 30, sth), base)
						draw_circle(Vector2(stx + 15, ground_y - fh - sth), 10, Color(2.5, 0.8, 0.1, 0.6))
					if depth == 2:
						draw_line(Vector2(fx, ground_y - fh + 40), Vector2(fx + fw + 200, ground_y - fh + 80), Color(0.3, 0.25, 0.2), 8.0)
					fx += fw + rng.randf_range(20, 200)
			"canyon":
				var mx := -100.0
				var mc := base.lerp(Color(0.5, 0.2, 0.25), 0.4 - depth * 0.1)
				while mx < W:
					var mw := rng.randf_range(200, 600) * (0.8 + depth * 0.3)
					var mh := rng.randf_range(150, 420) * (1.0 + depth * 0.2)
					var slope := rng.randf_range(30, 90)
					draw_colored_polygon(PackedVector2Array([Vector2(mx, ground_y + 3000), Vector2(mx, ground_y), Vector2(mx + slope, ground_y - mh), Vector2(mx + mw - slope, ground_y - mh), Vector2(mx + mw, ground_y), Vector2(mx + mw, ground_y + 3000)]), mc)
					for k in 3:
						var sy := ground_y - mh + 30 + k * mh * 0.25
						draw_line(Vector2(mx + slope * 0.6, sy), Vector2(mx + mw - slope * 0.6, sy), Color(mc.lightened(0.12), 0.6), 3.0)
					if depth == 2 and rng.randf() < 0.3:
						# hoodoo spire
						var hx := mx + mw + 60
						draw_rect(Rect2(hx, ground_y - mh * 0.8, 26, mh * 0.8 + 3000), mc)
						draw_circle(Vector2(hx + 13, ground_y - mh * 0.8), 20, mc)
					mx += mw + rng.randf_range(60, 400)
				draw_rect(Rect2(-100, ground_y, W + 200, 3000), mc)
			"mountains":
				if depth < 2:
					_mountains(rng, ground_y + depth * 100, 700 - depth * 250, base, W, true)
				else:
					var px := 0.0
					while px < W:
						var ph2 := rng.randf_range(160, 320)
						draw_colored_polygon(PackedVector2Array([Vector2(px - 50, ground_y + 200), Vector2(px + 50, ground_y + 200), Vector2(px, ground_y + 200 - ph2)]), base)
						px += rng.randf_range(40, 120)
					draw_rect(Rect2(0, ground_y + 200, W, 3000), base)

	func _hills(rng: RandomNumberGenerator, y: float, amp: float, c: Color, W: float) -> void:
		var pts := PackedVector2Array()
		var ph := rng.randf() * 10.0
		var x := 0.0
		while x <= W:
			pts.append(Vector2(x, y - amp * (0.5 + 0.5 * sin(x / W * TAU * 3.0 + ph)) - amp * 0.3 * sin(x / W * TAU * 7.0)))
			x += 32.0
		pts.append(Vector2(W, y + 3000))
		pts.append(Vector2(0, y + 3000))
		draw_colored_polygon(pts, c)

	func _mountains(rng: RandomNumberGenerator, y: float, amp: float, c: Color, W: float, snow := false) -> void:
		var x := -200.0
		while x < W + 200:
			var w := rng.randf_range(400, 900)
			var h := rng.randf_range(0.5, 1.0) * amp
			var peak := Vector2(x + w * 0.5, y - h)
			draw_colored_polygon(PackedVector2Array([Vector2(x, y + 3000), Vector2(x, y), peak, Vector2(x + w, y), Vector2(x + w, y + 3000)]), c)
			if snow:
				var s := 0.25
				draw_colored_polygon(PackedVector2Array([peak, peak.lerp(Vector2(x, y), s), peak.lerp(Vector2(x + w * 0.5, y), s * 0.6), peak.lerp(Vector2(x + w, y), s)]), Color(0.95, 0.97, 1.0, 0.9))
			x += w * 0.6
