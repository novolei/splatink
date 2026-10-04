class_name SplatUiBackdrop
extends ColorRect
## CSS iw-scrim-left, rendered in a single canvas batch.

var page: String = "main"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){float a=UV.x<0.36?mix(0.74,0.5,UV.x/0.36):(UV.x<0.6?mix(0.5,0.08,(UV.x-0.36)/0.24):mix(0.08,0.0,clamp((UV.x-0.6)/0.1,0.0,1.0)));float b=0.45*clamp((UV.y-0.78)/0.22,0.0,1.0);COLOR=vec4(vec3(12.,9.,22.)/255.,1.-(1.-a)*(1.-b));}"
	var face := ShaderMaterial.new()
	face.shader = shader
	material = face
