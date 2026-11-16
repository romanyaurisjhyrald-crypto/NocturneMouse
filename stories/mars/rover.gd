extends CharacterBody3D
## Drivable rover: box collider + the jelly Opportunity model as its visual.
## Not a suspension or realistic Mars rover simulation.
var spawn_point := Vector3(0.0,18.0,43.0)
var boundary: float = 68.0
var camera: Camera3D
## Jelly Opportunity model (res://stories/mars/godot_rover). Visual only: collision is the box below.
var model: OpportunityRover
var _steer_visual: float = 0.0
var _was_on_floor: bool = true
var _squash: float = 0.0
## Below this height the rover is considered lost and respawns.
var kill_depth: float = -30.0
# Third-person orbit camera: right mouse drag orbits, wheel zooms.
var cam_distance: float = 6.5
var cam_yaw: float = 0.0
var cam_pitch: float = deg_to_rad(16.0)
var _cam_heading: float = 0.0
var _cam_snap: bool = true      # jump straight behind the rover on the next physics frame
# Story hooks: the story can take the controls away, slow the rover down and aim its head.
var control_enabled: bool = true
var speed_scale: float = 1.0
var head_override: Variant = null   # Vector2(yaw, pitch) in radians, or null to follow steering
var dust: CPUParticles3D
var motor: AudioStreamPlayer

const Sfx = preload("res://stories/mars/sfx.gd")

const MODEL_SCENE: PackedScene = preload("res://stories/mars/godot_rover/opportunity_rover.tscn")
const MODEL_SCALE: float = 1.6      # the model is ~2 m long, the collider 3.6 m
const GROUND_OFFSET: float = -1.05  # bottom of the collision box

func _ready() -> void:
    floor_max_angle = deg_to_rad(48.0)
    floor_snap_length = 0.8
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(2.6,2.1,3.6)
    collider.shape = shape
    add_child(collider)
    model = MODEL_SCENE.instantiate() as OpportunityRover
    model.name = "Model"
    add_child(model)
    # The model faces +Z (glTF front); this body drives toward -Z.
    model.position = Vector3(0.0,GROUND_OFFSET,0.0)
    model.rotation.y = PI
    model.scale = Vector3.ONE*MODEL_SCALE
    dust = _make_dust()
    add_child(dust)
    motor = AudioStreamPlayer.new()
    motor.name = "Motor"
    motor.stream = Sfx.motor_loop()
    motor.volume_db = -60.0
    add_child(motor)
    motor.play()
    camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.far = 4000.0
    camera.fov = 65.0
    add_child(camera)
    camera.top_level = true     # follows smoothly instead of being glued to the body
    _cam_heading = rotation.y
    _update_camera(0.0,true)
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var label := Label.new()
    label.position = Vector2(20.0,68.0)
    label.text = "mars_controls"
    label.add_theme_color_override("font_color",Color("fff1db"))
    label.add_theme_color_override("font_shadow_color",Color("35152a"))
    label.add_theme_constant_override("shadow_offset_x",2)
    label.add_theme_constant_override("shadow_offset_y",2)
    canvas.add_child(label)

func _make_dust() -> CPUParticles3D:
    # Soft round puffs kicked up behind the wheels, in the soil's own color.
    var gradient := Gradient.new()
    gradient.set_color(0,Color(1.0,1.0,1.0,1.0))
    gradient.set_color(1,Color(1.0,1.0,1.0,0.0))
    var puff := GradientTexture2D.new()
    puff.gradient = gradient
    puff.fill = GradientTexture2D.FILL_RADIAL
    puff.fill_from = Vector2(0.5,0.5)
    puff.fill_to = Vector2(1.0,0.5)
    puff.width = 64
    puff.height = 64
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    material.billboard_keep_scale = true
    material.vertex_color_use_as_albedo = true
    material.albedo_texture = puff
    var quad := QuadMesh.new()
    quad.size = Vector2(1.1,1.1)
    quad.material = material
    var fade := Gradient.new()
    fade.set_color(0,Color(1.0,0.56,0.42,0.55))
    fade.set_color(1,Color(1.0,0.66,0.52,0.0))
    var grow := Curve.new()
    grow.add_point(Vector2(0.0,0.35))
    grow.add_point(Vector2(1.0,1.0))
    var particles := CPUParticles3D.new()
    particles.name = "WheelDust"
    particles.mesh = quad
    particles.amount = 56
    particles.lifetime = 1.3
    particles.local_coords = false
    particles.emitting = false
    particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    particles.emission_box_extents = Vector3(1.25,0.08,0.9)
    particles.position = Vector3(0.0,GROUND_OFFSET+0.25,0.9)
    particles.direction = Vector3(0.0,1.0,0.5)
    particles.spread = 40.0
    particles.initial_velocity_min = 0.8
    particles.initial_velocity_max = 2.4
    particles.gravity = Vector3(0.0,-0.9,0.0)
    particles.scale_amount_min = 0.5
    particles.scale_amount_max = 1.3
    particles.scale_amount_curve = grow
    particles.color_ramp = fade
    return particles

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam_distance = maxf(3.5,cam_distance-0.7)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam_distance = minf(30.0,cam_distance+0.7)
    elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
        cam_yaw -= event.relative.x*0.006
        cam_pitch = clampf(cam_pitch+event.relative.y*0.004,deg_to_rad(-8.0),deg_to_rad(75.0))

func _update_camera(delta: float, snap: bool = false) -> void:
    # The camera trails the rover's heading with a little lag, so turns are visible.
    _cam_heading = rotation.y if snap else lerp_angle(_cam_heading,rotation.y,clampf(delta*3.0,0.0,1.0))
    var target := global_position+Vector3(0.0,0.7,0.0)
    var yaw := _cam_heading+cam_yaw
    var back := Vector3(sin(yaw)*cos(cam_pitch),sin(cam_pitch),cos(yaw)*cos(cam_pitch))
    var wanted := target+back*cam_distance
    if not snap:
        # Pull in when terrain or a rock would hide the rover.
        var query := PhysicsRayQueryParameters3D.create(target,wanted)
        query.exclude = [get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty(): wanted = target.lerp(hit.position,0.9)+Vector3.UP*0.35
    camera.global_position = wanted if snap else camera.global_position.lerp(wanted,clampf(delta*10.0,0.0,1.0))
    camera.look_at(target)

func _animate_model(steer: float, delta: float) -> void:
    if model == null or model.skeleton == null: return
    # Wheels roll with the real ground speed, in model units.
    var forward_speed := velocity.dot(-transform.basis.z)
    model.drive(forward_speed*delta/MODEL_SCALE)
    _steer_visual = move_toward(_steer_visual,steer,delta*4.0)
    model.set_steering(_steer_visual)
    if head_override is Vector2: model.set_head(head_override.x,head_override.y)
    else: model.set_head(_steer_visual*0.6,0.0)
    # Dust and motor follow how fast the wheels really move over the ground.
    var ground_speed := Vector2(velocity.x,velocity.z).length()
    dust.emitting = is_on_floor() and ground_speed > 0.6
    var drive_amount := clampf(ground_speed/8.0,0.0,2.2)
    motor.volume_db = lerpf(motor.volume_db,-16.0 if drive_amount > 0.05 else -60.0,clampf(delta*6.0,0.0,1.0))
    motor.pitch_scale = lerpf(motor.pitch_scale,0.75+drive_amount*0.35,clampf(delta*5.0,0.0,1.0))
    # Jelly squash when landing, then spring back.
    if is_on_floor() and not _was_on_floor: _squash = 0.18
    _was_on_floor = is_on_floor()
    _squash = move_toward(_squash,0.0,delta*0.9)
    model.squash(_squash*cos(_squash*40.0))

func _physics_process(delta: float) -> void:
    var throttle := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
    var steer := float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))-float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
    if not control_enabled:
        throttle = 0.0
        steer = 0.0
    rotate_y(steer*delta*1.2)
    var speed := (18.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 8.0)*speed_scale
    var target := -transform.basis.z*throttle*speed
    if Input.is_physical_key_pressed(KEY_SPACE): target = Vector3.ZERO
    velocity.x = move_toward(velocity.x,target.x,12.0*delta)
    velocity.z = move_toward(velocity.z,target.z,12.0*delta)
    if not is_on_floor(): velocity.y -= 3.71*delta
    else: velocity.y = -0.5
    move_and_slide()
    _animate_model(steer,delta)
    if absf(position.x)>boundary or absf(position.z)>boundary or position.y < kill_depth:
        position = spawn_point
        velocity = Vector3.ZERO
        _cam_snap = true
    _update_camera(delta,_cam_snap)
    _cam_snap = false
