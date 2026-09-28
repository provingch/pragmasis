extends RoomKit
class_name WallGrid

## Seams in a regular grid over every wall's inner face: tile grout, panel
## joints. Lined up on the room's axes, so it's symmetric. Visual only.

## Spacing along the wall and up it.
@export var pitch := Vector2(0.5, 0.5)
@export var line := 0.025
@export var depth := 0.012
## Up to this height (0: the wall's top).
@export var top := 0.0
@export var kind := "dark"

func build(b: RoomBuilder) -> void:
	var segs := b.segments()
	for i in segs.size():
		var seg: Dictionary = segs[i]
		var h := b.wall_height(i) if top <= 0.0 else minf(top, b.wall_height(i))
		var face := b.WALL_THICKNESS / 2.0 + depth / 2.0
		var y := pitch.y
		while y < h - 0.01:
			b.strip(seg, y, line, depth, kind)
			y += pitch.y
		for k in range(ceili(seg.from / pitch.x), floori(seg.to / pitch.x) + 1):
			var a: float = k * pitch.x
			if a > seg.from + 0.01 and a < seg.to - 0.01:
				b.box(b.sized(seg, line, h, depth), b.at(seg, a, face, h / 2.0), kind)
