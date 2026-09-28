extends RoomKit
class_name CeilingFixture

## The room light's visible body (flickers with it), centred in the room.

@export var size := Vector3(2.4, 0.08, 0.5)
## Centre height: offset from the ceiling (or from the light, see below).
@export var offset := -0.04
@export var from_light := false

func build(b: RoomBuilder) -> void:
	b.fix(size, Vector3(0, (b.world.light_y if from_light else b.height) + offset, 0))
