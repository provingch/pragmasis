extends Node3D
class_name Room

## Cubic modular room, built procedurally so RoomGenerator can reuse one
## scene and just flip which of the 4 walls open into a door.

const ROOM_SIZE := 10.0
const WALL_THICKNESS := 0.5
const DOOR_WIDTH := 3.0

enum Exit { NORTH, SOUTH, EAST, WEST }

## Order: [north(-z), south(+z), east(+x), west(-x)]
@export var exits: Array[bool] = [true, true, true, true]

func _ready() -> void:
	_build_floor_ceiling()
	_build_walls()
	_build_light()

func _build_floor_ceiling() -> void:
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE)
	floor_box.position = Vector3(0, -WALL_THICKNESS / 2.0, 0)
	floor_box.use_collision = true
	add_child(floor_box)

	var ceiling_box := CSGBox3D.new()
	ceiling_box.size = Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE)
	ceiling_box.position = Vector3(0, ROOM_SIZE - WALL_THICKNESS / 2.0, 0)
	ceiling_box.use_collision = true
	add_child(ceiling_box)

func _build_walls() -> void:
	_build_wall(Exit.NORTH, Vector3(0, ROOM_SIZE / 2.0, -ROOM_SIZE / 2.0), false)
	_build_wall(Exit.SOUTH, Vector3(0, ROOM_SIZE / 2.0, ROOM_SIZE / 2.0), false)
	_build_wall(Exit.EAST, Vector3(ROOM_SIZE / 2.0, ROOM_SIZE / 2.0, 0), true)
	_build_wall(Exit.WEST, Vector3(-ROOM_SIZE / 2.0, ROOM_SIZE / 2.0, 0), true)

func _build_wall(exit_dir: int, center: Vector3, is_side: bool) -> void:
	if not exits[exit_dir]:
		var wall := CSGBox3D.new()
		wall.size = Vector3(WALL_THICKNESS, ROOM_SIZE, ROOM_SIZE) if is_side else Vector3(ROOM_SIZE, ROOM_SIZE, WALL_THICKNESS)
		wall.position = center
		wall.use_collision = true
		add_child(wall)
		return

	# Door: two side segments instead of one solid wall, leaving a gap.
	var segment_len := (ROOM_SIZE - DOOR_WIDTH) / 2.0
	for side: float in [-1.0, 1.0]:
		var offset := (DOOR_WIDTH / 2.0 + segment_len / 2.0) * side
		var seg := CSGBox3D.new()
		seg.use_collision = true
		if is_side:
			seg.size = Vector3(WALL_THICKNESS, ROOM_SIZE, segment_len)
			seg.position = center + Vector3(0, 0, offset)
		else:
			seg.size = Vector3(segment_len, ROOM_SIZE, WALL_THICKNESS)
			seg.position = center + Vector3(offset, 0, 0)
		add_child(seg)

func _build_light() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(0, ROOM_SIZE - 1.5, 0)
	light.omni_range = ROOM_SIZE * 1.2
	light.light_energy = 1.2
	add_child(light)
