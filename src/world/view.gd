extends RefCounted
## What the cameras can see this frame (world space, with a margin), so
## animated world props only re-record their drawing when someone can see
## them. Level.update_view() sets it every physics tick; outside a level it
## covers everything. A prop that skips redraws keeps showing its last frame.

static var rect := Rect2(-1e9, -1e9, 2e9, 2e9)

const MARGIN := 400.0


static func sees(r: Rect2) -> bool:
	return rect.intersects(r)


static func sees_point(p: Vector2, radius := 200.0) -> bool:
	return rect.intersects(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0))


static func reset() -> void:
	rect = Rect2(-1e9, -1e9, 2e9, 2e9)
