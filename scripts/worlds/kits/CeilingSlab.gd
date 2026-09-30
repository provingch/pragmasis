extends RoomKit
class_name CeilingSlab

## Flat ceiling at the world's height, optionally open in the middle (a
## skylight onto the fog above). None where the cube's ceiling is open to
## the void; over a spiral going up, open above FREE.

@export var kind := "wall"
@export var thickness := 0.5
## Opening centred over the room (zero = none).
@export var hole := Vector2.ZERO

func build(b: RoomBuilder) -> void:
	if b.open[4]:
		return
	var y := b.height + thickness / 2.0
	var s := b.ROOM_SIZE
	var holes: Array[Rect2] = []
	if hole != Vector2.ZERO:
		holes.append(Rect2(-hole / 2.0, hole))
	if b.up:
		holes.append(b.FREE)
	for r in b.cover(Rect2(-s / 2.0, -s / 2.0, s, s), holes):
		b.box(Vector3(r.size.x, thickness, r.size.y), Vector3(r.get_center().x, y, r.get_center().y), kind)
