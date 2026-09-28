extends RoomKit
class_name WallBays

## A feature repeated along every wall at a fixed spacing, symmetric about
## each wall's middle: doors, lancet windows, niches. A frame (sides, top,
## and a sill if it starts off the floor) standing out of the wall around
## a leaf, which may be split into panes (the wall shows between them),
## topped by a stepped point, repeated in rows. Visual only.

@export var spacing := 2.0
@export var width := 0.9
@export var height := 2.1
## Bottom of the first row.
@export var y := 0.0
@export var rows := 1
@export var row_gap := 0.3
@export var frame := 0.08
@export var depth := 0.08
@export var frame_kind := "trim"
@export var leaf_kind := "accent"
## Columns x rows of panes in each leaf.
@export var panes := Vector2i(1, 1)
## Pointed top: this many ever-narrower steps above the leaf.
@export var peak_steps := 0
## A handle ("" = none).
@export var knob_kind := ""

func build(b: RoomBuilder) -> void:
	var n := int(b.ROOM_SIZE / spacing) + 1
	for seg in b.segments():
		for k in range(-n, n):
			var a := (k + 0.5) * spacing
			var half := width / 2.0 + frame
			if a - half < seg.from + 0.15 or a + half > seg.to - 0.15:
				continue
			if b.reserved(b.at(seg, a - half, 0.3, 0)) or b.reserved(b.at(seg, a + half, 0.3, 0)):
				continue
			for r in rows:
				_bay(b, seg, a, y + r * (height + row_gap + frame))

func _bay(b: RoomBuilder, seg: Dictionary, a: float, y0: float) -> void:
	var face := b.WALL_THICKNESS / 2.0
	var top := y0 + height
	for s: float in [-1.0, 1.0]:
		b.box(b.sized(seg, frame, height + frame, depth), b.at(seg, a + s * (width + frame) / 2.0, face + depth / 2.0, y0 + (height + frame) / 2.0), frame_kind)
	b.box(b.sized(seg, width, frame, depth), b.at(seg, a, face + depth / 2.0, top + frame / 2.0), frame_kind)
	if y0 > 0.0:
		b.box(b.sized(seg, width + 2.0 * frame, frame, depth * 1.5), b.at(seg, a, face + depth * 0.75, y0 - frame / 2.0), frame_kind)
	var gap := 0.04
	var pw := (width - gap * (panes.x - 1)) / panes.x
	var ph := (height - gap * (panes.y - 1)) / panes.y
	for i in panes.x:
		for j in panes.y:
			var along := a - width / 2.0 + pw / 2.0 + i * (pw + gap)
			b.box(b.sized(seg, pw, ph, depth * 0.5), b.at(seg, along, face + depth * 0.25, y0 + ph / 2.0 + j * (ph + gap)), leaf_kind)
	for i in peak_steps:
		var sw := width * (1.0 - float(i + 1) / (peak_steps + 1))
		var sh := width * 0.35
		b.box(b.sized(seg, sw + 2.0 * frame, sh, depth), b.at(seg, a, face + depth / 2.0, top + frame + sh * (i + 0.5)), frame_kind if i == peak_steps - 1 else leaf_kind)
	if knob_kind != "":
		b.box(b.sized(seg, 0.06, 0.06, depth + 0.08), b.at(seg, a + width * 0.35, face + (depth + 0.08) / 2.0, y0 + minf(1.0, height / 2.0)), knob_kind)
