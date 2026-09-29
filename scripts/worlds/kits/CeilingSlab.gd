extends RoomKit
class_name CeilingSlab

## Flat ceiling at the world's height, optionally open in the middle (a
## skylight onto the fog above).

@export var kind := "wall"
@export var thickness := 0.5
## Opening centred over the room (zero = none).
@export var hole := Vector2.ZERO

func build(b: RoomBuilder) -> void:
	var y := b.height + thickness / 2.0
	var s := b.ROOM_SIZE
	if hole == Vector2.ZERO:
		b.box(Vector3(s, thickness, s), Vector3(0, y, 0), kind)
		return
	var side := (s - hole.x) / 2.0
	for sgn: float in [-1.0, 1.0]:
		b.box(Vector3(side, thickness, s), Vector3(sgn * (hole.x + side) / 2.0, y, 0), kind)
		b.box(Vector3(hole.x, thickness, (s - hole.y) / 2.0), Vector3(0, y, sgn * (hole.y + (s - hole.y) / 2.0) / 2.0), kind)
