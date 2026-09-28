extends Button
class_name HudButton

## HUD menu entry: when selected (focus; hovering focuses) an accent bar
## fading to the right plus a square marker. Text is drawn here too, so it
## always sits above the highlight. With a `value`, it's an option row:
## left/right step it (stepped), click/Enter steps forward (pressed).

signal stepped(dir: int)

const PAD_L := 16.0
const MARK := 10.0
const GAP := 12.0
const PAD_R := 26.0
const PAD_Y := 9.0

@export var label := "":
	set(v):
		label = v
		queue_redraw()
@export var font_size := 32
var value := "":
	set(v):
		value = v
		queue_redraw()

var _font: Font

func _ready() -> void:
	_font = Fonts.terminal(3)
	flat = true
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	custom_minimum_size.y = _font.get_height(font_size) + PAD_Y * 2.0
	if custom_minimum_size.x == 0.0:
		custom_minimum_size.x = PAD_L + MARK + GAP + _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + PAD_R
	mouse_entered.connect(grab_focus)
	focus_entered.connect(AudioManager.play_sfx.bind(&"ui_hover"))
	pressed.connect(AudioManager.play_sfx.bind(&"ui_select"))
	stepped.connect(func(_dir: int) -> void: AudioManager.play_sfx(&"ui_select"))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if value == "":
		return
	for dir: int in [-1, 1]:
		if event.is_action_pressed("ui_left" if dir < 0 else "ui_right"):
			stepped.emit(dir)
			accept_event()

func _draw() -> void:
	var on := has_focus()
	if on:
		var a := Color(MenuStyle.ACCENT, 0.85)
		var z := Color(MenuStyle.ACCENT, 0.0)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([a, z, z, a]))
		draw_rect(Rect2(PAD_L, (size.y - MARK) / 2.0, MARK, MARK), MenuStyle.ACCENT)
	var color := Color.WHITE if on else MenuStyle.TEXT
	var base := (size.y + _font.get_ascent(font_size) - _font.get_descent(font_size)) / 2.0
	draw_string(_font, Vector2(PAD_L + MARK + GAP, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if value != "":
		draw_string(_font, Vector2(0, base), "<  %s  >" % value, HORIZONTAL_ALIGNMENT_RIGHT, size.x - PAD_R, font_size, color)
