extends SceneTree
## Disc cam screenshots of a high hammer into the chains (needs a display).
##   godot --headless --fixed-fps 120 -s tools/shot_hammer.gd                 -> prints where it comes down
##   xvfb-run godot --fixed-fps 120 -s tools/shot_hammer.gd -- --basket X --shot out_prefix
## The run is seeded, so both passes fly the same path: the probe finds where
## the hammer drops through chain height, the second pass puts the basket there.

const ThrowTypes = preload("res://src/disc/throw_types.gd")
const Disc = preload("res://src/disc/disc.gd")
var DEG := 58.0
var x141 := 0.0

var lvl
var f := 0
var started := false
var basket_x := 40000.0
var probe := true
var shot := ""
var aim := Vector2.ZERO
var launched := false
var apex := INF
var cam
var targets: Array = []
var taken := 0


func _level() -> Dictionary:
	return {"version": 2, "id": "shot_hammer", "name": "Hammer", "theme": "field", "seed": 1, "difficulty": 0.1,
		"spawn": [0, 0], "basket": [basket_x, 0], "kill_y": 3000, "bounds": [-1500, -6000, 60000, 9000],
		"solids": [{"r": [-1400, 0, 60000, 600], "k": "ground"}], "polys": [], "entities": [],
		"route": [[0, 0], [basket_x, 0]], "segments": [], "sections": [],
		"medals": {"par": 6.0, "ace": 2.0, "gold": 6.0, "silver": 9.0, "bronze": 14.0}}


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		var a := OS.get_cmdline_user_args()
		var bi := a.find("--basket")
		if bi >= 0:
			basket_x = float(a[bi + 1])
			probe = false
		var di := a.find("--deg")
		if di >= 0:
			DEG = float(a[di + 1])
		var si := a.find("--shot")
		if si >= 0:
			shot = a[si + 1]
		G.main = root
		G.records.erase("shot_hammer")
		seed(4242)
		lvl = G.play_level(_level())
		lvl.player.throw_type = 2
		lvl.runners[0].inp.mouse_world_fn = func() -> Vector2: return aim
		return false
	f += 1
	var r = lvl.runners[0]
	var p = r.player
	aim = p.center() + Vector2.RIGHT.rotated(-deg_to_rad(DEG)) * 500.0
	if f == 10:
		Input.action_press("move_right")
	if f == 80:
		Input.action_release("move_right")
	if f == 100:
		Input.action_press("throw")
	if f == 160:
		Input.action_release("throw")
	if not launched and r.disc.state == Disc.FLIGHT:
		# replace whatever the inputs produced with a clean full-power, perfectly
		# snapped hammer along the aim (no snap key timing in a script)
		launched = true
		var dir := Vector2.RIGHT.rotated(-deg_to_rad(DEG))
		var lp := ThrowTypes.launch_params(ThrowTypes.get_type(2), 1.0, 1.0, 0.0, 0.0)
		r.disc.launch(r.disc.global_position, dir * float(lp.speed), 2, lp.spin, 0.0, lp.wobble, lp.quality)
	if probe:
		if launched:
			apex = minf(apex, r.disc.global_position.y)
			if r.disc.velocity.y > 0.0 and r.disc.global_position.y > -141.0 and x141 == 0.0:
				x141 = r.disc.global_position.x
			if r.disc.velocity.y > 0.0 and r.disc.global_position.y > -95.0:
				print("deg %.0f: comes down through chain height at x=%.0f (x=%.0f at lid height; apex y=%.0f, %d ticks after release, upside down=%s)" % [DEG, r.disc.global_position.x, x141, apex, int(r.disc.age * 120), r.disc.pose().y < 0.0])
				quit(0)
				return true
		if f > 120 * 20:
			print("probe: no landing")
			quit(1)
			return true
		return false
	if OS.get_environment("DBG") != "" and launched and r.disc.global_position.y > -300 and f % 2 == 0 and r.disc.state != Disc.REST:
		print("f%d disc %s v %s state %d" % [f, r.disc.global_position.round(), r.disc.velocity.round(), r.disc.state])
	if r.done and cam == null and f % 10 == 0:
		cam = _find_cam(lvl)
		if cam:
			_pick_targets()
			if shot == "":
				quit(0)
				return true
	if cam and taken < targets.size() and cam.hold_t == 0.0 and cam.t >= float(targets[taken][0]):
		var img: Image = cam.sv.get_texture().get_image()
		var path := "%s_%d.png" % [shot, taken]
		img.save_png(path)
		print("saved %s  %s  frame %d  view turned %.0f deg, %s" % [path, targets[taken][1], int(cam.t), rad_to_deg(cam.cam_rot), "upside down" if cam.flip < -0.5 else ("flipping" if cam.flip < 0.5 else "upright")])
		taken += 1
		if taken >= targets.size():
			quit(0)
			return true
	if f > 120 * 60:
		print("timed out: done=%s cam=%s" % [r.done, cam != null])
		quit(1)
		return true
	return false


func _pick_targets() -> void:
	var fr: Array = cam.frames
	var fi := 0
	while fi < fr.size() and int((fr[fi][0] as Array)[10]) == 0:
		fi += 1
	var flip_i := fi
	while flip_i < fr.size() and (fr[flip_i][2] as Vector2).y >= 0.0:
		flip_i += 1
	var sa: int = cam.score_at
	targets = [[maxi(fi - 40, 0), "in hand, running"], [fi + 14, "climbing"], [flip_i + 70, "flipped over"],
		[(flip_i + 70 + sa) / 2, "coming down"], [sa - 14, "diving at the chains"], [sa + 40, "in the chains"]]
	print("clip %d frames: release %d, flip %d, chains %d" % [fr.size(), fi, flip_i, sa])


func _find_cam(n: Node):
	if n.get_script() and n.get_script().resource_path.ends_with("disc_cam.gd"):
		return n
	for c in n.get_children():
		var x = _find_cam(c)
		if x:
			return x
	return null
