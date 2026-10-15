extends Node2D
## Battle Rush arrow. `friendly` arrows (the bow) hurt enemies, the rest hurt
## the player. Stepped in _physics_process with the level's world clock like
## every other moving thing, so replays see the same flight.

const Perf = preload("res://src/core/perf.gd")
const Weapons = preload("res://src/combat/weapons.gd")

var level: Node = null
var friendly := false
var vel := Vector2.ZERO
var dmg := 1.0
var gravity := 0.0
var life := 2.5
var color := Color(2, 1, 0.5)
var pierce := false
var _hit: Array = []


static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p0: float = a[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.00001:
			if p0 < lo or p0 > hi:
				return false
		else:
			var ta := (lo - p0) / dd
			var tb := (hi - p0) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true


func _ready() -> void:
	add_to_group("battle_arrows")
	z_index = 5
	rotation = vel.angle()


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_step(dt)
	if Perf.on:
		Perf.end("arrow.tick", _pt)


func _step(dt: float) -> void:
	if level == null:
		queue_free()
		return
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	vel.y += gravity * dt
	var to := from + vel * dt
	# stops at solid ground / walls (layer 1 holds the shared world and the arena doors)
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	var res := get_world_2d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		level.spawn_burst(res.position, color * 0.8, 4)
		queue_free()
		return
	global_position = to
	rotation = vel.angle()
	if friendly:
		for e in level.enemies:
			if not is_instance_valid(e) or not e.alive() or _hit.has(e):
				continue
			if seg_hits_rect(from, to, e.hurt_rect()):
				_hit.append(e)
				e.take_hit(dmg, from.x, 180.0, false, 0.0)
				level.battle_sfx("hit", to)
				if not pierce:
					queue_free()
					return
	else:
		var pl = level.battle_player()
		if pl != null and pl.state != pl.DEAD and seg_hits_rect(from, to, pl.hurt_rect()):
			pl.battle_hit(from, "arrow")
			level.spawn_burst(to, color, 8)
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	draw_line(Vector2(-26, 0), Vector2(6, 0), Color(c, 0.18), 7.0)
	draw_line(Vector2(-22, 0), Vector2(6, 0), c, 3.0)
	draw_polygon(PackedVector2Array([Vector2(12, 0), Vector2(2, -5), Vector2(2, 5)]), PackedColorArray([c, c, c]))
	draw_line(Vector2(-22, 0), Vector2(-28, -4), Color(c, 0.8), 2.0)
	draw_line(Vector2(-22, 0), Vector2(-28, 4), Color(c, 0.8), 2.0)
