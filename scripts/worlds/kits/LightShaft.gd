extends RoomKit
class_name LightShaft

## A visible shaft of light (the additive "beam" kind): under the room's
## light, through a skylight, or the core of a room. Seen only, never
## solid, never a real light.

@export var size := Vector2(2.2, 2.2)
@export var at := Vector2.ZERO
## Top: -1 = the ceiling. Bottom: the floor, or lower for a pit.
@export var top := -1.0
@export var bottom := 0.0
@export var kind := "beam"
## A thin solid core line inside it ("" = none).
@export var core_kind := ""

func build(b: RoomBuilder) -> void:
	if b.shaft() and b.in_free(Vector3(at.x, 0, at.y), 0.0):
		return
	var t := b.height if top < 0.0 else top
	var h := t - bottom
	b.box(Vector3(size.x, h, size.y), Vector3(at.x, bottom + h / 2.0, at.y), kind)
	if core_kind != "":
		b.box(Vector3(0.08, h, 0.08), Vector3(at.x, bottom + h / 2.0, at.y), core_kind)
