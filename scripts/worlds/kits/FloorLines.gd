extends RoomKit
class_name FloorLines

## Straight flush lines across the floor: grates, painted or glowing lines.
## Hung from the ceiling instead: beams.

## z of each line running along x.
@export var along_x: PackedFloat32Array = []
## x of each line running along z.
@export var along_z: PackedFloat32Array = []
@export var width := 0.6
@export var height := 0.02
@export var kind := "grate"
@export var from_ceiling := false

func build(b: RoomBuilder) -> void:
	var length := b.ROOM_SIZE - b.WALL_THICKNESS
	var y := b.height - height / 2.0 if from_ceiling else height / 2.0
	for z in along_x:
		b.box(Vector3(length, height, width), Vector3(0, y, z), kind)
	for x in along_z:
		b.box(Vector3(width, height, length), Vector3(x, y, 0), kind)
