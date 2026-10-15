extends RefCounted
## Battle Rush weapons and enemy tuning: every number lives here.
## Times are seconds (counted in physics ticks, so replays re-simulate them
## exactly), distances px, speeds px/s. Attack = `throw` key, block = `snap`.

const ORDER := ["sword", "bow", "axe", "pike"]

## melee: a swept shape in front of the player during the active phase
##   shape "box": reach x height rect starting at the body, facing the aim side
##   shape "line": a thrust along the aim direction, `reach` long, `height` thick
## bow: draws while the attack key is held, fires on release.
const WEAPONS := {
	"sword": {
		"name": "Sword", "blurb": "Quick, well rounded. Hold SNAP to block.",
		"kind": "melee", "shape": "box", "reach": 66.0, "height": 54.0,
		"windup": 0.06, "active": 0.12, "recover": 0.14,
		"dmg": 2.0, "knock": 300.0, "lunge": 120.0,
		"block": true, "block_time": 0.5, "block_cd": 0.3,
		"color": Color(0.35, 1.0, 1.4),
	},
	"bow": {
		"name": "Bow & Arrow", "blurb": "Ranged. Hold to draw, release to loose.",
		"kind": "bow", "draw_min": 0.12, "draw_full": 0.55, "recover": 0.18,
		"dmg_min": 1.0, "dmg_max": 3.0, "speed_min": 1100.0, "speed_max": 2000.0,
		"pierce": false, "full_draw": 0.9,   # a fully drawn arrow goes through a shield; others only chip it
		"shield_mult": 0.5,
		"color": Color(0.4, 1.2, 0.5),
	},
	"axe": {
		"name": "Battle Axe", "blurb": "Slow and heavy. Breaks shields.",
		"kind": "melee", "shape": "box", "reach": 84.0, "height": 92.0,
		"windup": 0.3, "active": 0.14, "recover": 0.36,
		"dmg": 6.0, "knock": 640.0, "lunge": 60.0, "breaks_shield": true,
		"splash": 170.0, "splash_mult": 0.7,   # everyone near the one it hits takes 70%
		"color": Color(1.0, 0.45, 0.25),
	},
	"pike": {
		"name": "Pike", "blurb": "Damage scales with your speed.",
		"kind": "melee", "shape": "line", "reach": 140.0, "height": 16.0,
		"windup": 0.08, "active": 0.14, "recover": 0.28,
		"dmg": 1.0, "speed_div": 170.0, "dmg_max": 9.0, "knock": 260.0, "lunge": 0.0,
		"pierce_speed": 650.0,   # fast enough and it goes through a shield
		"run_min": 320.0,        # running into someone at this speed or more hurts them, swing or not
		"run_reach": 64.0, "run_cd": 0.45,
		"color": Color(1.2, 1.0, 0.3),
	},
}

## Seconds of grace after a hit-respawn.
const RESPAWN_INVULN := 1.0
const ARROW_GRAVITY := 380.0

const ENEMIES := {
	"grunt": {
		"hp": 3.0, "w": 26.0, "h": 46.0, "patrol": 80.0, "charge": 300.0,
		"sight": 440.0, "reach": 58.0, "windup": 0.42, "strike": 0.14, "recover": 0.7,
		"stagger": 0.3, "color": Color(1.0, 0.3, 0.3),
	},
	"guard": {
		"hp": 5.0, "w": 30.0, "h": 50.0, "patrol": 60.0, "charge": 190.0,
		"sight": 420.0, "reach": 64.0, "windup": 0.5, "strike": 0.16, "recover": 0.8,
		"stagger": 0.2, "shield": true, "color": Color(1.0, 0.65, 0.2),
	},
	"archer": {
		"hp": 2.0, "w": 24.0, "h": 44.0, "patrol": 0.0, "charge": 0.0,
		"sight": 760.0, "reach": 0.0, "windup": 0.5, "strike": 0.0, "recover": 1.5,
		"stagger": 0.35, "ranged": true, "arrow_speed": 760.0, "color": Color(0.6, 1.0, 0.3),
	},
	"leader": {
		"hp": 16.0, "w": 40.0, "h": 72.0, "patrol": 90.0, "charge": 360.0,
		"sight": 900.0, "reach": 96.0, "windup": 0.36, "strike": 0.18, "recover": 0.5,
		"stagger": 0.0, "volley": 3, "volley_every": 4.5, "arrow_speed": 700.0,
		"color": Color(1.0, 0.25, 0.75),
	},
}


static func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["sword"])


static func clean(id: String) -> String:
	return id if WEAPONS.has(id) else "sword"


## Pike damage from the speed of the thrust (runner speed, plus the lunge).
static func pike_damage(w: Dictionary, speed: float) -> float:
	return minf(float(w.dmg_max), float(w.dmg) + speed / float(w.speed_div))
