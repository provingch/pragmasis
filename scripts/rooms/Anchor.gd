extends Area3D
class_name Anchor

## The sequence's exit: a large, slow, fully coherent tesseract in the
## scanner's "safe" green (its material runs at low energy: bright green
## washes out to white through the tonemapper), with its own light and a
## hum you can follow by ear. Touching it completes the sequence.

const COLOR := Color("4af626")

@onready var tesseract: Tesseract = $Tesseract

var _done := false

func _ready() -> void:
	tesseract.color = COLOR
	tesseract.coherence = 1.0
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	tesseract.phase += delta * 0.7

func _on_body_entered(body: Node3D) -> void:
	if not _done and body.is_in_group("player"):
		_done = true
		GameManager.complete_sequence()
