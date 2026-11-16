class_name OpportunityRover
extends Node3D
## Jelly-comic Opportunity rover character.
##
## Attach to the root of the imported opportunity_rover.glb (see
## opportunity_rover.tscn). On ready it rebuilds the Blender look by swapping
## the imported GD_* materials for the jelly toon shader, and exposes a small
## pose API driven by the skeleton exported from Blender.
##
## The model faces +Z (glTF front). Its left side (_L bones) is at +X.

const JELLY_SHADER: Shader = preload("jelly_toon.gdshader")

@export_group("Look")
## Fake subsurface rim strength (0 = flat cel shading).
@export_range(0.0, 1.0) var rim_amount: float = 0.45
## Highlight size: higher = smaller, harder highlight.
@export_range(1.0, 256.0) var gloss_power: float = 48.0
## Shadow / base color cut of the cel shading.
@export_range(0.0, 1.0) var shadow_threshold: float = 0.12

@export_group("Motion")
## Wheel radius in meters, used to convert distance into wheel spin.
@export var wheel_radius: float = 0.175
## Largest steering angle of the four corner wheels, in degrees.
@export_range(0.0, 60.0) var max_steer_degrees: float = 35.0
## Plays a looping showcase motion (drive, steer, look around, wobble).
@export var demo_motion: bool = false

const WHEELS: Array[StringName] = [
	&"Wheel_FL", &"Wheel_ML", &"Wheel_RL", &"Wheel_FR", &"Wheel_MR", &"Wheel_RR"]

var skeleton: Skeleton3D
var _bones: Dictionary = {}
var _wheel_angle: float = 0.0
var _base_scale: Vector3 = Vector3.ONE
var _time: float = 0.0
var _glint_material: StandardMaterial3D
var _jelly: Array[Dictionary] = []

const DUST_COLOR := Color(0.80, 0.33, 0.22)
const DUST_SHADOW := Color(0.50, 0.16, 0.14)


func _ready() -> void:
	skeleton = _find_first(self, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("OpportunityRover: no Skeleton3D found under %s" % name)
		return
	_base_scale = skeleton.scale
	for i in skeleton.get_bone_count():
		_bones[StringName(skeleton.get_bone_name(i))] = i
	_apply_materials()


func _process(delta: float) -> void:
	if not demo_motion or skeleton == null:
		return
	_time += delta
	drive(delta * 0.8)
	set_steering(sin(_time * 0.9) * 0.6)
	set_head(sin(_time * 0.7) * 0.7, sin(_time * 1.3) * 0.2)
	set_suspension(&"L", sin(_time * 2.0) * 0.12, sin(_time * 2.6) * 0.15)
	set_suspension(&"R", -sin(_time * 2.0) * 0.12, cos(_time * 2.6) * 0.15)
	set_arm(sin(_time * 0.8) * 0.3, 0.3 + sin(_time * 1.1) * 0.3, _time)
	squash(sin(_time * 4.0) * 0.03)


# ----------------------------------------------------------------------------
#  Pose API
# ----------------------------------------------------------------------------

## Spins all six wheels as if the rover rolled [param distance] meters forward.
func drive(distance: float) -> void:
	_wheel_angle = wrapf(_wheel_angle + distance / wheel_radius, 0.0, TAU)
	for wheel in WHEELS:
		_pose(wheel, Quaternion(Vector3.UP, _wheel_angle))


## Steers the corner wheels. [param amount] is -1 (right) .. 1 (left).
## Rear wheels counter-steer so the rover turns around its middle axle.
func set_steering(amount: float) -> void:
	var a := clampf(amount, -1.0, 1.0) * deg_to_rad(max_steer_degrees)
	_pose(&"Steer_FL", Quaternion(Vector3.UP, a))
	_pose(&"Steer_FR", Quaternion(Vector3.UP, a))
	_pose(&"Steer_RL", Quaternion(Vector3.UP, -a))
	_pose(&"Steer_RR", Quaternion(Vector3.UP, -a))


## Turns the camera head. Radians; positive yaw looks left, positive pitch nods down.
func set_head(yaw: float, pitch: float) -> void:
	_pose(&"Mast_Head", Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch))


## Rotates the whole mast around its vertical axis (radians).
func set_mast(yaw: float) -> void:
	_pose(&"Mast_Base", Quaternion(Vector3.UP, yaw))


## Rocks one suspension side. [param side] is &"L" or &"R"; angles in radians.
func set_suspension(side: StringName, rocker: float, bogie: float) -> void:
	_pose(StringName("Rocker_" + side), Quaternion(Vector3.UP, rocker))
	_pose(StringName("Bogie_" + side), Quaternion(Vector3.UP, bogie))


## Poses the robotic arm (radians): shoulder and elbow pitch, turret spin.
func set_arm(shoulder: float, elbow: float, turret: float) -> void:
	_pose(&"Arm_Shoulder", Quaternion(Vector3.RIGHT, shoulder))
	_pose(&"Arm_Elbow", Quaternion(Vector3.RIGHT, elbow))
	_pose(&"Arm_Turret", Quaternion(Vector3.RIGHT, turret))


## Jelly squash and stretch around the ground contact.
## Positive = squashed (shorter and wider), negative = stretched.
func squash(amount: float) -> void:
	skeleton.scale = _base_scale * Vector3(1.0 + amount * 0.5, 1.0 - amount, 1.0 + amount * 0.5)


## Covers the rover in red Martian dust. 0 = clean, 1 = fully dusty and matte.
func set_dust(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0) * 0.7
	for entry in _jelly:
		var mat: ShaderMaterial = entry.material
		mat.set_shader_parameter(&"base_color", (entry.base as Color).lerp(DUST_COLOR, a))
		mat.set_shader_parameter(&"shadow_color", (entry.shadow as Color).lerp(DUST_SHADOW, a))
		mat.set_shader_parameter(&"gloss", 1.0 - clampf(amount, 0.0, 1.0))


## Brightness of the glints in the camera eyes. 1 = awake, 0 = eyes off.
func set_eye_glow(amount: float) -> void:
	if _glint_material:
		var v := clampf(amount, 0.0, 1.0)
		_glint_material.albedo_color = Color(v, v, v)


## Returns every bone to its rest pose.
func reset_pose() -> void:
	skeleton.reset_bone_poses()
	skeleton.scale = _base_scale
	_wheel_angle = 0.0


# ----------------------------------------------------------------------------
#  Internals
# ----------------------------------------------------------------------------

func _pose(bone: StringName, local_rotation: Quaternion) -> void:
	var i: int = _bones.get(bone, -1)
	if i < 0:
		return
	var rest := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(i, rest * local_rotation)


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found:
			return found
	return null


func _apply_materials() -> void:
	for mesh_instance in _find_all_meshes(self, []):
		var mesh: Mesh = mesh_instance.mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			mesh_instance.set_surface_override_material(s, _make_material(src))


func _find_all_meshes(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and node.mesh:
		out.append(node)
	for child in node.get_children():
		_find_all_meshes(child, out)
	return out


func _make_material(src: BaseMaterial3D) -> Material:
	var mat_name := src.resource_name
	if mat_name.contains("Outline") or mat_name.contains("Glint"):
		# Ink hull (inverted normals, shown through back-face culling) and eye glints.
		var flat := StandardMaterial3D.new()
		flat.resource_name = mat_name
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color.WHITE if mat_name.contains("Glint") else Color(0.01, 0.005, 0.02)
		flat.cull_mode = BaseMaterial3D.CULL_BACK
		if mat_name.contains("Glint"):
			_glint_material = flat
		return flat

	var c := src.albedo_color
	var mat := ShaderMaterial.new()
	mat.resource_name = mat_name
	mat.shader = JELLY_SHADER
	mat.set_shader_parameter(&"base_color", c)
	mat.set_shader_parameter(&"shadow_color", Color.from_hsv(
		fposmod(c.h - 0.04, 1.0), minf(1.0, c.s * 1.15 + 0.05), c.v * 0.66))
	mat.set_shader_parameter(&"rim_color", Color.from_hsv(
		c.h, c.s * 0.45, minf(1.0, c.v + 0.55)))
	# Dark licorice parts get a subtler rim so they stay black.
	mat.set_shader_parameter(&"rim_amount", rim_amount * (0.4 if c.v < 0.2 else 1.0))
	mat.set_shader_parameter(&"gloss_power", gloss_power)
	mat.set_shader_parameter(&"shadow_threshold", shadow_threshold)
	_jelly.append({"material": mat, "base": c, "shadow": mat.get_shader_parameter(&"shadow_color")})
	return mat
