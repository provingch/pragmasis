extends RoomKit
class_name DoorJambs

## Thick jambs inside every door, on this room's side of it (the room
## beyond builds its own half), and optionally a lintel: the doorway reads
## narrower and lower. Keep DOOR_WIDTH - 2 * narrow wide enough for the
## player (0.8 m plus margin): solid jambs are real.

## Per side.
@export var narrow := 0.4
## Through the doorway, on this side.
@export var depth := 0.45
## Doorway height under the lintel (0 = no lintel).
@export var opening := 0.0
@export var kind := "accent"
@export var collide := true

func build(b: RoomBuilder) -> void:
	var half := b.ROOM_SIZE / 2.0
	var inset := half - depth / 2.0
	for dir in 4:
		if not b.exits[dir]:
			continue
		var side := dir == Room.Exit.EAST or dir == Room.Exit.WEST
		var sgn := -1.0 if dir == Room.Exit.NORTH or dir == Room.Exit.WEST else 1.0
		var along := b.DOOR_WIDTH / 2.0 - narrow / 2.0
		var parts := [[along, narrow, b.height], [-along, narrow, b.height]]
		if opening > 0.0:
			parts.append([0.0, b.DOOR_WIDTH, b.height - opening])
		for p: Array in parts:
			var h: float = p[2]
			var y := h / 2.0 if p[1] == narrow else b.height - h / 2.0
			var size := Vector3(depth, h, p[1]) if side else Vector3(p[1], h, depth)
			var pos := Vector3(sgn * inset, y, p[0]) if side else Vector3(p[0], y, sgn * inset)
			b.box(size, pos, kind, collide and p[1] == narrow)
