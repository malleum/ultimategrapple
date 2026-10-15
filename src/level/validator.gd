extends RefCounted
## Static course checks shared by the generator tests and the level loader.
##
## check(data) returns a list of human-readable problems. It looks for things
## that make a course unfair or broken rather than merely hard:
##   - spawn / basket without ground, buried in solids, basket mouth blocked
##   - grapple points inside solids
##   - spike strips buried inside solids or not attached to any surface
##   - ceiling spikes too low to slide under (the slide hitbox is Player.LOW)
##   - "pinch" gaps under solid ceilings that look passable but are not
##   - route points (the generator's intended path) inside solids or hazards
##
## repair(data) upgrades courses saved by older generator versions in place.

const Player = preload("res://src/player/player.gd")
const Gen = preload("res://src/level/generator.gd")

## Minimum clear height under ceiling spikes: slide hitbox + margin.
const SLIDE_CLEAR := Player.LOW.y + 8.0
## Solid gaps smaller than this cannot be crawled through at all.
const PINCH := Player.LOW.y + 4.0


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func _overlap_x(a: Rect2, b: Rect2) -> float:
	return minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)


## Top of the highest solid surface at or below `y` that spans more than a few
## pixels of [r.x, r.end.x]. INF when nothing is underneath.
static func _floor_below(solids: Array, r: Rect2, y: float) -> float:
	var best := INF
	for s in solids:
		var sr := _rect(s.r)
		if sr.position.y >= y - 0.5 and _overlap_x(sr, r) > 4.0 and sr.position.y < best:
			best = sr.position.y
	return best


static func check(d: Dictionary) -> Array:
	var errs := []
	var solids: Array = d.get("solids", [])
	var ents: Array = d.get("entities", [])
	var spawn := Vector2(d.spawn[0], d.spawn[1])
	var basket := Vector2(d.basket[0], d.basket[1])
	# a basket can be mounted sideways on a wall (its foot is in the wall) or
	# float (nothing under it)
	var brot := float(d.get("basket_rot", 0.0))
	var bfloat := bool(d.get("basket_float", false))
	var bfoot := basket + Vector2(0, 4).rotated(brot)
	var bmouth := Rect2(basket + Vector2(-50, -150).rotated(brot), Vector2.ZERO)
	for c in [Vector2(50, -150), Vector2(-50, -8), Vector2(50, -8)]:
		bmouth = bmouth.expand(basket + c.rotated(brot))
	var spawn_ok := false
	var basket_ok := bfloat
	for s in solids:
		var r := _rect(s.r)
		if r.size.x <= 0 or r.size.y <= 0:
			errs.append("degenerate solid %s" % [s.r])
		if r.has_point(spawn + Vector2(0, 4)):
			spawn_ok = true
		if r.has_point(bfoot):
			basket_ok = true
		if r.intersects(Rect2(spawn + Vector2(-10, -44), Vector2(20, 40))):
			errs.append("spawn inside solid")
		if r.intersects(bmouth):
			errs.append("basket blocked by solid %s" % [s.r])
	if not spawn_ok:
		errs.append("no ground under spawn")
	if not basket_ok:
		errs.append("no ground (or wall) under basket")
	if float(d.kill_y) < basket.y:
		errs.append("kill_y above basket")

	var hazards: Array = []
	for e in ents:
		match str(e.t):
			"grapple":
				var p := Vector2(e.p[0], e.p[1])
				for s in solids:
					if _rect(s.r).has_point(p):
						errs.append("grapple point inside solid at %s" % [p])
						break
			"spikes":
				var hr := _rect(e.r)
				hazards.append(hr)
				errs.append_array(_check_spikes(solids, hr, str(e.get("dir", "up"))))

	# a slick wall with a grippy solid overlapping it isn't slick: the wall
	# check hits the grippy body and you wall-jump up it anyway
	for s in solids:
		if str(s.get("k", "")) != "slick":
			continue
		var sr := _rect(s.r)
		for o in solids:
			if str(o.get("k", "")) in ["slick", "oneway", "fence"]:
				continue
			var ov := sr.intersection(_rect(o.r))
			if ov.size.x > 0.5 and ov.size.y > 0.5:
				errs.append("slick wall %s overlapped by %s %s" % [s.r, o.get("k", ""), o.r])

	# solid ceilings that leave a gap nobody fits through
	for s in solids:
		if str(s.get("k", "")) == "oneway":
			continue
		var sr := _rect(s.r)
		var gap := _floor_below(solids, sr, sr.end.y) - sr.end.y
		if gap > 0.5 and gap < PINCH:
			errs.append("pinch gap %dpx under solid %s" % [int(gap), s.r])

	# the intended path must be standable
	for rp in d.get("route", []):
		var body := Rect2(float(rp[0]) - 9.0, float(rp[1]) - Player.LOW.y - 1.0, 18.0, Player.LOW.y)
		for s in solids:
			if str(s.get("k", "")) != "oneway" and _rect(s.r).intersects(body):
				errs.append("route point %s inside solid %s" % [rp, s.r])
				break
		for hr in hazards:
			if hr.intersects(body):
				errs.append("route point %s inside spikes" % [rp])
				break
	if d.has("battle"):
		errs.append_array(_check_battle(solids, ents))
	return errs


## Battle Rush: enemies stand on the floor they patrol, arenas can be entered
## and left, no grippy solid touches a door (a door is slick and out of reach),
## and exactly one leader waits at the end.
static func _check_battle(solids: Array, ents: Array) -> Array:
	var errs := []
	var leaders := 0
	var arena_ids := {}
	var doors: Array = []
	for e in ents:
		match str(e.t):
			"arena":
				arena_ids[int(e.id)] = e
				doors.append(_rect(e.entry))
				if not (e.get("exit") as Array).is_empty():
					doors.append(_rect(e.exit))
				elif not bool(e.get("leader", false)):
					errs.append("arena %d has no way out" % int(e.id))
	for e in ents:
		if str(e.t) != "enemy":
			continue
		if str(e.k) == "leader":
			leaders += 1
		var p := Vector2(e.p[0], e.p[1])
		var x0 := float(e.get("x0", p.x))
		var x1 := float(e.get("x1", p.x))
		for x in [x0, p.x, x1]:
			var stands := false
			for s in solids:
				var sr := _rect(s.r)
				if str(s.get("k", "")) != "oneway" and absf(sr.position.y - p.y) < 1.0 and x >= sr.position.x and x <= sr.end.x:
					stands = true
					break
			if not stands:
				errs.append("%s at %s has no floor at x=%d" % [e.k, p, int(x)])
				break
		var body := Rect2(p.x - 13.0, p.y - 44.0, 26.0, 40.0)
		for s in solids:
			if _rect(s.r).intersects(body):
				errs.append("%s at %s inside solid %s" % [e.k, p, s.r])
				break
		var a := int(e.get("a", -1))
		if a != -1:
			if not arena_ids.has(a):
				errs.append("%s belongs to missing arena %d" % [e.k, a])
			else:
				var ar := _rect(arena_ids[a].r)
				if x0 < ar.position.x or x1 > ar.end.x:
					errs.append("%s patrols outside arena %d" % [e.k, a])
	if leaders != 1:
		errs.append("%d leaders (want 1)" % leaders)
	for dr in doors:
		for s in solids:
			if str(s.get("k", "")) in ["slick", "oneway", "fence"]:
				continue
			var ov: Rect2 = dr.intersection(_rect(s.r))
			if ov.size.x > 0.5 and ov.size.y > 0.5:
				errs.append("door %s overlapped by %s %s" % [dr, s.get("k", ""), s.r])
	return errs


static func _check_spikes(solids: Array, hr: Rect2, dir: String) -> Array:
	var errs := []
	var attached := false
	for s in solids:
		var sr := _rect(s.r)
		if sr.grow(0.5).encloses(hr):
			errs.append("spikes buried in solid %s" % [s.r])
			return errs
		match dir:
			"up": attached = attached or (absf(sr.position.y - hr.end.y) < 1.0 and _overlap_x(sr, hr) > 0.0)
			"down": attached = attached or (absf(sr.end.y - hr.position.y) < 1.0 and _overlap_x(sr, hr) > 0.0)
			"left": attached = attached or (absf(sr.position.x - hr.end.x) < 1.0 and sr.position.y < hr.end.y and sr.end.y > hr.position.y)
			_: attached = attached or (absf(sr.end.x - hr.position.x) < 1.0 and sr.position.y < hr.end.y and sr.end.y > hr.position.y)
	if not attached:
		errs.append("spikes (%s) not attached to a surface at %s" % [dir, hr])
	if dir == "down":
		var gap := _floor_below(solids, hr, hr.end.y) - hr.end.y
		if gap < SLIDE_CLEAR:
			errs.append("ceiling spikes only %dpx above floor at x=%d (slide needs %d)" % [int(gap), int(hr.position.x), int(SLIDE_CLEAR)])
	return errs


## Bring a saved course up to the current generator version. Idempotent.
## v2 -> v3 only added long disc bridges, v3 -> v4 throw puzzles, slick walls
## and fences to new courses: nothing to fix.
static func repair(d: Dictionary) -> void:
	if int(d.get("version", 1)) >= Gen.VERSION:
		return
	var solids: Array = d.get("solids", [])
	var ceil_px := Gen.SLIDE_CEIL * Gen.T
	for e in d.get("entities", []):
		if str(e.t) != "spikes" or str(e.get("dir", "")) != "down":
			continue
		var hr := _rect(e.r)
		# v1 chimney: spikes generated inside the hanging wall -> move to its underside
		for s in solids:
			var br := _rect(s.r)
			if br.grow(0.5).encloses(hr):
				hr.position.y = br.end.y
				e.r = [int(hr.position.x), int(hr.position.y), int(hr.size.x), int(hr.size.y)]
				break
		var fl := _floor_below(solids, hr, hr.end.y)
		if fl == INF or fl - hr.end.y >= SLIDE_CLEAR:
			continue
		# v1 slide tunnel: lift the block that carries the spikes
		for s in solids:
			var sr := _rect(s.r)
			if str(s.get("k", "")) == "block" and absf(sr.end.y - hr.position.y) < 1.0 and _overlap_x(sr, hr) > 0.0:
				var top := int(fl - ceil_px)
				s.r[3] = top - int(sr.position.y)
				e.r = [int(hr.position.x), top, int(hr.size.x), Gen.T / 2]
				break
	d["version"] = Gen.VERSION
