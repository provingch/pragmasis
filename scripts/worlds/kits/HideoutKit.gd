extends RefCounted
class_name HideoutKit

## The PRAGMASIS closet, the same in every world: a dark monolith in the
## reserved corner (x 3.25..4.75, z -4.75..-3.25, 3.2 m tall, its back and
## one side being the room's own walls), its edges and an upright triangle
## on the door lit in the world's signal color. A slit at eye height
## (2.6 m) to look out through.

const TOP := 3.2
const SLIT := Vector2(2.5, 2.7)
## The triangle on the door: centre height and side.
const MARK_Y := 1.45
const MARK := 0.62

static func build(b: RoomBuilder) -> void:
	var front := 3.3
	b.box(Vector3(1.5, TOP, 0.1), Vector3(4.0, TOP / 2.0, -3.3), "dark", true) # side
	b.box(Vector3(1.5, 0.12, 1.5), Vector3(4.0, TOP - 0.06, -4.0), "dark") # roof
	b.box(Vector3(0.1, SLIT.x, 1.4), Vector3(front, SLIT.x / 2.0, -4.05), "dark") # door, below the slit
	b.box(Vector3(0.1, TOP - SLIT.y, 1.4), Vector3(front, (TOP + SLIT.y) / 2.0, -4.05), "dark") # above it
	b.box(Vector3(0.1, TOP, 1.4), Vector3(front, TOP / 2.0, -4.05), "", true)
	# Lit edges: the front's outline and the top's.
	var e := 0.045
	var x := front - 0.06
	for z: float in [-3.26, -4.74]:
		b.box(Vector3(e, TOP, e), Vector3(x, TOP / 2.0, z), "edge")
	b.box(Vector3(e, e, 1.5), Vector3(x, TOP, -4.0), "edge")
	b.box(Vector3(1.5, e, e), Vector3(4.0, TOP, -3.26), "edge")
	# The door's seam and the mark: an upright triangle, three bars.
	b.box(Vector3(0.02, SLIT.x - 0.1, 0.02), Vector3(x, (SLIT.x - 0.1) / 2.0, -4.05), "void")
	var r := MARK / sqrt(3.0) # circumradius
	var centre := Vector3(x, MARK_Y, -4.05)
	for i in 3:
		var a0 := PI / 2.0 + TAU * i / 3.0
		var a1 := a0 + TAU / 3.0
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		var mid := (p0 + p1) / 2.0
		# In the door's plane (z across, y up), turned to run p0 -> p1.
		b.box(Vector3(0.03, 0.035, MARK), centre + Vector3(0, mid.y, -mid.x), "edge", false, Basis(Vector3.RIGHT, -atan2(p1.y - p0.y, -(p1.x - p0.x))))
