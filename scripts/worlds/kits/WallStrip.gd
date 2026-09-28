extends RoomKit
class_name WallStrip

## A band along every wall's inner face: baseboard, skirting, edge line.

@export var y := 0.3
@export var height := 0.08
@export var depth := 0.06
@export var kind := "trim"
## y counts down from the ceiling instead of up from the floor.
@export var from_ceiling := false

func build(b: RoomBuilder) -> void:
	for seg in b.segments():
		b.strip(seg, b.height - y if from_ceiling else y, height, depth, kind)
