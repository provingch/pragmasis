extends RoomKit
class_name CeilingHangers

## Things hanging from the ceiling at random spots: roots, chains,
## icicles, wax. Their tips stay above `clearance` so nothing brushes the
## camera; visual only. With taper, each ends in thinner steps.

@export var count_min := 4
@export var count_max := 8
@export var width_min := 0.05
@export var width_max := 0.15
@export var length_min := 0.5
@export var length_max := 2.0
@export var clearance := 2.9
@export var spread := 4.4
@export var taper := 0
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	for k in b.count(count_min, count_max):
		var wd := b.rng.randf_range(width_min, width_max)
		var length := minf(b.rng.randf_range(length_min, length_max), b.height - clearance)
		var p := Vector3(b.rng.randf_range(-spread, spread), 0, b.rng.randf_range(-spread, spread))
		var top := b.height
		for s in taper + 1:
			var l := length / (taper + 1)
			var ws := wd * (1.0 - 0.3 * s)
			b.box(Vector3(ws, l, ws), p + Vector3(0, top - l / 2.0, 0), kind)
			top -= l
