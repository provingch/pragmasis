extends RoomKit
class_name CeilingTiles

## Drop ceiling: tiles hung just under the ceiling (pair it with a dark
## CeilingSlab so the gaps read as the grid). Some cells are light panels
## with two fluorescent tubes (the room's fixture); one may be dead; from
## `missing_from_variant` on, one tile is missing.

@export var count := 8
@export var pitch := 1.25
@export var tile := 1.19
@export var tile_kind := "wall"
@export var panel_kind := "accent"
@export var panels: Array[Vector2i] = [Vector2i(2, 2), Vector2i(2, 5), Vector2i(5, 2), Vector2i(5, 5)]
## One panel in `dead_roll` rolls is dead (the rest: all lit).
@export var dead_roll := 6
@export var missing_from_variant := 2

func build(b: RoomBuilder) -> void:
	var dead := b.rng.randi() % dead_roll
	var missing := [Vector2i(b.rng.randi() % count, b.rng.randi() % count)] if b.variant >= missing_from_variant else []
	var half := b.ROOM_SIZE / 2.0
	for i in count:
		for j in count:
			var cell := Vector2i(i, j)
			var c := Vector3(-half + pitch * (i + 0.5), b.height - 0.02, -half + pitch * (j + 0.5))
			var p := panels.find(cell)
			if p >= 0:
				b.box(Vector3(tile, 0.04, tile), c, panel_kind)
				if p != dead:
					for dx: float in [-0.25, 0.25]:
						b.fix(Vector3(0.1, 0.04, 1.1), c + Vector3(dx, -0.03, 0))
			elif not cell in missing:
				b.box(Vector3(tile, 0.04, tile), c, tile_kind)
