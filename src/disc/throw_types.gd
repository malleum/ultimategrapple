extends RefCounted
## Throw archetypes. 2D side view: real-world curve (hyzer/anhyzer) is remapped
## to lift profile + attitude drift (fade = nose drops as disc slows).
##
## speed      launch speed (px/s) at full power
## cl0 / cla  lift coefficient at zero AoA / per radian of AoA
## cd0 / cda  drag coefficients (parabolic around a0)
## lift       global lift multiplier
## flip_t     seconds until the disc "flips over" (hammer/thumber) ; 0 = never
## flip_lift  lift multiplier after flipping (negative = pushes down)
## fade_v     speed (px/s) below which fade kicks in
## fade       fade strength (rad/s of nose drop at full fade)
## grav       gravity on the disc (px/s^2)
## move_pen   multiplier on moving-throw spray/range penalty
## spin       base spin factor (before snap)
## roll       converts to rolling on ground contact
## trim       initial nose attitude offset (rad) relative to aim

const TYPES := [
	{"id": "backhand", "name": "BACKHAND", "icon": "BH", "speed": 1500.0, "cl0": 0.16, "cla": 1.6, "cd0": 0.075, "cda": 2.2,
		"lift": 1.0, "flip_t": 0.0, "flip_lift": 1.0, "fade_v": 650.0, "fade": 0.9, "grav": 950.0,
		"move_pen": 1.0, "spin": 1.0, "roll": false, "trim": 0.0,
		"desc": "Stable glider. Long float, gentle late fade."},
	{"id": "forehand", "name": "FOREHAND", "icon": "FH", "speed": 1700.0, "cl0": 0.1, "cla": 1.3, "cd0": 0.09, "cda": 2.4,
		"lift": 0.8, "flip_t": 0.0, "flip_lift": 1.0, "fade_v": 900.0, "fade": 1.9, "grav": 1000.0,
		"move_pen": 1.1, "spin": 0.9, "roll": false, "trim": -0.05,
		"desc": "Fast and flat. Punches through wind, dips hard at the end."},
	{"id": "hammer", "name": "HAMMER", "icon": "HM", "speed": 1450.0, "cl0": 0.14, "cla": 1.2, "cd0": 0.1, "cda": 2.0,
		"lift": 0.9, "flip_t": 0.32, "flip_lift": -0.75, "fade_v": 500.0, "fade": 0.4, "grav": 1000.0,
		"move_pen": 1.2, "spin": 0.85, "roll": false, "trim": 0.1,
		"desc": "Overhead. Climbs, flips upside down, drops steeply over walls."},
	{"id": "roller", "name": "ROLLER", "icon": "RL", "speed": 1450.0, "cl0": 0.05, "cla": 0.6, "cd0": 0.08, "cda": 1.5,
		"lift": 0.35, "flip_t": 0.0, "flip_lift": 1.0, "fade_v": 900.0, "fade": 2.5, "grav": 1300.0,
		"move_pen": 0.8, "spin": 1.0, "roll": true, "trim": -0.25,
		"desc": "Edge-first. Rolls along floors and up ramps. Great under low roofs."},
	{"id": "scoober", "name": "SCOOBER", "icon": "SC", "speed": 950.0, "cl0": 0.12, "cla": 1.0, "cd0": 0.09, "cda": 2.0,
		"lift": 0.6, "flip_t": 0.0, "flip_lift": 1.0, "fade_v": 300.0, "fade": 0.3, "grav": 1050.0,
		"move_pen": 0.45, "spin": 0.95, "roll": false, "trim": 0.05,
		"desc": "Short, soft, precise. Half the moving-throw penalty."},
	{"id": "thumber", "name": "THUMBER", "icon": "TH", "speed": 1650.0, "cl0": 0.08, "cla": 1.0, "cd0": 0.09, "cda": 2.2,
		"lift": 0.8, "flip_t": 0.18, "flip_lift": -1.1, "fade_v": 700.0, "fade": 0.8, "grav": 1050.0,
		"move_pen": 1.15, "spin": 0.8, "roll": false, "trim": -0.05,
		"desc": "Fast inverted blade. Cuts down hard, hits and skips violently."},
]


## Snap outcomes. "spin" is the snap's spin level (also drives aero stability
## in disc.gd: an unspun disc flutters, losing lift and gaining drag),
## "speed" multiplies launch speed, "wobble" multiplies attitude noise.
const SNAP := {
	"PERFECT": {"spin": 1.0, "speed": 1.09, "wobble": 0.15},
	"GOOD": {"spin": 0.62, "speed": 0.95, "wobble": 0.6},
	"NONE": {"spin": 0.25, "speed": 0.8, "wobble": 1.5},
}
const SNAP_PERFECT_US := 35000   # |snap - release| for PERFECT
const SNAP_GOOD_US := 90000      # |snap - release| for GOOD


## Launch numbers for a throw. Shared by the player, late snaps and tools so
## early and late snaps are identical.
##   power 0..1 (charge), mf = movement penalty factor, oc = overcharge 0..1
static func launch_params(ty: Dictionary, power: float, quality: String, mf: float, oc: float) -> Dictionary:
	var q: Dictionary = SNAP[quality]
	var base_speed: float = ty.speed * power * (1.0 - 0.22 * minf(mf, 1.0)) * (1.0 - 0.1 * oc)
	return {
		"speed": base_speed * float(q.speed),
		"base_speed": base_speed,
		"spin": float(q.spin) * float(ty.spin) * (1.0 - 0.3 * minf(mf, 1.0)),
		"wobble": (0.25 + mf * 0.9 + oc * 0.8) * float(q.wobble),
		"quality": float(q.spin),
	}


static func count() -> int:
	return TYPES.size()


static func get_type(i: int) -> Dictionary:
	return TYPES[posmod(i, TYPES.size())]
