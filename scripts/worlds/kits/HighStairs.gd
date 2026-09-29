extends RoomKit
class_name HighStairs

## Flights of steps climbing the walls high above reach, each ending on a
## landing: the room goes on up past where you can follow. Seen only.

@export var flights_min := 1
@export var flights_max := 2
## Height the lowest step starts at (keep it above head height).
@export var y_min := 4.2
@export var rise := 3.0
@export var width := 1.2
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	var segs := b.segments()
	for k in b.count(flights_min, flights_max):
		var seg: Dictionary = segs[b.rng.randi() % segs.size()]
		var length := b.length(seg)
		if length < 2.5:
			continue
		var y0 := b.rng.randf_range(y_min, maxf(y_min, b.height - rise - 1.0))
		var n := int(rise / 0.3)
		var run := minf(length - 1.4, rise / 0.75)
		var from: float = seg.from + 0.1 if b.rng.randf() < 0.5 else seg.to - 0.1 - run - 1.2
		for i in n:
			var a := from + run * (i + 0.5) / n
			var y := y0 + rise * (i + 1) / n
			b.box(b.sized(seg, run / n, 0.3, width), b.at(seg, a, b.WALL_THICKNESS / 2.0 + width / 2.0, y - 0.15), kind)
		b.box(b.sized(seg, 1.2, 0.3, width), b.at(seg, from + run + 0.6, b.WALL_THICKNESS / 2.0 + width / 2.0, y0 + rise - 0.15), kind)
