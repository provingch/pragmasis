extends RoomKit
class_name CeilingDome

## A stepped dome over the room instead of a flat ceiling: square rings,
## each narrower and higher, capped at the top. The rings' undersides are
## dotted with tiny emissive points: stars.

@export var steps := 5
## Height the dome rises above the walls.
@export var rise := 4.0
@export var kind := "wall"
@export var stars := 40
@export var star_size := 0.06
@export var star_kind := "edge"

func build(b: RoomBuilder) -> void:
	var half := b.ROOM_SIZE / 2.0
	var ring := half / (steps + 0.5)
	var step_h := rise / steps
	for i in steps + 1:
		var outer := half - i * ring
		var y := b.height + i * step_h
		if i == steps:
			b.box(Vector3(outer * 2.0, step_h, outer * 2.0), Vector3(0, y + step_h / 2.0, 0), kind)
			break
		for s: float in [-1.0, 1.0]:
			b.box(Vector3(outer * 2.0, step_h, ring), Vector3(0, y + step_h / 2.0, s * (outer - ring / 2.0)), kind)
			b.box(Vector3(ring, step_h, outer * 2.0 - 2.0 * ring), Vector3(s * (outer - ring / 2.0), y + step_h / 2.0, 0), kind)
	for k in stars:
		var i := b.rng.randi() % steps
		var outer := half - i * ring
		var y := b.height + i * step_h - 0.01
		var p := Vector2(b.rng.randf_range(-outer, outer), b.rng.randf_range(outer - ring, outer) * (1.0 if b.rng.randf() < 0.5 else -1.0))
		if b.rng.randf() < 0.5:
			p = Vector2(p.y, p.x)
		b.box(Vector3(star_size, 0.02, star_size), Vector3(p.x, y, p.y), star_kind)
