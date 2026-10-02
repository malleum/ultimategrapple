extends Node2D
## Tapered motion ribbon behind a fast runner (drawn behind the runner itself).

const Perf = preload("res://src/core/perf.gd")

var runner: Node = null
var pts: Array = []
var amt := 0.0


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(dt: float) -> void:
	if runner == null or runner.player == null:
		return
	var p = runner.player
	var spd: float = p.velocity.length()
	amt = lerpf(amt, clampf((spd - 520.0) / 700.0, 0.0, 1.0), 1.0 - exp(-8.0 * dt))
	var c: Vector2 = p.interp_pos() + Vector2(0, -22)
	if p.state == 4:
		pts.clear()
	else:
		pts.push_front(c)
	while pts.size() > 14:
		pts.pop_back()
	queue_redraw()


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("speed_trail.draw", _pt)


func _draw_timed() -> void:
	if amt < 0.02 or pts.size() < 3:
		return
	var col: Color = runner.player.color
	for i in range(pts.size() - 1):
		var k := 1.0 - float(i) / pts.size()
		var w := 16.0 * k * amt
		var a: float = 0.22 * k * amt
		draw_line(pts[i], pts[i + 1], Color(col.r, col.g, col.b, a), w, true)
		draw_line(pts[i], pts[i + 1], Color(1, 1, 1, a * 0.6), w * 0.25, true)
