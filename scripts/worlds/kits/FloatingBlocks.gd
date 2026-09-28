extends RoomKit
class_name FloatingBlocks

## Cubes hanging in the air above head height. The count steps through
## count_min..count_max with the room's variant. Visual only.

@export var count_min := 1
@export var count_max := 2
@export var size_min := 0.4
@export var size_max := 1.0
@export var y_min := 3.5
@export var y_max := 7.0
@export var spread := 3.0
@export var kind := "glitch"

func build(b: RoomBuilder) -> void:
	var n := roundi((count_min + b.variant % (count_max - count_min + 1)) * b.world.prop_density)
	for k in n:
		var s := b.rng.randf_range(size_min, size_max)
		b.box(Vector3.ONE * s, Vector3(b.rng.randf_range(-spread, spread), b.rng.randf_range(y_min, y_max), b.rng.randf_range(-spread, spread)), kind)
