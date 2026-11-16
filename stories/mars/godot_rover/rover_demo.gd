extends Node3D
## Showcase scene for the jelly Opportunity rover: pastel sky, mint ground,
## one shadow-casting sun and a three-quarter camera.

const JELLY_SHADER: Shader = preload("jelly_toon.gdshader")


func _ready() -> void:
	$Camera3D.look_at_from_position(Vector3(3.3, 2.5, 4.3), Vector3(0.0, 0.62, 0.05))
	$Sun.look_at_from_position(Vector3(-2.5, 6.0, 4.0), Vector3(0.0, 0.5, 0.0))

	# The ground uses the same toon shader so its shadow is a flat comic shape.
	var ground := ShaderMaterial.new()
	ground.shader = JELLY_SHADER
	ground.set_shader_parameter(&"base_color", Color(0.62, 0.95, 0.84))
	ground.set_shader_parameter(&"shadow_color", Color(0.36, 0.74, 0.70))
	ground.set_shader_parameter(&"gloss", 0.0)
	ground.set_shader_parameter(&"rim_amount", 0.0)
	$Ground.material_override = ground
