extends RoomKit
class_name CeilingSlab

## Flat ceiling at the world's height.

@export var kind := "wall"
@export var thickness := 0.5

func build(b: RoomBuilder) -> void:
	b.box(Vector3(b.ROOM_SIZE, thickness, b.ROOM_SIZE), Vector3(0, b.height + thickness / 2.0, 0), kind)
