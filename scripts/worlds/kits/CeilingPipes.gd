extends RoomKit
class_name CeilingPipes

## Square pipes running along x under the ceiling, in random lanes, with
## flanges. Overhead: visual only.

@export var lanes: PackedFloat32Array = [-4.1, -3.5, -2.9, 2.9, 3.5, 4.1]
@export var count_min := 2
@export var count_max := 4
@export var big := 0.32
@export var small := 0.2
@export var drop_min := 0.4
@export var drop_max := 1.4
@export var flanges: PackedFloat32Array = [-3.0, 0.0, 3.0]
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	var free := Array(lanes)
	for k in mini(b.count(count_min, count_max), free.size()):
		var z: float = free.pop_at(b.rng.randi() % free.size())
		var s := big if b.rng.randf() < 0.5 else small
		var y := b.height - b.rng.randf_range(drop_min, drop_max)
		b.box(Vector3(b.ROOM_SIZE - b.WALL_THICKNESS, s, s), Vector3(0, y, z), kind)
		for x in flanges:
			b.box(Vector3(0.12, s + 0.1, s + 0.1), Vector3(x, y, z), kind)
