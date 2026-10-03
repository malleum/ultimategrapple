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
	var spawn_ok := false
	var basket_ok := false
	for s in solids:
		var r := _rect(s.r)
		if r.size.x <= 0 or r.size.y <= 0:
			errs.append("degenerate solid %s" % [s.r])
		if r.has_point(spawn + Vector2(0, 4)):
			spawn_ok = true
		if r.has_point(basket + Vector2(0, 4)):
			basket_ok = true
		if r.intersects(Rect2(spawn + Vector2(-10, -44), Vector2(20, 40))):
			errs.append("spawn inside solid")
		if r.intersects(Rect2(basket + Vector2(-50, -150), Vector2(100, 142))):
			errs.append("basket blocked by solid %s" % [s.r])
	if not spawn_ok:
		errs.append("no ground under spawn")
	if not basket_ok:
		errs.append("no ground under basket")
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
## v2 -> v3 only added long disc bridges to new courses: nothing to fix.
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
