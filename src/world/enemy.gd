extends Node2D
## Battle Rush enemy: grunt (melee), guard (shield), archer (ranged) and the
## leader (killing it ends the run). Origin is at the feet. Enemies stay on
## the flat floor between x0 and x1, so they need no physics, and they only
## think while Level.world_clock_on() (every attempt meets them the same way).

const Perf = preload("res://src/core/perf.gd")
const View = preload("res://src/world/view.gd")
const Weapons = preload("res://src/combat/weapons.gd")
const Arrow = preload("res://src/combat/arrow.gd")

enum { PATROL, CHARGE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

var kind := "grunt"
var cfg: Dictionary = {}
var th: Dictionary = {}
var level: Node = null
var arena_id := -1
var home := Vector2.ZERO
var x0 := 0.0
var x1 := 0.0
var hp := 1.0
var state := PATROL
var st := 0.0           # time left in WINDUP / STRIKE / RECOVER / STAGGER
var face := -1.0
var kx := 0.0           # knockback velocity
var shot_t := 0.0       # archer / leader: time until the next shot
var volley_t := 0.0
var flash := 0.0
var dead_t := 0.0
var struck := false
var t := 0.0


func setup(data: Dictionary, p_theme: Dictionary) -> void:
	th = p_theme
	kind = str(data.get("k", "grunt"))
	cfg = Weapons.ENEMIES[kind]
	arena_id = int(data.get("a", -1))
	home = Vector2(data.p[0], data.p[1])
	x0 = float(data.get("x0", home.x))
	x1 = float(data.get("x1", home.x))
	reset()


func reset() -> void:
	position = home
	hp = float(cfg.hp)
	state = PATROL
	st = 0.0
	face = -1.0
	kx = 0.0
	shot_t = 0.9
	volley_t = float(cfg.get("volley_every", 0.0)) * 0.6
	flash = 0.0
	dead_t = 0.0
	struck = false
	visible = true
	queue_redraw()


func alive() -> bool:
	return state != DEAD


func hurt_rect() -> Rect2:
	var w: float = cfg.w
	var h: float = cfg.h
	return Rect2(position.x - w * 0.5, position.y - h, w, h)


func center() -> Vector2:
	return position + Vector2(0, -float(cfg.h) * 0.55)


func _rage() -> float:
	return 1.0 + (0.35 if kind == "leader" and hp <= float(cfg.hp) * 0.5 else 0.0)


func shield_up() -> bool:
	return bool(cfg.get("shield", false)) and (state == PATROL or state == CHARGE or state == WINDUP)


## A hit from the player (sword, axe, pike, arrow). Returns whether it hurt.
func take_hit(dmg: float, from_x: float, knock: float, breaks_shield: bool, speed: float) -> bool:
	if state == DEAD:
		return false
	var from_front := signf(from_x - position.x) == face or absf(from_x - position.x) < 4.0
	if shield_up() and from_front and not breaks_shield and speed < float(cfg.get("pierce_speed", 650.0)):
		flash = 0.6
		level.battle_sfx("clang", center())
		level.spawn_burst(center() + Vector2(face * 16.0, 0), Color(2.2, 2.0, 1.2), 6)
		kx = -face * 90.0
		return false
	hp -= dmg
	flash = 1.0
	level.battle_sfx("hit", center())
	level.spawn_burst(center(), cfg.color, int(6 + dmg * 3.0))
	if hp <= 0.0:
		state = DEAD
		dead_t = 0.0
		level.on_enemy_killed(self)
		return true
	var stag: float = cfg.stagger
	if stag > 0.0:
		state = STAGGER
		st = stag
	kx = signf(position.x - from_x) * knock
	if kind == "leader":
		kx *= 0.3
	return true


func _physics_process(dt: float) -> void:
	var _pt := Perf.begin()
	_tick(dt)
	if Perf.on:
		Perf.end("enemy.tick", _pt)


func _tick(dt: float) -> void:
	if state == DEAD:
		dead_t += dt
		if dead_t < 0.6 or visible:
			visible = dead_t < 0.6
			queue_redraw()
		return
	flash = maxf(0.0, flash - dt * 4.0)
	if View.sees(hurt_rect().grow(300.0)):
		queue_redraw()
	if not level.world_clock_on() or level.battle_over:
		return
	t += dt
	# knockback slides along the floor, never off the patrol line
	if absf(kx) > 1.0:
		position.x = clampf(position.x + kx * dt, x0, x1)
		kx = move_toward(kx, 0.0, 1800.0 * dt)
	var pl = level.battle_player()
	var seen := false
	var dx := 0.0
	if pl != null and pl.state != pl.DEAD:
		var tp: Vector2 = pl.center()
		dx = tp.x - position.x
		var dy: float = tp.y - center().y
		seen = absf(dx) < float(cfg.sight) and absf(dy) < (230.0 if kind == "leader" else 150.0)
	match state:
		PATROL:
			_patrol(dt, seen, dx)
		CHARGE:
			_charge(dt, seen, dx, pl)
		WINDUP:
			if seen and absf(dx) > 8.0 and not bool(cfg.get("ranged", false)):
				face = signf(dx)   # tracks the player until the strike
			st -= dt
			if st <= 0.0:
				_begin_strike(pl, dx)
		STRIKE:
			st -= dt
			if bool(cfg.get("ranged", false)):
				state = RECOVER
				st = float(cfg.recover) / _rage()
			else:
				position.x = clampf(position.x + face * 120.0 * dt, x0, x1)   # lunges a little
				if not struck and pl != null:
					_strike_test(pl)
				if st <= 0.0:
					state = RECOVER
					st = float(cfg.recover) / _rage()
		RECOVER:
			st -= dt
			if st <= 0.0:
				state = CHARGE if seen and not bool(cfg.get("ranged", false)) else PATROL
		STAGGER:
			st -= dt
			if st <= 0.0:
				state = CHARGE if not bool(cfg.get("ranged", false)) else PATROL
	if kind == "leader" and state in [PATROL, CHARGE] and seen:
		volley_t -= dt
		if volley_t <= 0.0:
			volley_t = float(cfg.volley_every) / _rage()
			_fire(pl, int(cfg.volley), 0.22)


func _patrol(dt: float, seen: bool, dx: float) -> void:
	if bool(cfg.get("ranged", false)):
		if seen:
			face = signf(dx) if absf(dx) > 4.0 else face
			shot_t -= dt
			if shot_t <= 0.0:
				state = WINDUP
				st = float(cfg.windup)
		return
	if seen:
		state = CHARGE
		return
	if x1 - x0 < 4.0:
		return
	position.x += face * float(cfg.patrol) * dt
	if position.x <= x0:
		position.x = x0
		face = 1.0
	elif position.x >= x1:
		position.x = x1
		face = -1.0


func _charge(dt: float, seen: bool, dx: float, pl) -> void:
	if not seen and absf(dx) > float(cfg.sight) * 1.5:
		state = PATROL
		return
	if absf(dx) > 6.0:
		face = signf(dx)
	var dy: float = (pl.center().y - center().y) if pl != null else 0.0
	if absf(dx) < float(cfg.reach) * 0.85 and absf(dy) < 70.0:
		state = WINDUP
		st = float(cfg.windup) / _rage()
		return
	position.x = clampf(position.x + face * float(cfg.charge) * _rage() * dt, x0, x1)


func _begin_strike(pl, dx: float) -> void:
	if bool(cfg.get("ranged", false)):
		state = STRIKE
		st = 0.0
		shot_t = float(cfg.recover)
		_fire(pl, 1, 0.0)
		return
	state = STRIKE
	st = float(cfg.strike)
	struck = false
	level.battle_sfx("swing", center())


func _strike_test(pl) -> void:
	var reach: float = cfg.reach
	var h: float = cfg.h
	var r := Rect2(position.x + (0.0 if face > 0.0 else -reach), position.y - h - 6.0, reach, h + 12.0)
	if r.intersects(pl.hurt_rect()):
		struck = true
		pl.battle_hit(position, "melee")


func _fire(pl, n: int, spread: float) -> void:
	if pl == null:
		return
	var origin := position + Vector2(face * 14.0, -float(cfg.h) * 0.62)
	var aim: Vector2 = (pl.center() - origin).normalized()
	for i in n:
		var a := aim.rotated(spread * (i - (n - 1) * 0.5))
		var ar := Arrow.new()
		ar.level = level
		ar.friendly = false
		ar.vel = a * float(cfg.arrow_speed)
		ar.color = cfg.color
		ar.global_position = origin
		level.world.add_child(ar)
	level.battle_sfx("shoot", origin)


func _draw() -> void:
	if state == DEAD and dead_t >= 0.6:
		return
	var c: Color = cfg.color
	var fade := 1.0 if state != DEAD else clampf(1.0 - dead_t / 0.6, 0.0, 1.0)
	var w: float = cfg.w
	var h: float = cfg.h
	var f := face
	var bob := sin(t * 9.0) * 1.5 if state in [PATROL, CHARGE] and absf(kx) < 1.0 else 0.0
	var col := c.lerp(Color(3, 3, 3), flash * 0.7)
	col.a = fade
	# body
	draw_rect(Rect2(-w * 0.5, -h * 0.72 + bob, w, h * 0.72), Color(col, 0.22 * fade))
	draw_rect(Rect2(-w * 0.5, -h * 0.72 + bob, w, h * 0.72), col, false, 2.5)
	draw_circle(Vector2(0, -h * 0.86 + bob), h * 0.14, col)
	# legs
	var lw := sin(t * 14.0) * 5.0 if state == CHARGE else 0.0
	draw_line(Vector2(-w * 0.25, 0), Vector2(-w * 0.25 + lw, -h * 0.28), col, 3.0)
	draw_line(Vector2(w * 0.25, 0), Vector2(w * 0.25 - lw, -h * 0.28), col, 3.0)
	# telegraph / strike
	var tele := 0.0
	if state == WINDUP:
		tele = 1.0 - clampf(st / (float(cfg.windup) / _rage()), 0.0, 1.0)
		draw_arc(Vector2(0, -h - 14.0), 9.0 + tele * 6.0, 0, TAU, 20, Color(3, 0.5, 0.4, 0.4 + 0.6 * tele), 3.0)
		draw_line(Vector2(0, -h - 22.0), Vector2(0, -h - 14.0 + 2.0), Color(3, 0.5, 0.4, 0.9), 3.0)
	match kind:
		"archer":
			var bow_c := Color(col, fade)
			draw_arc(Vector2(f * (w * 0.5 + 6.0), -h * 0.5), 18.0, -PI * 0.5 - 0.0 if f > 0 else PI * 0.5, PI * 0.5 if f > 0 else PI * 1.5, 14, bow_c, 3.0)
			if state == WINDUP:
				draw_line(Vector2(f * (w * 0.5 + 6.0), -h * 0.5), Vector2(f * (w * 0.5 + 6.0) - f * (4.0 + tele * 14.0), -h * 0.5), Color(3, 3, 1, 0.9), 2.0)
		"guard":
			if shield_up():
				var sx := f * (w * 0.5 + 8.0)
				draw_rect(Rect2(sx - 5.0, -h * 0.85, 10.0, h * 0.8), Color(2.4, 1.8, 0.6, 0.35 * fade))
				draw_rect(Rect2(sx - 5.0, -h * 0.85, 10.0, h * 0.8), Color(2.4, 1.8, 0.6, fade), false, 3.0)
			_draw_weapon(col, f, w, h, tele)
		_:
			_draw_weapon(col, f, w, h, tele)
	if kind == "leader":
		# crown
		var cy := -h * 1.0 - 4.0
		var cc := Color(3, 2.4, 0.5, fade)
		draw_polyline(PackedVector2Array([Vector2(-10, cy), Vector2(-10, cy - 10), Vector2(-5, cy - 4), Vector2(0, cy - 12), Vector2(5, cy - 4), Vector2(10, cy - 10), Vector2(10, cy)]), cc, 2.5)
	# hp bar once hurt
	if hp < float(cfg.hp) and state != DEAD and kind != "leader":
		var bw := 38.0
		var by := -h - 30.0
		draw_rect(Rect2(-bw * 0.5, by, bw, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, by, bw * hp / float(cfg.hp), 5.0), Color(2.0, 0.4, 0.4))


func _draw_weapon(col: Color, f: float, w: float, h: float, tele: float) -> void:
	var base := Vector2(f * w * 0.4, -h * 0.5)
	var ang := -0.6 + tele * -0.9
	if state == STRIKE:
		ang = 0.5
	var tip := base + Vector2(f * cos(ang), sin(ang)) * (float(cfg.reach) * (0.7 if kind != "leader" else 0.85))
	draw_line(base, tip, col, 4.0 if kind != "leader" else 6.0)
	if state == STRIKE:
		draw_arc(base, float(cfg.reach) * 0.7, -1.0 if f > 0.0 else PI - 0.6, 0.6 if f > 0.0 else PI + 1.0, 12, Color(3, 1.0, 0.8, 0.5), 5.0)
