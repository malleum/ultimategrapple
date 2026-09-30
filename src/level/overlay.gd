extends Node2D
## World-space overlay: rope, grapple target marker, aim reticle and throw cone.

const Player = preload("res://src/player/player.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")

var level: Node = null
var _last_target: Node = null


func _init() -> void:
	z_index = 60
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if level == null or level.player == null:
		return
	var p = level.player
	var th: Dictionary = level.th
	var ppos: Vector2 = p.interp_pos()
	var hand: Vector2 = ppos + (p.hand() - p.global_position)
	var gcol: Color = th.get("grapple", Color(2, 2, 0.4))

	# ---- grapple target marker
	var tnode = p.target.get("node") if not p.target.is_empty() else null
	if _last_target != tnode:
		if is_instance_valid(_last_target):
			_last_target.targeted = false
		if tnode:
			tnode.targeted = true
		_last_target = tnode
	if not p.target.is_empty() and tnode == null and p.state != Player.DEAD:
		var tp: Vector2 = p.target.pos
		draw_line(tp + Vector2(-8, 0), tp + Vector2(8, 0), gcol, 2.0)
		draw_line(tp + Vector2(0, -8), tp + Vector2(0, 8), gcol, 2.0)
		draw_arc(tp, 12, 0, TAU, 16, Color(gcol, 0.6), 1.5)

	# ---- rope
	if (p.state == Player.SWING or p.state == Player.ZIP) and not p.anchors.is_empty():
		var pts := PackedVector2Array()
		pts.append(hand)
		for i in range(p.anchors.size() - 1, -1, -1):
			pts.append(p.anchors[i])
		var free_len: float = p.rope_len
		var d := hand.distance_to(pts[1])
		if p.state == Player.SWING and d < free_len - 8.0:
			# slack: sag the free segment
			var sag := minf((free_len - d) * 0.5, 80.0)
			var a := hand
			var b: Vector2 = pts[1]
			var curve := PackedVector2Array()
			for k in 13:
				var tt := k / 12.0
				curve.append(a.lerp(b, tt) + Vector2(0, sin(tt * PI) * sag))
			draw_polyline(curve, Color(gcol, 0.9), 2.5, true)
			var rest := PackedVector2Array()
			for i in range(1, pts.size()):
				rest.append(pts[i])
			if rest.size() > 1:
				draw_polyline(rest, gcol, 2.5, true)
		else:
			draw_polyline(pts, Color(gcol.r * 0.5, gcol.g * 0.5, gcol.b * 0.5, 0.4), 7.0, true)
			draw_polyline(pts, gcol, 2.5, true)
		for i in range(1, pts.size() - 1):
			draw_circle(pts[i], 3.0, gcol)

	# ---- reticle
	if p.state == Player.DEAD:
		return
	var m: Vector2 = get_global_mouse_position()
	var rc := Color(2.2, 2.2, 2.2, 0.9)
	draw_arc(m, 10, 0, TAU, 20, rc, 1.5, true)
	draw_circle(m, 1.8, rc)
	if p.charging:
		var power: float = p.charge_power()
		var oc: float = p.overcharge()
		var col: Color = level.disc.color if oc <= 0.0 else Color(2.2, 0.4, 0.3)
		draw_arc(m, 16, -PI * 0.5, -PI * 0.5 + TAU * power, 32, col, 3.0, true)
		# throw direction with sway + spread cone (move penalty)
		var ang: float = p.aim_dir.angle() + p.sway_angle()
		var spread: float = 0.035 * p.move_factor * 2.0 + 0.04 * oc * 2.0
		var dir := Vector2.RIGHT.rotated(ang)
		var len := 110.0 + power * 90.0
		draw_line(hand, hand + dir * len, Color(col, 0.8), 2.0, true)
		if spread > 0.004:
			draw_line(hand, hand + Vector2.RIGHT.rotated(ang - spread) * len * 0.85, Color(col, 0.3), 1.5, true)
			draw_line(hand, hand + Vector2.RIGHT.rotated(ang + spread) * len * 0.85, Color(col, 0.3), 1.5, true)
		# nose attitude tick at the end of the line
		var tip := hand + dir * len
		var nose_dir := Vector2.RIGHT.rotated(ang - p.nose * signf(dir.x if absf(dir.x) > 0.01 else 1.0))
		draw_line(tip - nose_dir * 12.0, tip + nose_dir * 12.0, Color(2.2, 2.2, 2.2), 2.5, true)
	elif p.state == Player.PIVOT:
		draw_arc(ppos + Vector2(0, -2), 26, 0, TAU, 24, Color(p.color * 1.6, 0.6), 2.0)
