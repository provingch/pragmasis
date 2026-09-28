class_name MenuStyle

## Shared look of MainMenu and Options. Change ACCENT to recolor both.

const ACCENT := Color("ff2b3d")
const BG := Color("050506")
## Second channel of the title's chromatic glitch.
const GHOST := Color("22e6ff")
const TEXT := Color(0.9, 0.9, 0.9, 0.75)
const DIM := Color(1, 1, 1, 0.55)
## The approved design is specified at 1440x900.
const DESIGN_H := 900.0

## Lays `ui` out in a DESIGN_H-tall virtual space scaled to its parent's
## real height, so every size from the design can be used as is.
static func fit(ui: Control) -> void:
	var parent := ui.get_parent() as Control
	var refit := func() -> void:
		var s := parent.size.y / DESIGN_H
		ui.scale = Vector2(s, s)
		ui.size = parent.size / s
	parent.resized.connect(refit)
	refit.call()

static func label(l: Label, font: Font, font_size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
