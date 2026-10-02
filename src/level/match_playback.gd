extends Node
## Plays back a match recording (Game.load_match) inside a Level in "match"
## mode: every runner of the round as a puppet with their disc, on the race
## clock after the same countdown. The level's own runner is only the camera
## and HUD: its body is switched off. Left / right (move bindings) switch
## which runner the camera follows; restart re-watches.

const PlayerVisual = preload("res://src/player/player_visual.gd")
const DiscCam = preload("res://src/ui/disc_cam.gd")
const Bindings = preload("res://src/core/bindings.gd")
const UI = preload("res://src/ui/ui.gd")

const HZ := 30.0
const END_HOLD := 2.5

var level: Node
var rec: Dictionary
var puppets: Array = []    # [{visual, disc, frames, name, time}]
var follow := 0
var t := -1.0              # race clock; < 0 until the countdown ends
var length := 0.0
var hint: Label
var card: Control = null
var _layer: CanvasLayer


func _ready() -> void:
	rec = level.replay
	var r = level.runners[0]
	# the level's own runner is just the camera + HUD here
	for n in [r.player, r.disc]:
		n.visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
		n.collision_layer = 0
		n.collision_mask = 0
	r.pb_ghost.visible = false
	r.overlay.visible = false
	r.follow_fn = _follow_state
	for e in rec.runners:
		var vis := PlayerVisual.new()
		vis.color = e.color
		vis.name_tag = str(e.name)
		vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		vis.z_index = 5
		level.add_child(vis)
		var dd := DiscCam.DiscDraw.new()
		dd.color = Color(e.color) * 1.6
		dd.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		dd.z_index = 20
		dd.visible = false
		level.add_child(dd)
		var frames: Array = e.frames
		length = maxf(length, frames.size() / HZ)
		puppets.append({"visual": vis, "disc": dd, "frames": frames, "name": str(e.name), "time": float(e.time)})
		if not frames.is_empty():
			_apply(puppets[-1], 0.0, 0.0)
	# start on the winner
	for i in puppets.size():
		if puppets[i].name == str(rec.get("winner", "")):
			follow = i
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	hint = UI.label("", 20, Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 150)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(hint)
	_update_hint()
	level.start_countdown(float(rec.get("countdown", 3.0)))


func start() -> void:
	t = 0.0


func _follow_state() -> Array:
	if puppets.is_empty():
		return [level.spawn, Vector2.ZERO]
	var p: Dictionary = puppets[follow]
	var v: Node2D = p.visual
	return [v.position, v.vel]


func _update_hint() -> void:
	if puppets.is_empty():
		return
	var p: Dictionary = puppets[follow]
	var res := "  ·  %s" % Game.format_time(p.time) if p.time >= 0.0 else "  ·  DNF"
	hint.text = "%s  WATCHING %s%s  %s     %s re-watch" % [Bindings.label("move_left"), p.name.to_upper(), res,
		Bindings.label("move_right"), Bindings.label("restart")]


func _physics_process(dt: float) -> void:
	if puppets.is_empty() or get_tree().paused:
		return
	if Input.is_action_just_pressed("move_left"):
		follow = (follow + puppets.size() - 1) % puppets.size()
		_update_hint()
	elif Input.is_action_just_pressed("move_right"):
		follow = (follow + 1) % puppets.size()
		_update_hint()
	if Input.is_action_just_pressed("restart"):
		Game.play_match(str(rec.get("id", "")))
		return
	if t < 0.0:
		return
	t += dt
	for p in puppets:
		_apply(p, t, dt)
	if t > length + END_HOLD and card == null:
		_show_card()


func _apply(p: Dictionary, tt: float, dt: float) -> void:
	var frames: Array = p.frames
	if frames.is_empty():
		return
	var k := tt * HZ
	var i := clampi(int(k), 0, frames.size() - 1)
	var j := mini(i + 1, frames.size() - 1)
	var w := clampf(k - i, 0.0, 1.0)
	var fa: Array = frames[i]
	var fb: Array = frames[j]
	var pa := Vector2(fa[0], fa[1])
	var pb := Vector2(fb[0], fb[1])
	if pa.distance_to(pb) > 200.0:
		w = 0.0
	var vis: Node2D = p.visual
	vis.position = pa.lerp(pb, w)
	var f: Array = fa.duplicate()
	f[5] = int(fa[5])
	vis.update_from_snapshot(f, vis.position, dt)
	var dd = p.disc
	var shown: bool = fa.size() > 10 and int(fa[10]) != 0
	dd.visible = shown
	if shown:
		var dpa := Vector2(fa[8], fa[9])
		var dpb := Vector2(fb[8], fb[9]) if fb.size() > 10 and int(fb[10]) != 0 else dpa
		dd.position = dpa.lerp(dpb, w)
		if fa.size() >= 13:
			dd.ang = float(fa[11])
			dd.squash = float(fa[12])
		dd.queue_redraw()


func _show_card() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.015, 0.06, 0.92)
	sb.border_color = Color(1, 0.8, 0.3)
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label("%s  ·  %s" % [str(rec.name).to_upper(), "COUCH" if rec.get("mode", "") == "couch" else "ONLINE"], 28, Color(1, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER))
	var order := puppets.duplicate()
	order.sort_custom(func(a, b):
		var ta: float = a.time if a.time >= 0.0 else INF
		var tb: float = b.time if b.time >= 0.0 else INF
		return ta < tb)
	var place := 1
	for p in order:
		var line := "%d.  %s   %s" % [place, p.name, Game.format_time(p.time) if p.time >= 0.0 else "DNF"]
		v.add_child(UI.label(line, 22, Color(1, 1, 1) if place > 1 else UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		place += 1
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UI.button("WATCH AGAIN", func(): Game.play_match(str(rec.get("id", ""))), 22))
	h.add_child(UI.button("REPLAYS", func(): Game.goto_menu("replays"), 22))
	h.add_child(UI.button("MENU", func(): Game.goto_menu(), 22))
	v.add_child(h)
	card = CenterContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	_layer.add_child(card)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
