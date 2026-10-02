extends AnimatableBody2D
## Moving platform. Oscillates between base and base+move (cosine ease).

const Perf = preload("res://src/core/perf.gd")

var base_pos := Vector2.ZERO
var move := Vector2.ZERO
var period := 3.0
var phase := 0.0
var size := Vector2(128, 16)
var th: Dictionary = {}
var t := 0.0


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	var r: Array = data.r
	base_pos = Vector2(r[0], r[1])
	size = Vector2(r[2], r[3])
	move = Vector2(data.move[0], data.move[1])
	period = float(data.get("period", 3.0))
	phase = float(data.get("phase", 0.0))
	position = base_pos
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	cs.position = size * 0.5
	add_child(cs)
	set_meta("rect", Rect2(base_pos, size))


func reset() -> void:
	t = 0.0
	position = base_pos
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_physics_process_timed(dt)
	if Perf.on:
		Perf.end("mover.tick", _pt)


func _physics_process_timed(dt: float) -> void:
	t += dt
	position = base_pos + move * (0.5 - 0.5 * cos((t / period + phase) * TAU))
	set_meta("rect", Rect2(position, size))


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("mover.draw", _pt)


func _draw_timed() -> void:
	var c: Color = th.get("accent", Color(2, 0.5, 1.5))
	var body: Color = th.get("block", Color(0.2, 0.2, 0.3))
	draw_rect(Rect2(Vector2.ZERO, size), body)
	draw_rect(Rect2(Vector2.ZERO, size), c, false, 2.5)
	draw_line(Vector2(4, 4), Vector2(size.x - 4, 4), Color(c, 0.6), 2.0)
	# path hint (drawn relative)
	var off := base_pos - position
	draw_dashed_line(off + size * 0.5, off + size * 0.5 + move, Color(c, 0.25), 2.0, 10.0)
