extends RoomKit
class_name CeilingSoffits

## Lowered ceiling over the room's four corners, leaving a plus between
## the doors at full height: the walkways read as corridors running on.

@export var drop := 0.6
## Width of the full-height plus.
@export var lane := 3.4
@export var kind := "wall"
## Strip along the soffits' inner edges ("" = none).
@export var edge_kind := ""

func build(b: RoomBuilder) -> void:
	var half := b.ROOM_SIZE / 2.0
	var s := half - lane / 2.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (lane / 2.0 + s / 2.0), b.height - drop / 2.0, sz * (lane / 2.0 + s / 2.0))
			b.box(Vector3(s, drop, s), c, kind)
			if edge_kind != "":
				b.box(Vector3(s, 0.05, 0.05), Vector3(c.x, b.height - drop, sz * lane / 2.0), edge_kind)
				b.box(Vector3(0.05, 0.05, s), Vector3(sx * lane / 2.0, b.height - drop, c.z), edge_kind)
