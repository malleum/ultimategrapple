extends VBoxContainer
## Results card disc cam: the last 10 s of the run seen from the disc, from
## the hand that carries it to the chains. With "lock" on (the default,
## remembered in settings) the disc stays level and upright in the middle of
## the view and the world turns around it: a hammer flipping over turns the
## world upside down, a tilt tilts it. With lock off the world stays upright
## and the disc tilts.
##
## A SubViewport shares the level's World2D. The runner's live body, disc,
## ghost and overlays are moved to RUNNER_BIT for as long as the cam exists
## (the cam leaves that bit out); the puppet runner and disc drawn here live
## on CAM_BIT, which the main view leaves out.

const PlayerVisual = preload("res://src/player/player_visual.gd")
const Background = preload("res://src/fx/background.gd")
const UI = preload("res://src/ui/ui.gd")

const CAM_BIT := 17
const RUNNER_BIT := 18
const VIEW := Vector2i(640, 360)
const HOLD := 1.2           # seconds on the last frame before looping
const SLOWMO := 0.35        # playback speed around the moment it hits the chains
const SLOWMO_TICKS := 45    # ... for this many ticks either side

var runner: Node
var frames: Array = []
var score_at := 0
var sv: SubViewport
var bg: Node2D
var puppet: Node2D
var disc_draw: DiscDraw
var lock_btn: Button
var bar: ProgressBar
var t := 0.0               # playback position in ticks
var hold_t := 0.0
var cam_pos := Vector2.ZERO
var cam_rot := 0.0
var flip := 1.0            # smoothed y mirror: -1 = disc upside down
var _main_vp: Viewport
var _main_mask := 0


## The disc as seen in the cam (world space, on CAM_BIT) plus a short trail.
class DiscDraw:
	extends Node2D
	var color := Color(2, 0.5, 1.5)
	var ang := 0.0
	var squash := 0.3
	var trail := PackedVector2Array()

	func _draw() -> void:
		var inv := global_transform.affine_inverse()
		if trail.size() > 1:
			var pts := PackedVector2Array()
			for p in trail:
				pts.append(inv * p)
			draw_polyline(pts, Color(color, 0.35), 3.0, true)
		var pts2 := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts2.append(Vector2(cos(a) * 14.0, sin(a) * 14.0 * absf(squash)).rotated(ang))
		draw_colored_polygon(pts2, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5))
		pts2.append(pts2[0])
		draw_polyline(pts2, color, 2.5, true)
		# a bright rim on the disc's top face, so upside down reads as upside down
		var top := Vector2(0, -14.0 * squash).rotated(ang)
		draw_line(-Vector2(11, 0).rotated(ang) + top * 0.5, Vector2(11, 0).rotated(ang) + top * 0.5, Color(2.2, 2.2, 2.2), 1.6, true)


func setup(p_runner: Node) -> void:
	runner = p_runner
	var clip: Dictionary = runner.pov_frames()
	frames = clip.frames
	score_at = int(clip.score_at)
	add_theme_constant_override("separation", 8)

	var title := UI.label("DISC CAM", 18, Color(1, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(title)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.custom_minimum_size = Vector2(VIEW)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	sv = SubViewport.new()
	sv.size = VIEW
	sv.world_2d = runner.player.get_world_2d()
	sv.use_hdr_2d = true
	sv.physics_object_picking = false
	sv.handle_input_locally = false
	sv.audio_listener_enable_2d = false
	sv.canvas_cull_mask = 1 | (1 << CAM_BIT)
	cont.add_child(sv)

	bg = Background.new()
	sv.add_child(bg)
	bg.setup(runner.level.th, null, false)

	puppet = PlayerVisual.new()
	puppet.color = runner.player.visual.color
	puppet.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	puppet.visibility_layer = 1 << CAM_BIT
	puppet.z_index = runner.player.z_index
	sv.add_child(puppet)
	disc_draw = DiscDraw.new()
	disc_draw.color = runner.disc.color
	disc_draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	disc_draw.visibility_layer = 1 << CAM_BIT
	disc_draw.z_index = 20
	sv.add_child(disc_draw)

	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	lock_btn = UI.button("", _toggle_lock)
	lock_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(lock_btn)
	_update_lock_text()

	# hide the live runner from the cam, the cam's puppet from the main view
	runner.set_body_layer(1 << RUNNER_BIT)
	_main_vp = runner.player.get_viewport()
	_main_mask = _main_vp.canvas_cull_mask
	_main_vp.canvas_cull_mask = _main_mask & ~(1 << CAM_BIT)
	_restart()


func _exit_tree() -> void:
	if is_instance_valid(runner):
		runner.set_body_layer(1)
	if is_instance_valid(_main_vp):
		_main_vp.canvas_cull_mask = _main_mask


func lock_on() -> bool:
	return bool(Game.settings.get("disc_cam_lock", true))


func _toggle_lock() -> void:
	Game.settings["disc_cam_lock"] = not lock_on()
	Game.save_settings()
	_update_lock_text()


func _update_lock_text() -> void:
	lock_btn.text = "LOCK TO DISC: %s" % ("ON" if lock_on() else "OFF")


func _restart() -> void:
	t = 0.0
	hold_t = 0.0
	if frames.is_empty():
		return
	var f: Array = frames[0]
	cam_pos = f[1]
	var pz: Vector2 = f[2]
	cam_rot = pz.x if lock_on() else 0.0
	flip = (-1.0 if pz.y < 0.0 else 1.0) if lock_on() else 1.0
	disc_draw.trail.clear()


func _sample(k: float) -> Array:
	var i := clampi(int(k), 0, frames.size() - 1)
	var j := mini(i + 1, frames.size() - 1)
	return [frames[i], frames[j], clampf(k - i, 0.0, 1.0)]


func _process(dt: float) -> void:
	if frames.size() < 2 or not is_instance_valid(runner):
		return
	var last := float(frames.size() - 1)
	if t >= last:
		hold_t += dt
		if hold_t > HOLD:
			_restart()
	else:
		var near_score := absf(t - score_at) < SLOWMO_TICKS
		t = minf(t + dt * Engine.physics_ticks_per_second * (SLOWMO if near_score else 1.0), last)
	var s := _sample(t)
	var a: Array = s[0]
	var b: Array = s[1]
	var k: float = s[2]
	var fa: Array = a[0]
	var fb: Array = b[0]
	# puppet runner
	var pa := Vector2(fa[0], fa[1])
	var pb := Vector2(fb[0], fb[1])
	if pa.distance_to(pb) > 200.0:   # a respawn: don't streak across the map
		k = 0.0
	puppet.position = pa.lerp(pb, k)
	puppet.visible = int(fa[5]) & 32 == 0
	puppet.update_from_snapshot(fa, puppet.position, dt)
	# disc
	var dp: Vector2 = (a[1] as Vector2).lerp(b[1], k)
	var pz: Vector2 = a[2]
	disc_draw.position = dp
	disc_draw.ang = lerp_angle(pz.x, (b[2] as Vector2).x, k)
	disc_draw.squash = pz.y
	disc_draw.trail.append(dp)
	if disc_draw.trail.size() > 40:
		disc_draw.trail = disc_draw.trail.slice(-40)
	disc_draw.queue_redraw()
	# camera: rides the disc; with lock, turns and mirrors with it
	var lock := lock_on()
	if cam_pos.distance_to(dp) > 300.0:
		cam_pos = dp
	cam_pos = cam_pos.lerp(dp, 1.0 - exp(-18.0 * dt))
	cam_rot = lerp_angle(cam_rot, disc_draw.ang if lock else 0.0, 1.0 - exp(-14.0 * dt))
	var want_flip := (-1.0 if pz.y < 0.0 else 1.0) if lock else 1.0
	flip = move_toward(flip, want_flip, dt * 4.0)
	var fy := flip if absf(flip) > 0.05 else 0.05 * signf(flip + 0.0001)
	var z: float = runner.camera.zoom.x if runner.camera else 0.85
	z *= Vector2(sv.size).x / float(runner.player.get_viewport().get_visible_rect().size.x) * 1.6
	var c := Vector2(sv.size) * 0.5
	sv.canvas_transform = Transform2D.IDENTITY.translated(-cam_pos).rotated(-cam_rot).scaled(Vector2(z, z * fy)).translated(c)
	if bg.sky_mat:
		bg.sky_mat.set_shader_parameter("view_rot", cam_rot)
		bg.sky_mat.set_shader_parameter("view_flip", fy)
		bg.sky_mat.set_shader_parameter("cam", cam_pos)
	bar.value = t / last
