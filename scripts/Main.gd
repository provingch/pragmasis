extends Node3D

@onready var rooms_root: Node3D = $Rooms
@onready var player: Node3D = $Player

func _ready() -> void:
	RoomGenerator.init_world(rooms_root, player, DimensionState.player_w)
