extends SubViewportContainer
class_name AvatarView

## A PlayerAvatar on its own little stage (transparent, lit like the
## character sheet: a warm key from above, a cold rim from behind), for
## 2D screens: the main menu stands it by the tesseract, game over has it
## on its knees.

const AVATAR := preload("res://scenes/player/PlayerAvatar.tscn")

@export var edge_color := Color("f2e6d4")
@export var crouching := false
## Turns slowly in place (rad/s); 0 = three-quarter view, still.
@export var spin := 0.0

var avatar: PlayerAvatar

func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.25
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 5.4)
	cam.fov = 34.0
	vp.add_child(cam)
	cam.look_at(Vector3(0, 1.3, 0))
	var key := SpotLight3D.new()
	key.position = Vector3(1.2, 4.5, 2.0)
	key.light_energy = 6.0
	key.spot_range = 9.0
	key.spot_angle = 35.0
	key.light_color = Color(1.0, 0.92, 0.82)
	vp.add_child(key)
	key.look_at(Vector3(0, 1.2, 0))
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.4, 2.6, -1.8)
	rim.light_energy = 2.5
	rim.light_color = Color(0.6, 0.75, 1.0)
	vp.add_child(rim)
	avatar = AVATAR.instantiate()
	avatar.edge_color = edge_color
	avatar.size = 1.0
	avatar.crouching = crouching
	avatar.rotation.y = deg_to_rad(-28.0)
	vp.add_child(avatar)

func _process(delta: float) -> void:
	avatar.rotation.y += spin * delta
