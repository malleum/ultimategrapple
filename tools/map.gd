extends SceneTree
## Renders whole courses zoomed out (needs a display, e.g. xvfb-run with a big screen).
## godot --path . --resolution 7680x1440 -s tools/map.gd -- OUT_DIR [level ids or seed:theme ...]
## Writes <name>_full.png (panorama) and <name>_stacked.png (panorama cut into rows).

var out_dir := "/tmp/shots/maps"
var jobs: Array = []
var i := -1
var f := 0
var lvl
var Game


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	for k in range(1, a.size()):
		jobs.append(a[k])
	DirAccess.make_dir_recursive_absolute(out_dir)


func _content_rect(d: Dictionary) -> Rect2:
	var r := Rect2(Vector2(d.spawn[0], d.spawn[1]), Vector2.ZERO)
	for s in d.solids:
		var top := Vector2(s.r[0], s.r[1])
		r = r.expand(top).expand(top + Vector2(s.r[2], 0))
	for e in d.entities:
		if e.has("p"):
			r = r.expand(Vector2(e.p[0], e.p[1]))
		if e.has("r"):
			r = r.expand(Vector2(e.r[0], e.r[1]))
	r = r.expand(Vector2(d.basket[0], d.basket[1] - 200))
	return r.grow_individual(200, 380, 200, 520)


func _process(_dt: float) -> bool:
	if Game == null:
		Game = root.get_node("Game")
		Game.main = root
	if i < 0 or f > 30:
		i += 1
		f = 0
		if i >= jobs.size():
			quit()
			return false
		var job: String = jobs[i]
		var data: Dictionary
		if job.contains(":"):
			data = Game.generate_level(int(job.get_slice(":", 0)), job.get_slice(":", 1), 0.6, 12)
		else:
			for d in Game.list_pinned_levels():
				if d.id == job:
					data = d
		lvl = Game.play_level(data)
		return false
	f += 1
	if f == 3:
		var r = lvl.runners[0]
		r.hud.visible = false
		r.overlay.visible = false
		r.lock_input(true)
		var cr := _content_rect(lvl.level_data)
		var vis: Vector2 = root.get_viewport().get_visible_rect().size
		var z := minf(vis.x / cr.size.x, vis.y / cr.size.y)
		r.camera.zoom = Vector2(z, z)
		r.cam_zoom = z
		r.camera.position = cr.get_center()
		r.camera.reset_physics_interpolation()
		r.set_physics_process(false)
		set_meta("cr", cr)
		set_meta("z", z)
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		var cr: Rect2 = get_meta("cr")
		var z: float = get_meta("z")
		# crop to the content area actually covered
		var scale := float(img.get_width()) / root.get_viewport().get_visible_rect().size.x
		var w := mini(img.get_width(), int(cr.size.x * z * scale))
		var h := mini(img.get_height(), int(cr.size.y * z * scale))
		var x0 := (img.get_width() - w) / 2
		var y0 := (img.get_height() - h) / 2
		var full := img.get_region(Rect2i(x0, y0, w, h))
		var name: String = str(lvl.level_data.get("name", "course")).to_lower().replace(" ", "_") + "_" + str(lvl.level_data.theme)
		full.save_png("%s/%s_full.png" % [out_dir, name])
		# stacked rows (easier to view)
		var rows := 3
		var rw := int(ceil(w / float(rows)))
		var stacked := Image.create(rw, h * rows + 8 * (rows - 1), false, full.get_format())
		stacked.fill(Color(0, 0, 0))
		for k in rows:
			var part := full.get_region(Rect2i(k * rw, 0, mini(rw, w - k * rw), h))
			stacked.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, k * (h + 8)))
		stacked.save_png("%s/%s_stacked.png" % [out_dir, name])
		print("saved map ", name, " ", full.get_size(), " zoom ", z)
		f = 100
	return false
