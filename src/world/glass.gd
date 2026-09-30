extends Node2D
## Breakable glass wall. Shatters from a dash, a fast body or a fast disc.

var rect := Rect2()
var th: Dictionary = {}
var body: StaticBody2D
var broken := false
var level: Node = null
var t := 0.0


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	rect = Rect2(data.r[0], data.r[1], data.r[2], data.r[3])
	body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("glass", true)
	body.set_meta("rect", rect)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rect.size
	cs.shape = sh
	cs.position = rect.get_center()
	body.add_child(cs)
	add_child(body)


func set_physics_layer(bits: int) -> void:
	body.collision_layer = bits


func shatter(_vel: Vector2) -> void:
	if broken:
		return
	broken = true
	for c in body.get_children():
		(c as CollisionShape2D).set_deferred("disabled", true)
	if level:
		level.spawn_burst(rect.get_center(), th.get("accent2", Color(0.5, 1.5, 2)), 40, rect.size)
		level.play_sfx("glass", rect.get_center())
		level.shake(6.0)
	queue_redraw()


func reset() -> void:
	broken = false
	for c in body.get_children():
		(c as CollisionShape2D).set_deferred("disabled", false)
	queue_redraw()


func _draw() -> void:
	if broken:
		return
	var c: Color = th.get("accent2", Color(0.5, 1.5, 2.0))
	draw_rect(rect, Color(c, 0.18))
	draw_rect(rect, Color(c, 0.9), false, 2.0)
	var y := rect.position.y + 20.0
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x + 3, y), Vector2(rect.end.x - 3, y - 14), Color(2, 2, 2, 0.35), 1.5)
		y += 46.0
