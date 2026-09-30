extends SceneTree
## Headless flight test: prints carry distance / apex / flight time per throw type.
## godot --headless --fixed-fps 120 -s tools/sim_disc.gd

const Disc = preload("res://src/disc/disc.gd")
const ThrowTypes = preload("res://src/disc/throw_types.gd")

var discs := []
var frames := 0
var angles := [0.0, 8.0, 18.0, 30.0, 45.0]


func _initialize() -> void:
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(200000, 200)
	cs.shape = r
	floor_body.position = Vector2(0, 100)
	floor_body.add_child(cs)
	root.add_child(floor_body)
	for ti in ThrowTypes.count():
		for a in angles:
			var d := Disc.new()
			root.add_child(d)
			var ty = ThrowTypes.get_type(ti)
			d.launch(Vector2(0, -60), Vector2.RIGHT.rotated(-deg_to_rad(a)) * ty.speed, ti, 1.0, 0.0, 0.0)
			discs.append({"d": d, "type": ty.id, "angle": a, "apex": 0.0, "land_x": -1.0, "land_t": -1.0})


func _physics_process(_dt: float) -> bool:
	frames += 1
	for e in discs:
		var d = e.d
		e.apex = minf(e.apex, d.global_position.y)
		if e.land_x < 0 and d.state != Disc.FLIGHT:
			e.land_x = d.global_position.x
			e.land_t = frames / 120.0
	if frames > 120 * 12:
		for e in discs:
			print("%-9s %4.0f deg  carry %6.0f px (%5.1f tiles)  apex %5.0f  t=%4.2fs  final_x %6.0f" % [e.type, e.angle, e.land_x, e.land_x / 32.0, -e.apex, e.land_t, e.d.global_position.x])
		return true
	return false
