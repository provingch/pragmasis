extends RoomKit
class_name Bars

## Rows of vertical bars: they stop the player but not the eye (nor the
## entity's: their collision is see-through, RoomBuilder.see_through).
## Each line is (x0, z0, x1, z1) in room coordinates; keep them off the
## walkway's middle so there's always a way around.

@export var lines: Array[Vector4] = [Vector4(-1.6, 1.6, -1.6, 4.75), Vector4(-4.75, 1.6, -1.6, 1.6)]
@export var spacing := 0.3
@export var bar := 0.07
## 0 = up to the ceiling.
@export var height := 0.0
@export var kind := "accent"
## Rail across the top and at the foot ("" = none).
@export var rail_kind := "accent"

func build(b: RoomBuilder) -> void:
	var h := b.height if height <= 0.0 else height
	for l in lines:
		var a := Vector2(l.x, l.y)
		var z := Vector2(l.z, l.w)
		var c := (a + z) / 2.0
		var along_x := absf(z.x - a.x) > absf(z.y - a.y)
		var length := (z - a).length()
		var n := maxi(roundi(length / spacing), 1)
		for i in n + 1:
			var p := a.lerp(z, float(i) / n)
			b.box(Vector3(bar, h, bar), Vector3(p.x, h / 2.0, p.y), kind)
		b.see_through(Vector3(length, h, 0.1) if along_x else Vector3(0.1, h, length), Vector3(c.x, h / 2.0, c.y))
		if rail_kind != "":
			for y: float in [0.1, h - 0.1]:
				b.box(Vector3(length, 0.12, 0.12) if along_x else Vector3(0.12, 0.12, length), Vector3(c.x, y, c.y), rail_kind)
