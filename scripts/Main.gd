extends Node3D

@onready var rooms_root: Node3D = $Rooms

func _ready() -> void:
	RoomGenerator.init_world(rooms_root, 1, DimensionState.player_w)
