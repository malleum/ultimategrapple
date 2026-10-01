extends SceneTree
## Steep-throw flight paths for backhand/forehand (and hammer/scoober for
## reference): how far forward the disc gets, where it lands, how far it comes
## back, and the disc's attitude at apex / landing. Optionally renders a PNG
## with the path and the disc plane drawn every 0.15 s.
## godot --headless --fixed-fps 120 -s tools/flight_path.gd -- [out.png]

const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")
const PX_PER_M := 32.0
const HAND_Y := -44.0 * 0.72

const TYPES := [0, 1, 2, 4]               # backhand forehand hammer scoober
const ANGLES := [35.0, 50.0, 65.0, 75.0]
const SNAPS := [[1.0, "perfect"], [0.45, "good"], [0.0, "none"]]
const NOSE := deg_to_rad(15.0)

var runs: Array = []
var frames := 0
var started := false
var out_png := ""


func _plane(d) -> float:
	return d.plane_angle() if d.has_method("plane_angle") else -d.phi * d.facing


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		var args := OS.get_cmdline_user_args()
		out_png = args[0] if args.size() > 0 else ""
		var floor_body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(400000, 400)
		cs.shape = r
		floor_body.position = Vector2(0, 200)
		floor_body.add_child(cs)
		root.add_child(floor_body)
		for ti in TYPES:
			var ty: Dictionary = ThrowTypes.get_type(ti)
			for a in ANGLES:
				for sn in SNAPS:
					for nose in [0.0, NOSE]:
						var d := Disc.new()
						root.add_child(d)
						var dir := Vector2.RIGHT.rotated(-deg_to_rad(a))
						var lp := ThrowTypes.launch_params(ty, 1.0, sn[0], 0.0, 0.0)
						d.launch(Vector2(0, HAND_Y) + dir * 16.0, dir * float(lp.speed), ti, lp.spin, nose, 0.0, lp.quality)
						runs.append({"d": d, "type": ty.id, "deg": a, "snap": sn[1], "nose": nose, "max_x": 0.0, "apex": 0.0,
							"apex_att": 0.0, "land_x": INF, "land_att": 0.0, "t": 0.0, "pts": [], "planes": []})
		return false
	frames += 1
	var all_done := true
	for e in runs:
		var d = e.d
		if e.land_x != INF:
			continue
		all_done = false
		var p: Vector2 = d.global_position
		e.max_x = maxf(e.max_x, p.x)
		if p.y < e.apex:
			e.apex = p.y
			e.apex_att = rad_to_deg(-_plane(d))
		if frames % 3 == 0:
			e.pts.append(p)
		if frames % 18 == 0:
			e.planes.append([p, _plane(d)])
		if d.state == Disc.FLIGHT:
			e.land_att = rad_to_deg(-_plane(d))
		else:
			e.land_x = p.x
			e.t = frames / 120.0
	if all_done or frames > 120 * 20:
		_report()
		if out_png != "":
			_render()
		return true
	return false


func _report() -> void:
	print("type      angle nose snap     | forward  landed  came back | apex   | plane@apex plane@land  time")
	for e in runs:
		print("%-9s %4.0f° %3.0f° %-8s | %6.1fm %6.1fm  %6.1fm  | %5.1fm | %6.0f°    %6.0f°   %4.2fs" % [
			e.type, e.deg, rad_to_deg(e.nose), e.snap, e.max_x / PX_PER_M, e.land_x / PX_PER_M,
			(e.max_x - e.land_x) / PX_PER_M, -e.apex / PX_PER_M, e.apex_att, e.land_att, e.t])


## One panel per throw type: max nose, all angles, perfect (bright) vs none (dim).
func _render() -> void:
	var W := 1800
	var H := 1000
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0.06, 0.06, 0.1))
	var cols := 2
	var pw := W / cols
	var ph := H / 2
	var palette := [Color(0.3, 0.9, 1.0), Color(1.0, 0.5, 0.9), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5)]
	for k in TYPES.size():
		var tid: String = ThrowTypes.get_type(TYPES[k]).id
		var ox := (k % cols) * pw
		var oy := (k / cols) * ph
		# fit
		var minx := -5.0 * PX_PER_M
		var maxx := 10.0 * PX_PER_M
		var miny := -10.0 * PX_PER_M
		for e in runs:
			if e.type == tid and e.nose > 0.0 and e.snap != "good":
				minx = minf(minx, e.land_x)
				maxx = maxf(maxx, e.max_x)
				miny = minf(miny, e.apex)
		var sc := minf((pw - 60) / (maxx - minx), (ph - 60) / (20.0 - miny))
		var to := func(p: Vector2) -> Vector2i:
			return Vector2i(int(ox + 30 + (p.x - minx) * sc), int(oy + ph - 30 - (-p.y) * sc))
		_line(img, to.call(Vector2(minx, 0)), to.call(Vector2(maxx, 0)), Color(0.4, 0.4, 0.45))
		_line(img, to.call(Vector2(0, 0)), to.call(Vector2(0, miny)), Color(0.25, 0.25, 0.3))
		_text_bar(img, ox + 10, oy + 10, tid)
		var ci := 0
		for a in ANGLES:
			for e in runs:
				if e.type != tid or e.deg != a or e.nose == 0.0 or e.snap == "good":
					continue
				var c: Color = palette[ci % palette.size()]
				if e.snap == "none":
					c = c.darkened(0.6)
				for i in range(1, e.pts.size()):
					_line(img, to.call(e.pts[i - 1]), to.call(e.pts[i]), c)
				if e.snap == "perfect":
					for pl in e.planes:
						var dirv := Vector2(cos(pl[1]), sin(pl[1])) * 12.0 / sc
						_line(img, to.call(pl[0] - dirv), to.call(pl[0] + dirv), Color(1, 1, 1))
			ci += 1
	img.save_png(out_png)
	print("saved ", out_png)


func _text_bar(img: Image, x: int, y: int, label: String) -> void:
	# no fonts in Image: mark panels with a coloured tab sized by name length
	img.fill_rect(Rect2i(x, y, label.length() * 10, 6), Color(0.8, 0.8, 0.9))


func _line(img: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var n: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var p := Vector2(a).lerp(Vector2(b), float(i) / maxf(n, 1))
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, c)
