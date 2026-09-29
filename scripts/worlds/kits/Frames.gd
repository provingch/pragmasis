extends RoomKit
class_name Frames

## Square rings around the walkway's arms: posts just off the walkway and
## a lintel over it, at `distances` from the centre, so a corridor reads
## as a tunnel receding to a point. Posts that would land on a pad are
## left out (lintels stay: overhead).

@export var distances: PackedFloat32Array = [1.75, 4.5]
@export var post := 0.3
@export var opening := 3.4
@export var lintel := 0.4
@export var kind := "accent"
@export var edge_kind := ""

func build(b: RoomBuilder) -> void:
	var across := b.WALK_HALF + post / 2.0
	for d in distances:
		for arm: Array in [[false, -1.0], [false, 1.0], [true, 1.0], [true, -1.0]]:
			var along: float = d * arm[1]
			for s: float in [-1.0, 1.0]:
				var p := Vector3(along, 0, s * across) if arm[0] else Vector3(s * across, 0, along)
				if b.clear(p, Vector3(post, 0, post)):
					b.box(Vector3(post, opening, post), p + Vector3(0, opening / 2.0, 0), kind, true)
			var span := across * 2.0 + post
			var size := Vector3(post, lintel, span) if arm[0] else Vector3(span, lintel, post)
			var at := Vector3(along, opening + lintel / 2.0, 0) if arm[0] else Vector3(0, opening + lintel / 2.0, along)
			b.box(size, at, kind)
			if edge_kind != "":
				b.box(size * Vector3(1.02, 0.1, 1.02), at - Vector3(0, lintel / 2.0, 0), edge_kind)
