extends MultiMeshInstance3D
class_name CubeField

## The universe the rooms float in: one MultiMesh of plain cubes on the
## cell grid all around the streamed rooms (up and down too), out to
## MARGIN cells past them. Not a single instance is touched after layout:
## the node steps along with the player's cell and the shader
## (cube_field.gdshader) hashes each cube's cell for its gap, size and
## nudge. No collision, no shadows. It starts past the cells rooms may
## still stand in (free radius), so it never pokes into one.

const SHADER := preload("res://shaders/cube_field.gdshader")
const MARGIN := 4
const MARGIN_V := 3

var _player: Node3D
var _mat := ShaderMaterial.new()

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shader = SHADER
	material_override = _mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	multimesh.mesh = box
	_layout()
	Settings.changed.connect(_layout)
	_tint(DimensionState.player_w)
	DimensionState.layer_changed.connect(_tint)

## Instances: every cell in the shell between the rooms' reach and MARGIN
## past it, rounded off at the corners.
func _layout() -> void:
	var inner := RoomGenerator.free_radius
	var inner_v := RoomGenerator.v_radius + 1
	var outer := inner + MARGIN
	var outer_v := inner_v + MARGIN_V
	var cells: Array[Vector3i] = []
	for dy in range(-outer_v, outer_v + 1):
		for dx in range(-outer, outer + 1):
			for dz in range(-outer, outer + 1):
				if absi(dx) <= inner and absi(dz) <= inner and absi(dy) <= inner_v:
					continue
				if Vector2(dx, dz).length() > outer + 0.5:
					continue
				cells.append(Vector3i(dx, dy, dz))
	multimesh.instance_count = cells.size()
	var scale := Basis.from_scale(Vector3(Room.ROOM_SIZE, Room.CELL_H, Room.ROOM_SIZE))
	for i in cells.size():
		multimesh.set_instance_transform(i, Transform3D(scale, RoomGenerator.origin(cells[i]) + Vector3(0, Room.CELL_H / 2.0, 0)))
	custom_aabb = AABB(Vector3(-outer - 1, -outer_v - 1, -outer - 1) * Room.ROOM_SIZE, Vector3(2 * outer + 2, 2 * outer_v + 2, 2 * outer + 2) * Room.ROOM_SIZE)
	_mat.set_shader_parameter("fade_begin", (inner + 0.5) * Room.ROOM_SIZE)
	_mat.set_shader_parameter("fade_end", (outer + 1.0) * Room.ROOM_SIZE)

## The active world's palette: its walls darkened, its signal color on the
## edges, and more gaps where it has more void.
func _tint(w: int) -> void:
	var d := Worlds.def(w)
	_mat.set_shader_parameter("albedo", d.wall_color.darkened(0.85))
	_mat.set_shader_parameter("edge_color", d.trim_color)
	_mat.set_shader_parameter("fog_color", d.fog_color)
	_mat.set_shader_parameter("gaps", clampf(0.3 + d.void_chance, 0.3, 0.75))

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(_player):
		global_position = RoomGenerator.origin(RoomGenerator.cell_of(_player.global_position))
