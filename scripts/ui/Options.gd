extends CanvasLayer

## Graphics options. Every row applies (and saves) the moment it changes,
## so there's nothing to confirm or cancel. Opened from MainMenu, or in game
## with ESC (tree paused; this keeps processing, and the live FPS counter
## then measures the actual scene behind). In game it also offers the way
## back to the main menu.

signal closed

const ROW_W := 720.0
## [Settings field, label, [[value, shown as], ...], help line]
const ROWS := [
	["preset", "CALIDAD", [["BAJA", "BAJA"], ["MEDIA", "MEDIA"], ["ALTA", "ALTA"]],
		"Ajusta todo de una vez. Tocar cualquier fila de calidad lo vuelve PERSONALIZADO."],
	["render_scale", "ESCALA DE RENDER", [[0.5, "50%"], [0.55, "55%"], [0.6, "60%"], [0.65, "65%"], [0.7, "70%"], [0.75, "75%"], [0.8, "80%"], [0.85, "85%"], [0.9, "90%"], [0.95, "95%"], [1.0, "100%"]],
		"Resolución 3D interna, reescalada con AMD FSR 1 (bilineal en MOBILE). El ajuste de mayor impacto."],
	["ssao", "OCLUSIÓN AMBIENTAL", [[false, "NO"], [true, "SÍ"]],
		"SSAO: sombreado de contacto en rincones. Caro en GPUs integradas."],
	["glow", "RESPLANDOR", [[false, "NO"], [true, "SÍ"]],
		"Brillo de luces y zócalos emisivos."],
	["shadow_radius", "SOMBRAS", [[-1, "NO"], [0, "SALA ACTUAL"], [1, "RADIO 1"], [2, "RADIO 2"]],
		"Sombras en tiempo real: cada luz con sombra vuelve a dibujar la escena 6 veces."],
	["gen_radius", "DISTANCIA", [[2, "CORTA"], [3, "MEDIA"], [4, "LARGA"]],
		"Salas generadas a tu alrededor. La niebla se ajusta para tapar el borde."],
	["rendering_method", "MÉTODO DE RENDER", [["forward_plus", "FORWARD+"], ["mobile", "MOBILE"]],
		"MOBILE es bastante más liviano, pero sin SSAO ni FSR. Se aplica al reiniciar el juego."],
	["vsync", "VSYNC", [[false, "NO"], [true, "SÍ"]],
		"Sincroniza con el monitor. Desactivalo para ver el FPS máximo real."],
	["fullscreen", "MODO", [[false, "VENTANA"], [true, "PANTALLA COMPLETA"]],
		""],
]

@onready var rows: VBoxContainer = %Rows
@onready var help: Label = %Help
@onready var restart: Label = %Restart
@onready var fps: Label = %Fps

var _buttons: Array[HudButton] = []
## Opened from a run (set before adding it): shows VOLVER AL MENÚ.
var in_game := false

func _ready() -> void:
	MenuStyle.fit($Root/UI)
	MenuStyle.label(%Title, Fonts.pixel(4), 40, Color("f2f2f2"))
	MenuStyle.label(%Subtitle, Fonts.terminal(4), 20, MenuStyle.DIM)
	MenuStyle.label(help, Fonts.terminal(2), 20, MenuStyle.DIM)
	MenuStyle.label(restart, Fonts.terminal(2), 20, MenuStyle.ACCENT)
	MenuStyle.label(fps, Fonts.terminal(2), 24, MenuStyle.ACCENT)
	%Subtitle.text = "CALIBRACIÓN DE RENDER // %s" % RenderingServer.get_video_adapter_name().to_upper()
	for row: Array in ROWS:
		var b := HudButton.new()
		b.label = row[1]
		b.font_size = 28
		b.custom_minimum_size.x = ROW_W
		b.stepped.connect(_step.bind(row))
		b.pressed.connect(_step.bind(1, row))
		b.focus_entered.connect(func() -> void: help.text = row[3])
		rows.add_child(b)
		_buttons.append(b)
	%Back.pressed.connect(_close)
	%Back.focus_entered.connect(func() -> void: help.text = "")
	%ToMenu.visible = in_game
	%ToMenu.pressed.connect(GameManager.to_menu)
	%ToMenu.focus_entered.connect(func() -> void: help.text = "Termina la partida actual.")
	Settings.changed.connect(_refresh)
	_refresh()
	_buttons[0].grab_focus()

func _process(_delta: float) -> void:
	var win := get_tree().root.size
	fps.text = "FPS %d  //  3D %dx%d" % [Engine.get_frames_per_second(), win.x * Settings.render_scale, win.y * Settings.render_scale]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _step(dir: int, row: Array) -> void:
	var opts: Array = row[2]
	var v: Variant = opts[posmod(_index(row) + dir, opts.size())][0]
	if row[0] == "preset":
		Settings.apply_preset(v)
	else:
		Settings.set_option(row[0], v)

## Position of the current value in the row's options, -1 if not listed
## (the CUSTOM preset).
func _index(row: Array) -> int:
	var cur: Variant = Settings.get(row[0])
	for i in row[2].size():
		var v: Variant = row[2][i][0]
		if (is_equal_approx(v, cur) if cur is float else v == cur):
			return i
	return -1

func _refresh() -> void:
	for i in ROWS.size():
		var j := _index(ROWS[i])
		_buttons[i].value = ROWS[i][2][j][1] if j >= 0 else Settings.CUSTOM
	restart.visible = Settings.needs_restart()

func _close() -> void:
	closed.emit()
	queue_free()
