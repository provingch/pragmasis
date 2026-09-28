extends RoomKit
class_name CeilingArches

## Arches across the room (along x), stepping down toward the east/west
## walls. Each step: Vector3(from x, to x, drop below the ceiling).

@export var z_positions: PackedFloat32Array = [-3.0, 0.0, 3.0]
@export var steps: Array[Vector3] = [Vector3(4.75, 3.75, 1.6), Vector3(3.75, 2.5, 1.0), Vector3(2.5, 1.25, 0.6), Vector3(1.25, 0.0, 0.35)]
@export var thickness := 0.3
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	for z in z_positions:
		for s in steps:
			for sgn: float in [-1.0, 1.0]:
				b.box(Vector3(s.x - s.y, s.z, thickness), Vector3(sgn * (s.x + s.y) / 2.0, b.height - s.z / 2.0, z), kind)
