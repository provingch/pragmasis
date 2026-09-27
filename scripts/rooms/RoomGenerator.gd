extends Node

## Autoload. Streams an unbounded room lattice keyed by Vector4i(x, y, z, w)
## around the player's cell. y is fixed at 0 (no floors yet); w spans
## DimensionState.W_MIN..W_MAX. Each (x, z) is always generated for every w
## at once, so a portal anywhere has a ready destination. Only the active
## layer is attached to the tree (renders/collides); detached rooms keep
## their exits/portal flags readable for the scanner.
##
## Everything about a cell (doors, portals) comes from a hash of the run
## seed and its coordinates, so a freed cell regenerates identically and
## both sides of a shared wall always agree.

const ROOM_SCENE := preload("res://scenes/rooms/Room.tscn")
## Cells within this Chebyshev distance of the player always exist.
const GEN_RADIUS := 3
## Cells farther than this are freed. Gap to GEN_RADIUS avoids churn when
## pacing back and forth across a cell border.
const FREE_RADIUS := 6
## Per room, any direction: mean 12 rooms walked before meeting a portal.
const PORTAL_CHANCE := 1.0 / 12.0
## Doors beyond the one every cell is guaranteed (see edge_open).
const EXTRA_DOOR_CHANCE := 0.3

enum Salt { CARVE, EAST, SOUTH, PORTAL, PORTAL_DIR }

var rooms: Dictionary[Vector4i, Room] = {}
var active_w := 0
var world_seed := 0

var _parent: Node3D
var _player: Node3D
var _center := Vector2i.ZERO

func init_world(parent: Node3D, player: Node3D, start_w: int) -> void:
	# Autoloads survive reload_current_scene(); drop the previous run's rooms.
	_free_detached_rooms()
	rooms.clear()

	world_seed = randi()
	_parent = parent
	_player = player
	active_w = start_w
	_center = cell_of(player.global_position)
	_stream()

func _process(_delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_parent):
		return
	var c := cell_of(_player.global_position)
	if c != _center:
		_center = c
		_stream()

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

static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / Room.ROOM_SIZE), roundi(pos.z / Room.ROOM_SIZE))

# --- streaming -----------------------------------------------------------------

func _stream() -> void:
	# ponytail: a border crossing builds up to 7 cells x 3 layers in one frame; spread over frames if it hitches
	for dx in range(-GEN_RADIUS, GEN_RADIUS + 1):
		for dz in range(-GEN_RADIUS, GEN_RADIUS + 1):
			var x := _center.x + dx
			var z := _center.y + dz
			if rooms.has(Vector4i(x, 0, z, active_w)):
				continue
			for w in range(DimensionState.W_MIN, DimensionState.W_MAX + 1):
				_create(x, z, w)

	var far: Array[Vector4i] = []
	for coord in rooms:
		if maxi(absi(coord.x - _center.x), absi(coord.z - _center.y)) > FREE_RADIUS:
			far.append(coord)
	for coord in far:
		# queue_free: some of these are attached and may be mid-frame.
		rooms[coord].queue_free()
		rooms.erase(coord)

func _create(x: int, z: int, w: int) -> void:
	var room := ROOM_SCENE.instantiate() as Room
	room.exits = exits_for(x, z)
	room.w = w
	var dir := portal_dir(x, z, w)
	room.phase_positive = dir == 1
	room.phase_negative = dir == -1
	room.position = Vector3(x * Room.ROOM_SIZE, 0, z * Room.ROOM_SIZE)
	rooms[Vector4i(x, 0, z, w)] = room
	if w == active_w:
		_parent.add_child(room)

func _set_layer_attached(w: int, attached: bool) -> void:
	for coord in rooms:
		if coord.w != w:
			continue
		var room := rooms[coord]
		if attached:
			_parent.add_child(room)
		else:
			_parent.remove_child(room)

# --- deterministic layout -------------------------------------------------------

func _rand(x: int, z: int, w: int, salt: Salt) -> float:
	return float(hash([world_seed, x, z, w, salt]) & 0xFFFF) / 65536.0

## Door on the east (or south) side of cell (x, z). Every cell carves one of
## its east/south doors (binary-tree maze), so following those always leads
## out of any finite region: no sealed pockets, even in a map that is never
## complete. Extra doors add loops. Same for every w-layer.
func edge_open(x: int, z: int, east: bool) -> bool:
	var carved_east := _rand(x, z, 0, Salt.CARVE) < 0.5
	if carved_east == east:
		return true
	return _rand(x, z, 0, Salt.EAST if east else Salt.SOUTH) < EXTRA_DOOR_CHANCE

## [north, south, east, west], matching Room.Exit.
func exits_for(x: int, z: int) -> Array[bool]:
	return [edge_open(x, z - 1, false), edge_open(x, z, false), edge_open(x, z, true), edge_open(x - 1, z, true)]

## +1 / -1 for a portal in that w direction, 0 for none.
func portal_dir(x: int, z: int, w: int) -> int:
	if _rand(x, z, w, Salt.PORTAL) >= PORTAL_CHANCE:
		return 0
	if w == DimensionState.W_MAX:
		return -1
	if w == DimensionState.W_MIN:
		return 1
	return 1 if _rand(x, z, w, Salt.PORTAL_DIR) < 0.5 else -1
