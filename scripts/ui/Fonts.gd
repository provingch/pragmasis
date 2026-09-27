class_name Fonts

## Telemetry type: wide-tracked monospace for data, tight heavy sans for
## macro numerals. System fonts with fallbacks.
# ponytail: SystemFont depends on what's installed; bundle .ttf files in res:// before shipping

static var mono: Font = _make(["JetBrains Mono", "IBM Plex Mono", "Liberation Mono", "Adwaita Mono", "monospace"], 500, 1)
static var heavy: Font = _make(["Archivo Black", "Inter", "Inter Display", "sans-serif"], 900, -3)

static func _make(names: Array, weight: int, tracking: int) -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(names)
	sys.font_weight = weight
	var v := FontVariation.new()
	v.base_font = sys
	v.spacing_glyph = tracking
	return v
