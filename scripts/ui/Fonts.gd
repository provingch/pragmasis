class_name Fonts

## Telemetry type: wide-tracked monospace for data, tight heavy sans for
## macro numerals. System fonts with fallbacks.
# ponytail: SystemFont depends on what's installed; bundle .ttf files in res:// before shipping

static var mono: Font = _make(["JetBrains Mono", "IBM Plex Mono", "Liberation Mono", "Adwaita Mono", "monospace"], 500, 1)
static var heavy: Font = _make(["Archivo Black", "Inter", "Inter Display", "sans-serif"], 900, -3)

## Menu type, bundled (OFL, see fonts/): pixel display face for titles,
## VT323 terminal face for everything else.
static var _pixel_file: Font = load("res://fonts/PressStart2P-Regular.ttf")
static var _terminal_file: Font = load("res://fonts/VT323-Regular.ttf")

static func pixel(tracking := 0) -> Font:
	return _track(_pixel_file, tracking)

static func terminal(tracking := 0) -> Font:
	return _track(_terminal_file, tracking)

static func _make(names: Array, weight: int, tracking: int) -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(names)
	sys.font_weight = weight
	return _track(sys, tracking)

static func _track(base: Font, tracking: int) -> Font:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = tracking
	return v
