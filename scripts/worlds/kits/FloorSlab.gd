extends RoomKit
class_name FloorSlab

## Plain solid floor.

@export var kind := "floor"

func build(b: RoomBuilder) -> void:
	b.box(Vector3(b.ROOM_SIZE, b.WALL_THICKNESS, b.ROOM_SIZE), Vector3(0, -b.WALL_THICKNESS / 2.0, 0), kind, true)
