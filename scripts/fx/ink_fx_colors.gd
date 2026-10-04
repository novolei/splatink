class_name InkFxColors
extends RefCounted

## Palette/hex inputs are sRGB. Original THREE.Color recipes and raw GPU COLOR
## attributes are linear; source_color uniforms and StandardMaterial stay sRGB.
static var _linear_cache: Dictionary = {}

static func from_srgb(color: Color) -> Color:
	if not _linear_cache.has(color):
		_linear_cache[color] = color.srgb_to_linear()
	return _linear_cache[color]

static func team_of(color: Color, palette: Array, input_linear: bool = true) -> int:
	var linear: Color = color if input_linear else from_srgb(color)
	# main.js _teamOfColor uses first L1 match, including identical palette entries.
	for team in mini(2, palette.size()):
		var candidate: Color = from_srgb(palette[team])
		if absf(linear.r-candidate.r)+absf(linear.g-candidate.g)+absf(linear.b-candidate.b)<.05:
			return team
	return -1
