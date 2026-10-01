extends RefCounted
## Procedural course generator.
##
## Works on a 32px tile grid. A cursor walks left->right placing "segments"
## (parkour challenges) from a weighted grammar. Every segment starts on the
## cursor's floor, reserves its bounding box, emits solids / entities / route
## points and a time estimate, and hands back the new cursor. Afterwards we add
## a finale (basket green), optional high-skill sky shortcuts, decoration,
## floor fills, kill zones and medal times.
##
## Output is a plain Dictionary (JSON-serialisable) so any course can be pinned.

const Themes = preload("res://src/core/theme_db.gd")

const T := 32                 # tile size in px
const RUN_TILES_PER_SEC := 12.0
## 2: slide tunnels got a 48px ceiling (older saves are repaired on load)
const VERSION := 2
const SLIDE_CEIL := 1.5        # slide tunnel ceiling height, tiles

# Player movement envelope, in tiles (kept conservative so levels are fair).
const SAFE_JUMP_UP := 4
const SAFE_GAP := 7
const GRAPPLE_RANGE := 16

const SEGMENTS := {
	"run_gaps":      {"w": 10.0, "min_d": 0.0, "dir": 0},
	"stairs_up":     {"w": 6.0,  "min_d": 0.0, "dir": -1},
	"stairs_down":   {"w": 4.0,  "min_d": 0.0, "dir": 1},
	"chimney":       {"w": 5.0,  "min_d": 0.1, "dir": -1},
	"swing_chain":   {"w": 10.0, "min_d": 0.0, "dir": 0},
	"zip_ledge":     {"w": 6.0,  "min_d": 0.0, "dir": -1},
	"slide_tunnel":  {"w": 5.0,  "min_d": 0.0, "dir": 0},
	"movers":        {"w": 6.0,  "min_d": 0.15, "dir": 0},
	"bounce":        {"w": 5.0,  "min_d": 0.0, "dir": 0},
	"disc_gate":     {"w": 7.0,  "min_d": 0.0, "dir": 0, "disc": true},
	"disc_bridge":   {"w": 4.0,  "min_d": 0.25, "dir": 0, "disc": true},
	"updraft":       {"w": 4.0,  "min_d": 0.2, "dir": -1},
	"lasers":        {"w": 5.0,  "min_d": 0.3, "dir": 0},
	"saws":          {"w": 5.0,  "min_d": 0.3, "dir": 0},
	"glass":         {"w": 4.0,  "min_d": 0.0, "dir": 0, "disc": true},
	"drop":          {"w": 4.0,  "min_d": 0.0, "dir": 1},
	"hammer_wall":   {"w": 5.0,  "min_d": 0.2, "dir": 0, "disc": true},
	"ramp_jump":     {"w": 5.0,  "min_d": 0.0, "dir": 0},
	"grip_ceiling":  {"w": 5.0,  "min_d": 0.2, "dir": 0},
	"pillars":       {"w": 5.0,  "min_d": 0.35, "dir": 0},
	"booster_gap":   {"w": 4.0,  "min_d": 0.0, "dir": 0},
	"zip_tower":     {"w": 4.0,  "min_d": 0.3, "dir": -1},
	"wrap_block":    {"w": 3.0,  "min_d": 0.45, "dir": 0},
	# disc-loop style sections: open fairways reward throw-and-chase,
	# tight tunnels reward carrying the disc.
	"fairway":       {"w": 8.0,  "min_d": 0.0, "dir": 0, "style": "throw"},
	"tunnel":        {"w": 6.0,  "min_d": 0.0, "dir": 0, "style": "carry"},
	"slope_run":     {"w": 4.0,  "min_d": 0.0, "dir": 1},
	"crosswind":     {"w": 2.0,  "min_d": 0.2, "dir": 0, "style": "throw"},
}

const THEME_BIAS := {
	"field": {"run_gaps": 1.5, "disc_gate": 1.6, "hammer_wall": 1.5, "bounce": 1.2},
	"cyber": {"lasers": 2.0, "slide_tunnel": 1.5, "zip_ledge": 1.4, "glass": 1.5},
	"fantasy": {"swing_chain": 1.6, "grip_ceiling": 1.8, "pillars": 1.4, "wrap_block": 1.5},
	"heaven": {"bounce": 1.8, "updraft": 2.0, "disc_bridge": 1.6, "zip_tower": 1.4},
	"foundry": {"saws": 2.0, "movers": 1.8, "chimney": 1.4, "booster_gap": 1.3},
	"frost": {"ramp_jump": 2.0, "slide_tunnel": 1.6, "drop": 1.5, "booster_gap": 1.5, "slope_run": 3.0},
	"canyon": {"fairway": 1.8, "crosswind": 4.0, "swing_chain": 1.3, "bounce": 1.3, "hammer_wall": 1.3},
}

const DECOR := {
	"field": ["cone", "cone", "flag", "bench", "tree", "yardline"],
	"cyber": ["neon_sign", "antenna", "vent", "holo", "neon_sign"],
	"fantasy": ["tree", "mushroom", "crystal", "ruin_pillar", "mushroom"],
	"heaven": ["pillar", "cloud_puff", "statue", "arch"],
	"foundry": ["barrel", "pipe", "crate", "chain", "barrel"],
	"frost": ["pine", "ice_crystal", "rock", "pine", "snowman"],
	"canyon": ["cactus", "cactus", "mesa_rock", "skull", "tumbleweed"],
}

const NAME_A := {
	"field": ["Hyzer", "Huck", "Layout", "Endzone", "Pull", "Stall", "Greatest", "Callahan"],
	"cyber": ["Chrome", "Neon", "Static", "Proxy", "Kernel", "Glitch", "Vector", "Ghost"],
	"fantasy": ["Elder", "Moss", "Rune", "Thorn", "Wisp", "Hollow", "Briar", "Oracle"],
	"heaven": ["Halo", "Seraph", "Aether", "Zenith", "Choir", "Radiant", "Empyrean", "Vesper"],
	"foundry": ["Slag", "Rivet", "Crucible", "Piston", "Ingot", "Furnace", "Anvil", "Cinder"],
	"frost": ["Rime", "Glacier", "Hoarfrost", "Serac", "Crevasse", "Aurora", "Floe", "Tundra"],
	"canyon": ["Mesa", "Dustdevil", "Sirocco", "Arroyo", "Butte", "Sundown", "Hoodoo", "Coyote"],
}
const NAME_B := ["Line", "Drift", "Run", "Ascent", "Circuit", "Gauntlet", "Sprint", "Spiral",
	"Descent", "Flight", "Break", "Relay", "Rush", "Chase", "Dash", "Ladder"]

var rng := RandomNumberGenerator.new()
var d := 0.5
var theme := "cyber"
var ice_mode := false

var solids: Array = []
var polys: Array = []
var ents: Array = []
var route: Array = []
var reserves: Array = []   # Array[Rect2] in tiles
var seg_log: Array = []
var sections: Array = []   # [{x0, x1, style}] in px: "throw" / "carry" / ""
var est_time := 0.0

# staging buffers for the segment currently being attempted
var _s_solids: Array = []
var _s_polys: Array = []
var _s_ents: Array = []
var _s_route: Array = []
var _s_est := 0.0
var _s_box := Rect2()
var _s_has_box := false


# ============================================================ public API

func generate(seed_value: int, theme_id: String = "", difficulty: float = 0.5, length: int = 12) -> Dictionary:
	rng.seed = seed_value
	d = clampf(difficulty, 0.0, 1.0)
	theme = theme_id if Themes.THEMES.has(theme_id) else Themes.random_id(rng)
	ice_mode = theme == "frost"
	length = clampi(length, 3, 40)
	solids.clear(); polys.clear(); ents.clear(); route.clear(); reserves.clear(); seg_log.clear(); sections.clear()
	est_time = 0.0

	# --- start pad
	_begin()
	_solid(-14, -30, 2, 30, "block")          # back wall
	ground(-12, 8, 0)
	_route(2, 0)
	_s_est += 0.6
	_commit("start")
	var cur := Vector2i(8, 0)

	# --- main body
	var last := ["", ""]
	var since_disc := 0
	for i in length:
		var force_disc := since_disc >= 4
		var placed := false
		for attempt in 8:
			var seg := _pick_segment(cur, last, force_disc and attempt < 5)
			_begin()
			var nxt: Vector2i = call("seg_" + seg, cur.x, cur.y)
			if _box_ok():
				_commit(seg)
				var sty: String = SEGMENTS[seg].get("style", "")
				if sty != "":
					sections.append({"x0": cur.x * T, "x1": nxt.x * T, "style": sty})
				cur = nxt
				last = [last[1], seg]
				since_disc = 0 if SEGMENTS[seg].get("disc", false) else since_disc + 1
				placed = true
				break
		if not placed:
			_begin()
			cur = seg_run_gaps(cur.x, cur.y)
			_commit("run_gaps")

	# --- finale
	_begin()
	var basket: Vector2 = _finale(cur.x, cur.y)
	_commit("finale")

	_add_shortcuts()
	_add_decor()

	# --- finalize geometry
	var bounds := _compute_bounds()
	var floor_bottom := bounds.end.y + 44 * T
	for s in solids:
		if s.get("fill", false):
			var r: Array = s["r"]
			r[3] = int(floor_bottom - r[1])
			s.erase("fill")
	_merge_grounds()
	var kill_y := bounds.end.y + 10 * T

	var times := _medals()
	var name := "%s %s" % [_pick(NAME_A[theme]), _pick(NAME_B)]
	var id := "g%d_%s_%d_%d" % [seed_value, theme, int(round(d * 10)), length]
	return {
		"version": VERSION,
		"id": id,
		"name": name,
		"seed": seed_value,
		"theme": theme,
		"difficulty": d,
		"length": length,
		"spawn": [2 * T, 0],
		"basket": [basket.x, basket.y],
		"bounds": [bounds.position.x - 20 * T, bounds.position.y - 30 * T, bounds.size.x + 40 * T, floor_bottom - bounds.position.y + 30 * T],
		"kill_y": kill_y,
		"solids": solids,
		"polys": polys,
		"entities": ents,
		"route": route,
		"segments": seg_log,
		"sections": sections,
		"medals": times,
	}


# ============================================================ staging

func _begin() -> void:
	_s_solids = []; _s_polys = []; _s_ents = []; _s_route = []
	_s_est = 0.0
	_s_has_box = false


func _grow(x: float, y: float, w: float, h: float) -> void:
	var r := Rect2(x, y, w, h).abs()
	if _s_has_box:
		_s_box = _s_box.merge(r)
	else:
		_s_box = r
		_s_has_box = true


func _box_ok() -> bool:
	if not _s_has_box:
		return true
	var inner := _s_box.grow(-0.6)
	# ignore the directly preceding segment (we share its edge)
	for i in range(0, reserves.size() - 1):
		if inner.intersects(reserves[i]):
			return false
	return true


func _commit(seg: String) -> void:
	solids.append_array(_s_solids)
	polys.append_array(_s_polys)
	ents.append_array(_s_ents)
	route.append_array(_s_route)
	est_time += _s_est
	if _s_has_box:
		reserves.append(_s_box)
	seg_log.append(seg)


# ============================================================ primitives (tile units)

func _solid(x: float, y: float, w: float, h: float, kind: String, fill := false) -> void:
	var s := {"r": [int(round(x * T)), int(round(y * T)), int(round(w * T)), int(round(h * T))], "k": kind}
	if fill:
		s["fill"] = true
	_s_solids.append(s)
	_grow(x, y, w, maxf(h, 1.0))


## Floor from x0 to x1 whose top surface is at row y; extends down to the level bottom.
func ground(x0: float, x1: float, y: float, kind := "") -> void:
	if x1 <= x0:
		return
	if kind == "":
		kind = "ice" if ice_mode and rng.randf() < 0.35 else "ground"
	_solid(x0, y, x1 - x0, 0, kind, true)
	_grow(x0, y, x1 - x0, 3)


func block(x: float, y: float, w: float, h: float) -> void:
	_solid(x, y, w, h, "block")


func oneway(x: float, y: float, w: float) -> void:
	_solid(x, y, w, 0.5, "oneway")


func grip(x: float, y: float, w: float, h: float) -> void:
	_solid(x, y, w, h, "grip")


func _ent(e: Dictionary, bx: float, by: float, bw := 1.0, bh := 1.0) -> void:
	_s_ents.append(e)
	_grow(bx, by, bw, bh)


func _route(x: float, y: float) -> void:
	_s_route.append([int(x * T), int(y * T)])


func _p(x: float, y: float) -> Array:
	return [int(round(x * T)), int(round(y * T))]


func grapple_pt(x: float, y: float, kind := "") -> void:
	if kind == "":
		kind = "static"
		var r := rng.randf()
		if d > 0.35 and r < 0.18 + d * 0.15:
			kind = "fragile"
		elif r > 0.9 - d * 0.05:
			kind = "boost"
	var e := {"t": "grapple", "p": _p(x, y), "k": kind}
	if kind == "moving":
		e["move"] = _p(rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		e["period"] = snappedf(rng.randf_range(2.2, 3.6), 0.1)
		e["phase"] = snappedf(rng.randf(), 0.01)
	_ent(e, x - 1, y - 1, 2, 2)


func spikes(x: float, y: float, w: float, dir := "up") -> void:
	var r: Array
	match dir:
		"up": r = [x, y - 0.5, w, 0.5]
		"down": r = [x, y, w, 0.5]
		"left": r = [x - 0.5, y, 0.5, w]
		_: r = [x, y, 0.5, w]
	_ent({"t": "spikes", "r": [int(r[0] * T), int(r[1] * T), int(r[2] * T), int(r[3] * T)], "dir": dir}, r[0], r[1], r[2], r[3])


## Pit between x0 and x1 below floor row y. Spiked floor or abyss kill zone.
func pit(x0: float, x1: float, y: float) -> void:
	if x1 - x0 < 1:
		return
	if rng.randf() < 0.65:
		var depth := rng.randi_range(4, 7)
		ground(x0, x1, y + depth, "ground")
		spikes(x0, y + depth, x1 - x0, "up")
	else:
		_ent({"t": "kill", "r": [int(x0 * T), int((y + 9) * T), int((x1 - x0) * T), 6 * T]}, x0, y + 9, x1 - x0, 1)


func ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)


func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func chance(p: float) -> bool:
	return rng.randf() < p


func dl(a: float, b: float) -> int:
	return int(round(lerpf(a, b, d)))


func _pick(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


# ============================================================ segment selection

func _pick_segment(cur: Vector2i, last: Array, force_disc: bool) -> String:
	var bias: Dictionary = THEME_BIAS.get(theme, {})
	var names := []
	var weights := []
	var total := 0.0
	for seg in SEGMENTS:
		var info: Dictionary = SEGMENTS[seg]
		if d < info.min_d:
			continue
		if seg == last[1] or (seg == last[0] and seg != "run_gaps"):
			continue
		if force_disc and not info.get("disc", false):
			continue
		var w: float = info.w * bias.get(seg, 1.0)
		var dir: int = info.dir
		if dir < 0 and cur.y < -40:
			continue
		if dir > 0 and cur.y > 30:
			continue
		if dir < 0 and cur.y > 12:
			w *= 2.0
		if dir > 0 and cur.y < -18:
			w *= 2.2
		names.append(seg)
		weights.append(w)
		total += w
	if names.is_empty():
		return "run_gaps"
	var r := rng.randf() * total
	for i in names.size():
		r -= weights[i]
		if r <= 0.0:
			return names[i]
	return names[-1]


# ============================================================ segments
# Each takes the cursor (tile x of the ledge end, tile y of its floor top)
# and returns the new cursor.

func seg_run_gaps(x: int, y: int) -> Vector2i:
	var cx := x
	var cy := y
	var first := ri(3, 6)
	ground(cx, cx + first, cy)
	cx += first
	var n := ri(1, 2 + int(d * 2.0))
	for i in n:
		var gap := ri(3, 4 + dl(0, 3))
		var dy := ri(-2, 2)
		if gap >= 6:
			dy = maxi(dy, -1)
		pit(cx, cx + gap, cy + maxi(0, dy))
		cx += gap
		cy += dy
		var l := ri(3, 7)
		ground(cx, cx + l, cy)
		if chance(0.25):
			oneway(cx + 1, cy - ri(3, 4), ri(2, 4))
		cx += l
		_route(cx, cy)
	_s_est += float(cx - x) / RUN_TILES_PER_SEC + 0.15 * n
	return Vector2i(cx, cy)


func seg_stairs_up(x: int, y: int) -> Vector2i:
	var cx := x
	var cy := y
	var floor_under := d < 0.5 or chance(0.4)
	var steps := ri(3, 5)
	ground(cx, cx + 3, cy)
	cx += 3
	var sx := cx
	for i in steps:
		var dx := ri(2, 3 + dl(0, 2))
		var rise := ri(2, SAFE_JUMP_UP)
		var w := ri(3, 6 - dl(0, 2))
		cx += dx
		cy -= rise
		if chance(0.4):
			oneway(cx, cy, w)
		else:
			block(cx, cy, w, ri(1, 2))
		cx += w
		_route(cx - 1, cy)
	var top_gap := ri(2, 3)
	cx += top_gap
	cy -= ri(0, 2)
	ground(cx, cx + ri(4, 7), cy)
	if floor_under:
		ground(sx, cx, y, "ground")
	else:
		pit(sx, cx, y)
	cx += 4
	_s_est += float(cx - x) / (RUN_TILES_PER_SEC * 0.8)
	return Vector2i(cx, cy)


func seg_stairs_down(x: int, y: int) -> Vector2i:
	var cx := x
	var cy := y
	ground(cx, cx + 3, cy)
	cx += 3
	var steps := ri(3, 5)
	var last_y := cy
	for i in steps:
		var dx := ri(2, 4)
		cx += dx
		cy += ri(2, 4)
		var w := ri(3, 5)
		block(cx, cy, w, ri(1, 3))
		if d > 0.4 and chance(0.3):
			spikes(cx + 1, cy, 1, "up")
		cx += w
		last_y = cy
	cx += ri(2, 3)
	cy = last_y + ri(1, 3)
	pit(x + 3, cx, cy + 2)
	ground(cx, cx + ri(4, 6), cy)
	cx += 4
	_s_est += float(cx - x) / RUN_TILES_PER_SEC
	return Vector2i(cx, cy)


func seg_chimney(x: int, y: int) -> Vector2i:
	var h := ri(8, 10 + dl(0, 6))
	var gapw := ri(4, 6)
	var cx := x
	ground(cx, cx + 4 + gapw, y)
	# hanging left wall: player walks underneath then wall-jumps up
	block(cx + 2, y - h - 2, 2, h - 2)
	if d > 0.5 and chance(0.5):
		# under the hanging wall: punishes jumping too early
		spikes(cx + 2, y - 4, 2, "down")
	# right side: the cliff of the upper ledge
	var top := y - h
	ground(cx + 4 + gapw, cx + 4 + gapw + ri(6, 9), top)
	if chance(0.35):
		grapple_pt(cx + 4 + gapw * 0.5, top - 5, "static")
	cx += 4 + gapw + 6
	_route(cx, top)
	_s_est += 1.6 + h * 0.08
	return Vector2i(cx, top)


func seg_swing_chain(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var w := ri(16, 18 + dl(4, 16))
	var n := maxi(1, int(ceil(w / 11.0)))
	var ceil_y := y - ri(7, 9)
	for i in n:
		var px := cx + w * (i + 0.5) / n + rf(-1.5, 1.5)
		var py := ceil_y + rf(-1.5, 1.5)
		var kind := ""
		if d > 0.55 and chance(0.25):
			kind = "moving"
		grapple_pt(px, py, kind)
		if theme in ["cyber", "foundry"] and chance(0.5):
			block(px - 1, py - 6, 2, 5)  # support pylon
	var land_dy := ri(-3, 2)
	pit(cx, cx + w, y + maxi(0, land_dy))
	cx += w
	ground(cx, cx + ri(5, 7), y + land_dy)
	cx += 5
	_route(cx, y + land_dy)
	_s_est += w / 14.0 + 0.5
	return Vector2i(cx, y + land_dy)


func seg_zip_ledge(x: int, y: int) -> Vector2i:
	var h := ri(9, 10 + dl(0, 5))
	ground(x, x + 7, y)
	var top := y - h
	ground(x + 7, x + 16, top)
	grapple_pt(x + 9, top - ri(3, 5), "static")
	if d > 0.4 and chance(0.5):
		spikes(x + 7, y - 4, 4, "left")
	_route(x + 16, top)
	_s_est += 1.4
	return Vector2i(x + 16, top)


func seg_slide_tunnel(x: int, y: int) -> Vector2i:
	var l := ri(5, 7 + dl(0, 5))
	var cx := x
	ground(cx, cx + 6 + l + 5, y)
	if chance(0.5 + d * 0.3):
		_ent({"t": "booster", "r": [int((cx + 1) * T), int(y * T - 8), 4 * T, 8], "dir": 1}, cx + 1, y - 1, 4, 1)
	# ceiling 48px up, spike tips at 32px: a 22px slide clears them by 10px,
	# standing (44px) or jumping inside the tunnel does not
	block(cx + 6, y - 12, l, 12 - SLIDE_CEIL)
	spikes(cx + 6, y - SLIDE_CEIL, l, "down")
	if d > 0.5 and chance(0.4):
		# low tunnel ends in a small gap you have to slide-jump
		pass
	cx += 6 + l + 5
	_route(cx, y)
	_s_est += float(cx - x) / RUN_TILES_PER_SEC + 0.2
	return Vector2i(cx, y)


func seg_movers(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var n := ri(1, 2 + dl(0, 1))
	var start := cx
	for i in n:
		cx += ri(3, 4)
		var vertical := chance(0.4)
		var mv: Array
		var py := y + ri(-1, 1)
		if vertical:
			mv = _p(0, -ri(3, 5))
		else:
			mv = _p(ri(3, 5), 0)
		var period := snappedf(rf(2.2, 3.8) - d * 0.6, 0.1)
		_ent({"t": "mover", "r": [int(cx * T), int(py * T), 4 * T, T / 2], "move": mv, "period": period, "phase": snappedf(rng.randf(), 0.01)},
			cx, py - 6, 4 + (mv[0] / T), 7)
		cx += 4 + (mv[0] / T)
	cx += ri(3, 4)
	pit(start, cx, y)
	ground(cx, cx + 5, y)
	cx += 5
	_route(cx, y)
	_s_est += (cx - x) / RUN_TILES_PER_SEC + n * 0.9
	return Vector2i(cx, y)


func seg_bounce(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 7, y)
	var up := chance(0.5)
	var dir := Vector2(0.45, -1.0).normalized() if up else Vector2(0.62, -0.78).normalized()
	_ent({"t": "pad", "p": _p(cx + 5, y), "dir": [dir.x, dir.y], "power": 1550 if up else 1450}, cx + 4, y - 1, 2, 1)
	cx += 7
	var gap := ri(10, 14) if up else ri(13, 18)
	var land_dy := -ri(5, 9) if up else ri(-3, 1)
	pit(cx, cx + gap, y)
	cx += gap
	ground(cx, cx + 6, y + land_dy)
	_grow(cx - gap, y + land_dy - 10, gap, 10)
	cx += 6
	_route(cx, y + land_dy)
	_s_est += 1.3 + gap / 20.0
	return Vector2i(cx, y + land_dy)


func seg_disc_gate(x: int, y: int) -> Vector2i:
	var cx := x
	var gid := rng.randi()
	ground(cx, cx + 22, y)
	var wx := cx + 12
	if chance(0.6):
		# window variant: ring in a window in the wall, door below
		var win_top := y - ri(9, 11)
		block(wx, y - 22, 1, win_top - (y - 22))
		_ent({"t": "gate", "ring": _p(wx + 0.5, win_top + 1.5), "door": [int(wx * T), int((win_top + 3) * T), T, int((y - win_top - 3) * T)], "mode": "open", "id": gid},
			wx, win_top, 1, y - win_top)
	else:
		# high ring variant: ring floating before a full-height door
		block(wx, y - 22, 1, 12)
		_ent({"t": "gate", "ring": _p(cx + ri(4, 8), y - ri(7, 10)), "door": [int(wx * T), int((y - 10) * T), T, 10 * T], "mode": "open", "id": gid},
			wx, y - 10, 1, 10)
	if chance(0.4):
		oneway(cx + 4, y - 4, 3)
	cx += 22
	_route(cx, y)
	_s_est += 22 / RUN_TILES_PER_SEC + 1.4
	return Vector2i(cx, y)


func seg_disc_bridge(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 6, y)
	cx += 6
	var gap := ri(14, 18)
	pit(cx, cx + gap, y)
	var gid := rng.randi()
	var ring_x := cx + gap - ri(2, 5)
	var ring_y := y - ri(6, 9)
	_ent({"t": "gate", "ring": _p(ring_x, ring_y), "door": [int(cx * T), int(y * T), gap * T, T / 2], "mode": "bridge", "id": gid},
		cx, ring_y - 1, gap, y - ring_y + 1)
	cx += gap
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	_s_est += 2.0 + gap / RUN_TILES_PER_SEC
	return Vector2i(cx, y)


func seg_updraft(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 5, y)
	cx += 5
	var w := ri(7, 11)
	var rise := ri(6, 11)
	pit(cx, cx + w, y)
	_ent({"t": "wind", "r": [int((cx + 1) * T), int((y - rise - 6) * T), (w - 2) * T, (rise + 12) * T], "force": [0, -3400]},
		cx + 1, y - rise - 6, w - 2, rise + 12)
	cx += w
	ground(cx, cx + 6, y - rise)
	cx += 6
	_route(cx, y - rise)
	_s_est += 1.6
	return Vector2i(cx, y - rise)


func seg_lasers(x: int, y: int) -> Vector2i:
	var n := ri(2, 3 + dl(0, 2))
	var spacing := ri(4, 6)
	var l := n * spacing + 6
	ground(x, x + l, y)
	block(x + 2, y - 16, l - 4, 11)
	var on_t := snappedf(rf(0.8, 1.1) + d * 0.4, 0.05)
	var off_t := snappedf(rf(0.9, 1.2) - d * 0.3, 0.05)
	for i in n:
		var lx := x + 4 + i * spacing
		_ent({"t": "laser", "a": _p(lx, y - 5), "b": _p(lx, y), "on": on_t, "off": off_t, "phase": snappedf(i * 0.22, 0.01)}, lx, y - 5, 1, 5)
	_route(x + l, y)
	_s_est += l / RUN_TILES_PER_SEC + 0.6
	return Vector2i(x + l, y)


func seg_saws(x: int, y: int) -> Vector2i:
	var n := ri(2, 3)
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var start := cx
	for i in n:
		if chance(0.5):
			# gap with a saw bobbing vertically in it
			var gap := ri(4, 6)
			pit(cx, cx + gap, y)
			_ent({"t": "saw", "p": _p(cx + gap * 0.5, y - 1), "move": _p(0, -ri(3, 5)), "period": snappedf(rf(1.4, 2.2), 0.1), "phase": snappedf(rng.randf(), 0.01), "radius": 28},
				cx, y - 7, gap, 7)
			cx += gap
			ground(cx, cx + 4, y)
			cx += 4
		else:
			ground(cx, cx + 9, y)
			_ent({"t": "saw", "p": _p(cx + 2, y - 0.8), "move": _p(5, 0), "period": snappedf(rf(1.6, 2.4), 0.1), "phase": snappedf(rng.randf(), 0.01), "radius": 26},
				cx, y - 2, 9, 2)
			cx += 9
	_route(cx, y)
	_s_est += (cx - x) / RUN_TILES_PER_SEC + 0.5 * n
	return Vector2i(cx, y)


func seg_glass(x: int, y: int) -> Vector2i:
	ground(x, x + 16, y)
	block(x + 9, y - 22, 1, 13)
	_ent({"t": "glass", "r": [int((x + 9) * T), int((y - 9) * T), T, 9 * T]}, x + 9, y - 9, 1, 9)
	_route(x + 16, y)
	_s_est += 16 / RUN_TILES_PER_SEC + 0.3
	return Vector2i(x + 16, y)


func seg_drop(x: int, y: int) -> Vector2i:
	var h := ri(10, 12 + dl(0, 8))
	ground(x, x + 4, y)
	var wall_x := x + 11
	block(wall_x, y - 6, 2, h + 2)
	if chance(0.6):
		spikes(wall_x, y + ri(1, h - 5), 3, "left")
	if chance(0.5):
		grapple_pt(x + 8, y + h * 0.5, "static")
	ground(x + 4, wall_x, y + h)
	ground(wall_x, x + 18, y + h - 0)
	_route(x + 18, y + h)
	_s_est += 1.2 + h * 0.04
	return Vector2i(x + 18, y + h)


func seg_hammer_wall(x: int, y: int) -> Vector2i:
	ground(x, x + 20, y)
	var h := ri(14, 18)
	block(x + 10, y - h, 2, h)
	grapple_pt(x + 8, y - h - ri(2, 4), "static")
	if chance(0.5):
		grapple_pt(x + 15, y - h - ri(1, 3), "static")
	_route(x + 20, y)
	_s_est += 2.4
	return Vector2i(x + 20, y)


func seg_ramp_jump(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 8, y)
	if chance(0.6):
		_ent({"t": "booster", "r": [int((cx + 1) * T), int(y * T - 8), 5 * T, 8], "dir": 1}, cx + 1, y - 1, 5, 1)
	cx += 8
	var rl := ri(5, 7)
	var rh := ri(2, 4)
	# ramp polygon: rises from floor to rh tiles, then vertical drop
	var pts := [cx * T, y * T, (cx + rl) * T, (y - rh) * T, (cx + rl) * T, y * T]
	_s_polys.append({"pts": pts, "k": "ramp"})
	_grow(cx, y - rh, rl, rh)
	ground(cx, cx + rl, y)
	cx += rl
	var gap := ri(9, 12 + dl(0, 4))
	var land_dy := ri(-2, 3)
	pit(cx, cx + gap, y + maxi(0, land_dy))
	cx += gap
	ground(cx, cx + 6, y + land_dy)
	cx += 6
	_route(cx, y + land_dy)
	_s_est += (cx - x) / (RUN_TILES_PER_SEC * 1.4) + 0.4
	return Vector2i(cx, y + land_dy)


func seg_grip_ceiling(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var w := ri(14, 18 + dl(0, 8))
	var ch := y - ri(8, 10)
	grip(cx - 1, ch - 2, w + 2, 2)
	pit(cx, cx + w, y)
	cx += w
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	_s_est += w / 13.0 + 0.5
	return Vector2i(cx, y)


func seg_pillars(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var start := cx
	var n := ri(3, 5)
	var py := y
	for i in n:
		cx += ri(3, 4 + dl(0, 1))
		py = clampi(py + ri(-2, 2), y - 5, y + 2)
		ground(cx, cx + ri(1, 2), py)
		cx += 2
	cx += ri(3, 4)
	pit(start, cx, y + 3)
	ground(cx, cx + 5, py)
	cx += 5
	_route(cx, py)
	_s_est += (cx - x) / (RUN_TILES_PER_SEC * 0.8)
	return Vector2i(cx, py)


func seg_booster_gap(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 12, y)
	_ent({"t": "booster", "r": [int((cx + 2) * T), int(y * T - 8), 7 * T, 8], "dir": 1}, cx + 2, y - 1, 7, 1)
	cx += 12
	var gap := ri(11, 14)
	pit(cx, cx + gap, y)
	cx += gap
	var dy := ri(-1, 3)
	ground(cx, cx + 6, y + dy)
	cx += 6
	_route(cx, y + dy)
	_s_est += (cx - x) / (RUN_TILES_PER_SEC * 1.5) + 0.3
	return Vector2i(cx, y + dy)


func seg_zip_tower(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 6, y)
	var levels := ri(2, 3)
	var cy := y
	var side := 1
	var tx := cx + 6
	var h_total := 0
	for i in levels:
		var rise := ri(7, 9)
		cy -= rise
		h_total += rise
		var lx := tx + (0 if side > 0 else 6)
		oneway(lx, cy, 5)
		grapple_pt(lx + 2.5, cy - ri(3, 4), "static" if i == 0 else "")
		side = -side
	block(tx - 1, cy - 4, 1, h_total - 2)
	var top := cy
	ground(tx + 12, tx + 20, top)
	grapple_pt(tx + 12, top - 5, "static")
	ground(tx, tx + 12, y, "ground")
	_route(tx + 20, top)
	_s_est += 1.2 * levels + 1.0
	return Vector2i(tx + 20, top)


func seg_wrap_block(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var w := ri(16, 20)
	pit(cx, cx + w, y)
	block(cx + w * 0.3, y - 7, 5, 3)
	grapple_pt(cx + w * 0.3 + 7, y - 12, "static")
	grapple_pt(cx + w * 0.85, y - 9, "")
	cx += w
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	_s_est += w / 13.0 + 0.8
	return Vector2i(cx, y)


func add_sign(x: float, y: float, text: String) -> void:
	_ent({"t": "sign", "p": _p(x, y), "text": text}, x - 1, y - 3, 3, 3)


## Open fairway: running unencumbered + a long throw beats carrying.
func seg_fairway(x: int, y: int) -> Vector2i:
	var variant := ri(0, 2)
	var cx := x
	add_sign(x + 2, y, "FAIRWAY")
	match variant:
		0:  # open field with hurdles the disc sails over
			var l := ri(34, 50)
			ground(cx, cx + l, y)
			var hx := cx + ri(8, 12)
			while hx < cx + l - 8:
				if chance(0.6):
					block(hx, y - ri(1, 2), 1, 2)
				else:
					var rl := ri(3, 4)
					_s_polys.append({"pts": [hx * T, y * T, (hx + rl) * T, (y - 1) * T, (hx + rl * 2) * T, y * T], "k": "ramp"})
				hx += ri(8, 12)
			cx += l
			_s_est += l / (RUN_TILES_PER_SEC * 1.1)
		1:  # valley: the runner drops in and climbs out, the disc flies straight across
			ground(cx, cx + 6, y)
			cx += 6
			var w := ri(22, 30)
			var depth := ri(6, 9)
			ground(cx, cx + w, y + depth)
			var steps := int(ceil(depth / 3.0))
			for i in steps:
				oneway(cx + w - 4 - (steps - 1 - i) * 4, y + depth - 3 * (i + 1), 3)
			cx += w
			ground(cx, cx + 10, y)
			cx += 10
			_s_est += (w + 16) / (RUN_TILES_PER_SEC * 1.05) + 0.6
		_:  # high tailwind lane: lofted throws ride it
			var l2 := ri(36, 48)
			ground(cx, cx + l2, y)
			_ent({"t": "wind", "r": [int((cx + 6) * T), int((y - 16) * T), (l2 - 10) * T, 8 * T], "force": [1400, 0]}, cx + 6, y - 16, l2 - 10, 8)
			cx += l2
			_s_est += l2 / (RUN_TILES_PER_SEC * 1.1)
	_route(cx, y)
	return Vector2i(cx, y)


## Tight tunnel: low ceilings and kinks swallow throws, so carry the disc.
func seg_tunnel(x: int, y: int) -> Vector2i:
	var l := ri(20, 32)
	var cx := x
	ground(cx, cx + l + 6, y)
	add_sign(cx + 1, y, "TUNNEL")
	var top := y - 4
	var kink := chance(0.5)
	var kx := cx + 3 + l / 2
	if kink:
		# tunnel steps up through a short shaft halfway along
		block(cx + 3, top - 8, kx - (cx + 3), 8)
		block(kx + 3, top - 12, (cx + 3 + l) - (kx + 3), 8)
		ground(kx + 3, cx + 3 + l, y - 4)
		block(kx - 1, y - 2, 1, 2)
	else:
		block(cx + 3, top - 8, l, 8)
	var bx := cx + 6
	while bx < cx + l - 2:
		if kink and absi(bx - kx) < 5:
			bx += 4
			continue
		var floor_y := y if not (kink and bx > kx) else y - 4
		if chance(0.5):
			block(bx, floor_y - 1, 2, 1)
		else:
			block(bx, floor_y - 4, 2, 1.5)
		bx += ri(4, 6)
	cx += l + 6
	var end_y := y
	if kink:
		ground(cx - 3, cx + 4, y - 4)
		end_y = y - 4
		cx += 4
	_route(cx, end_y)
	_s_est += l / (RUN_TILES_PER_SEC * 0.85) + 0.4
	return Vector2i(cx, end_y)


## Downhill slope: slide down it to build speed, then launch off a kicker.
func seg_slope_run(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var l := ri(10, 16)
	var h := ri(5, 8)
	var kind := "ice" if ice_mode else "ramp"
	_s_polys.append({"pts": [cx * T, y * T, (cx + l) * T, (y + h) * T, cx * T, (y + h) * T], "k": kind})
	_grow(cx, y, l, h)
	var by := y + h
	ground(cx, cx + l + 4, by)
	cx += l + 4
	# kicker
	_s_polys.append({"pts": [cx * T, by * T, (cx + 3) * T, (by - 1.5) * T, (cx + 3) * T, by * T], "k": "ramp"})
	ground(cx, cx + 3, by)
	cx += 3
	var gap := ri(8, 12)
	pit(cx, cx + gap, by)
	cx += gap
	var land := by + ri(-1, 2)
	ground(cx, cx + 6, land)
	cx += 6
	_route(cx, land)
	_s_est += (cx - x) / (RUN_TILES_PER_SEC * 1.4)
	return Vector2i(cx, land)


## Gusty gap: grapple across while a crosswind pushes you (and your disc).
func seg_crosswind(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 5, y)
	cx += 5
	var w := ri(16, 22)
	var dirx := 1 if chance(0.65) else -1
	pit(cx, cx + w, y)
	_ent({"t": "wind", "r": [int(cx * T), int((y - 14) * T), w * T, 18 * T], "force": [1500 * dirx, -150]}, cx, y - 14, w, 18)
	var n := maxi(1, int(w / 9.0))
	for i in n:
		grapple_pt(cx + w * (i + 0.5) / n, y - ri(7, 9), "static")
	cx += w
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	_s_est += w / 13.0 + 0.6
	return Vector2i(cx, y)


# ============================================================ finale

func _finale(x: int, y: int) -> Vector2:
	var variant := ri(0, 4)
	var bx: float
	var by: float
	var end_y := y
	match variant:
		0:  # open green
			ground(x, x + 30, y)
			bx = x + 22; by = y
			if chance(0.5):
				block(x + 14, y - 3, 1, 3)
		1:  # island green across a pit (only the disc has to get there)
			ground(x, x + 8, y)
			var gap := ri(12, 18)
			pit(x + 8, x + 8 + gap, y)
			var iy := y - ri(0, 4)
			ground(x + 8 + gap, x + 8 + gap + 8, iy)
			bx = x + 8 + gap + 4; by = iy
		2:  # elevated green behind a lip
			ground(x, x + 16, y)
			var ey := y - ri(6, 9)
			ground(x + 16, x + 28, ey)
			block(x + 16, ey - 3, 1, 3)
			bx = x + 23; by = ey
			end_y = ey
		3:  # alcove: basket under a low roof, needs a flat line or a roller
			ground(x, x + 28, y)
			block(x + 14, y - 14, 14, 9)
			bx = x + 23; by = y
		_:  # guarded: moving blocker in front of the basket
			ground(x, x + 28, y)
			_ent({"t": "mover", "r": [int((x + 16) * T), int((y - 8) * T), T, 3 * T], "move": _p(0, 5), "period": 2.4, "phase": 0.0},
				x + 16, y - 9, 1, 9)
			bx = x + 22; by = y
	_grow(bx - 1, by - 4, 2, 4)
	_route(bx, by)
	_s_est += 2.5
	var end_x := x + 34
	ground(x + 28, end_x, end_y)
	block(end_x, end_y - 40, 2, 40)
	return Vector2(bx * T, by * T)


# ============================================================ shortcuts & decor

func _add_shortcuts() -> void:
	if route.size() < 6 or d < 0.2:
		return
	var tries := 1 + int(d * 2.0)
	for t in tries:
		if not chance(0.55 + d * 0.3):
			continue
		var i := ri(1, route.size() - 5)
		var j := i + ri(2, 4)
		var a: Array = route[i]
		var b: Array = route[j]
		var ax: float = a[0] / float(T)
		var bx: float = b[0] / float(T)
		if bx - ax < 18:
			continue
		var top: float = minf(a[1], b[1]) / T
		for k in range(i, j + 1):
			top = minf(top, route[k][1] / float(T))
		var sky: float = top - ri(8, 11)
		var n: int = int((bx - ax) / 10.0)
		var pts := []
		var ok := true
		for k in n:
			var px: float = ax + 3 + (bx - ax - 6) * (k + 0.5) / n
			var py: float = sky + rf(-1.5, 1.5)
			if _hits_solid(Rect2(px - 2, py - 2, 4, 4)):
				ok = false
				break
			pts.append(Vector2(px, py))
		if not ok or pts.is_empty():
			continue
		for p in pts:
			var kind := "boost" if chance(0.25) else "static"
			ents.append({"t": "grapple", "p": [int(p.x * T), int(p.y * T)], "k": kind, "sky": true})


func _hits_solid(r: Rect2) -> bool:
	for s in solids:
		var a: Array = s["r"]
		var h: float = a[3] if a[3] > 0 else 999 * T
		var sr := Rect2(a[0] / float(T), a[1] / float(T), a[2] / float(T), h / T)
		if sr.intersects(r):
			return true
	return false


func _add_decor() -> void:
	var kinds: Array = DECOR.get(theme, ["cone"])
	var busy := []
	for e in ents:
		if e.has("p"):
			busy.append(Vector2(e.p[0], e.p[1]))
		elif e.has("r"):
			busy.append(Vector2(e.r[0] + e.r[2] * 0.5, e.r[1]))
		elif e.has("ring"):
			busy.append(Vector2(e.ring[0], e.ring[1]))
	for s in solids:
		if not (s.k in ["ground", "block", "ice"]):
			continue
		var r: Array = s["r"]
		var w: int = r[2]
		if w < 3 * T:
			continue
		var x: float = r[0] + rf(1, 3) * T
		while x < r[0] + w - T:
			var pos := Vector2(x, r[1])
			var clear := true
			for bpos in busy:
				if bpos.distance_to(pos) < 3 * T:
					clear = false
					break
			if clear and chance(0.45):
				ents.append({"t": "decor", "p": [int(x), int(r[1])], "k": _pick(kinds), "s": snappedf(rf(0.7, 1.3), 0.05), "v": ri(0, 99)})
			x += rf(3, 8) * T


## Merge horizontally touching/overlapping floor pieces with the same top so
## the terrain draws as continuous slabs (no seams).
func _merge_grounds() -> void:
	var groups := {}
	var rest := []
	for s in solids:
		if s.k in ["ground", "ice"]:
			var key := "%s:%d:%d" % [s.k, s.r[1], s.r[3]]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(s)
		else:
			rest.append(s)
	var out := []
	for key in groups:
		var arr: Array = groups[key]
		arr.sort_custom(func(a, b): return a.r[0] < b.r[0])
		var cur: Dictionary = arr[0].duplicate(true)
		for i in range(1, arr.size()):
			var n: Dictionary = arr[i]
			var cur_end: int = cur.r[0] + cur.r[2]
			if n.r[0] <= cur_end:
				cur.r[2] = maxi(cur_end, n.r[0] + n.r[2]) - cur.r[0]
			else:
				out.append(cur)
				cur = n.duplicate(true)
		out.append(cur)
	out.sort_custom(func(a, b): return a.r[0] < b.r[0])
	solids = out + rest


func _compute_bounds() -> Rect2:
	var r := Rect2(0, -200, 100, 100)
	var first := true
	for s in solids:
		var a: Array = s["r"]
		var sr := Rect2(a[0], a[1], a[2], maxi(a[3], T))
		r = sr if first else r.merge(sr)
		first = false
	for e in ents:
		if e.has("p"):
			r = r.expand(Vector2(e.p[0], e.p[1]))
	return r


## Par = estimated time for a clean, confident run. Medals scale off par.
func _medals() -> Dictionary:
	var par := snappedf(est_time * 0.85, 0.01)
	return {
		"par": par,
		"ace": snappedf(par * 0.78, 0.01),
		"gold": par,
		"silver": snappedf(par * 1.3, 0.01),
		"bronze": snappedf(par * 1.8, 0.01),
	}
