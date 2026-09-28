extends RoomKit
class_name WallCells

## Honeycomb over the walls: flat-topped hexagonal cells (three stacked
## boxes, each wider and shorter, stepping out the hexagon), in columns each shifted half a cell
## from the last, each standing a little out of a backing slab, from the
## floor up to `top`. Visual only.

## Cell width, corner to corner.
@export var cell := 1.0
@export var gap := 0.1
@export var top := 3.6
@export var depth := 0.08
@export var fill_kind := "glass"
## Backing slab ("" = the bare wall).
@export var back_kind := "accent"

func build(b: RoomBuilder) -> void:
	var face := b.WALL_THICKNESS / 2.0
	var w := cell - gap
	var col := cell * 0.75
	var row := cell * 0.866
	for seg in b.segments():
		var h := minf(top, b.height)
		if back_kind != "":
			b.box(b.sized(seg, b.length(seg), h, depth), b.at(seg, b.mid(seg), face + depth / 2.0, h / 2.0), back_kind)
		for k in range(floori(seg.from / col) - 1, ceili(seg.to / col) + 1):
			var a := k * col
			if a - w / 2.0 < seg.from + 0.05 or a + w / 2.0 > seg.to - 0.05 or b.reserved(b.at(seg, a, 0.3, 0)):
				continue
			var y := row * (0.5 + 0.5 * posmod(k, 2))
			while y + row * 0.5 <= h:
				var d := face + depth + 0.03
				for step: Vector2 in [Vector2(0.5, 0.866), Vector2(0.75, 0.6), Vector2(1.0, 0.3)]:
					b.box(b.sized(seg, w * step.x, w * step.y, 0.06), b.at(seg, a, d, y), fill_kind)
				y += row
