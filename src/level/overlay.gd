extends Node2D
## World-space overlay for one runner: reticle + charge ring, throw preview
## arc with spread wedge, grapple lock-on brackets, twisted rope, pivot
## momentum arrow. Colours stay close to LDR so the bloom doesn't smear them.

const Player = preload("res://src/player/player.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")

var runner: Node = null
var _last_target: Node = null
var t := 0.0
var lock_t := 0.0
var lock_pos := Vector2.ZERO
var full_flash := 0.0
var _was_full := false
## The cursor is drawn by its own node so a screen-reading shader can flip it
## dark over bright skies and bright over dark ones.
var reticle: Node2D

const RETICLE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	// average of what is behind the cursor (blurred mip so thin details don't flicker it)
	vec3 bg = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	float lum = dot(min(bg, vec3(1.0)), vec3(0.299, 0.587, 0.114));
	float k = smoothstep(0.42, 0.62, lum);
	vec3 c = COLOR.rgb;
	bool halo = max(c.r, max(c.g, c.b)) < 0.02;
	if (halo) {
		// outline: black on dark backgrounds, white on bright ones
		COLOR = vec4(vec3(k), COLOR.a * mix(1.0, 0.9, k));
	} else {
		// stroke: keep its hue but sink it to deep ink over bright backgrounds
		vec3 ink = c * 0.16 + vec3(0.06, 0.0, 0.12);
		COLOR = vec4(mix(c, ink, k), COLOR.a);
	}
}
"""


func _init() -> void:
	z_index = 60
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reticle = Node2D.new()
	var sh := Shader.new()
	sh.code = RETICLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	reticle.material = mat
	reticle.draw.connect(_draw_reticle)
	add_child(reticle)


func _process(dt: float) -> void:
	t += dt
	lock_t += dt
	full_flash = maxf(0.0, full_flash - dt * 3.0)
	reticle.visibility_layer = visibility_layer
	queue_redraw()
	reticle.queue_redraw()


static func _soft(c: Color, cap := 1.15) -> Color:
	var m := maxf(c.r, maxf(c.g, c.b))
	if m <= cap:
		return c
	return Color(c.r * cap / m, c.g * cap / m, c.b * cap / m, c.a)


func _draw() -> void:
	if runner == null or runner.player == null:
		return
	var p = runner.player
	var th: Dictionary = runner.level.th
	var ppos: Vector2 = p.interp_pos()
	var hand: Vector2 = ppos + (p.hand() - p.global_position)
	var gcol: Color = _soft(th.get("grapple", Color(2, 2, 0.4)))
	var dcol: Color = _soft(runner.disc.color)

	# ---------------------------------------------------------------- grapple lock
	var tnode = p.target.get("node") if not p.target.is_empty() else null
	if _last_target != tnode:
		if is_instance_valid(_last_target):
			_last_target.targeted = false
		if tnode:
			tnode.targeted = true
		_last_target = tnode
	var has_target: bool = not p.target.is_empty() and p.state != Player.DEAD
	if has_target:
		var tp: Vector2 = p.target.pos
		if tp.distance_to(lock_pos) > 4.0:
			lock_t = 0.0
		lock_pos = tp
		var e := 1.0 - pow(1.0 - clampf(lock_t / 0.14, 0.0, 1.0), 3.0)
		var rr := lerpf(42.0, 22.0, e)
		var rot := PI * 0.25 + (1.0 - e) * 0.8
		for i in 4:
			var a := rot + i * PI * 0.5
			var corner := tp + Vector2(cos(a), sin(a)) * rr
			var d1 := Vector2(cos(a + PI * 0.75), sin(a + PI * 0.75)) * 9.0
			var d2 := Vector2(cos(a - PI * 0.75), sin(a - PI * 0.75)) * 9.0
			draw_polyline(PackedVector2Array([corner + d1, corner, corner + d2]), Color(0, 0, 0, 0.5), 5.0, true)
			draw_polyline(PackedVector2Array([corner + d1, corner, corner + d2]), Color(gcol, e), 2.5, true)
		# marching "lock line" from hand to target
		if p.state == Player.NORMAL or p.state == Player.PIVOT:
			var dir := (tp - hand)
			var len := dir.length()
			dir /= maxf(len, 1.0)
			var off := fmod(t * 160.0, 22.0)
			var s := off
			while s < len - 28.0:
				draw_line(hand + dir * s, hand + dir * minf(s + 8.0, len), Color(gcol, 0.35 * e), 2.0)
				s += 22.0

	# ---------------------------------------------------------------- rope
	if (p.state == Player.SWING or p.state == Player.ZIP) and not p.anchors.is_empty():
		var pts := PackedVector2Array()
		pts.append(hand)
		for i in range(p.anchors.size() - 1, -1, -1):
			pts.append(p.anchors[i])
		var free_len: float = p.rope_len
		var d0 := hand.distance_to(pts[1])
		if p.state == Player.SWING and d0 < free_len - 8.0:
			var sag := minf((free_len - d0) * 0.5, 80.0)
			var curve := PackedVector2Array()
			for k in 15:
				var tt := k / 14.0
				curve.append(hand.lerp(pts[1], tt) + Vector2(0, sin(tt * PI) * sag))
			for i in range(2, pts.size()):
				curve.append(pts[i])
			pts = curve
		_rope(pts, gcol, p.state == Player.ZIP)
		for i in range(1, p.anchors.size()):
			draw_circle(p.anchors[i], 4.0, Color(0, 0, 0, 0.6))
			draw_circle(p.anchors[i], 2.5, gcol)

	if p.state == Player.DEAD:
		return

	# ---------------------------------------------------------------- pivot
	if p.state == Player.PIVOT:
		var pulse := 0.5 + 0.5 * sin(t * 10.0)
		var pc := _soft(Color(1.0, 0.45, 0.9))
		draw_arc(ppos + Vector2(0, -2), 24.0 + pulse * 4.0, 0, TAU, 32, Color(pc, 0.7), 2.0, true)
		draw_line(ppos + Vector2(-26, 0), ppos + Vector2(26, 0), Color(pc, 0.8), 3.0)
		var sv: Vector2 = p.pivot_stored
		if sv.length() > 40.0:
			var c: Vector2 = ppos + Vector2(0, -24)
			var tip := c + sv.normalized() * clampf(sv.length() * 0.12, 30.0, 120.0)
			draw_line(c, tip, Color(pc, 0.55), 4.0, true)
			var n := (tip - c).normalized()
			draw_colored_polygon(PackedVector2Array([tip + n * 10.0, tip + n.orthogonal() * 7.0, tip - n.orthogonal() * 7.0]), Color(pc, 0.7))

	if p.charging:
		var power: float = p.charge_power()
		var oc: float = p.overcharge()
		# predicted launch arc (first ~0.3s, ballistic) + spread wedge for movement penalty
		var ty: Dictionary = ThrowTypes.get_type(p.throw_type)
		var ang: float = p.aim_dir.angle() + p.sway_angle()
		var dir := Vector2.RIGHT.rotated(ang)
		var v0: Vector2 = dir * float(ty.speed) * power * 0.9 + p.velocity * 0.2
		var spread: float = 0.035 * p.move_factor * 2.0 + 0.04 * oc * 2.0
		if spread > 0.004:
			var wl := 150.0 + power * 110.0
			var wedge := PackedVector2Array([hand, hand + Vector2.RIGHT.rotated(ang - spread) * wl, hand + Vector2.RIGHT.rotated(ang + spread) * wl])
			draw_colored_polygon(wedge, Color(1.0, 0.6, 0.3, 0.1 + 0.1 * clampf(spread * 8.0, 0.0, 1.0)))
		var g := float(ty.grav) * 0.55
		for k in 10:
			var tt := 0.025 + k * 0.03
			var pos := hand + v0 * tt + Vector2(0, g) * tt * tt * 0.5
			var r := 4.0 - k * 0.3
			draw_circle(pos, r + 1.5, Color(0, 0, 0, 0.35))
			draw_circle(pos, r, Color(dcol, 0.95 - k * 0.08))
		# nose attitude marker at the start of the arc
		var tip := hand + v0 * 0.06
		var nd := dir.rotated(-p.nose * (1.0 if dir.x >= 0.0 else -1.0))
		draw_line(tip - nd * 14.0, tip + nd * 14.0, Color(0, 0, 0, 0.5), 5.0, true)
		draw_line(tip - nd * 14.0, tip + nd * 14.0, Color(1, 1, 1, 0.95), 2.5, true)


func _draw_reticle() -> void:
	if runner == null or runner.player == null:
		return
	var p = runner.player
	if p.state == Player.DEAD:
		return
	var c := reticle
	var th: Dictionary = runner.level.th
	var gcol: Color = _soft(th.get("grapple", Color(2, 2, 0.4)))
	var dcol: Color = _soft(runner.disc.color)
	var has_target: bool = not p.target.is_empty()
	var m: Vector2 = p.mouse_world_draw()
	# halo strokes are pure black: the shader turns them white over bright skies
	var halo := Color(0, 0, 0, 0.6)
	var rc := Color(1.0, 1.0, 1.0, 0.95) if not has_target else Color(gcol.lightened(0.25), 0.95)
	var spin := t * 0.7
	for i in 4:
		var a := spin + i * PI * 0.5
		c.draw_arc(m, 13.0, a + 0.25, a + PI * 0.5 - 0.25, 8, halo, 5.0, true)
		c.draw_arc(m, 13.0, a + 0.25, a + PI * 0.5 - 0.25, 8, rc, 2.5, true)
	c.draw_circle(m, 3.6, halo)
	c.draw_circle(m, 2.4, rc)
	if p.charging:
		var power: float = p.charge_power()
		var oc: float = p.overcharge()
		var full := power >= 0.999
		if full and not _was_full:
			full_flash = 1.0
		_was_full = full
		var segs := 16
		for i in segs:
			var a0 := -PI * 0.5 + i * TAU / segs + 0.05
			var a1 := a0 + TAU / segs - 0.1
			var on := float(i) / segs < (power - 0.3) / 0.7
			var col := dcol if oc <= 0.0 else Color(1.0, 0.35 + 0.25 * sin(t * 30.0), 0.3)
			c.draw_arc(m, 22.0, a0, a1, 4, halo, 7.0, true)
			c.draw_arc(m, 22.0, a0, a1, 4, Color(col, 0.95) if on else Color(0.6, 0.6, 0.6, 0.35), 4.0, true)
		if full_flash > 0.0:
			c.draw_arc(m, 22.0 + (1.0 - full_flash) * 16.0, 0, TAU, 32, Color(1, 1, 1, full_flash), 2.0, true)


func _rope(pts: PackedVector2Array, col: Color, zip: bool) -> void:
	draw_polyline(pts, Color(0, 0, 0, 0.45), 6.0, true)
	draw_polyline(pts, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55), 3.5, true)
	# twisted strand highlights
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var l := a.distance_to(b)
		if l < 0.5:
			continue
		var d := (b - a) / l
		var nrm := d.orthogonal()
		var s := fmod(-acc, 12.0)
		if zip:
			s = fmod(-acc + t * 260.0, 12.0)
		while s < l:
			if s >= 0.0:
				var p0 := a + d * s
				draw_line(p0 - nrm * 1.6, p0 + d * 5.0 + nrm * 1.6, col.lightened(0.35), 1.6, true)
			s += 12.0
		acc += l
