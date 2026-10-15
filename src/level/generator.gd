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
const RUN_TILES_PER_SEC := 17.0
## Running empty-handed (Player.RUN_SPEED 858 px/s): how most of a course is
## run (throw it ahead, chase it). Timed pieces are synced to this.
const RUN_EMPTY := 858.0 / T
## 2: slide tunnels got a 48px ceiling (older saves are repaired on load)
## 3: long disc bridges
## 4: throw puzzles (roller plates, hammer lobs, chase gaps), stacked lanes,
##    slick gate walls (no wall-jumping over them), sunken baskets
## 5: optional bonus rings (a shallow throw drops a booster bridge) instead of
##    mandatory hammer lobs, any-throw fence lanes (roller-only lanes are rare,
##    signposted early and end on an uphill backstop), jump / slide laser
##    hurdles, mixed-up stacked lanes, climbing and descending courses
## 6: lob skylights (an optional forward lob through a mesa's skylight opens its tunnel),
##    vent shafts (an updraft up an enclosed tunnel) and drop shafts,
##    switchbacks, drop wells, glass floors, lift shafts, pad climbs,
##    tailwind gaps, pit launches, slide chutes, ring ledges
## 7: no green waves (blinking laser doors that make you wait)
## 8: no going round the pieces (one grippy wall climbs forever, so walls that
##    shut a piece are slick and out of reach): slick drop shaft / drop well /
##    stairwell walls, flat fence lanes, lob skylights retired, ring ledges with no other way up, glass floors under a mesa,
##    higher pit launches / pad climbs / updrafts, slide chutes into a cliff,
##    grapple gaps wider than an empty-handed jump, headwind crosswinds, long
##    disc bridges only; wall-mounted and floating baskets
const VERSION := 8
## Long disc bridges span at least this many tiles (> max double-jump reach).
const LONG_BRIDGE_MIN := 52
const SLIDE_CEIL := 1.5        # slide tunnel ceiling height, tiles
## Chase gaps: wider than any jump with the disc in hand (~19.4 tiles even off a
## slide), well inside an empty-handed jump + double jump (~33.7 tiles from a
## run). tools/reach_table.gd measures both.
const CHASE_GAP_MIN := 24
const CHASE_GAP_MAX := 28
## Slick walls this tall can't be jumped over (jump + double jump ~9 tiles).
const WALL_TALL := 12
## Over the wall: the mesa's tunnel headroom and length, and the parapet's
## height above the floor (out of jump reach; tools/piece_check.gd).
const LOB_TUNNEL_H := 4
const LOB_MESA_L := [16, 20]
const LOB_PARAPET_H := [12, 13]
const LOB_BACK_H := 26          # the back wall: tall enough to stop nearly any overthrow
## Tailwind gap: wider than an empty-handed slide jump (~37.7 tiles); the wind
## (px/s^2 along x) adds ~16 tiles to a jump + double jump: empty-handed
## (~33.7) clears it with room to spare, carrying the disc (~18.5) can't.
const TAILWIND_GAP := [40, 44]
## Pad climb: where the next island starts / where a full-speed empty-handed
## flight off a pad comes down, in tiles past the pad.
const PAD_LAND := [11, 30]
const TAILWIND_FORCE := 650.0
## Pit launch: pad aim, power, and how far above the entry floor the top is.
const PIT_LAUNCH_DIR := [0.15, -1.0]
const PIT_LAUNCH_POWER := 2000
const PIT_LAUNCH_RISE := [12, 13]
## Pad climb: each island is this much higher than the last (past jump +
## double jump + mantle, ~10.5 tiles) and its pads this strong.
const PAD_CLIMB_RISE := [11, 12]
const PAD_CLIMB_POWER := 1700
## Grapple gaps (swing chains, grip ceilings, wrap blocks, crosswinds): wider
## than an empty-handed slide jump (~37.7 tiles).
const GRAPPLE_GAP := [40, 46]
## Lob wall ring: tiles behind the wall's back face / above the floor
## (tuned with tools/piece_check.gd so a hammer gets there and flat throws don't).
const LOB_RING_X := [3.0, 5.0]
const LOB_RING_Y := [1.5, 2.5]

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
	"lasers":        {"w": 5.0,  "min_d": 0.15, "dir": 0},
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
	# throw puzzles: the runner can't get past without the right throw
	"roll_lane":     {"w": 1.2,  "min_d": 0.0, "dir": 1, "disc": true, "style": "throw"},
	"throw_lane":    {"w": 4.0,  "min_d": 0.0, "dir": 1, "disc": true, "style": "throw"},
	# retired in v5 (w 0: never picked; tools can still force it)
	"lob_wall":      {"w": 0.0,  "min_d": 0.15, "dir": 0, "disc": true, "style": "throw"},
	"bonus_ring":    {"w": 4.0,  "min_d": 0.0, "dir": 0, "disc": true, "style": "throw"},
	"chase_gap":     {"w": 4.0,  "min_d": 0.1, "dir": 0, "disc": true, "style": "throw"},
	"stacked":       {"w": 3.0,  "min_d": 0.25, "dir": 0, "disc": true},
	# big height changes: mostly on climbing / descending courses (see PROFILES)
	"climb_shaft":   {"w": 1.0,  "min_d": 0.0, "dir": -1},
	"cascade":       {"w": 1.0,  "min_d": 0.0, "dir": 1},
	# vertical tunnels: on any course
	"vent_shaft":    {"w": 3.0,  "min_d": 0.1, "dir": -1},
	"drop_shaft":    {"w": 3.0,  "min_d": 0.0, "dir": 1},
	# over the wall: any throw that clears the parapet drops in and opens the
	# tunnel. Retired in v8 (w 0): clearing a wall you can't jump means waiting
	# ~1.3 s for the disc to come back down, a stop no other door has
	"lob_skylight":  {"w": 0.0,  "min_d": 0.15, "dir": 0, "disc": true, "style": "throw"},
	# v6 pieces
	"switchback":    {"w": 2.5,  "min_d": 0.1, "dir": -1},
	"drop_well":     {"w": 2.5,  "min_d": 0.0, "dir": 1},
	"glass_floor":   {"w": 3.0,  "min_d": 0.1, "dir": 1, "disc": true, "style": "throw"},
	"lift_shaft":    {"w": 2.5,  "min_d": 0.25, "dir": -1},
	"pad_climb":     {"w": 2.5,  "min_d": 0.0, "dir": -1},
	"tailwind_gap":  {"w": 2.0,  "min_d": 0.2, "dir": 0, "style": "throw"},
	"pit_launch":    {"w": 2.5,  "min_d": 0.1, "dir": -1},
	"slide_chute":   {"w": 3.0,  "min_d": 0.0, "dir": 1},
	"ring_ledges":   {"w": 2.5,  "min_d": 0.15, "dir": -1, "disc": true},
	# Battle Rush pieces (battle: only picked on battle courses; "disc" here
	# only means "forced in every few segments", like the disc gates are)
	"arena_flat":    {"w": 6.0,  "min_d": 0.0, "dir": 0, "battle": true, "disc": true},
	"arena_tier":    {"w": 4.0,  "min_d": 0.15, "dir": 0, "battle": true, "disc": true},
	"arena_shield":  {"w": 3.0,  "min_d": 0.3, "dir": 0, "battle": true, "disc": true},
	"skirmish":      {"w": 7.0,  "min_d": 0.0, "dir": 0, "battle": true},
}

## Throw / disc pieces a battle course never uses (no disc to throw).
const BATTLE_BANNED := ["disc_gate", "disc_bridge", "glass", "hammer_wall", "roll_lane", "throw_lane", "lob_wall",
	"bonus_ring", "chase_gap", "stacked", "lob_skylight", "glass_floor", "ring_ledges", "tailwind_gap"]
const NAME_BATTLE := ["Siege", "Skirmish", "Onslaught", "Charge", "Assault", "Raid", "Crusade", "Vanguard", "Reckoning", "Rampage"]
const DOOR_H := 16             # arena doors are slick and out of reach (WALL_TALL + a margin)

## Course shapes: most run along, some climb or descend a long way.
##   up / down: weight multipliers for segments heading that way
##   lo / hi:   the cursor's floor row stays between these (tiles; up is negative)
const PROFILES := {
	"flat":    {"w": 64.0, "up": 1.0, "down": 1.0, "lo": -40, "hi": 30},
	"climb":   {"w": 18.0, "up": 5.0, "down": 0.08, "lo": -600, "hi": 6},
	"descent": {"w": 18.0, "up": 0.08, "down": 5.0, "lo": -6, "hi": 600},
}
## Segments only worth picking on a climbing / descending course.
const PROFILE_ONLY := {"climb_shaft": "climb", "cascade": "descent"}

## Segments that end at speed (slopes, boosters, pads): a chase gap right
## after one could be cleared with the disc in hand.
const FAST_EXITS := ["slide_chute", "tailwind_gap", "pit_launch", "slope_run", "ramp_jump", "booster_gap", "bounce", "slide_tunnel", "roll_lane", "throw_lane", "bonus_ring", "cascade"]

const THEME_BIAS := {
	"field": {"run_gaps": 1.5, "disc_gate": 1.6, "hammer_wall": 1.5, "bounce": 1.2, "chase_gap": 1.5, "bonus_ring": 1.4, "lob_skylight": 1.4, "glass_floor": 1.2, "pad_climb": 1.2},
	"cyber": {"lasers": 2.0, "slide_tunnel": 1.5, "zip_ledge": 1.4, "glass": 1.5, "throw_lane": 1.5, "stacked": 1.4, "drop_shaft": 1.4, "switchback": 1.3},
	"fantasy": {"swing_chain": 1.6, "grip_ceiling": 1.8, "pillars": 1.4, "wrap_block": 1.5, "bonus_ring": 1.3, "ring_ledges": 1.5, "switchback": 1.3},
	"heaven": {"bounce": 1.8, "updraft": 2.0, "disc_bridge": 1.6, "zip_tower": 1.4, "chase_gap": 1.4, "vent_shaft": 1.6, "pad_climb": 1.5, "tailwind_gap": 1.6},
	"foundry": {"saws": 2.0, "movers": 1.8, "chimney": 1.4, "booster_gap": 1.3, "throw_lane": 1.6, "stacked": 1.3, "vent_shaft": 1.5, "lift_shaft": 1.6, "drop_well": 1.3},
	"frost": {"ramp_jump": 2.0, "slide_tunnel": 1.6, "drop": 1.5, "booster_gap": 1.5, "slope_run": 3.0, "roll_lane": 1.8, "slide_chute": 2.0},
	"canyon": {"fairway": 1.8, "crosswind": 4.0, "swing_chain": 1.3, "bounce": 1.3, "hammer_wall": 1.3, "bonus_ring": 1.5, "chase_gap": 1.3, "lob_skylight": 1.5, "tailwind_gap": 1.8, "pit_launch": 1.3},
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
const PROFILE_NAMES := {"climb": ["Ascent", "Ladder", "Spire", "Climb", "Summit"], "descent": ["Descent", "Plunge", "Cascade", "Dive", "Freefall"]}

var rng := RandomNumberGenerator.new()
var d := 0.5
var theme := "cyber"
var ice_mode := false
var profile := "flat"

var solids: Array = []
var polys: Array = []
var ents: Array = []
var route: Array = []
var reserves: Array = []   # Array[Rect2] in tiles
var seg_log: Array = []
var sections: Array = []   # [{x0, x1, style}] in px: "throw" / "carry" / ""
var locks: Array = []      # [x0, x1] in tiles: no sky shortcut may skip these
## Tools (tools/test_cheese.gd): px rects the way through a piece passes
## through (inside the shaft, the tunnel behind the door...). Not saved.
var musts: Array = []
var est_time := 0.0
## Tools: place exactly these segments (in order) instead of picking, and
## this finale variant (-1: random).
var force_segments: Array = []
var force_finale := -1
var basket_rot := 0.0      # the finale's basket: mounted sideways / floating
var basket_float := false
## Battle Rush: enemies + arenas, no baskets or throw gates (see seg_arena_*)
var battle := false
var _aid := 0

# staging buffers for the segment currently being attempted
var _s_solids: Array = []
var _s_polys: Array = []
var _s_ents: Array = []
var _s_route: Array = []
var _s_locks: Array = []
var _s_musts: Array = []
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
	profile = _pick_profile()
	solids.clear(); polys.clear(); ents.clear(); route.clear(); reserves.clear(); seg_log.clear(); sections.clear(); locks.clear(); musts.clear()
	est_time = 0.0
	_aid = 0

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
	if not force_segments.is_empty():
		length = force_segments.size()
	for i in length:
		var force_disc := since_disc >= 4
		var placed := false
		for attempt in 8:
			var seg := _pick_segment(cur, last, force_disc and attempt < 5)
			if not force_segments.is_empty():
				seg = str(force_segments[i])
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
	basket_rot = 0.0
	basket_float = false
	var basket: Vector2 = _finale_battle(cur.x, cur.y) if battle else _finale(cur.x, cur.y)
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
	var name := "%s %s" % [_pick(NAME_A[theme]), _pick(NAME_BATTLE if battle else (NAME_B if profile == "flat" else PROFILE_NAMES[profile]))]
	# the version is in the id from v5 on: the same seed lays out differently,
	# so PBs / ghosts / splits of the older layout stay with that one
	var id := "%s%d_%s_%d_%d_v%d" % ["b" if battle else "g", seed_value, theme, int(round(d * 10)), length, VERSION]
	var out := {
		"version": VERSION,
		"id": id,
		"name": name,
		"seed": seed_value,
		"theme": theme,
		"difficulty": d,
		"length": length,
		"profile": profile,
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
	if battle:
		out["battle"] = {"weapon": "sword"}   # the weapon is picked at the start (Game.start_battle)
	if basket_rot != 0.0:
		out["basket_rot"] = basket_rot
	if basket_float:
		out["basket_float"] = true
	return out


# ============================================================ staging

func _begin() -> void:
	_s_solids = []; _s_polys = []; _s_ents = []; _s_route = []; _s_locks = []; _s_musts = []
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
	locks.append_array(_s_locks)
	musts.append_array(_s_musts)
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


## Too smooth to wall-jump on (Player._grippy_wall).
func slick(x: float, y: float, w: float, h: float) -> void:
	_solid(x, y, w, h, "slick")


## Runners can't pass a fence, discs fly straight through it.
func fence(x: float, y: float, w: float, h: float) -> void:
	_solid(x, y, w, h, "fence")


## Tools: the way through this piece passes through this rect (tiles).
func _must(x: float, y: float, w: float, h: float) -> void:
	_s_musts.append(Rect2(x * T, y * T, w * T, h * T).abs())


## No sky shortcut may pass over tiles x0..x1 (the throw is the point).
func lock(x0: float, x1: float) -> void:
	_s_locks.append([x0, x1])


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

func _pick_profile() -> String:
	var total := 0.0
	for k in PROFILES:
		total += float(PROFILES[k].w)
	var r := rng.randf() * total
	for k in PROFILES:
		r -= float(PROFILES[k].w)
		if r <= 0.0:
			return k
	return "flat"


func _pick_segment(cur: Vector2i, last: Array, force_disc: bool) -> String:
	var bias: Dictionary = THEME_BIAS.get(theme, {})
	var names := []
	var weights := []
	var total := 0.0
	for seg in SEGMENTS:
		var info: Dictionary = SEGMENTS[seg]
		if bool(info.get("battle", false)) != false and not battle:
			continue
		if battle and BATTLE_BANNED.has(seg):
			continue
		if d < info.min_d:
			continue
		if seg == last[1] or (seg == last[0] and seg != "run_gaps"):
			continue
		if force_disc and not info.get("disc", false):
			continue
		if seg == "chase_gap" and last[1] in FAST_EXITS:
			continue
		if PROFILE_ONLY.has(seg) and PROFILE_ONLY[seg] != profile:
			continue
		var w: float = info.w * bias.get(seg, 1.0)
		if w <= 0.0:
			continue
		var dir: int = info.dir
		var pf: Dictionary = PROFILES[profile]
		if dir < 0 and cur.y < int(pf.lo):
			continue
		if dir > 0 and cur.y > int(pf.hi):
			continue
		if profile == "flat":
			if dir < 0 and cur.y > 12:
				w *= 2.0
			if dir > 0 and cur.y < -18:
				w *= 2.2
		else:
			w *= float(pf.up) if dir < 0 else (float(pf.down) if dir > 0 else 1.0)
			if PROFILE_ONLY.has(seg):
				w *= 4.0
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
	var w := ri(GRAPPLE_GAP[0], GRAPPLE_GAP[1] + dl(0, 6))
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
	# the wall and door are slick (no wall-jumping over them): the throw is the
	# only way through
	if chance(0.6):
		# window variant: ring in a fenced window in the wall, door below
		var win_top := y - ri(9, 11)
		slick(wx, y - 24, 1, win_top - (y - 24))
		fence(wx, win_top, 1, 3)
		_ent({"t": "gate", "ring": _p(wx + 0.5, win_top + 1.5), "door": [int(wx * T), int((win_top + 3) * T), T, int((y - win_top - 3) * T)], "mode": "open", "slick": true, "id": gid},
			wx, win_top, 1, y - win_top)
	else:
		# high ring variant: ring floating before a full-height door
		slick(wx, y - 24, 1, 14)
		_ent({"t": "gate", "ring": _p(cx + ri(4, 8), y - ri(7, 10)), "door": [int(wx * T), int((y - 10) * T), T, 10 * T], "mode": "open", "slick": true, "id": gid},
			wx, y - 10, 1, 10)
	if chance(0.4):
		oneway(cx + 4, y - 4, 3)
	cx += 22
	_route(cx, y)
	lock(x, cx)
	_s_est += 22 / RUN_TILES_PER_SEC + 1.4
	return Vector2i(cx, y)


## Throw through the ring to materialise a bridge over the pit: wider than
## any double jump, even empty-handed off a slide, so the throw is the only
## way over. The ring hangs over the near half of the gap.
func seg_disc_bridge(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 6, y)
	cx += 6
	var gap := ri(LONG_BRIDGE_MIN, LONG_BRIDGE_MIN + 14)
	pit(cx, cx + gap, y)
	var gid := rng.randi()
	var ring_x := cx + ri(7, 14)
	var ring_y := y - ri(5, 8)
	_ent({"t": "gate", "ring": _p(ring_x, ring_y), "door": [int(cx * T), int(y * T), gap * T, T / 2], "mode": "bridge", "id": gid},
		cx, ring_y - 1, gap, y - ring_y + 1)
	cx += gap
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	lock(x, cx)
	_s_est += 2.0 + gap / RUN_TILES_PER_SEC
	return Vector2i(cx, y)


func seg_updraft(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 5, y)
	cx += 5
	var w := ri(7, 11)
	var rise := ri(12, 15)        # out of reach of a jump: ride the updraft
	pit(cx, cx + w, y)
	_ent({"t": "wind", "r": [int((cx + 1) * T), int((y - rise - 6) * T), (w - 2) * T, (rise + 12) * T], "force": [0, -3400]},
		cx + 1, y - rise - 6, w - 2, rise + 12)
	cx += w
	slick(cx, y - rise, 1, rise + 10)
	ground(cx + 1, cx + 6, y - rise)
	cx += 6
	_route(cx, y - rise)
	_s_est += 1.6
	return Vector2i(cx, y - rise)


## Laser hurdles: always-on beams in a low corridor, taken at full speed.
## Floor beams are jumped, beams hanging from the roof are slid under (they
## stop 32px above the floor: a slide clears them, standing does not). The
## spacing leaves room to land / stand up between them, so a clean rhythm of
## jumps and slides keeps all your speed.
func seg_lasers(x: int, y: int) -> Vector2i:
	var n := ri(3, 4 + dl(0, 2))
	var roof := y - 6
	var cx := x + 5
	var kinds: Array = []
	for i in n:
		kinds.append("jump" if chance(0.5) else "slide")
	if not ("jump" in kinds and "slide" in kinds):
		kinds[ri(0, n - 1)] = "slide" if kinds[0] == "jump" else "jump"
	var beams: Array = []
	var prev := ""
	for k in kinds:
		# after a jump you need to land first; after a slide, stand up and go
		cx += (ri(9, 11) if prev == "jump" else ri(6, 8)) if prev != "" else 0
		beams.append([cx, k])
		prev = k
	var l := cx + 8 - x
	ground(x, x + l, y)
	block(x + 2, roof - 10, l - 4, 10)
	for bm in beams:
		var lx: int = bm[0]
		if bm[1] == "jump":
			_ent({"t": "laser", "a": _p(lx, y - 1.5), "b": _p(lx, y), "on": 1.0, "off": 0.0, "phase": 0.0}, lx, y - 1.5, 1, 1.5)
		else:
			_ent({"t": "laser", "a": _p(lx, roof), "b": [int(lx * T), int(y * T) - 32], "on": 1.0, "off": 0.0, "phase": 0.0}, lx, roof, 1, y - roof)
	add_sign(x + 2, y, "LASERS")
	_must(x + 2, roof, l - 4, y - roof)
	_route(x + l, y)
	_s_est += l / RUN_TILES_PER_SEC + 0.15 * n
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
	slick(x + 9, y - 24, 1, 15)
	_ent({"t": "glass", "r": [int((x + 9) * T), int((y - 9) * T), T, 9 * T], "slick": true}, x + 9, y - 9, 1, 9)
	_route(x + 16, y)
	lock(x, x + 16)
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
	var w := ri(GRAPPLE_GAP[0], GRAPPLE_GAP[1] + dl(0, 4))
	var ch := y - ri(8, 10)
	grip(cx - 1, ch - 2, w + 2, 2)
	spikes(cx - 1, ch - 2, w + 2, "up")     # hang under it, don't run along the top
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
	var w := ri(GRAPPLE_GAP[0], GRAPPLE_GAP[1])
	pit(cx, cx + w, y)
	grapple_pt(cx + 9, y - 9, "static")
	block(cx + w * 0.4, y - 7, 5, 3)
	spikes(cx + w * 0.4, y - 7, 5, "up")    # swing round it, not hop off it
	grapple_pt(cx + w * 0.4 + 7, y - 12, "static")
	grapple_pt(cx + w * 0.82, y - 9, "")
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
	var w := ri(GRAPPLE_GAP[0], GRAPPLE_GAP[1])
	var dirx := -1     # a headwind: a tailwind carries a plain jump right over
	pit(cx, cx + w, y)
	_ent({"t": "wind", "r": [int(cx * T), int((y - 14) * T), w * T, 18 * T], "force": [1100 * dirx, -150]}, cx, y - 14, w, 18)
	var n := maxi(1, int(w / 9.0))
	for i in n:
		grapple_pt(cx + w * (i + 0.5) / n, y - ri(7, 9), "static")
	cx += w
	ground(cx, cx + 6, y)
	cx += 6
	_route(cx, y)
	_s_est += w / 13.0 + 0.6
	return Vector2i(cx, y)



# ============================================================ throw puzzles

## A ramp down from row y over l tiles to row y + h (the slope faces right).
func _ramp_down(x: float, y: float, l: float, h: float) -> void:
	_s_polys.append({"pts": [x * T, y * T, (x + l) * T, (y + h) * T, x * T, (y + h) * T], "k": "ice" if ice_mode else "ramp"})
	_grow(x, y, l, h)


## A ramp up from row y over l tiles to row y - h (the slope faces left).
func _ramp_up(x: float, y: float, l: float, h: float) -> void:
	_s_polys.append({"pts": [x * T, y * T, (x + l) * T, (y - h) * T, (x + l) * T, y * T], "k": "ice" if ice_mode else "ramp"})
	_grow(x, y - h, l, h)


## Roller target: a yellow plate on the floor of a low tunnel, behind a fence.
## Only a disc ROLLING over the plate sets it off (rollers), and the fence
## (runners can't pass, discs fly through) drops once it has. The tunnel's
## roof is slick and too high to jump onto, and the lane is level with its
## run-up, so you can throw into it from well back. Signposted from the start of a
## long run-up (roll it early), and the lane climbs out on an uphill ramp so a
## long roller rolls back instead of off the next drop.
func seg_roll_lane(x: int, y: int) -> Vector2i:
	return _fence_lane(x, y, true)


## The any-throw version: a ring hangs in the low tunnel behind the fence. Any
## throw low enough to fly into the tunnel (or a roller) opens it.
func seg_throw_lane(x: int, y: int) -> Vector2i:
	return _fence_lane(x, y, false)


func _fence_lane(x: int, y: int, roller: bool) -> Vector2i:
	var cx := x
	var run_up := ri(14, 18) if roller else 6
	ground(cx, cx + run_up, y)
	if roller:
		add_sign(cx + 2, y, "ROLLER")
	cx += run_up
	# level with the run-up (a ramp down into it hid the tunnel mouth from a
	# throw further back, and put the roof in reach from the top of the ramp)
	var fy := y
	if not roller:
		add_sign(cx - 2, fy, "THROW")
	var ceil_h := 3
	var tl := ri(20, 26)
	ground(cx, cx + tl + 6, fy)
	slick(cx, fy - ceil_h - 10, tl, 10)
	var fx := cx + ri(7, 10)
	var px := fx + ri(3, 5)
	if roller:
		_ent({"t": "gate", "plate": [int(px * T), int(fy * T) - 6, 3 * T, 6], "door": [int(fx * T), int((fy - ceil_h) * T), T, ceil_h * T],
			"mode": "open", "fence": true, "id": rng.randi()}, fx, fy - ceil_h, px + 3 - fx, ceil_h)
	else:
		_ent({"t": "gate", "ring": _p(px + 1.5, fy - 1.5), "door": [int(fx * T), int((fy - ceil_h) * T), T, ceil_h * T],
			"mode": "open", "fence": true, "id": rng.randi()}, fx, fy - ceil_h, px + 3 - fx, ceil_h)
	_must(cx, fy - ceil_h, tl, ceil_h)
	_route(cx + 2, fy)
	cx += tl + 6
	if roller:
		# uphill backstop: a roller that keeps going rolls back down into the lane
		var rl := ri(9, 11)
		var rh := 4
		_ramp_up(cx, fy, rl, rh)
		ground(cx, cx + rl, fy)
		cx += rl
		fy -= rh
		ground(cx, cx + 6, fy)
		cx += 6
	_route(cx, fy)
	lock(x, cx)
	_s_est += float(cx - x) / RUN_TILES_PER_SEC + (1.2 if roller else 0.8)
	return Vector2i(cx, fy)


## Bonus ring: a valley you can just run down into and climb out of, with a
## ring hanging low over its near side. Any shallow throw through it drops a
## booster bridge across the valley: no detour, and a speed kick. Optional,
## so it never stalls the run; it just rewards the throw.
func seg_bonus_ring(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 8, y)
	add_sign(cx + 2, y, "BONUS")
	cx += 8
	var w := ri(16, 22)
	var depth := ri(5, 7)
	ground(cx, cx + w, y + depth)
	var steps := int(ceil(depth / 3.0))
	for i in steps:
		oneway(cx + w - 4 - (steps - 1 - i) * 4, maxf(y + depth - 3 * (i + 1), y + 1), 3)   # under the bridge, never through it
	var gid := rng.randi()
	var ring_x := cx + ri(4, 8)
	var ring_y := y - rf(2.5, 4.5)
	_ent({"t": "gate", "ring": _p(ring_x, ring_y), "door": [int(cx * T), int(y * T), w * T, T / 2], "mode": "bridge", "id": gid},
		cx, ring_y - 1, w, y - ring_y + 1)
	_ent({"t": "booster", "r": [int((cx + 2) * T), int(y * T - 8), (w - 4) * T, 8], "dir": 1}, cx + 2, y - 1, w - 4, 1)
	cx += w
	ground(cx, cx + 8, y)
	cx += 8
	_route(cx, y)
	_s_est += float(cx - x) / (RUN_TILES_PER_SEC * 1.2) + 0.5
	return Vector2i(cx, y)


## Hammer lob: a tall slick wall with a door at its foot and the ring low
## down just behind it. A flat throw sails over and away; the disc has to drop
## steeply behind the wall: a hammer (flips and dives) or a stalled lob.
func seg_lob_wall(x: int, y: int) -> Vector2i:
	var l := ri(28, 32)
	ground(x, x + l, y)
	var wx := x + ri(13, 16)
	var h := ri(WALL_TALL, WALL_TALL + 2)
	var door_h := 4
	slick(wx, y - h, 2, h - door_h)
	_ent({"t": "gate", "ring": _p(wx + 2 + rf(LOB_RING_X[0], LOB_RING_X[1]), y - rf(LOB_RING_Y[0], LOB_RING_Y[1])),
		"door": [int(wx * T), int((y - door_h) * T), 2 * T, door_h * T], "mode": "open", "slick": true, "id": rng.randi()},
		wx, y - h, 8, h)
	add_sign(wx - 3, y, "LOB")
	_route(x + l, y)
	lock(x, x + l)
	_s_est += float(l) / RUN_TILES_PER_SEC + 1.6
	return Vector2i(x + l, y)


## Chase gap: wider than any jump with the disc in hand, an easy jump without
## it. Throw the disc across, run, jump, pick it up. Slick cliff faces (no
## wall-jumping out of the pit), long run-ups and run-outs with nothing to
## grapple, so it's the throw or nothing.
func seg_chase_gap(x: int, y: int) -> Vector2i:
	var cx := x
	var run_up := ri(20, 24)
	ground(cx, cx + run_up - 1, y)     # the cliff edge is the slick face's top
	add_sign(cx + run_up - 4, y, "CHASE")
	cx += run_up
	var gap := ri(CHASE_GAP_MIN, CHASE_GAP_MIN + dl(0, CHASE_GAP_MAX - CHASE_GAP_MIN))
	var dy := ri(-1, 3)        # a little down is fine: still out of reach carrying
	var depth := 8
	slick(cx - 1, y, 1, depth + 6)
	pit(cx, cx + gap, y + maxi(0, dy))
	cx += gap
	var ly := y + dy
	slick(cx, ly, 1, depth + 6 - dy)
	ground(cx + 1, cx + 22, ly)
	_grow(cx - gap, ly - 6, gap, 6)
	cx += 22
	_route(cx, ly)
	lock(x, cx)
	_s_est += float(cx - x) / RUN_TILES_PER_SEC + 1.4
	return Vector2i(cx, ly)


## Stacked lanes to pick from (two or three), joining again at the end. Each
## lane's challenge is picked separately so no two stacks play alike:
##   high  over a spiked roof: grapple swings, platform hops or a grip ceiling
##   mid   a corridor: a door with its ring (any throw), laser hurdles or a saw
##   low   a tunnel: a fence with a ring (any throw) or a roller plate, a
##         spiked slide section or laser hurdles
## The lanes are sealed from each other (solid slabs), so each lane's way
## through is its own.
func seg_stacked(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 8, y)
	cx += 8
	var w := ri(34, 46)
	var x0 := cx
	var xe := cx + w
	var three := chance(0.7)
	var hl := ri(4, 5)                 # low lane headroom
	var low_top := y - hl              # low lane roof (slab underside)
	var mid_floor := low_top - 1       # top of the first slab
	var high_floor := mid_floor
	var mid_top := mid_floor
	ground(x0, xe + 8, y)
	block(x0, mid_floor, w, 1)
	if three:
		var hm := ri(5, 7)
		mid_top = mid_floor - hm
		high_floor = mid_top - 1
		block(x0, high_floor, w, 1)
	spikes(x0 + 3, high_floor, w - 3, "up")
	var low_kind: String = _pick(["ring", "ring", "roller", "slide", "lasers"])
	var mid_kind: String = _pick(["door", "door", "lasers", "saw"])
	var high_kind: String = _pick(["swing", "swing", "hop", "grip"])
	# --- low lane
	match low_kind:
		"ring", "roller":
			var fx := xe - ri(7, 12)
			if low_kind == "roller":
				_ent({"t": "gate", "plate": [int((fx + 3) * T), int(y * T) - 6, 3 * T, 6], "door": [int(fx * T), int(low_top * T), T, hl * T],
					"mode": "open", "fence": true, "id": rng.randi()}, fx, low_top, 7, hl)
			else:
				_ent({"t": "gate", "ring": _p(fx + 4.5, y - hl * 0.5), "door": [int(fx * T), int(low_top * T), T, hl * T],
					"mode": "open", "fence": true, "id": rng.randi()}, fx, low_top, 7, hl)
		"slide":
			var sl := ri(8, 14)
			var sx := x0 + ri(8, w - sl - 6)
			block(sx, low_top, sl, (y - SLIDE_CEIL) - low_top)
			spikes(sx, y - SLIDE_CEIL, sl, "down")
		_:
			_laser_row(x0 + 6, xe - 4, y, low_top)
	# --- mid lane
	if three:
		match mid_kind:
			"door":
				var dx := xe - 3
				_ent({"t": "gate", "ring": _p(dx - ri(8, 14), mid_floor - (mid_floor - mid_top) * 0.5), "door": [int(dx * T), int(mid_top * T), T, (mid_floor - mid_top) * T],
					"mode": "open", "slick": true, "id": rng.randi()}, dx - 14, mid_top, 15, mid_floor - mid_top)
			"lasers":
				_laser_row(x0 + 6, xe - 4, mid_floor, mid_top)
			_:
				var sw := ri(6, 9)
				var sx2 := x0 + ri(10, w - sw - 6)
				_ent({"t": "saw", "p": _p(sx2, mid_floor - 0.8), "move": _p(sw, 0), "period": snappedf(rf(1.6, 2.4), 0.1), "phase": snappedf(rng.randf(), 0.01), "radius": 26},
					sx2, mid_floor - 2, sw, 2)
	# --- high lane: in from a grapple point before the stack
	grapple_pt(x0 - 3, high_floor - 7, "static")
	match high_kind:
		"hop":
			var hx := x0 + 2
			while hx < xe - 6:
				oneway(hx, high_floor - ri(3, 5), 3)
				hx += ri(7, 9)
		"grip":
			grip(x0 + 2, high_floor - 9, w - 4, 2)
			grapple_pt(xe - 2, high_floor - 6, "static")
		_:
			var hx := x0 + 2
			while hx < xe - 8:
				oneway(hx, high_floor - 4, 4)
				grapple_pt(hx + ri(6, 9), high_floor - ri(9, 11), "static")
				hx += ri(11, 14)
	add_sign(x0 - 4, y, "%d LANES" % (3 if three else 2))
	_must(x0, low_top, w, hl)                          # each lane's a way through
	_must(x0, mid_top, w, mid_floor - mid_top)
	_must(x0, high_floor - 12, w, 12)
	_route(x0 + 1, y)
	_route(xe + 8, y)
	lock(x, xe + 8)
	_s_est += float(xe + 8 - x) / RUN_TILES_PER_SEC + 1.5
	return Vector2i(xe + 8, y)


## Jump / slide laser hurdles between x0 and x1 in a corridor (floor row
## floor_y, roof row roof_y; see seg_lasers).
func _laser_row(x0: int, x1: int, floor_y: float, roof_y: float) -> void:
	var lx := x0
	var prev := ""
	while lx < x1:
		var k := "jump" if chance(0.5) else "slide"
		if k == "jump":
			_ent({"t": "laser", "a": _p(lx, floor_y - 1.5), "b": _p(lx, floor_y), "on": 1.0, "off": 0.0, "phase": 0.0}, lx, floor_y - 1.5, 1, 1.5)
		else:
			_ent({"t": "laser", "a": _p(lx, roof_y), "b": [int(lx * T), int(floor_y * T) - 32], "on": 1.0, "off": 0.0, "phase": 0.0}, lx, roof_y, 1, floor_y - roof_y)
		prev = k
		lx += ri(9, 11) if prev == "jump" else ri(6, 8)


## Over the wall: a mesa with a tunnel through it, its door shut, and a tall
## slick parapet up its front edge, out of reach. The whole roof is a fence
## (discs fall through, runners don't) with a tall wall at the far end: any
## throw that clears the parapet comes down into the tunnel, an overthrow off
## the back wall included, and opens the door. Lob it over on the run; the
## disc is on the tunnel floor as you go through. Short, and it's lying out
## front on your way: pick it up and go again.
func seg_lob_skylight(x: int, y: int) -> Vector2i:
	var cx := x
	var run_up := ri(12, 16)
	ground(cx, cx + run_up, y)
	add_sign(cx + 2, y, "OVER")
	cx += run_up
	var mx := cx
	var l := ri(LOB_MESA_L[0], LOB_MESA_L[1])
	var roof := y - LOB_TUNNEL_H                 # underside of the roof
	var top := roof - 2                           # the roof's top surface
	var pw := 2                                   # parapet / back wall thickness
	var ph := ri(LOB_PARAPET_H[0], LOB_PARAPET_H[1])
	var bx := mx + l - pw                         # the back wall
	ground(cx, cx + l + 10, y)
	slick(mx, y - ph, pw, ph - LOB_TUNNEL_H)      # parapet, down to the tunnel mouth
	fence(mx + pw, top, bx - mx - pw, 2)          # discs drop through, runners don't
	slick(bx, y - LOB_BACK_H, pw, LOB_BACK_H - LOB_TUNNEL_H)   # back wall: overthrows bounce back in
	# the door is set back in the tunnel mouth: flush with the front it met the
	# parapet in a seam on the face you run into, and contacts on a seam
	# between two bodies don't replay exactly. Anything that comes down into
	# the tunnel behind it opens it.
	var dx := mx + pw + 1
	_ent({"t": "gate", "ring": _p((dx + 1 + bx) * 0.5, roof + 1.2), "zone": [int((dx + 1) * T), int(roof * T), int((bx - dx - 1) * T), int((LOB_TUNNEL_H - 1) * T)],
		"door": [int(dx * T), int(roof * T), T, LOB_TUNNEL_H * T], "mode": "open", "slick": true, "id": rng.randi()}, mx, y - LOB_BACK_H, l, LOB_BACK_H)
	_must(mx, roof, l, LOB_TUNNEL_H)       # through the tunnel
	_route(mx - 3, y)
	cx = mx + l + 10
	_route(cx, y)
	lock(x, cx)   # no sky shortcut over the mesa
	_s_est += float(cx - x) / RUN_EMPTY + 0.8
	return Vector2i(cx, y)

# ============================================================ vertical tunnels

## Vent shaft: in at the foot of an enclosed tunnel, up an updraft (hold jump
## to rise) past spikes on the walls, out to the right under the roof at the
## top. The right wall is grippy too: wall-jumping up it works, just slower.
## The left one is slick, or you'd climb its back onto the roof and skip it.
func seg_vent_shaft(x: int, y: int) -> Vector2i:
	var h := ri(16, 20 + dl(0, 6))
	var top := y - h
	var sw := 6
	var sx := x + 6
	ground(x, sx + sw, y)
	slick(sx - 1, top - 6, 1, (y - 4) - (top - 6))       # left wall, open at the foot (slick: no climbing its back onto the roof)
	ground(sx + sw, sx + sw + 12, top)                   # its fill is the right wall
	block(sx - 1, top - 7, sw + 6, 1)                    # roof over the top and the way out
	_ent({"t": "wind", "r": [int(sx * T), int((top - 6) * T), sw * T, int((y - top + 6) * T)], "force": [0, -3400]},
		sx, top - 6, sw, y - top + 6)
	# spikes on alternate walls, clear of the foot and the way out
	var sy := y - 9    # room to slow down after running in
	var left := chance(0.5)
	var n := 0
	while sy - 3 > top + 1 and n < 2 + dl(0, 3):
		if left:
			spikes(sx, sy - 3, 3, "right")
		else:
			spikes(sx + sw, sy - 3, 3, "left")
		left = not left
		sy -= ri(4, 6)
		n += 1
	_must(sx, top - 6, sw, y - top + 2)
	_route(sx + 2, y)
	_route(sx + sw + 10, top)
	_s_est += 1.0 + h * 0.07
	return Vector2i(sx + sw + 12, top)


## Drop shaft: the floor ends at an enclosed tunnel straight down. Fall past
## spikes on alternate walls (steer between them) and run out along the
## corridor at the bottom.
func seg_drop_shaft(x: int, y: int) -> Vector2i:
	var h := ri(18, 24 + dl(0, 6))
	var bottom := y + h
	var sw := 5
	var sx := x + 8
	ground(x, sx, y)                                     # its fill is the left wall
	# right wall, open at the bottom: slick and out of reach from the rim, or
	# you'd wall-jump up its face and over the top
	slick(sx + sw, y - WALL_TALL - 1, 2, (bottom - 4) - (y - WALL_TALL - 1))
	ground(sx, sx + sw + 12, bottom)
	# spikes on alternate walls, close enough together that you steer, not just
	# fall. The first is on the near wall: running in, momentum takes you to
	# the far one, so its spikes start lower down, once you've had time to steer.
	var sy := y + 2
	var left := true
	var n := 0
	while sy + 3 <= bottom - 5 and n < 2 + dl(0, 4):
		if left:
			spikes(sx, sy, 3, "right")
		elif sy >= y + 6:
			spikes(sx + sw, sy, 3, "left")
		left = not left
		sy += ri(4, 5)
		n += 1
	_must(sx, y + 3, sw, h - 7)
	lock(x, sx + sw + 12)
	_route(sx - 2, y)
	_route(sx + sw + 10, bottom)
	_s_est += float(sx + sw + 12 - x) / RUN_TILES_PER_SEC + 0.6 + h * 0.02
	return Vector2i(sx + sw + 12, bottom)


# ============================================================ v6 pieces
# Sized for running empty-handed (RUN_EMPTY): throw it ahead, chase it.

## Switchback: a stairwell. Run right along the bottom, up through the gap at
## the end, back left along the next floor, up again, and out to the right at
## the top. Spike strips to hop on the floors of harder ones.
func seg_switchback(x: int, y: int) -> Vector2i:
	var k := 4 if d > 0.6 and chance(0.3) else 2    # climbs (even: the top floor runs right)
	var w := ri(18, 24)
	var hole := 5
	var x0 := x + 6
	var top := y - k * 6
	ground(x, x0 + w, y)
	slick(x0 - 1, top - 6, 1, (y - 4) - (top - 6))     # left wall, open at the foot (slick: no climbing its back onto the roof)
	block(x0 - 1, top - 7, w + 1, 1)                   # roof
	ground(x0 + w, x0 + w + 10, top)                   # its fill is the right wall
	for i in range(1, k + 1):
		var fy := y - i * 6
		var east := i % 2 == 1                         # where you come up into this floor
		if east:
			block(x0, fy, w - hole, 1)
			oneway(x0 + w - hole + 1, fy + 3, 3)
		else:
			block(x0 + hole, fy, w - hole, 1)
			oneway(x0 + 1, fy + 3, 3)
	# hop the spikes on the floors (never under a gap you come up through)
	if d > 0.35:
		for i in range(0, k + 1):
			if chance(0.5):
				var fy2 := y - i * 6
				spikes(x0 + hole + ri(3, w - hole * 2 - 5), fy2, 2, "up")
	_must(x0, top - 6, w, 5)
	_route(x0 + w - 3, y)
	_route(x0 + 3, y - 6)
	_route(x0 + w + 8, top)
	_s_est += float(w * (k + 1) + 16) / RUN_EMPTY + k * 0.45
	return Vector2i(x0 + w + 10, top)


## Drop well: the reverse. In along the top floor, down through the gap at its
## end, back the other way, down again, out along the bottom. A roof keeps
## you from hopping the wall and skipping it.
func seg_drop_well(x: int, y: int) -> Vector2i:
	var k := ri(2, 3)                                   # floors inside the well
	var w := ri(18, 24)
	var hole := 5
	var x0 := x + 6
	var bottom := y + k * 6
	ground(x, x0, y)                                    # its fill is the left wall
	block(x0, y - 5, w, 1)                              # roof
	# right wall, open at the foot: slick, and well over the roof (you can hop
	# up onto the roof, but not over the wall from it)
	slick(x0 + w, y - 6 - WALL_TALL, 1, (bottom - 4) - (y - 6 - WALL_TALL))
	ground(x0, x0 + w + 10, bottom)
	for i in k:
		var fy := y + i * 6
		var east := i % 2 == 0                          # the gap you drop through
		if east:
			block(x0, fy, w - hole, 1)
		else:
			block(x0 + hole, fy, w - hole, 1)
		if d > 0.3 and chance(0.6):
			spikes(x0 + hole + ri(3, w - hole * 2 - 5), fy, 2, "up")
	_must(x0, y + 1, w, bottom - y - 2)
	lock(x, x0 + w + 10)
	_route(x0 + 2, y)
	_route(x0 + w + 8, bottom)
	_s_est += float(w * k + 16) / RUN_EMPTY + k * 0.3
	return Vector2i(x0 + w + 10, bottom)


## Glass floor: a pane in the floor ahead and a tall slick mesa straight after
## it. Throw the disc down through the pane and drop into the lane that runs
## under the mesa (the disc lands in it too). There's no way over the top.
func seg_glass_floor(x: int, y: int) -> Vector2i:
	var x0 := x + 8
	var w := ri(34, 40)
	var xe := x0 + w
	var gx := x0 + ri(8, 11)
	ground(x, x0, y)
	block(x0, y, gx - x0, 1)
	_ent({"t": "glass", "r": [int(gx * T), int(y * T), 6 * T, T], "slick": true}, gx, y, 6, 1)   # wide: at full speed you still drop in
	var mx := gx + 6 + ri(1, 2)
	block(gx + 6, y, mx - gx - 6, 1)
	# the mesa: its underside is the lane's roof, its top far out of reach
	slick(mx, y - WALL_TALL - 1, xe - mx, WALL_TALL + 2)
	ground(x0, xe + 10, y + 5)
	add_sign(x + 2, y, "GLASS")
	_must(x0, y + 1, w, 4)
	_route(x0 + 2, y)
	_route(xe + 8, y + 5)
	lock(x, xe + 10)
	_s_est += float(xe + 10 - x) / RUN_EMPTY + 1.4
	return Vector2i(xe + 10, y + 5)


## Lift shaft: platforms riding up and down a shaft, one side then the other.
## Step on one at the bottom of its run, ride it up, hop across to the next.
## Out to the right at the top.
func seg_lift_shaft(x: int, y: int) -> Vector2i:
	var n := ri(2, 3)
	var sw := 10
	var sx := x + 6
	var m := ri(6, 7)
	ground(x, sx + sw, y)
	var py := y - 2.0      # the first one bottoms out a jump up, with room to stand under it
	var left := true
	var period := snappedf(rf(2.6, 3.2) - d * 0.4, 0.1)
	for i in n:
		var px := sx + (1 if left else sw - 4)
		_ent({"t": "mover", "r": [int(px * T), int(py * T), 3 * T, T / 2], "move": _p(0, -m), "period": period, "phase": snappedf(0.5 * i, 0.01)},
			px, py - m - 1, 3, m + 2)
		py -= m + 1
		left = not left
	var top := int(ceil(py)) + 1
	slick(sx - 1, top - 6, 1, (y - 4) - (top - 6))     # left wall, open at the foot (slick: no climbing its back)
	block(sx - 1, top - 7, sw + 7, 1)                  # roof
	ground(sx + sw, sx + sw + 10, top)                 # its fill is the right wall
	_must(sx, top - 6, sw, y - top + 2)
	_route(sx + 2, y)
	_route(sx + sw + 8, top)
	_s_est += 1.0 + n * period * 0.9
	return Vector2i(sx + sw + 10, top)


## Pad climb: islands stepping up over a pit, a pad near the far end of each
## that throws you up onto the next (each is out of reach of a jump, with a
## slick front). The islands are long: a full-speed,
## empty-handed runner flies about 28 tiles off a pad, one carrying the disc
## about half that, and both land on the next island.
func seg_pad_climb(x: int, y: int) -> Vector2i:
	var cx := x
	var cy := y
	var n := ri(2, 3)
	var start := cx
	ground(cx, cx + 6, cy)
	var pad_x := cx + 4
	var dir := Vector2(0.45, -1.0).normalized()
	for i in n:
		_ent({"t": "pad", "p": _p(pad_x, cy), "dir": [dir.x, dir.y], "power": PAD_CLIMB_POWER}, pad_x - 1, cy - 16, 2, 16)
		_must(pad_x - 1.5, cy - 2, 3, 2)
		var land := pad_x + PAD_LAND[0]
		var rise := ri(PAD_CLIMB_RISE[0], PAD_CLIMB_RISE[1])
		cy -= rise
		var last := i == n - 1
		var len := (PAD_LAND[1] - PAD_LAND[0]) + (10 if last else 2)
		slick(land, cy, 1, y + 4 - cy)        # its front, down to the pit floor: no wall-jumping up it
		ground(land + 1, land + len, cy)
		_grow(pad_x, cy - 10, land - pad_x, 10)
		_route(land + 2, cy)
		pad_x = land + len - 3
		cx = land + len
	pit(start + 6, cx, y)
	_route(cx, cy)
	_s_est += 1.3 * n + 0.4
	return Vector2i(cx, cy)


## Tailwind gap: a gap too wide for any jump, with a strong tailwind blowing
## across it. Flat out empty-handed (or off a slide) the wind carries you
## over; carrying the disc it doesn't. Throw it over first: the wind takes the
## disc too.
func seg_tailwind_gap(x: int, y: int) -> Vector2i:
	var cx := x
	var run_up := ri(16, 20)
	ground(cx, cx + run_up, y)
	add_sign(cx + 2, y, "TAILWIND")
	cx += run_up
	var gap := ri(TAILWIND_GAP[0], TAILWIND_GAP[1])
	pit(cx, cx + gap, y)
	_ent({"t": "wind", "r": [int((cx - 2) * T), int((y - 14) * T), (gap + 2) * T, 16 * T], "force": [TAILWIND_FORCE, 0]},
		cx - 2, y - 14, gap + 2, 16)
	cx += gap
	ground(cx, cx + 10, y)
	cx += 10
	_route(cx, y)
	lock(x, cx)
	_s_est += float(cx - x) / RUN_EMPTY + 0.6
	return Vector2i(cx, y)


## Pit launch: drop into a pit onto a pad that fires you straight back up, up
## past a tall slick wall and onto the ledge high above it.
func seg_pit_launch(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 6, y)
	cx += 6
	var depth := ri(5, 7)
	var pw := 8
	var floor_y := y + depth
	ground(cx, cx + pw, floor_y)
	var dir := Vector2(PIT_LAUNCH_DIR[0], PIT_LAUNCH_DIR[1]).normalized()
	# at the foot of the far wall: running in at full speed you land right on it
	_ent({"t": "pad", "p": _p(cx + pw - 0.9, floor_y), "dir": [dir.x, dir.y], "power": PIT_LAUNCH_POWER}, cx + pw - 2, floor_y - 1, 2, 1)
	cx += pw
	var top := y - ri(PIT_LAUNCH_RISE[0], PIT_LAUNCH_RISE[1])
	slick(cx, top, 1, floor_y - top)
	ground(cx + 1, cx + 12, top)     # not over the slick face: it would be grippy again
	_grow(cx - pw, top - 10, pw + 6, 10)
	_must(cx - pw, y + 1, pw, depth - 1)
	_route(cx - pw + 2, floor_y)
	cx += 12
	_route(cx, top)
	_s_est += float(cx - x) / RUN_EMPTY + 0.9
	return Vector2i(cx, top)


## Slide chute: a steep ramp down into a low tunnel hung with spikes, cut
## into a cliff (slide through it at speed), out over a kicker and across a gap.
func seg_slide_chute(x: int, y: int) -> Vector2i:
	var cx := x
	ground(cx, cx + 4, y)
	cx += 4
	var rl := ri(9, 12)
	var rh := ri(6, 8)
	_ramp_down(cx, y, rl, rh)
	var fy := y + rh
	ground(cx, cx + rl, fy)
	cx += rl
	var tl := ri(8, 12)
	ground(cx, cx + tl + 6, fy)
	# cut into a cliff: from the top of the chute you can't jump over it
	slick(cx, y - WALL_TALL + 1, tl, (fy - SLIDE_CEIL) - (y - WALL_TALL + 1))
	spikes(cx, fy - SLIDE_CEIL, tl, "down")
	_must(cx, fy - SLIDE_CEIL, tl, SLIDE_CEIL)
	cx += tl
	_route(cx + 1, fy)
	cx += 2
	var kl := 4
	_ramp_up(cx, fy, kl, 1.5)
	ground(cx, cx + kl, fy)
	cx += kl
	var gap := ri(14, 18)
	pit(cx, cx + gap, fy)
	cx += gap
	var ly := fy + ri(0, 2)
	ground(cx, cx + 8, ly)
	_grow(cx - gap, ly - 8, gap, 8)
	cx += 8
	_route(cx, ly)
	_s_est += float(cx - x) / (RUN_EMPTY * 1.1) + 0.3
	return Vector2i(cx, ly)


## Ring ledges: a tall slick cliff, out of reach from the floor. A ring hangs
## high in front of it: hit it and a wide ledge appears halfway up, a double
## jump from the floor and one from the top. There's no other way up; a throw
## through the ring sails on up onto the top, where you pick it up.
func seg_ring_ledges(x: int, y: int) -> Vector2i:
	var cx := x
	var run := ri(16, 20)
	ground(cx, cx + run, y)
	var wx := cx + run
	var h := ri(13, 14)
	var top := y - h
	slick(wx, top, 1, h)          # no wall-jumping up the face
	ground(wx + 1, wx + 12, top)
	var gid := rng.randi()
	var ledge_y := y - 6
	_ent({"t": "gate", "ring": _p(wx - ri(5, 8), top - rf(1.5, 3.0)), "door": [int((wx - 7) * T), int(ledge_y * T), 7 * T, T / 2], "mode": "bridge", "id": gid},
		wx - 9, top - 4, 9, y - top + 4)
	add_sign(cx + 2, y, "RING")
	_route(cx + 2, y)
	cx = wx + 12
	_route(cx, top)
	lock(x, cx)
	_s_est += float(cx - x) / RUN_EMPTY + 1.6
	return Vector2i(cx, top)


# ============================================================ height

## Climbing shaft: walk in under a hanging wall, then up ledges on alternate
## sides (wall-jump the walls, or zip to the point over the top) and out
## onto a ledge high above.
func seg_climb_shaft(x: int, y: int) -> Vector2i:
	var h := ri(14, 20 + dl(0, 6))
	var top := y - h
	var sw := 8
	var sx := x + 6
	ground(x, sx + sw, y)
	block(sx - 1, top - 3, 1, (y - 4) - (top - 3))      # hanging left wall
	var ly := y - 4
	var left := false
	while ly > top:
		oneway(sx if left else sx + sw - 3, ly, 3)
		left = not left
		ly -= 4
	ground(sx + sw, sx + sw + 8, top)                  # its fill is the right wall
	grapple_pt(sx + sw * 0.5, top - 6, "static")
	if d > 0.5 and chance(0.5):
		spikes(sx + sw, y - 3, 2, "left")
	_route(sx + 2, y)
	_route(sx + sw + 8, top)
	_s_est += 1.0 + h * 0.09
	return Vector2i(sx + sw + 8, top)


## Cascade: a long way down in drops and slides. Ledges step down and right,
## some joined by slopes you can slide down for speed.
func seg_cascade(x: int, y: int) -> Vector2i:
	var cx := x
	var cy := y
	ground(cx, cx + 4, cy)
	cx += 4
	var n := ri(3, 5)
	for i in n:
		if chance(0.45):
			var l := ri(6, 10)
			var hgt := ri(3, 6)
			_ramp_down(cx, cy, l, hgt)
			cy += hgt
			ground(cx, cx + l, cy)
			cx += l
		else:
			cy += ri(5, 9)
			if d > 0.4 and chance(0.3):
				spikes(cx + 1, cy, 1, "up")
				ground(cx, cx + 6, cy)
				cx += 6
				_route(cx, cy)
				continue
		var lw := ri(4, 7)
		ground(cx, cx + lw, cy)
		cx += lw
		_route(cx, cy)
	ground(cx, cx + 4, cy)
	cx += 4
	_route(cx, cy)
	_s_est += float(cx - x) / (RUN_TILES_PER_SEC * 1.2) + 0.25 * n
	return Vector2i(cx, cy)


# ============================================================ finale

func _finale(x: int, y: int) -> Vector2:
	# now and then the basket is somewhere odd: on the end wall, or floating
	var variant := 7 + ri(0, 1) if chance(0.16) else ri(0, 6)
	if force_finale >= 0:
		variant = force_finale
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
		4:  # guarded: moving blocker in front of the basket
			ground(x, x + 28, y)
			_ent({"t": "mover", "r": [int((x + 16) * T), int((y - 8) * T), T, 3 * T], "move": _p(0, 5), "period": 2.4, "phase": 0.0},
				x + 16, y - 9, 1, 9)
			bx = x + 22; by = y
		5:  # sunken: the basket sits in a dip, its chains level with the lip
			# you stand on, so a roller rolls straight off the lip into them
			# (and a skip skips in)
			ground(x, x + 20, y)
			var sink := 3
			ground(x + 20, x + 34, y + sink)
			bx = x + 22.5; by = y + sink
			end_y = y + sink
		7:  # mounted sideways on the end wall: its mouth opens up and down,
			# so it's a drop-in (lob it down just in front of the wall)
			ground(x, x + 30, y)
			bx = x + 34; by = y - rf(3.0, 5.0)
			basket_rot = -PI / 2.0
		8:  # floating in the air: over the green, or over a pit
			if chance(0.5):
				ground(x, x + 30, y)
			else:
				ground(x, x + 14, y)
				pit(x + 14, x + 28, y)
				ground(x + 28, x + 30, y)
			bx = x + 21; by = y - rf(4.5, 6.0)
			basket_float = true
		_:  # bowl: a ramp runs down into the basket (rollers love it)
			ground(x, x + 10, y)
			var drop := ri(3, 5)
			_ramp_down(x + 10, y, 9, drop)
			ground(x + 10, x + 34, y + drop)
			bx = x + 22; by = y + drop
			end_y = y + drop
	if variant == 7:
		_grow(bx - 5, by - 1.5, 5, 3)
		_route(bx - 4, y)
	else:
		_grow(bx - 1, by - 4, 2, 4)
		_route(bx, by if variant != 8 else y)
	_s_est += 2.5
	var end_x := x + 34
	ground(x + 28, end_x, end_y)
	block(end_x, end_y - 40, 2, 40)
	if variant >= 5:
		lock(x, end_x)   # no sky line straight to the chains
	return Vector2(bx * T, by * T)


# ============================================================ battle rush

func enemy(kind: String, x: float, y: float, x0: float, x1: float, aid := -1) -> void:
	_ent({"t": "enemy", "k": kind, "p": [int(round(x * T)), int(round(y * T))], "x0": int(round(x0 * T)), "x1": int(round(x1 * T)), "a": aid},
		x0 - 1, y - 3, x1 - x0 + 2, 3)


## Enemies for an arena of `w` tiles: [kind, offset from the first inner tile, platform height].
func _arena_plan(w: int, style: String) -> Array:
	var grunts := 1 + dl(1, 3)
	var archers := dl(0, 2)
	var guards := 0 if d < 0.25 else dl(0, 2)
	match style:
		"tier":
			archers += 1
		"shield":
			guards = 1 + dl(1, 2)
			grunts = maxi(1, grunts - 1)
	var kinds := []
	for i in guards:
		kinds.append("guard")
	for i in grunts:
		kinds.append("grunt")
	var plan := []
	var n := kinds.size() + archers
	var k := 0
	for kind in kinds:
		var off := int(w * 0.38 + (w * 0.5) * float(k) / maxf(n - 1, 1.0))
		plan.append([kind, off + ri(-2, 2), 0])
		k += 1
	for i in archers:
		var off2 := int(w * 0.38 + (w * 0.5) * float(k) / maxf(n - 1, 1.0))
		plan.append(["archer", off2 + ri(-1, 1), 3 if style == "tier" else 0])
		k += 1
	return plan


## Door to door arena: the way in closes behind the runner, the way out opens
## once everything inside is dead (Arena). Returns the cursor.
func _arena(x: int, y: int, w: int, style: String) -> Vector2i:
	_aid += 1
	var aid := _aid
	var ex := x + 6                 # entry door tile
	var in0 := ex + 1
	var in1 := in0 + w              # exit door tile
	ground(x, in1 + 9, y)
	var top := y - DOOR_H
	_ent({"t": "arena", "id": aid, "r": [in0 * T, top * T, w * T, DOOR_H * T], "entry": [ex * T, top * T, T, DOOR_H * T],
		"exit": [in1 * T, top * T, T, DOOR_H * T], "spawn": [(ex - 3) * T, y * T], "leader": false},
		x, top, in1 + 9 - x, DOOR_H + 1)
	var plan := _arena_plan(w, style)
	for it in plan:
		var kind: String = it[0]
		var ox: int = clampi(int(it[1]), 5, w - 4)
		var px := in0 + ox
		var plat: int = it[2]
		if plat > 0:
			block(px - 2, y - plat, 4, 1)
			enemy(kind, px, y - plat, px, px, aid)
		elif kind == "archer":
			enemy(kind, px, y, px, px, aid)
		else:
			enemy(kind, px, y, maxi(in0 + 3, px - 5), mini(in1 - 3, px + 5), aid)
	if style == "tier":
		# a raised ledge in the middle: cover and a jump-in for the sword
		block(in0 + int(w * 0.3), y - 3, 3, 1)
	_route(ex - 2, y)
	_route(in1 + 2, y)
	lock(x - 2, in1 + 9)
	_s_est += float(w + 14) / RUN_EMPTY + 1.4 * plan.size() + 2.5
	return Vector2i(in1 + 9, y)


func seg_arena_flat(x: int, y: int) -> Vector2i:
	return _arena(x, y, 34 + dl(0, 10), "flat")


func seg_arena_tier(x: int, y: int) -> Vector2i:
	return _arena(x, y, 38 + dl(0, 10), "tier")


func seg_arena_shield(x: int, y: int) -> Vector2i:
	return _arena(x, y, 36 + dl(0, 10), "shield")


## An open field with a few enemies, no doors: kill them or run through.
func seg_skirmish(x: int, y: int) -> Vector2i:
	var len := 40 + dl(0, 14)
	ground(x, x + len, y)
	var n := 2 + dl(0, 3)
	var spread := float(len - 16) / maxf(n, 1)
	for i in n:
		var px := x + 10 + int(spread * i + ri(0, 3))
		var r := rng.randf()
		if d > 0.3 and r < 0.2:
			enemy("guard", px, y, px - 4, px + 4)
		elif r < 0.55:
			enemy("grunt", px, y, px - 6, px + 6)
		else:
			var plat := 4 if chance(0.5) else 0
			if plat > 0:
				block(px - 2, y - plat, 4, 1)
			enemy("archer", px, y - plat, px, px)
	_route(x + len, y)
	_s_est += float(len) / RUN_EMPTY + 0.8 * n
	return Vector2i(x + len, y)


## The leader's arena: no way out, the run ends when the leader falls.
func _finale_battle(x: int, y: int) -> Vector2:
	_aid += 1
	var aid := _aid
	var w := 46
	var ex := x + 6
	var in0 := ex + 1
	var in1 := in0 + w
	ground(x, in1 + 2, y)
	block(in1, y - 40, 2, 40)         # the back wall
	var top := y - DOOR_H
	_ent({"t": "arena", "id": aid, "r": [in0 * T, top * T, w * T, DOOR_H * T], "entry": [ex * T, top * T, T, DOOR_H * T],
		"exit": [], "spawn": [(ex - 3) * T, y * T], "leader": true}, x, top, in1 + 2 - x, DOOR_H + 1)
	var lx := in1 - 9
	enemy("leader", lx, y, in0 + int(w * 0.45), in1 - 4, aid)
	# escorts, and ledges for the archers (clear of the leader's mouth)
	var esc := 2 + dl(0, 2)
	for i in esc:
		var px := in0 + 8 + int((w * 0.45) * float(i) / maxf(esc, 1.0)) + ri(0, 3)
		enemy("grunt" if i % 2 == 0 or d < 0.3 else "guard", px, y, px - 4, px + 4, aid)
	var ax := in0 + int(w * 0.25)
	block(ax - 2, y - 3, 4, 1)
	enemy("archer", ax, y - 3, ax, ax, aid)
	if d > 0.4:
		var bx := in0 + int(w * 0.6)
		block(bx - 2, y - 3, 4, 1)
		enemy("archer", bx, y - 3, bx, bx, aid)
	_route(ex - 2, y)
	_route(lx, y)
	lock(x - 2, in1 + 2)
	_s_est += float(w + 10) / RUN_EMPTY + 1.4 * (esc + 3) + 8.0
	return Vector2(lx * T, y * T)


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
		if bx - ax < 18 or _locked(ax - GRAPPLE_RANGE, bx + GRAPPLE_RANGE):
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


## Any locked span (throw puzzles) overlapping tiles x0..x1?
func _locked(x0: float, x1: float) -> bool:
	for lk in locks:
		if x1 > float(lk[0]) and x0 < float(lk[1]):
			return true
	return false


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
