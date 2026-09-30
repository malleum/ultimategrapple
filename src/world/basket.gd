extends Node2D
## Disc golf basket (visual). Scoring logic lives in disc.gd.
## Origin is the ground point under the pole.

var th: Dictionary = {}
var t := 0.0
var shake := 0.0
var scored := false


func _physics_process(dt: float) -> void:
	t += dt
	shake = maxf(0.0, shake - dt * 2.5)
	queue_redraw()


func hit(strength: float) -> void:
	shake = clampf(strength / 900.0, 0.3, 1.0)


func _draw() -> void:
	var metal := Color(0.75, 0.78, 0.82)
	var gc: Color = th.get("basket", Color(2.2, 2.0, 0.3))
	# beacon column (visible from afar)
	var beacon := Color(gc, 0.07 + 0.03 * sin(t * 3.0))
	draw_rect(Rect2(-18, -1400, 36, 1300), beacon)
	draw_rect(Rect2(-6, -1400, 12, 1300), Color(gc, 0.08))
	# base
	draw_rect(Rect2(-22, -4, 44, 4), metal)
	# pole
	draw_line(Vector2(0, 0), Vector2(0, -112), metal, 5.0)
	# tray
	var tray := PackedVector2Array([Vector2(-32, -54), Vector2(32, -54), Vector2(26, -36), Vector2(-26, -36)])
	draw_colored_polygon(tray, Color(0.25, 0.25, 0.28))
	draw_polyline(PackedVector2Array([Vector2(-32, -54), Vector2(-26, -36), Vector2(26, -36), Vector2(32, -54)]), gc, 3.0)
	draw_line(Vector2(-32, -54), Vector2(32, -54), gc, 2.0)
	# chains: two rows of catenary strands
	var sway := sin(t * 18.0) * 6.0 * shake
	for i in 9:
		var fx := -24.0 + i * 6.0
		var top := Vector2(fx * 0.5, -104)
		var bot := Vector2(fx + sway * (1.0 - absf(fx) / 30.0), -58)
		var mid := (top + bot) * 0.5 + Vector2(sway * 0.6, 4)
		draw_polyline(PackedVector2Array([top, mid, bot]), Color(0.85, 0.88, 0.95, 0.9), 1.5)
	# top band
	draw_rect(Rect2(-32, -112, 64, 8), gc)
	draw_rect(Rect2(-32, -112, 64, 8), Color(1, 1, 1, 0.5), false, 1.0)
	# flag
	var fl := PackedVector2Array([Vector2(0, -112), Vector2(0, -150), Vector2(26 + sin(t * 6.0) * 3.0, -142), Vector2(0, -134)])
	draw_line(Vector2(0, -112), Vector2(0, -150), metal, 2.0)
	draw_colored_polygon(PackedVector2Array([fl[1], fl[2], fl[3]]), gc)
