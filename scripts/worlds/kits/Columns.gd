extends RoomKit
class_name Columns

## Floor-to-ceiling columns with a base and a cap. Solid: only put them in
## the free corner (-x, +z), never the walkway, portal or hideout corners.

@export var positions: Array[Vector3] = [Vector3(-3.0, 0, 3.0)]
@export var size := 0.7
@export var base := 1.0
@export var base_height := 0.35
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	var h := b.height
	for p in positions:
		b.box(Vector3(size, h, size), p + Vector3(0, h / 2.0, 0), kind, true)
		b.box(Vector3(base, base_height, base), p + Vector3(0, base_height / 2.0, 0), kind, true)
		b.box(Vector3(base, base_height, base), p + Vector3(0, h - base_height / 2.0, 0), kind)
