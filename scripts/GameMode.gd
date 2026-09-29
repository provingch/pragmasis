extends Resource
class_name GameMode

## What a run plays like. GameManager.mode holds the active one; systems
## read its fields instead of asking which mode it is.

@export var display_name := ""
## One line, shown on the mode select screen.
@export var description := ""
## Anchors, the sequence clock, collapse, beacons, score and record.
@export var anchors := true
## World the run starts in (-1: one of the surface's, at random).
@export var start_w := -1
## Multiplies the portal and fissure chances (RoomGenerator.link_of).
@export var link_scale := 1.0
## There is an entity at all.
@export var entities := true
## Multiplies the entity's spawn delay.
@export var spawn_delay_scale := 1.0

static func normal() -> GameMode:
	var m := GameMode.new()
	m.display_name = "NORMAL"
	m.description = "Llegá al ancla antes del colapso. Cada ancla, un estrato más hondo."
	return m

static func free_roam(start_world: int, entity_delay: float) -> GameMode:
	var m := GameMode.new()
	m.display_name = "PARTIDA LIBRE"
	m.description = "Sin anclas ni reloj. Explorá los mundos a tu ritmo."
	m.anchors = false
	m.start_w = start_world
	m.link_scale = 2.0
	m.entities = entity_delay > 0.0
	m.spawn_delay_scale = entity_delay
	return m

func start_world() -> int:
	return start_w if start_w >= 0 else Worlds.in_stratum(0).pick_random()
