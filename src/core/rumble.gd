extends RefCounted
## Controller rumble. Each runner's PlayerInput says which pad(s) it reads:
## one specific pad (couch), or every pad in solo while the last input came
## from a pad. Strength scales with settings.rumble (0 = off). Never during
## replays or video renders.

const PlayerInput = preload("res://src/core/player_input.gd")

## name -> [weak motor, strong motor, seconds]
const PATTERNS := {
	"throw": [0.15, 0.0, 0.05],
	"catch": [0.3, 0.1, 0.08],
	"sky_catch": [0.5, 0.25, 0.12],
	"grapple": [0.25, 0.0, 0.06],
	"land_hard": [0.3, 0.45, 0.1],
	"pad": [0.25, 0.2, 0.1],
	"death": [0.5, 0.8, 0.3],
	"chains": [0.6, 0.85, 0.5],
	"clash": [0.4, 0.6, 0.15],
	"frozen": [0.2, 0.45, 0.3],
	"tackle_landed": [0.4, 0.5, 0.15],
	"tackled": [0.6, 0.9, 0.35],
	"hit_landed": [0.3, 0.3, 0.1],
	"hit_head": [0.7, 1.0, 0.4],
	"hit_arm": [0.5, 0.5, 0.2],
	"hit_leg": [0.4, 0.65, 0.25],
}


## Pads this input would rumble right now.
static func pads_for(inp) -> Array:
	if inp == null:
		return []
	if inp.device >= 0:
		return [inp.device] if Input.get_connected_joypads().has(inp.device) else []
	if inp.device == PlayerInput.ANY and inp.using_pad:
		return Input.get_connected_joypads()
	return []


## Play a named pattern, `scale` 0..1 on top of the setting.
static func play(inp, name: String, scale := 1.0) -> void:
	if not PATTERNS.has(name) or Game.render_mode:
		return
	var k: float = clampf(float(Game.settings.get("rumble", 1.0)), 0.0, 1.0) * clampf(scale, 0.0, 1.0)
	if k <= 0.01:
		return
	var p: Array = PATTERNS[name]
	for id in pads_for(inp):
		Input.start_joy_vibration(id, float(p[0]) * k, float(p[1]) * k, float(p[2]))


## Snap feedback: a crisp tick that is stronger the better the snap.
static func snap(inp, score: float) -> void:
	if Game.render_mode:
		return
	var k: float = clampf(float(Game.settings.get("rumble", 1.0)), 0.0, 1.0)
	if k <= 0.01:
		return
	var s := clampf(score, 0.0, 1.0)
	for id in pads_for(inp):
		Input.start_joy_vibration(id, (0.2 + 0.6 * s) * k, 0.35 * s * k, 0.05 + 0.05 * s)
