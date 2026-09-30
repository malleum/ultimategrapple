extends SceneTree
## Rope wrap test: swing under a block so the rope must wrap its corner, then unwrap.
var lvl
var f := 0
var started := false
var max_anchors := 0
var log := []

func _physics_process(_dt: float) -> bool:
	var Game = root.get_node("Game")
	if not started:
		started = true
		Game.main = root
		var data := {
			"id": "rope_test", "theme": "cyber", "spawn": [0, 0], "basket": [3000, 0], "kill_y": 3000,
			"solids": [{"r": [-400, 0, 800, 400], "k": "ground"}, {"r": [440, -480, 140, 70], "k": "block"}],
			"polys": [], "route": [[0, 0]], "medals": {},
			"entities": [{"t": "grapple", "p": [400, -620], "k": "static"}],
		}
		lvl = Game.play_level(data)
		return false
	f += 1
	var p = lvl.player
	if f == 5:
		# hang the player to the left of the block, below the anchor line
		p.respawn(Vector2(60, -330))
		p.aim_override = Vector2(400, -620)
		Input.action_press("grapple")
	if f == 7:
		log.append("attached state=%d anchors=%d rope=%.0f" % [p.state, p.anchors.size(), p.rope_len])
		p.velocity = Vector2(700, 300)
	max_anchors = maxi(max_anchors, p.anchors.size())
	if f % 20 == 0 and f < 200:
		log.append("f%d pos=(%.0f,%.0f) anchors=%d rope=%.0f" % [f, p.global_position.x, p.global_position.y, p.anchors.size(), p.rope_len])
	if f == 200:
		Input.action_release("grapple")
		for l in log:
			print(l)
		print("max anchors: ", max_anchors)
		quit()
	return false
