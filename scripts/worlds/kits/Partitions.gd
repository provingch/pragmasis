extends RoomKit
class_name Partitions

## A small maze inside the room: baffles jutting alternately into the
## walkway's arms (each leaves a gap wider than the player, so the way
## between doors bends but never closes) and walls inside FREE.

@export var reach := 1.8
@export var thickness := 0.25
## 0 = up to the ceiling.
@export var height := 0.0
## Distances from the centre where a baffle may go along each arm.
@export var along_min := 2.2
@export var along_max := 3.8
@export var kind := "wall"
## Walls in FREE (x, z, size x, size z).
@export var walls: Array[Rect2] = [Rect2(-3.6, 1.6, 0.25, 2.0), Rect2(-4.75, 3.4, 1.4, 0.25)]

func build(b: RoomBuilder) -> void:
	var h := b.height if height <= 0.0 else height
	var half := b.WALK_HALF
	# One baffle per arm, from a random side. [arm axis along x?, sign]
	for arm: Array in [[false, -1.0], [false, 1.0], [true, 1.0], [true, -1.0]]:
		var along: float = b.rng.randf_range(along_min, along_max) * arm[1]
		var side := 1.0 if b.rng.randf() < 0.5 else -1.0
		# The hideout's door opens off the north arm's east side: leave it.
		if not arm[0] and arm[1] < 0.0 and absf(along) > 2.4:
			side = -1.0
		var across := side * (half - reach / 2.0)
		var size := Vector3(thickness, h, reach) if arm[0] else Vector3(reach, h, thickness)
		var pos := Vector3(along, h / 2.0, across) if arm[0] else Vector3(across, h / 2.0, along)
		b.box(size, pos, kind, true)
	for r in walls:
		if b.shaft() and r.intersects(b.FREE):
			continue
		var c := r.get_center()
		b.box(Vector3(r.size.x, h, r.size.y), Vector3(c.x, h / 2.0, c.y), kind, true)
