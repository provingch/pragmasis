extends CanvasLayer

## NUEVA PARTIDA: pick a GameMode. Opened over MainMenu like Options; the
## focused row explains itself in the help line. PARTIDA LIBRE's two rows
## (start world, entities) sit under it and apply only to it.

signal picked(mode: GameMode)
signal closed

const ROW_W := 720.0
## [spawn delay multiplier (0: no entity), shown as, help line]
const ENTITIES := [
	[1.0, "NORMALES", "La entidad aparece como en NORMAL."],
	[3.0, "POCAS", "La entidad tarda el triple en aparecer."],
	[0.0, "NINGUNA", "Sin entidad ni presagios: solo explorar."],
]

@onready var rows: VBoxContainer = %Rows
@onready var help: Label = %Help

var _worlds: Array[int] = []
var _world := 0
var _entities := 0
var _world_row: HudButton
var _entities_row: HudButton

func _ready() -> void:
	MenuStyle.fit($Root/UI)
	MenuStyle.label(%Title, Fonts.pixel(4), 40, Color("f2f2f2"))
	MenuStyle.label(%Subtitle, Fonts.terminal(4), 20, MenuStyle.DIM)
	MenuStyle.label(help, Fonts.terminal(2), 20, MenuStyle.DIM)
	_worlds = GameManager.atlas()
	var normal := GameMode.normal()
	var free := GameMode.free_roam(-1, 1.0)
	var first := _row(normal.display_name, normal.description, func() -> void: picked.emit(normal))
	_row(free.display_name, free.description, func() -> void:
		picked.emit(GameMode.free_roam(_worlds[_world], ENTITIES[_entities][0])))
	_world_row = _row("   MUNDO INICIAL", "Solo mundos ya descubiertos en el Atlas (%d de %d)." % [_worlds.size(), Worlds.ids().size()], _step_world.bind(1))
	_world_row.stepped.connect(_step_world)
	_entities_row = _row("   ENTIDADES", "", _step_entities.bind(1))
	_entities_row.stepped.connect(_step_entities)
	_entities_row.focus_entered.connect(func() -> void: help.text = ENTITIES[_entities][2])
	%Back.pressed.connect(_close)
	%Back.focus_entered.connect(func() -> void: help.text = "")
	_refresh()
	first.grab_focus()

func _row(text: String, help_line: String, on_press: Callable) -> HudButton:
	var b := HudButton.new()
	b.label = text
	b.font_size = 28
	b.custom_minimum_size.x = ROW_W
	b.pressed.connect(on_press)
	if help_line != "":
		b.focus_entered.connect(func() -> void: help.text = help_line)
	rows.add_child(b)
	return b

func _step_world(dir: int) -> void:
	_world = posmod(_world + dir, _worlds.size())
	_refresh()

func _step_entities(dir: int) -> void:
	_entities = posmod(_entities + dir, ENTITIES.size())
	help.text = ENTITIES[_entities][2]
	_refresh()

func _refresh() -> void:
	var d := Worlds.def(_worlds[_world])
	_world_row.value = d.tag()
	_world_row.value_color = d.trim_color
	_entities_row.value = ENTITIES[_entities][1]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
