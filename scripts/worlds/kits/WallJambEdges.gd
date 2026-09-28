extends RoomKit
class_name WallJambEdges

## A thin vertical line at both ends of every wall segment (door jambs and
## room corners).

@export var width := 0.05
@export var kind := "edge"

func build(b: RoomBuilder) -> void:
	var segs := b.segments()
	for i in segs.size():
		var seg: Dictionary = segs[i]
		var h := b.wall_height(i)
		for a: float in [seg.from, seg.to]:
			var edge := clampf(a, -b.INNER + width / 2.0, b.INNER - width / 2.0)
			b.box(Vector3(width, h, width), b.at(seg, edge, b.WALL_THICKNESS / 2.0 + width / 2.0, h / 2.0), kind)
