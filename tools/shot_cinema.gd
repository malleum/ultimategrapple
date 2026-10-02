extends SceneTree
## Cinematic stills: stages a moment on a generated course with real inputs
## and effects, hides the HUD panels (popups and speed lines stay) and saves a
## few frames around the peak. Needs a display (xvfb-run).
##   godot --fixed-fps 120 -s tools/shot_cinema.gd -- <scene> <out_prefix>
## scenes: swing zip pivot hammer chains skip skycatch charge

const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")

var scene := "swing"
var out := "cine"
var lvl
var r
var p
var f := 0
var started := false
var aim := Vector2.ZERO
var shots: Array = []      # frames to save
var zoom := 0.95
var data: Dictionary
var st := {}
var follow := ""           # "", "mid" (player + disc), "disc"
var taken := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		scene = a[0]
	if a.size() > 1:
		out = a[1]


func _setup(seed_v: int, theme: String) -> void:
	var G = root.get_node("Game")
	G.main = root
	data = G.generate_level(seed_v, theme, 0.6, 10)
	data["id"] = "cine_%s" % scene
	G.settings["show_ghost"] = false
	G.settings["screen_shake"] = 0.6
	lvl = G.play_level(data)
	r = lvl.runners[0]
	p = r.player
	r.inp.mouse_world_fn = func() -> Vector2: return aim
	r.hud.cinema = true
	r.overlay.reticle.visible = false


## Is a player-sized box at feet position `feet` clear of solid rectangles?
func _free(feet: Vector2, extra := Vector2.ZERO) -> bool:
	var box := Rect2(feet + Vector2(-14, -50) - extra, Vector2(28, 50) + extra * 2.0)
	for s in data.solids:
		var sr := Rect2(float(s.r[0]), float(s.r[1]), float(s.r[2]), float(s.r[3]))
		if sr.intersects(box):
			return false
	return true


## A grapple point with a clear swing arc of radius `rad` below it.
func _swing_point(rad: float) -> Vector2:
	for gp in _grapples():
		var ok := true
		for deg in range(20, 161, 10):
			if not _free(gp + Vector2.from_angle(deg_to_rad(deg)) * rad + Vector2(0, 30), Vector2(16, 16)):
				ok = false
				break
		if ok:
			return gp
	return Vector2.ZERO


func _grapples() -> Array:
	var out_g: Array = []
	for e in data.entities:
		if str(e.t) == "grapple":
			out_g.append(Vector2(e.p[0], e.p[1]))
	return out_g


func _route() -> Array:
	var out_r: Array = []
	for rp in data.route:
		out_r.append(Vector2(rp[0], rp[1]))
	return out_r


func _place(pos: Vector2, vel: Vector2) -> void:
	p.respawn(pos)
	p.velocity = vel
	r.camera.position = p.center()
	r.camera.reset_physics_interpolation()


func _process(_dt: float) -> bool:
	if r and is_instance_valid(r):
		r.zoom_override = zoom
	return false


func _physics_process(_dt: float) -> bool:
	if not started:
		started = true
		_begin()
		return false
	f += 1
	call("_tick_" + scene)
	if follow != "" and not r.done:
		var target: Vector2 = p.center()
		if follow == "mid":
			target = (p.center() + r.disc.global_position) * 0.5 if r.disc.state != Disc.HELD else p.center()
		elif follow == "disc" and r.disc.state != Disc.HELD:
			target = r.disc.global_position
		r.follow_fn = func() -> Array: return [target, Vector2.ZERO]
	if shots.has(f):
		_save()
	if (not shots.is_empty() and f > shots.max() + 1) or f > 2400:
		_cleanup()
		quit(0)
		return true
	return false


func _save() -> void:
	var info := "frame %d: player state %d at %s v=%s, disc state %d at %s, done=%s" % [f, p.state, p.global_position.round(), p.velocity.round(), r.disc.state, r.disc.global_position.round(), r.done]
	if DisplayServer.get_name() == "headless":
		print("[dry] ", info)
		taken += 1
		return
	print(info)
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s_%s_%d.png" % [out, scene, taken]
	img.save_png(path)
	print("saved %s (frame %d)" % [path, f])
	taken += 1


func _cleanup() -> void:
	var G = root.get_node("Game")
	G.records.erase(data.id)
	G.delete_replay(data.id)
	G.save_ghost(data.id, [])


func _press(a: String) -> void:
	Input.action_press(a)


func _release(a: String) -> void:
	Input.action_release(a)


# ------------------------------------------------------------------ scenes

func _begin() -> void:
	match scene:
		"swing":
			_setup(37, "cyber")
		"zip":
			_setup(37, "frost")
		"pivot":
			_setup(23, "heaven")
		"hammer":
			_setup(11, "canyon")
		"chains":
			_setup(23, "field")
		"skip":
			_setup(23, "fantasy")
		"skycatch":
			_setup(37, "field")
		"charge":
			# first course (other than the swing shot's) with a clear swing arc
			var G = root.get_node("Game")
			for c in [[11, "heaven"], [37, "field"], [11, "canyon"], [37, "canyon"], [23, "fantasy"], [11, "heaven"], [37, "foundry"], [23, "frost"]]:
				data = G.generate_level(int(c[0]), str(c[1]), 0.6, 10)
				if _swing_point(380.0) != Vector2.ZERO:
					print("charge on ", c)
					_setup(int(c[0]), str(c[1]))
					break


## Grapple swing at full tilt over the gap, disc in hand.
func _tick_swing() -> void:
	if f == 2:
		var best := _swing_point(380.0)
		print("swing point ", best)
		_place(best + Vector2(-300, 210), Vector2(1100, 250))
		aim = best
		zoom = 1.8
		shots = [26, 34, 42, 50]
	if f == 3:
		_press("grapple")
	if f == 60:
		_release("grapple")


## Zip line across, snow streaming.
func _tick_zip() -> void:
	if f == 2:
		var best := Vector2.ZERO
		for gp in _grapples():
			if _free(gp + Vector2(-520, 300), Vector2(20, 20)):
				best = gp
				break
		_place(best + Vector2(-520, 300), Vector2(500, -300))
		aim = best
		zoom = 1.7
		shots = [16, 24, 32]
	if f == 3:
		_press("zip")


## Mid-air pivot: freeze in the air, throw, release into the launch.
func _tick_pivot() -> void:
	if f == 2:
		var rt := _route()
		var pos := Vector2.ZERO
		for i in range(2, rt.size()):
			var c: Vector2 = rt[i] + Vector2(0, -300)
			if _free(c, Vector2(60, 60)):
				pos = c
				break
		_place(pos, Vector2(760, -520))
		zoom = 2.0
		shots = [64, 70, 76, 86]
	aim = p.center() + Vector2(600, -380)
	if f == 6:
		_press("pivot")
	if f == 10:
		_press("throw")
	if f == 62:
		_release("throw")
		_press("snap")
	if f == 64:
		_release("snap")
	if f == 66:
		_release("pivot")


## Hammer flipping over at the top of a huge arc, runner tiny below.
func _tick_hammer() -> void:
	if f == 2:
		var rt := _route()
		var pos: Vector2 = rt[3]
		for i in range(2, rt.size()):
			# open sky above and ahead for the arc
			var ok := true
			for k in range(1, 12):
				if not _free(rt[i] + Vector2(k * 40.0, -k * 90.0), Vector2(30, 30)):
					ok = false
					break
			if ok and _free(rt[i] + Vector2(0, -4)):
				pos = rt[i]
				break
		print("hammer from ", pos)
		_place(pos + Vector2(0, -4), Vector2.ZERO)
		p.throw_type = 2
		zoom = 0.85
		follow = "mid"
	aim = p.center() + Vector2.RIGHT.rotated(-deg_to_rad(62)) * 500.0
	if f == 6:
		_press("throw")
	if f == 66:
		_release("throw")
		_press("snap")
	if f == 68:
		_release("snap")
	if r.disc.state == Disc.FLIGHT and not st.has("t0"):
		st["t0"] = f
		var lp := ThrowTypes.launch_params(ThrowTypes.get_type(2), 1.0, 1.0, 0.0, 0.0)
		r.disc.launch(r.disc.global_position, Vector2.RIGHT.rotated(-deg_to_rad(62)) * float(lp.speed), 2, lp.spin, 0.0, lp.wobble, lp.quality)
		shots = [f + 40, f + 52, f + 64, f + 80]


## Straight into the chains: burst, chains swinging, CHAINS!
func _tick_chains() -> void:
	var bp: Vector2 = lvl.basket_pos
	if f == 2:
		var pos := bp + Vector2(-380, 0)
		for dx in [320.0, 380.0, 260.0, 440.0, 220.0, 190.0, 165.0]:
			var c := bp + Vector2(-dx, 0)
			var clear := _free(c + Vector2(0, -4))
			for k in range(1, 9):   # line from the hand to the chains
				var q: Vector2 = c + Vector2(0, -32) + (bp + Vector2(0, -95) - c - Vector2(0, -32)) * (k / 9.0)
				clear = clear and _free(q + Vector2(0, 25), Vector2(-4, -12))
			if clear:
				pos = c
				break
		_place(pos + Vector2(0, -4), Vector2.ZERO)
		zoom = 2.1
		follow = "disc"
		st["try"] = 0
	if f == 6 and not st.has("thrown"):
		st["thrown"] = true
		p.has_disc = false
		var from: Vector2 = p.hand() + Vector2(16, 0)
		var to := bp + Vector2(-6, -100 - 14 * int(st.try))
		var lp := ThrowTypes.launch_params(ThrowTypes.get_type(0), 1.0, 1.0, 0.0, 0.0)
		r.disc.launch(from, (to - from).normalized() * 1250.0, 0, lp.spin, 0.0, 0.0, 1.0)
	if r.done and not st.has("in"):
		st["in"] = f
		r.hud.popup("CHAINS!", Color(2.2, 1.8, 0.3), 2.0)
		shots = [f + 2, f + 6, f + 12, f + 24]
	if not r.done and f > 6 and r.disc.state != Disc.FLIGHT and r.disc.state != Disc.CHAINED and not st.has("in"):
		# missed: try a bit higher
		print("chains try %d: player %s basket %s disc ended %s state %d" % [st.try, p.global_position.round(), bp, r.disc.global_position.round(), r.disc.state])
		st.try = int(st.try) + 1
		st.erase("thrown")
		r.disc.hold()
		p.has_disc = true
		f = 5
		if int(st.try) > 8:
			print("chains: no luck")
			quit(1)


## Thumber skipping off the floor in a spray of sparks.
func _tick_skip() -> void:
	if f == 2:
		var rt := _route()
		var pos: Vector2 = rt[2]
		# an open fairway section: flat ground to skip along
		for sec in data.get("sections", []):
			if str(sec.style) == "throw":
				var best := INF
				for rp in rt:
					if absf(rp.x - float(sec.x0) - 96.0) < best:
						best = absf(rp.x - float(sec.x0) - 96.0)
						pos = rp
				break
		print("skip from ", pos)
		_place(pos + Vector2(0, -4), Vector2.ZERO)
		zoom = 1.9
		follow = "disc"
	if f == 6:
		p.has_disc = false
		var lp := ThrowTypes.launch_params(ThrowTypes.get_type(5), 1.0, 1.0, 0.0, 0.0)
		r.disc.launch(p.hand() + Vector2(16, 0), Vector2(1650, 170), 5, lp.spin, 0.0, 0.0, 1.0)
		r.disc.impact.connect(func(kind, _s):
			print("impact ", kind, " at ", r.disc.global_position.round())
			if kind == "skip" and not st.has("skip"):
				st["skip"] = f
				shots = [f + 1, f + 4, f + 9])


## Double-jump sky catch with the disc dropping in.
func _tick_skycatch() -> void:
	if f == 2:
		var rt := _route()
		var pos: Vector2 = rt[4]
		for i in range(3, rt.size()):
			if _free(rt[i] + Vector2(0, -200), Vector2(40, 40)):
				pos = rt[i]
				break
		_place(pos + Vector2(0, -4), Vector2.ZERO)
		zoom = 2.1
		p.has_disc = false
		r.disc.launch(pos + Vector2(-500, -500), Vector2(500, 0), 0, 1.0, 0.0, 0.0)
		r.disc.age = 1.0
	if f == 26:
		# bring it in to the top of the double jump
		r.disc.global_position = p.center() + Vector2(-110, -50)
		r.disc.velocity = Vector2(700, 260)
		r.disc.reset_physics_interpolation()
	if f == 8:
		_press("jump")
	if f == 14:
		_release("jump")
	if f == 22:
		_press("jump")
	if f == 26:
		_release("jump")
	if f > 3 and p.has_disc and not st.has("caught"):
		st["caught"] = f
		shots = [f + 1, f + 4, f + 8]
	if f > 200 and not st.has("caught"):
		print("skycatch: missed (disc %s, player %s)" % [r.disc.global_position, p.center()])
		quit(1)


## Winding up a full-power throw mid-air off a grapple release.
func _tick_charge() -> void:
	if f == 2:
		var best := _swing_point(380.0)
		print("charge point ", best)
		st["gp"] = best
		_place(best + Vector2(-300, 210), Vector2(1100, 250))
		aim = best
		zoom = 2.0
		shots = [40, 48, 56, 64]
	if f == 3:
		_press("grapple")
	if f == 12:
		_press("throw")
	if f > 12:
		aim = p.center() + Vector2(700, -260)
