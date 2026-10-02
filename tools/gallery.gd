extends SceneTree
## Captures a batch of gameplay screenshots (needs a display, e.g. xvfb-run).
## godot --path . --resolution 1600x900 -s tools/gallery.gd -- OUT_DIR
## Each shot: generate a course, drop the runner at a route point, perform an
## action (run / swing / throw / zip), capture mid-action.

const PlayerInput = preload("res://src/core/player_input.gd")

var shots := [
	{"seed": 101, "theme": "field", "idx": 0, "act": "charge", "out": "00_field_charge"},
	{"seed": 404, "theme": "canyon", "idx": 0, "act": "pivot", "out": "00_canyon_pivot"},
	{"seed": 101, "theme": "field", "idx": 1, "act": "throw", "out": "01_field_throw"},
	{"seed": 202, "theme": "heaven", "idx": 2, "act": "swing", "out": "02_heaven_swing"},
	{"seed": 303, "theme": "fantasy", "idx": 3, "act": "swing", "out": "03_fantasy_swing"},
	{"seed": 404, "theme": "canyon", "idx": 2, "act": "throw", "out": "04_canyon_throw"},
	{"seed": 505, "theme": "cyber", "idx": 4, "act": "swing", "out": "05_cyber_swing"},
	{"seed": 606, "theme": "frost", "idx": 3, "act": "run", "out": "06_frost_run"},
	{"seed": 707, "theme": "foundry", "idx": 2, "act": "throw", "out": "07_foundry_throw"},
	{"seed": 808, "theme": "cyber", "idx": 6, "act": "zip", "out": "08_cyber_zip"},
	{"seed": 909, "theme": "field", "idx": -1, "act": "putt", "out": "09_field_basket"},
	{"seed": 111, "theme": "canyon", "idx": 5, "act": "swing", "out": "10_canyon_swing"},
	{"seed": 222, "theme": "fantasy", "idx": -1, "act": "putt", "out": "11_fantasy_basket"},
	{"seed": 333, "theme": "heaven", "idx": 5, "act": "throw", "out": "12_heaven_throw"},
	{"seed": 444, "theme": "frost", "idx": 6, "act": "swing", "out": "13_frost_swing"},
	{"seed": 555, "theme": "foundry", "idx": 5, "act": "run", "out": "14_foundry_run"},
	{"seed": 666, "theme": "cyber", "idx": 2, "act": "split2", "out": "15_couch_2p"},
	{"seed": 777, "theme": "canyon", "idx": 3, "act": "split4", "out": "16_couch_4p"},
]

var out_dir := "/tmp/shots/gallery"
var i := -1
var f := 0
var lvl
var Game


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	if a.size() > 1:
		var keep := []
		for sh in shots:
			for k in range(1, a.size()):
				if str(sh.out).contains(a[k]):
					keep.append(sh)
					break
		shots = keep
	DirAccess.make_dir_recursive_absolute(out_dir)


func _release_all() -> void:
	for a in ["move_right", "move_left", "jump", "grapple", "zip", "throw", "snap", "pivot"]:
		Input.action_release(a)


func _process(_dt: float) -> bool:
	if Game == null:
		Game = root.get_node("Game")
		Game.main = root
	if i < 0 or f > 140:
		_release_all()
		i += 1
		f = 0
		if i >= shots.size():
			quit()
			return false
		var s: Dictionary = shots[i]
		var data: Dictionary = Game.generate_level(s.seed, s.theme, 0.6, 12)
		if s.act.begins_with("split"):
			var n := 2 if s.act == "split2" else 4
			var locals := []
			for k in n:
				locals.append({"input": PlayerInput.new(PlayerInput.KBM if k == 0 else k - 1), "name": "P%d" % (k + 1), "color": Game.player_palette(k)})
			lvl = Game.play_level(data, "couch", locals)
		else:
			lvl = Game.play_level(data)
		return false
	f += 1
	var s: Dictionary = shots[i]
	var r = lvl.runners[0]
	var p = r.player
	if f == 4:
		var route: Array = lvl.level_data.route
		var pos: Vector2
		if s.idx < 0:
			pos = lvl.basket_pos + Vector2(-520, -4)
		else:
			var pt: Array = route[clampi(s.idx, 0, route.size() - 1)]
			pos = Vector2(pt[0], pt[1] - 4)
		for rr in lvl.runners:
			rr.player.respawn(pos + Vector2(-rr.index * 70, 0))
			rr.camera.position = rr.player.center()
			rr.camera.reset_physics_interpolation()
		p.aim_override = p.center() + Vector2(500, -260)
	match s.act:
		"run", "split2", "split4":
			if f == 8:
				Input.action_press("move_right")
			if f == 30:
				Input.action_press("jump")
			if f == 70:
				Input.action_press("throw")
		"throw":
			if f == 8:
				Input.action_press("move_right")
				Input.action_press("throw")
			if f == 40:
				Input.action_press("snap")
				Input.action_release("throw")
		"charge":
			if f >= 10:
				# hold a mid-run charge so the HUD/overlay show it
				Input.action_press("throw")
				p.has_disc = true
				p.charging = true
				p.charge_t = minf(0.6, (f - 10) * 0.03)
				p.move_factor = 0.55
				p.aim_override = p.center() + Vector2(420, -260)
			if f == 20:
				r.hud.flow_event("CATCH")
				r.hud.flow_event("SNAP")
				r.hud.flow_event("SKIP")
				r.hud.popup("SKY CATCH", r.disc.color, 2.0)
				r.hud.snap_popup("PERFECT SNAP", Color(0.4, 2.4, 1.2))
		"pivot":
			if f >= 10:
				p.has_disc = true
				p.state = 3
				p.pivot_t = 0.5
				p.pivot_stored = Vector2(520, -120)
				p.velocity = Vector2.ZERO
				Input.action_press("throw")
				Input.action_press("pivot")
				p.charging = true
				p.charge_t = 0.7
				p.move_factor = 0.0
				p.aim_override = p.center() + Vector2(380, -300)
		"putt":
			if f == 6:
				p.aim_override = lvl.basket_pos + Vector2(0, -200)
				Input.action_press("throw")
			if f == 30:
				Input.action_press("snap")
				Input.action_release("throw")
		"swing", "zip":
			if f == 6:
				var best = null
				var bd := INF
				for gp in r.grapple_points:
					var d: float = gp.global_position.distance_to(p.center())
					if d < bd and d > 120:
						bd = d
						best = gp
				if best:
					var gpos: Vector2 = best.global_position
					p.respawn(gpos + Vector2(-260, 230))
					r.camera.position = p.center()
					r.camera.reset_physics_interpolation()
					p.aim_override = gpos
			if f == 8:
				Input.action_press("grapple" if s.act == "swing" else "zip")
				p.velocity = Vector2(500, 0)
			if f == 30:
				Input.action_press("move_right")
	var cap := 34 if s.act == "charge" else (62 if s.act == "pivot" else 0)
	if cap == 0:
		cap = 70 if s.act in ["swing", "zip"] else (75 if s.act == "throw" else (60 if s.act == "putt" else 100))
	if f == cap:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, s.out])
		print("saved ", s.out)
		f = 1000
	return false
