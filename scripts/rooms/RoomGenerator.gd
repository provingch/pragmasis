extends Node

## Autoload. First-delivery version: generates a fixed NxN grid once,
## no streaming yet (see spec item 3 — streaming comes later).

const ROOM_SCENE := preload("res://scenes/rooms/Room.tscn")

func generate_grid(parent: Node3D, grid_radius: int = 1) -> void:
	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var room := ROOM_SCENE.instantiate() as Room
			room.exits = [
				gz > -grid_radius, # north: neighbor exists towards -z
				gz < grid_radius,  # south: neighbor exists towards +z
				gx < grid_radius,  # east
				gx > -grid_radius, # west
			]
			room.position = Vector3(gx * Room.ROOM_SIZE, 0, gz * Room.ROOM_SIZE)
			parent.add_child(room)
