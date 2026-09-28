extends RoomKit
class_name FloatingFrames

## Nested cube wireframes (12 bars each) floating over the room's centre:
## a tesseract's projection, frozen. With the "spin" kind they turn slowly
## about the room's axis, the inner ones against the outer. Visual only;
## keep the lowest bar above head height.

## Edge length of each cube.
@export var sizes: PackedFloat32Array = [4.0, 2.2]
## Centre height.
@export var y := 6.0
@export var bar := 0.08
@export var kind := "spin"

func build(b: RoomBuilder) -> void:
	for s in sizes:
		var h := s / 2.0
		for u: float in [-h, h]:
			for v: float in [-h, h]:
				b.box(Vector3(s + bar, bar, bar), Vector3(0, y + u, v), kind)
				b.box(Vector3(bar, s + bar, bar), Vector3(u, y, v), kind)
				b.box(Vector3(bar, bar, s + bar), Vector3(u, y + v, 0), kind)
