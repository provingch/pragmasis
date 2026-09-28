extends RoomKit
class_name FloorLines

## Straight flush lines across the floor: grates, painted or glowing lines.

## z of each line running along x.
@export var along_x: PackedFloat32Array = []
## x of each line running along z.
@export var along_z: PackedFloat32Array = []
@export var width := 0.6
@export var height := 0.02
@export var kind := "grate"

func build(b: RoomBuilder) -> void:
	var length := b.ROOM_SIZE - b.WALL_THICKNESS
	for z in along_x:
		b.box(Vector3(length, height, width), Vector3(0, height / 2.0, z), kind)
	for x in along_z:
		b.box(Vector3(width, height, length), Vector3(x, height / 2.0, 0), kind)
