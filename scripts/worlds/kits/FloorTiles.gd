extends RoomKit
class_name FloorTiles

## Grid of tiles over a base (gaps show the base). Uneven tops and missing
## tiles are visual only: the collision floor stays flat at 0.

@export var count := 5
@export var pitch := 2.0
@export var tile := 1.86
@export var thickness := 0.1
## Each tile's top lands at random in this range.
@export var top_min := 0.0
@export var top_max := 0.0
@export_range(0.0, 1.0) var missing := 0.0
@export var tile_kind := "floor"
@export var base_kind := "dark"
## Base drawn this far below 0 (then an invisible slab collides at 0).
@export var base_drop := 0.0

func build(b: RoomBuilder) -> void:
	var slab := Vector3(b.ROOM_SIZE, b.WALL_THICKNESS, b.ROOM_SIZE)
	var at := Vector3(0, -b.WALL_THICKNESS / 2.0, 0)
	if base_drop == 0.0:
		b.box(slab, at, base_kind, true)
	else:
		b.box(slab, at, "", true)
		b.box(slab, at - Vector3(0, base_drop, 0), base_kind)
	var first := -(count - 1) * pitch / 2.0
	for i in count:
		for j in count:
			if missing > 0.0 and b.rng.randf() < missing:
				continue
			var top := top_min if top_max <= top_min else b.rng.randf_range(top_min, top_max)
			b.box(Vector3(tile, thickness, tile), Vector3(first + i * pitch, top - thickness / 2.0, first + j * pitch), tile_kind)
