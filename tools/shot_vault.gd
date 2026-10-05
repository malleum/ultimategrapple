extends SceneTree
## Frames of the ledge vault (carrying: one-hand vault) and the side flip
## (empty-handed, fast) for checking the animation (needs a display).
## godot -s tools/shot_vault.gd -- out_prefix

var lvl
var r
var f := 0
var started := false
var run := 0          # 0 = carrying (vault), 1 = empty-handed (side flip)
var shots := 0
var mant_f := -1
var out := "vault"


func _level() -> Dictionary:
	return {"version": 4, "id": "vault", "name": "Vault", "theme": "cyber", "spawn": [0, 0], "basket": [9000, 0],
		"kill_y": 4000, "bounds": [-2000, -3000, 14000, 9000],
		"solids": [{"r": [-2000, 0, 14000, 400], "k": "ground"}, {"r": [700, -170, 800, 170], "k": "block"}],
		"polys": [], "entities": [], "route": [], "segments": [], "medals": {"par": 9}}


func _physics_process(_dt: float) -> bool:
	var G = root.get_node("Game")
	if not started:
		started = true
		out = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "vault"
		G.main = root
		G.settings["name_chosen"] = true
		lvl = G.play_level(_level())
		return false
	if r == null:
		r = lvl.runners[0]
		r.zoom_override = 2.2
		_start()
		return false
	f += 1
	var p = r.player
	r.follow_fn = func() -> Array: return [Vector2(690, -60), Vector2.ZERO]
	if f == 4 and run == 1:
		p.has_disc = false
		r.disc.launch(Vector2(-1800, -40), Vector2.ZERO, 0, 1.0, 0.0, 0.0)
	if not Input.is_action_pressed("jump") and mant_f < 0 and p.global_position.x > 700.0 - (130.0 if run == 0 else 210.0) and f > 5:
		Input.action_press("jump")
	if p.mantle_t > 0.0 and mant_f < 0:
		mant_f = f
	if mant_f >= 0:
		var k := f - mant_f
		if k in [2, 10, 18, 26, 36]:
			root.get_viewport().get_texture().get_image().save_png("%s_%s_%d.png" % [out, "vault" if run == 0 else "flip", k])
		if k > 40:
			run += 1
			if run > 1:
				print("saved vault frames")
				quit()
				return true
			_start()
	return false


func _start() -> void:
	lvl.restart()
	Input.action_release("jump")
	Input.action_press("move_right")
	r.player.respawn(Vector2(-200 if run == 0 else -900, 0))
	mant_f = -1
	f = 0
