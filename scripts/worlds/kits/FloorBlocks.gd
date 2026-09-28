extends RoomKit
class_name FloorBlocks

## Blocks standing on the floor: shelving, cabinets, columns, ossuary
## stacks, machinery. Solid by default. Any block that would touch the
## walkway plus, a portal corner or the hideout corner is dropped
## (RoomBuilder.clear), so none ever blocks a way through; a room may end
## up with fewer than asked.

## Fixed spots (x, 0, z); each dropped with chance `skip`.
@export var positions: Array[Vector3] = []
@export_range(0.0, 1.0) var skip := 0.0
## Random spots, tried at random until they fit.
@export var count_min := 0
@export var count_max := 0
## Footprint x, height, footprint z. Height 0: up to the ceiling.
@export var size := Vector3(0.6, 3.0, 2.4)
## Random extra height, as a fraction of it.
@export var height_jitter := 0.0
## Random blocks may turn 90° (swap x and z).
@export var turn := true
## Shelves: horizontal slabs, a bit wider than the block, evenly up it.
@export var levels := 0
@export var level_kind := "dark"
@export var kind := "accent"
@export var collide := true

func build(b: RoomBuilder) -> void:
	var placed: Array[Rect2] = []
	for p in positions:
		if skip == 0.0 or b.rng.randf() >= skip:
			_place(b, p, size, placed)
	var want := b.count(count_min, count_max)
	var tries := want * 12
	while want > 0 and tries > 0:
		tries -= 1
		var s := Vector3(size.z, size.y, size.x) if turn and b.rng.randf() < 0.5 else size
		var p := Vector3(b.rng.randf_range(-b.INNER, b.INNER), 0, b.rng.randf_range(-b.INNER, b.INNER))
		if _place(b, p, s, placed):
			want -= 1

func _place(b: RoomBuilder, p: Vector3, s: Vector3, placed: Array[Rect2]) -> bool:
	var r := Rect2(p.x - s.x / 2.0, p.z - s.z / 2.0, s.x, s.z)
	if not b.clear(p, s) or placed.any(func(o: Rect2) -> bool: return o.grow(0.3).intersects(r)):
		return false
	placed.append(r)
	var h := b.height if s.y <= 0.0 else s.y * (1.0 + b.rng.randf() * height_jitter)
	b.box(Vector3(s.x, h, s.z), p + Vector3(0, h / 2.0, 0), kind, collide)
	for i in levels:
		var y := h * (i + 1) / (levels + 1.0)
		b.box(Vector3(s.x + 0.08, 0.05, s.z + 0.08), p + Vector3(0, y, 0), level_kind)
	return true
