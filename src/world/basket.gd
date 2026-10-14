extends Node2D
## Disc golf basket (visual). Scoring logic lives in disc.gd.
## Origin is the ground point under the pole.

const Perf = preload("res://src/core/perf.gd")

## Geometry, shared with the scoring in disc.gd (y is up = negative). 50%
## bigger than the original basket and set lower: the catch zone now spans
## from the band down to just above the base.
const HALF_W := 48.0          # top band / tray rim half-width
const BAND_TOP := -141.0
const BAND_BOT := -129.0
const CHAIN_HALF := 39.0      # chains catch zone half-width
const CHAIN_TOP := -129.0
const CHAIN_BOT := -60.0
const TRAY_HALF := 45.0
const TRAY_TOP := -57.0
const TRAY_BOT := -30.0
const POLE_HALF := 6.0
const CATCH_Y := -44.0        # where a caught disc settles (in the tray)
const SPIT_X := 21.0          # hot discs this far off-centre bounce off the chains (no snap at all)
const SPIT_SPEED := 1500.0    # "hot"

var th: Dictionary = {}
var t := 0.0
var shake := 0.0
var scored := false
## Mounted sideways (radians its up is turned by: -PI/2 = on a wall to its
## right, facing left) / floating in the air (no pole down to a base).
var rot := 0.0
var floating := false


func _physics_process(dt: float) -> void:
	t += dt
	shake = maxf(0.0, shake - dt * 2.5)
	queue_redraw()


func hit(strength: float) -> void:
	shake = clampf(strength / 900.0, 0.3, 1.0)


func _draw() -> void:
	var _pt := Perf.begin()
	_draw_timed()
	if Perf.on:
		Perf.end("basket.draw", _pt)


func _draw_timed() -> void:
	var metal := Color(0.75, 0.78, 0.82)
	var gc: Color = th.get("basket", Color(2.2, 2.0, 0.3))
	# beacon column (visible from afar)
	var beacon := Color(gc, 0.07 + 0.03 * sin(t * 3.0))
	var m := Vector2(0, -85).rotated(rot)       # always straight up from the chains
	draw_rect(Rect2(m.x - 24, m.y - 1355, 48, 1300), beacon)
	draw_rect(Rect2(m.x - 8, m.y - 1355, 16, 1300), Color(gc, 0.08))
	draw_set_transform(Vector2.ZERO, rot)
	if floating:
		# hovering: a glow under the tray instead of a pole down to a base
		var hv := 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(Vector2(0, TRAY_BOT + 10), 16 + 4 * hv, Color(gc, 0.18))
		draw_circle(Vector2(0, TRAY_BOT + 10), 7, Color(gc, 0.5))
		draw_line(Vector2(0, TRAY_BOT), Vector2(0, BAND_TOP), metal, 7.0)
	else:
		# base (on a wall: the mounting plate)
		draw_rect(Rect2(-30, -5, 60, 5), metal)
		# pole
		draw_line(Vector2(0, 0), Vector2(0, BAND_TOP), metal, 7.0)
	# tray
	var tl := Vector2(-HALF_W, TRAY_TOP)
	var tr := Vector2(HALF_W, TRAY_TOP)
	var br := Vector2(HALF_W - 9, TRAY_BOT)
	var bl := Vector2(-HALF_W + 9, TRAY_BOT)
	draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]), Color(0.25, 0.25, 0.28))
	draw_polyline(PackedVector2Array([tl, bl, br, tr]), gc, 4.0)
	draw_line(tl, tr, gc, 3.0)
	# chains: catenary strands from the band down into the tray
	var sway := sin(t * 18.0) * 9.0 * shake
	for i in 11:
		var fx := -36.0 + i * 7.2
		var top := Vector2(fx * 0.5, BAND_BOT)
		var bot := Vector2(fx + sway * (1.0 - absf(fx) / 45.0), CHAIN_BOT + 2.0)
		var mid := (top + bot) * 0.5 + Vector2(sway * 0.6, 6)
		draw_polyline(PackedVector2Array([top, mid, bot]), Color(0.85, 0.88, 0.95, 0.9), 2.0)
	# top band
	var band := Rect2(-HALF_W, BAND_TOP, HALF_W * 2.0, BAND_BOT - BAND_TOP)
	draw_rect(band, gc)
	draw_rect(band, Color(1, 1, 1, 0.5), false, 1.5)
	# flag
	var fy := BAND_TOP
	draw_line(Vector2(0, fy), Vector2(0, fy - 52), metal, 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, fy - 52), Vector2(36 + sin(t * 6.0) * 4.0, fy - 41), Vector2(0, fy - 30)]), gc)
