extends Node2D
## Battle Rush arena: the way in closes behind the runner and the way out
## stays shut until every enemy in the arena is dead. Dying inside resets the
## fight and puts the runner back at the entrance. The leader arena has no way
## out: the run ends when its leader falls.

const Perf = preload("res://src/core/perf.gd")
const View = preload("res://src/world/view.gd")

enum { IDLE, LOCKED, CLEARED }

var id := 0
var th: Dictionary = {}
var level: Node = null
var rect := Rect2()          # the fighting floor (door to door)
var entry_rect := Rect2()
var exit_rect := Rect2()     # size 0: no way out (the leader's arena)
var spawn_pos := Vector2.ZERO
var leader := false
var state := IDLE
var entry_body: StaticBody2D
var exit_body: StaticBody2D
var t := 0.0
var left := 0                # enemies still alive, for the HUD


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	id = int(data.id)
	var r: Array = data.r
	rect = Rect2(r[0], r[1], r[2], r[3])
	var e: Array = data.entry
	entry_rect = Rect2(e[0], e[1], e[2], e[3])
	if data.get("exit") is Array and not (data.exit as Array).is_empty():
		var x: Array = data.exit
		exit_rect = Rect2(x[0], x[1], x[2], x[3])
	spawn_pos = Vector2(data.spawn[0], data.spawn[1])
	leader = bool(data.get("leader", false))
	entry_body = _door(entry_rect)
	if exit_rect.size.x > 0.0:
		exit_body = _door(exit_rect)
	reset()


func _door(r: Rect2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	b.add_child(cs)
	b.set_meta("rect", r)
	b.set_meta("slick", true)   # no wall-jumping up a door
	add_child(b)
	return b


func _set_door(b: StaticBody2D, closed: bool) -> void:
	if b == null:
		return
	b.process_mode = Node.PROCESS_MODE_INHERIT if closed else Node.PROCESS_MODE_DISABLED
	for c in b.get_children():
		(c as CollisionShape2D).set_deferred("disabled", not closed)


func reset() -> void:
	state = IDLE
	_set_door(entry_body, false)
	_set_door(exit_body, true)
	left = 0
	queue_redraw()


## Dying mid-fight: the arena starts over.
func reset_fight() -> void:
	# the dead stay dead; whoever is left goes back to patrolling
	var alive := 0
	for e in level.enemies:
		if is_instance_valid(e) and e.arena_id == id and e.alive():
			alive += 1
			e.calm()
	reset()
	if alive == 0 and not leader:
		_clear()


func _lock() -> void:
	state = LOCKED
	_set_door(entry_body, true)
	level.battle_sfx("gate", entry_rect.get_center())
	var r = level.runners[0] if not level.runners.is_empty() else null
	if r:
		r.hud.popup("ARENA LOCKED", Color(2.4, 0.5, 0.4), 1.2)


func _clear() -> void:
	state = CLEARED
	_set_door(entry_body, false)
	_set_door(exit_body, false)
	level.battle_sfx("gate", rect.get_center())
	var r = level.runners[0] if not level.runners.is_empty() else null
	if r and not leader:
		r.hud.popup("ARENA CLEAR", Color(0.5, 2.2, 0.8), 1.2)
		r.shake(4.0)


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_tick(dt)
	if Perf.on:
		Perf.end("arena.tick", _pt)


func _tick(dt: float) -> void:
	if View.sees(rect.grow(300.0)):
		t += dt
		queue_redraw()
	if not level.world_clock_on() or level.battle_over:
		return
	var alive := 0
	for e in level.enemies:
		if is_instance_valid(e) and e.arena_id == id and e.alive():
			alive += 1
	left = alive
	if state == IDLE:
		var pl = level.battle_player()
		if pl != null and pl.state != pl.DEAD:
			var p: Vector2 = pl.global_position
			if p.x > entry_rect.end.x + 90.0 and p.x < rect.end.x and p.y > rect.position.y - 700.0 and p.y < rect.end.y + 40.0:
				_lock()
	elif state == LOCKED and alive == 0:
		_clear()


func _draw() -> void:
	var c: Color = th.get("accent", Color(2, 0.5, 1.5))
	var locked := state == LOCKED
	var door_c := Color(2.4, 0.4, 0.35) if state != CLEARED else Color(0.4, 2.0, 0.8)
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	# a faint banner across the arena floor
	var fl := Rect2(rect.position.x, rect.end.y - 4.0, rect.size.x, 4.0)
	draw_rect(fl, Color(door_c, 0.25 + 0.2 * pulse * (1.0 if locked else 0.0)))
	for d in [[entry_rect, state == LOCKED], [exit_rect, state != CLEARED]]:
		var r: Rect2 = d[0]
		if r.size.x <= 0.0:
			continue
		var closed: bool = d[1]
		if closed:
			draw_rect(r, Color(door_c, 0.16))
			draw_rect(r, Color(door_c, 0.9), false, 3.0)
			var y := r.position.y + 16.0
			while y < r.end.y:
				draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y + 10.0), Color(door_c, 0.35), 2.0)
				y += 32.0
		else:
			# open: just the posts, so the way through reads clearly
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 12.0), Color(door_c, 0.5))
			draw_line(r.position, Vector2(r.position.x, r.end.y), Color(door_c, 0.18), 2.0)
	if state != CLEARED and (locked or leader):
		var font := ThemeDB.fallback_font
		var label := "KILL THE LEADER" if leader else "%d LEFT" % left
		if state == IDLE and not leader:
			label = ""
		if label != "":
			draw_string(font, Vector2(rect.position.x + 24.0, rect.end.y - 60.0 - 300.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(door_c, 0.35))
