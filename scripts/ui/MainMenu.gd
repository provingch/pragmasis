extends Control

## Title screen (approved design: industrial HUD, pixel title with a
## chromatic glitch, spinning line tesseract). Options and the mode select
## (NUEVA PARTIDA) open on top as overlays while this screen's UI hides.

const GAME := "res://scenes/Main.tscn"
const OPTIONS := preload("res://scenes/ui/Options.tscn")
const MODE_SELECT := preload("res://scenes/ui/ModeSelect.tscn")
## Title ghosts, keyframes over one period: [t, clip top, clip bottom
## (fractions of the title's height), dx, dy]. Linear in between.
const GLITCH_RED := [[0.0, 0.0, 0.0, -3.0, 0.0], [0.88, 0.0, 0.0, -3.0, 0.0], [0.90, 0.12, 0.58, -7.0, 2.0], [0.92, 0.52, 0.08, 4.0, -2.0], [0.94, 0.0, 0.0, -3.0, 0.0], [1.0, 0.0, 0.0, -3.0, 0.0]]
const GLITCH_CYAN := [[0.0, 0.0, 0.0, 3.0, 0.0], [0.91, 0.0, 0.0, 3.0, 0.0], [0.93, 0.04, 0.70, 6.0, -2.0], [0.96, 0.64, 0.06, -4.0, 2.0], [0.98, 0.0, 0.0, 3.0, 0.0], [1.0, 0.0, 0.0, 3.0, 0.0]]
const NOTICE_TIME := 1.6

@onready var ui: Control = $UI
@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle

var _t := 0.0
var _ghosts: Array[Dictionary] = []
var _notice_t := 0.0

func _ready() -> void:
	MenuStyle.fit(ui)
	MenuStyle.label(title, Fonts.pixel(4), 62, Color("f2f2f2"))
	MenuStyle.label(subtitle, Fonts.terminal(5), 22, MenuStyle.DIM)
	MenuStyle.label(%LogoText, Fonts.terminal(4), 15, MenuStyle.DIM)
	for l: Label in [%Status, %Build, %Keys]:
		MenuStyle.label(l, Fonts.terminal(2), 17, Color(1, 1, 1, 0.5))
	if GameManager.best > 0:
		%Status.text = "RÉCORD // PROFUNDIDAD %d" % (GameManager.best + 1)
	_ghosts = [_ghost(MenuStyle.ACCENT, GLITCH_RED, 3.4), _ghost(MenuStyle.GHOST, GLITCH_CYAN, 2.7)]
	%NewGame.pressed.connect(_open_mode_select)
	%Continue.pressed.connect(_notice.bind("NO HAY PARTIDA GUARDADA"))
	%Options.pressed.connect(_open_options)
	%Credits.pressed.connect(_notice.bind("CRÉDITOS // PRÓXIMAMENTE"))
	%Quit.pressed.connect(get_tree().quit)
	%NewGame.grab_focus()

func _process(delta: float) -> void:
	_t += delta
	var h := title.size.y
	for g in _ghosts:
		var k := _sample(g.keys, fmod(_t / g.period, 1.0))
		g.clip.position = Vector2(k[3], k[1] * h + k[4])
		g.clip.size = Vector2(title.size.x + 16.0, (1.0 - k[1] - k[2]) * h)
		g.label.position.y = -k[1] * h
	if _notice_t > 0.0:
		_notice_t -= delta
		if _notice_t <= 0.0:
			subtitle.text = "Escapa a través de la cuarta dimensión"
			subtitle.add_theme_color_override("font_color", MenuStyle.DIM)

## An additive, clipped copy of the title (CSS ::before/::after, blend screen).
func _ghost(color: Color, keys: Array, period: float) -> Dictionary:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = MOUSE_FILTER_IGNORE
	var g := Label.new()
	g.text = title.text
	MenuStyle.label(g, title.get_theme_font("font"), 62, color)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	clip.add_child(g)
	title.add_child(clip)
	return {"clip": clip, "label": g, "keys": keys, "period": period}

static func _sample(keys: Array, t: float) -> Array:
	var i := 0
	while keys[i + 1][0] < t:
		i += 1
	var f := inverse_lerp(keys[i][0], keys[i + 1][0], t)
	var out := []
	for j in 5:
		out.append(lerpf(keys[i][j], keys[i + 1][j], f))
	return out

func _new_game(mode: GameMode) -> void:
	GameManager.mode = mode
	DimensionState.reset()
	AudioManager.reset()
	get_tree().change_scene_to_file(GAME)

## Placeholder entries answer in the subtitle line.
func _notice(text: String) -> void:
	subtitle.text = "[ %s ]" % text
	subtitle.add_theme_color_override("font_color", MenuStyle.ACCENT)
	_notice_t = NOTICE_TIME

func _open_options() -> void:
	_overlay(OPTIONS.instantiate(), %Options)

func _open_mode_select() -> void:
	var select := MODE_SELECT.instantiate()
	select.picked.connect(_new_game)
	_overlay(select, %NewGame)

func _overlay(screen: Node, back_to: Control) -> void:
	ui.visible = false
	screen.closed.connect(func() -> void:
		ui.visible = true
		back_to.grab_focus())
	add_child(screen)
