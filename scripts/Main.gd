extends Node3D

@onready var rooms_root: Node3D = $Rooms

func _ready() -> void:
	RoomGenerator.generate_grid(rooms_root, 1)
