extends Node2D
## Disc gate: throwing the disc through the ring opens a door ("open") or
## materialises a bridge ("bridge").

var ring_pos := Vector2.ZERO
var door_rect := Rect2()
var mode := "open"
var triggered := false
var th: Dictionary = {}
var body: StaticBody2D
var anim := 0.0
var t := 0.0
var level: Node = null


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	ring_pos = Vector2(data.ring[0], data.ring[1])
	var r: Array = data.door
	door_rect = Rect2(r[0], r[1], r[2], r[3])
	mode = data.get("mode", "open")
	body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = door_rect.size
	cs.shape = sh
	cs.position = door_rect.get_center()
	body.add_child(cs)
	body.set_meta("rect", door_rect)
	add_child(body)
	_apply()


func _apply() -> void:
	var solid := (mode == "open" and not triggered) or (mode == "bridge" and triggered)
	body.process_mode = Node.PROCESS_MODE_INHERIT if solid else Node.PROCESS_MODE_DISABLED
	for c in body.get_children():
		(c as CollisionShape2D).set_deferred("disabled", not solid)


func trigger() -> void:
	if triggered:
		return
	triggered = true
	anim = 0.0
	_apply()
	if level:
		level.on_gate(self)


func reset() -> void:
	triggered = false
	anim = 0.0
	_apply()


func _physics_process(dt: float) -> void:
	t += dt
	anim = minf(anim + dt * 3.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var c: Color = th.get("accent", Color(2, 0.5, 1.5))
	var gc: Color = th.get("basket", Color(2, 2, 0.4))
	var ring_c := gc if not triggered else Color(0.4, 2.2, 0.8)
	# ring
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	draw_arc(ring_pos, 34.0, 0, TAU, 32, Color(ring_c, 0.25), 10.0)
	draw_arc(ring_pos, 34.0, 0, TAU, 32, ring_c, 3.0, true)
	if not triggered:
		draw_arc(ring_pos, 40.0 + pulse * 6.0, 0, TAU, 32, Color(ring_c, 0.35 * (1.0 - pulse)), 2.0)
		draw_circle(ring_pos, 5.0, Color(ring_c, 0.8))
	# link line ring -> door
	draw_dashed_line(ring_pos, door_rect.get_center(), Color(ring_c, 0.12), 2.0, 12.0)
	# door / bridge
	if mode == "open":
		var vis := 1.0 - anim if triggered else 1.0
		if vis > 0.01:
			var r := Rect2(door_rect.position, Vector2(door_rect.size.x, door_rect.size.y * vis))
			draw_rect(r, Color(c.r * 0.3, c.g * 0.3, c.b * 0.3, 0.9))
			draw_rect(r, c, false, 2.5)
			var y := r.position.y + 12
			while y < r.end.y:
				draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y), Color(c, 0.4), 2.0)
				y += 18.0
	else:
		if triggered:
			var r2 := Rect2(door_rect.position, Vector2(door_rect.size.x * anim, door_rect.size.y))
			draw_rect(r2, Color(c.r * 0.4, c.g * 0.4, c.b * 0.4))
			draw_line(r2.position, Vector2(r2.end.x, r2.position.y), c, 3.0)
		else:
			draw_dashed_line(door_rect.position, Vector2(door_rect.end.x, door_rect.position.y), Color(c, 0.35), 2.0, 14.0)
