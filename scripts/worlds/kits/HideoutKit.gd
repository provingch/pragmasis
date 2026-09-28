extends Resource
class_name HideoutKit

## The world's hideout: a closet in the reserved corner, x 3.25..4.75,
## z -4.75..-3.25, 3.2 m tall, its back and one side being the room's own
## walls, with a slit at eye height (2.6 m) to look out through.

enum Dressing { NONE, VENT_SLATS, HANDLE_AND_SEAM, FRAMING_RIBS, TOP_OUTLINE, EDGE_LINES }

@export var body_kind := "accent"
@export var front_kind := "accent"
@export var dressing := Dressing.NONE

func build(b: RoomBuilder) -> void:
	var top := 3.2
	var slit := Vector2(2.5, 2.7)
	b.box(Vector3(1.5, top, 0.1), Vector3(4.0, top / 2.0, -3.3), body_kind, true) # side
	b.box(Vector3(1.5, 0.1, 1.5), Vector3(4.0, top - 0.05, -4.0), body_kind) # roof
	b.box(Vector3(0.1, slit.x, 1.4), Vector3(3.3, slit.x / 2.0, -4.05), front_kind) # door, below the slit
	b.box(Vector3(0.1, top - slit.y, 1.4), Vector3(3.3, (top + slit.y) / 2.0, -4.05), front_kind) # above it
	b.box(Vector3(0.1, top, 1.4), Vector3(3.3, top / 2.0, -4.05), "", true)
	match dressing:
		Dressing.VENT_SLATS:
			for y: float in [1.9, 2.05, 2.2]:
				b.box(Vector3(0.03, 0.04, 1.0), Vector3(3.24, y, -4.05), "grate")
		Dressing.HANDLE_AND_SEAM:
			b.box(Vector3(0.04, 0.3, 0.04), Vector3(3.23, 1.4, -3.95), "dark")
			b.box(Vector3(0.02, slit.x, 0.02), Vector3(3.24, slit.x / 2.0, -4.05), "dark")
		Dressing.FRAMING_RIBS:
			for z: float in [-3.3, -4.7]:
				b.box(Vector3(0.35, top + 0.4, 0.25), Vector3(3.2, (top + 0.4) / 2.0, z), "accent")
		Dressing.TOP_OUTLINE:
			b.box(Vector3(0.12, 0.05, 1.5), Vector3(3.3, top, -4.0), "trim")
		Dressing.EDGE_LINES:
			for z: float in [-3.3, -4.72]:
				b.box(Vector3(0.05, top, 0.05), Vector3(3.24, top / 2.0, z), "edge")
			b.box(Vector3(0.05, 0.05, 1.5), Vector3(3.24, top, -4.0), "edge")
