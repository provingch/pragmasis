extends Resource
class_name WorldDef

## One world, as data: one .tres in res://worlds/ per world. Worlds (the
## registry) loads every file in that folder, so adding a world is adding a
## file; code only changes when it needs a kit that doesn't exist yet.
##
## Architecture comes from kits (RoomKit subclasses) in four slots, run in
## this order: floor, walls, wall props, ceiling, ceiling props, floor
## props. Kits only ever see the room through a RoomBuilder.

@export var id: StringName
@export var display_name := ""

@export_group("Topología")
## Depth band (0 = surface). Worlds are grouped in strata of Worlds.STRATUM_SIZE.
@export_range(0, 4) var stratum := 0
## Position inside the stratum; slot 0 is the stratum's entry.
@export_range(0, 3) var slot := 0

@export_group("Paleta")
@export var wall_color := Color.GRAY
@export var floor_color := Color.DIM_GRAY
@export var accent_color := Color.GRAY
## Signal color: trims, portal glow, entity tint, transition flash.
@export var trim_color := Color.WHITE
@export var light_color := Color.WHITE
@export var fog_color := Color.BLACK
## Surface of the "water" kind.
@export var water_color := Color(0.1, 0.18, 0.2)

@export_group("Luz y niebla")
@export var light_energy := 1.6
## Height of the room's one light.
@export var light_y := 3.5
@export_enum("steady", "stutter", "breathe", "heartbeat", "glitch") var flicker := "steady"
@export var fog_begin := 10.0
## Ambient light, in light_color.
@export var ambient := 0.4
## Share of rooms (picked per cell, deterministic) that have their light;
## the rest are dark. 0 = no room lights at all.
@export_range(0.0, 1.0) var light_chance := 1.0
## Particles drifting around the player (see AirParticles).
@export_enum("none", "sparks", "snow", "dust", "drips") var air := "none"

@export_group("Superficies")
@export_range(0.0, 1.0) var roughness := 0.9
## Props (accent) get it all; walls and floor 30% of it.
@export_range(0.0, 1.0) var metallic := 0.0
## Frequency of the world-space grime noise every surface shares.
@export var grime_frequency := 0.12

@export_group("Arquitectura")
## Ceiling height (m).
@export var height := 4.0
@export var floor_kit: RoomKit
@export var wall_kit: RoomKit
@export var wall_props: Array[RoomKit] = []
@export var ceiling_kit: RoomKit
@export var ceiling_props: Array[RoomKit] = []
@export var floor_props: Array[RoomKit] = []
## Scales how many random props kits place (1 = as authored).
@export var prop_density := 1.0
@export var hideout: HideoutKit

@export_group("Música")
## A MusicTrack (.tres): stream + loop point. Several worlds may share one.
@export_file("*.tres") var music := ""
## Effects on the Music bus while here (none = neutral).
@export var music_fx: MusicFX

@export_group("Juego")
## Divides the entity's spawn delay while the player is in this world.
@export var threat := 1.0
## Multiplies the entity's speed while the player is in this world.
@export var entity_speed := 1.0
## Multiplies how loud the player's steps are.
@export var noise := 1.0
## Multiplies how fast sprinting drains stamina.
@export var stamina_drain := 1.0
## Multiplies the player's walk and sprint speed.
@export var player_speed := 1.0
## Multiplies how far the entity sees (catching you hiding).
@export var visibility := 1.0
## The entity's sounds (stinger, omens, chase music) reach the player.
@export var entity_audio := true

## The kits in build order.
func kits() -> Array[RoomKit]:
	var out: Array[RoomKit] = []
	for k in [floor_kit, wall_kit]:
		if k:
			out.append(k)
	out.append_array(wall_props)
	if ceiling_kit:
		out.append(ceiling_kit)
	out.append_array(ceiling_props)
	out.append_array(floor_props)
	return out
