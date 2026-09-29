extends RoomKit
class_name FloorLines

## Straight flush lines across the floor: grates, painted or glowing lines.
## Hung from the ceiling, or at any height: beams.

## z of each line running along x.
@export var along_x: PackedFloat32Array = []
## x of each line running along z.
@export var along_z: PackedFloat32Array = []
@export var width := 0.6
@export var height := 0.02
@export var kind := "trim"
@export var from_ceiling := false
## Centre height (-1: on the floor, or under the ceiling): beams mid-air.
@export var at_y := -1.0

func build(b: RoomBuilder) -> void:
	var length := b.ROOM_SIZE - b.WALL_THICKNESS
	var y := at_y if at_y >= 0.0 else (b.height - height / 2.0 if from_ceiling else height / 2.0)
	for z in along_x:
		b.box(Vector3(length, height, width), Vector3(0, y, z), kind)
	for x in along_z:
		b.box(Vector3(width, height, length), Vector3(x, y, 0), kind)
