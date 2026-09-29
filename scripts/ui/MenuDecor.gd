extends Control
class_name MenuDecor

## Hand-drawn pieces of the menu look; `kind` picks which one this node draws.

enum Kind { GRID, VIGNETTE, HAZARD, HAZARD_SMALL, LOGO, TESSERACT, DOT, SCANLINES }

@export var kind := Kind.GRID

const GRID_STEP := 26.0
const VIGNETTE_DEPTH := 260.0
const OUTER_SPIN := 46.0 # seconds per turn, clockwise
const INNER_SPIN := 27.0 # counter-clockwise
const PULSE := 1.7

var _t := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = kind in [Kind.HAZARD, Kind.HAZARD_SMALL]
	set_process(kind in [Kind.TESSERACT, Kind.DOT])
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	match kind:
		Kind.GRID:
			var c := Color(1, 1, 1, 0.02)
			for x in range(0, int(size.x), GRID_STEP):
				draw_line(Vector2(x, 0), Vector2(x, size.y), c)
			for y in range(0, int(size.y), GRID_STEP):
				draw_line(Vector2(0, y), Vector2(size.x, y), c)
		Kind.VIGNETTE:
			_vignette()
		Kind.HAZARD:
			_stripes(10.0, Color(MenuStyle.ACCENT, 0.9), Color(0.067, 0.067, 0.067, 0.9))
		Kind.HAZARD_SMALL:
			_stripes(8.0, Color(MenuStyle.ACCENT, 0.75), Color.TRANSPARENT)
		Kind.LOGO: # the PRAGMASIS triangle (as on every hideout's door)
			var c := Color(1, 1, 1, 0.6)
			draw_polyline(PackedVector2Array([Vector2(10, 1.5), Vector2(19, 17.5), Vector2(1, 17.5), Vector2(10, 1.5)]), c, 1.6)
		Kind.TESSERACT:
			_tesseract()
		Kind.DOT:
			var a := 0.625 + 0.375 * cos(TAU * _t / PULSE)
			draw_rect(Rect2(-3, -3, 14, 14), Color(MenuStyle.ACCENT, 0.25 * a))
			draw_rect(Rect2(0, 0, 8, 8), Color(MenuStyle.ACCENT, a))
		Kind.SCANLINES:
			for y in range(2, int(size.y), 3):
				draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.19))

## 45-degree bands, `band` px wide, alternating colors a/b.
func _stripes(band: float, a: Color, b: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), b)
	var w := band * sqrt(2.0)
	var h := size.y
	var x := -h
	while x < size.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w + h, h), Vector2(x + h, h)]), a)
		x += 2.0 * w

func _vignette() -> void:
	var s := size
	var d := VIGNETTE_DEPTH
	var colors := PackedColorArray([Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.9), Color(0, 0, 0, 0), Color(0, 0, 0, 0)])
	for quad in [
		[Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, d), Vector2(0, d)],
		[Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - d), Vector2(0, s.y - d)],
		[Vector2(0, 0), Vector2(0, s.y), Vector2(d, s.y), Vector2(d, 0)],
		[Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - d, s.y), Vector2(s.x - d, 0)],
	]:
		draw_polygon(PackedVector2Array(quad), colors)

## Two nested squares spinning opposite ways, joined corner to corner by
## static struts (viewBox 300: outer 220, inner 100).
func _tesseract() -> void:
	var k := size.x / 300.0
	var c := size / 2.0
	_square(c, 110.0 * k, _t * TAU / OUTER_SPIN, 2.4 * k)
	_square(c, 50.0 * k, -_t * TAU / INNER_SPIN, 2.4 * k)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		draw_line(c + corner * 110.0 * k, c + corner * 50.0 * k, Color(1, 1, 1, 0.55), 1.4 * k, true)

func _square(c: Vector2, half: float, angle: float, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		pts.append(c + Vector2(half * sqrt(2.0), 0).rotated(angle + PI / 4.0 + i * PI / 2.0))
	# Wide faint passes first: the design's accent drop-shadow glow.
	draw_polyline(pts, Color(MenuStyle.ACCENT, 0.08), width * 6.0, true)
	draw_polyline(pts, Color(MenuStyle.ACCENT, 0.18), width * 3.0, true)
	draw_polyline(pts, MenuStyle.ACCENT, width, true)
