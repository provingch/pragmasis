extends Resource
class_name RoomKit

## A reusable, parametrised piece of room architecture. A WorldDef lists
## kits per slot; Room runs them in order through a RoomBuilder. A new look
## is a new combination of kits and params in a .tres; a new kind of
## geometry is a new RoomKit subclass.
##
## Kits keep nothing collidable in the walkway (the plus between the doors),
## the portal corners (+x +z, -x -z) or the hideout corner (b.reserved()).

## Material kinds kits use (see Room.layer_material): floor, wall, accent,
## trim, edge, grate, dark, void, glitch.
func build(_b: RoomBuilder) -> void:
	pass
