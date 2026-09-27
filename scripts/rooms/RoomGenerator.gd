extends Node

## Autoload. Rooms are keyed by Vector4i(x, y, z, w). y is fixed at 0 (no
## floors yet) and w spans DimensionState.W_MIN..W_MAX. Every w-layer uses
## the same x/z footprint; only the active layer is attached to the tree,
## so only it renders and collides. Detached layers keep their exits/phase
## flags readable (the scanner uses them) but haven't built geometry yet —
## Room._ready() runs on first attach.

const ROOM_SCENE := preload("res://scenes/rooms/Room.tscn")
const PHASE_PORTAL_CHANCE := 1.0 / 6.0

var rooms: Dictionary[Vector4i, Room] = {}
var active_w := 0
var grid_radius := 1

var _parent: Node3D

func init_world(parent: Node3D, radius: int, start_w: int) -> void:
	# Autoloads survive reload_current_scene(); drop the previous run's rooms.
	_free_detached_rooms()
	rooms.clear()

	_parent = parent
	grid_radius = radius
	active_w = start_w
	for w in range(DimensionState.W_MIN, DimensionState.W_MAX + 1):
		_generate_layer(w)
	_set_layer_attached(active_w, true)

func _exit_tree() -> void:
	_free_detached_rooms()

# Detached layers aren't owned by the scene, so nothing else frees them.
func _free_detached_rooms() -> void:
	for room in rooms.values():
		if is_instance_valid(room) and not room.is_inside_tree():
			room.free()

func switch_layer(new_w: int) -> void:
	if new_w == active_w:
		return
	_set_layer_attached(active_w, false)
	active_w = new_w
	_set_layer_attached(active_w, true)

func _generate_layer(w: int) -> void:
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var room := ROOM_SCENE.instantiate() as Room
			room.exits = [
				gz > -grid_radius, # north: neighbor exists towards -z
				gz < grid_radius,  # south: neighbor exists towards +z
				gx < grid_radius,  # east
				gx > -grid_radius, # west
			]
			room.w = w
			room.phase_positive = w < DimensionState.W_MAX and randf() < PHASE_PORTAL_CHANCE
			room.phase_negative = w > DimensionState.W_MIN and randf() < PHASE_PORTAL_CHANCE
			room.position = Vector3(gx * Room.ROOM_SIZE, 0, gz * Room.ROOM_SIZE)
			rooms[Vector4i(gx, 0, gz, w)] = room

func _set_layer_attached(w: int, attached: bool) -> void:
	for coord in rooms:
		if coord.w != w:
			continue
		var room := rooms[coord]
		if attached:
			_parent.add_child(room)
		else:
			_parent.remove_child(room)
