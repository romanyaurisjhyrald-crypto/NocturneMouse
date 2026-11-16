extends Node
## "Sweet Horizon (Sol 5111)": a four-act story played on the endless planet.
##
## The story is a list of steps run one after another. Dialogue and title steps
## last a fixed time; "reach" steps block until the rover drives from where it
## is (point A) to the active waypoint (point B), so the acts cannot be skipped.
##
## Voice-over: drop a file named after the line id into res://stories/mars/audio/voice/
## (for example a1_n1.ogg, .mp3 or .wav) and it plays instead of the placeholder
## tone, and the subtitle stays for the length of the recording.

const Sfx = preload("res://stories/mars/sfx.gd")
const NARRATOR: String = "mars_narrator"
const OPPY: String = "mars_oppy"
const VOICE_DIR: String = "res://stories/mars/audio/voice/"

signal finished

var mars    # the mars.gd node (untyped: its script members are used directly)
var rover   # the rover.gd CharacterBody3D
## Multiplies every dialogue, title and pause duration. Tests shrink it.
var line_time_scale: float = 1.0
var is_finished: bool = false

# Step machine
var steps: Array[Dictionary] = []
var step_index: int = -1
var _step_time: float = 0.0
var _step_duration: float = 0.0
var _skip: bool = false

# Waypoints (the "point B" of each mission)
var goals: Array[Vector3] = []
var goal_radius: Array[float] = [9.0, 9.0, 5.0]
var goal_index: int = -1
var goal_active: bool = false
var _beacons: Array[MeshInstance3D] = []

# World blending targets, all 0..1
var storm: float = 0.0
var night: float = 0.0
var _storm_target: float = 0.0
var _night_target: float = 0.0
var _storm_building: bool = false
var _dust_on_rover: float = 0.0
var _dust_target: float = 0.0
var _fade: float = 0.0
var _fade_target: float = 0.0
var _flash: float = 0.0
var _card_alpha: float = 0.0
var _card_target: float = 0.0
var _creep: float = 0.0          # seconds of slow wheel roll left before the rover stops
var _led_on: bool = false
var _sleep_time: float = -1.0    # >= 0 while the eyes are closing
var _orbit_speed: float = 0.0
var _cam_yaw_target: Variant = null
var _clock: float = 0.0

# Nodes
var _subtitle_panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _objective_label: Label
var _battery: ProgressBar
var _marker: Control
var _marker_label: Label
var _card_title: Label
var _card_subtitle: Label
var _fade_rect: ColorRect
var _flash_rect: ColorRect
var _wind: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _storm_particles: CPUParticles3D
var _led: OmniLight3D
var _led_bulb: MeshInstance3D
var _sky: ProceduralSkyMaterial
var _env: Environment
var _sun: DirectionalLight3D


func setup(mars_node: Node3D, rover_node: CharacterBody3D) -> void:
    # Call before adding the story to the tree.
    mars = mars_node
    rover = rover_node
    _env = mars.environment
    _sun = mars.sun
    _sky = mars.sky_material


func _ready() -> void:
    _place_goals()
    _build_hud()
    _build_world_effects()
    _write_script()


# ----------------------------------------------------------------------------
#  The script
# ----------------------------------------------------------------------------

func _write_script() -> void:
    _title(tr("mars_act_0_title"), tr("mars_act_0_subtitle"))

    # Act I: the little explorer of the shiny stones
    _title(tr("mars_act_1_title"), tr("mars_act_1_subtitle"))
    _goal(0, tr("mars_goal_0"))
    _line(NARRATOR, "a1_n1", tr("mars_a1_n1"))
    _reach()
    _call(_take_photo)
    _line(OPPY, "a1_o1", tr("mars_a1_o1"))
    _goal(1, tr("mars_goal_1"))
    _reach()
    _call(_take_photo)
    _line(NARRATOR, "a1_n2", tr("mars_a1_n2"))

    # Act II: when the sky decides to close its curtains
    _title(tr("mars_act_2_title"), tr("mars_act_2_subtitle"))
    _call(_begin_storm)
    _goal(2, tr("mars_goal_2"))
    _line(NARRATOR, "a2_n1", tr("mars_a2_n1"))
    _reach()
    _call(_storm_arrives)
    _line(OPPY, "a2_o1", tr("mars_a2_o1"))
    _call(_last_roll)
    _wait(3.0)
    _line(OPPY, "a2_o2", tr("mars_a2_o2"))
    _line(NARRATOR, "a2_n2", tr("mars_a2_n2"))

    # Act III: learning to sleep without fear
    _title(tr("mars_act_3_title"), tr("mars_act_3_subtitle"))
    _call(_begin_night)
    _wait(2.5)
    _line(OPPY, "a3_o1", tr("mars_a3_o1"))
    _line(NARRATOR, "a3_n1", tr("mars_a3_n1"))
    _line(OPPY, "a3_o2", tr("mars_a3_o2"))
    _line(OPPY, "a3_o3", tr("mars_a3_o3"))
    _call(_fall_asleep)
    _wait(5.0)

    # Act IV: epilogue, the rest
    _call(_fade_out)
    _wait(2.5)
    _call(_begin_dawn)
    _title(tr("mars_act_4_title"), tr("mars_act_4_subtitle"))
    _call(_fade_in)
    _wait(2.0)
    _line(NARRATOR, "a4_n1", tr("mars_a4_n1"))
    _wait(1.5)
    _line(NARRATOR, "a4_n2", tr("mars_a4_n2"))
    _wait(2.0)
    _call(_show_ending)


func _title(title: String, subtitle: String) -> void:
    steps.append({"kind": "title", "title": title, "subtitle": subtitle})

func _line(speaker: String, id: String, text: String) -> void:
    steps.append({"kind": "line", "speaker": speaker, "id": id, "text": text})

func _goal(index: int, hint: String) -> void:
    steps.append({"kind": "goal", "index": index, "hint": hint})

func _reach() -> void:
    steps.append({"kind": "reach"})

func _wait(seconds: float) -> void:
    steps.append({"kind": "wait", "seconds": seconds})

func _call(action: Callable) -> void:
    steps.append({"kind": "call", "action": action})


# ----------------------------------------------------------------------------
#  Step machine
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
    _clock += delta
    _animate_world(delta)
    _animate_rover(delta)
    _update_goal()
    _update_hud(delta)
    if is_finished:
        return
    _step_time += delta
    # Instant steps chain within one frame; timed steps hold until they finish.
    var guard := 0
    while guard < 32 and (step_index < 0 or _step_done()):
        guard += 1
        step_index += 1
        _step_time = 0.0
        _skip = false
        if step_index >= steps.size():
            is_finished = true
            finished.emit()
            return
        _enter_step(steps[step_index])


func _step_done() -> bool:
    var step: Dictionary = steps[step_index]
    match step.kind:
        "reach":
            return not goal_active
        "line":
            if _step_time >= _step_duration or _skip:
                _subtitle_panel.visible = false
                return true
            return false
        "title":
            if _step_time >= _step_duration-1.0:
                _card_target = 0.0
            return _step_time >= _step_duration
        "wait":
            return _step_time >= _step_duration
    return true


func _enter_step(step: Dictionary) -> void:
    match step.kind:
        "title":
            _card_title.text = step.title
            _card_subtitle.text = step.subtitle
            _card_target = 1.0
            _step_duration = 4.5*line_time_scale
        "line":
            _speaker_label.text = tr(step.speaker)
            _speaker_label.add_theme_color_override("font_color", Color("8fd8ff") if step.speaker == OPPY else Color("ffd9a0"))
            _text_label.text = step.text
            _subtitle_panel.visible = true
            _step_duration = (2.5+step.text.length()*0.065)*line_time_scale
            var voice := _find_voice(step.id)
            if voice != null:
                _voice.stream = voice
                _voice.volume_db = 0.0
                _voice.play()
                _step_duration = maxf(voice.get_length()+0.6, 1.0)*line_time_scale
            else:
                _voice.stream = Sfx.chirp() if step.speaker == OPPY else Sfx.narrator_tone()
                _voice.volume_db = -8.0
                _voice.play()
        "goal":
            goal_index = step.index
            goal_active = true
            _objective_label.text = tr("mars_mission") % step.hint
            _beacons[goal_index].visible = true
        "wait":
            _step_duration = step.seconds*line_time_scale
        "call":
            (step.action as Callable).call()


func _find_voice(id: String) -> AudioStream:
    for extension in ["ogg", "mp3", "wav"]:
        var path: String = VOICE_DIR+TranslationServer.get_locale().left(2)+"/"+id+"."+extension
        if ResourceLoader.exists(path):
            return load(path) as AudioStream
    return null


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_E):
        _skip = true


# ----------------------------------------------------------------------------
#  Missions: point A -> point B
# ----------------------------------------------------------------------------

func _place_goals() -> void:
    # A winding route ahead of the landing site; heights follow the terrain.
    var start: Vector3 = rover.position
    var route := [Vector2(-25.0,-115.0), Vector2(55.0,-140.0), Vector2(-45.0,-150.0)]
    var point := Vector2(start.x, start.z)
    for index in route.size():
        point += route[index]
        var ground: float = mars.planet_height(point.x, point.y)
        goals.append(Vector3(point.x, ground, point.y))
        var radius := 2.4 if index < 2 else 0.75
        var rock := MeshInstance3D.new()
        rock.name = "StoryRock_%d" % index
        rock.mesh = mars._rock_mesh(900+index, radius)
        rock.material_override = mars._rock_material
        add_child(rock)
        rock.position = Vector3(point.x, ground+radius*0.3, point.y)
        mars._rock_collision(rock)
        _beacons.append(_make_beacon(rock.position))


func _make_beacon(at: Vector3) -> MeshInstance3D:
    # Tall soft light column so point B can be seen from far away.
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.albedo_color = Color(1.0, 0.86, 0.55, 0.30)
    material.disable_fog = true
    var column := CylinderMesh.new()
    column.top_radius = 0.9
    column.bottom_radius = 0.9
    column.height = 90.0
    column.radial_segments = 8
    column.material = material
    var beacon := MeshInstance3D.new()
    beacon.name = "Beacon"
    beacon.mesh = column
    beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    beacon.visible = false
    add_child(beacon)
    beacon.position = at+Vector3(0.0, 45.0, 0.0)
    return beacon


func _update_goal() -> void:
    if not goal_active:
        return
    var to_goal: Vector3 = goals[goal_index]-rover.global_position
    if Vector2(to_goal.x, to_goal.z).length() <= goal_radius[goal_index]:
        goal_active = false
        _beacons[goal_index].visible = false
        _objective_label.text = ""
        _play(Sfx.chime(), -6.0)


# ----------------------------------------------------------------------------
#  Story actions
# ----------------------------------------------------------------------------

func _take_photo() -> void:
    _flash = 0.85
    _play(Sfx.shutter(), -4.0)

func _begin_storm() -> void:
    _storm_building = true

func _storm_arrives() -> void:
    # The rover reached the little red stone: the storm closes in and it stops.
    _storm_building = false
    _storm_target = 1.0
    rover.control_enabled = false
    rover.head_override = Vector2(0.0, -0.45)   # looks up at the dark sky
    _cam_yaw_target = 2.55
    rover.cam_distance = 5.5

func _last_roll() -> void:
    _creep = 2.4
    rover.head_override = Vector2(0.0, 0.1)

func _begin_night() -> void:
    _night_target = 1.0
    _led_on = true

func _fall_asleep() -> void:
    _sleep_time = 0.0
    _play(Sfx.power_down(), -8.0)

func _fade_out() -> void:
    _fade_target = 1.0

func _begin_dawn() -> void:
    # Days later: the storm is gone, the sun is back, Oppy rests under red dust.
    _storm_target = 0.0
    _night_target = 0.0
    storm = 0.0
    night = 0.0
    _dust_target = 1.0
    _dust_on_rover = 1.0
    _led_on = false
    rover.model.set_eye_glow(0.0)
    rover.cam_distance = 9.0
    rover.cam_pitch = deg_to_rad(12.0)
    _cam_yaw_target = null
    _orbit_speed = 0.07
    _play(Sfx.lullaby(), -9.0)

func _fade_in() -> void:
    _fade_target = 0.0

func _show_ending() -> void:
    _card_title.text = "mars_act_0_title"
    _card_subtitle.text = "mars_ending"
    _card_target = 1.0


# ----------------------------------------------------------------------------
#  Per-frame animation
# ----------------------------------------------------------------------------

func _animate_world(delta: float) -> void:
    if _storm_building:
        # The storm grows while the rover travels, draining light and speed.
        _storm_target = minf(0.8, _storm_target+delta/55.0)
        rover.speed_scale = lerpf(1.0, 0.4, storm)
    storm = move_toward(storm, _storm_target, delta*0.3)
    night = move_toward(night, _night_target, delta*0.22)
    var dark := 1.0-night*0.9
    _sun.light_energy = lerpf(1.3, 0.14, storm)*(1.0-night*0.95)
    _env.ambient_light_energy = lerpf(0.32, 0.22, storm)*(1.0-night*0.7)
    _env.fog_density = lerpf(0.0024, 0.032, storm)
    _env.fog_light_color = Color("ffba91").lerp(Color(0.46,0.23,0.15), storm)*dark
    _env.fog_aerial_perspective = 1.0-storm
    _env.fog_sky_affect = storm
    _sky.sky_top_color = Color("b94064").lerp(Color(0.26,0.13,0.12), storm)*dark
    _sky.sky_horizon_color = Color("ffba91").lerp(Color(0.50,0.27,0.17), storm)*dark
    _sky.ground_horizon_color = Color("f58d7d").lerp(Color(0.42,0.22,0.15), storm)*dark
    _sky.ground_bottom_color = Color("6c183c").lerp(Color(0.20,0.09,0.09), storm)*dark
    _storm_particles.emitting = storm > 0.15
    var rover_at: Vector3 = rover.global_position
    _storm_particles.global_position = rover_at+Vector3(-18.0, 4.0, 0.0)
    _wind.volume_db = lerpf(-24.0, -3.0, storm)-night*8.0
    _wind.pitch_scale = lerpf(0.9, 1.35, storm)
    _fade = move_toward(_fade, _fade_target, delta*0.5)
    _flash = move_toward(_flash, 0.0, delta*2.2)
    _card_alpha = move_toward(_card_alpha, _card_target, delta*1.2)


func _animate_rover(delta: float) -> void:
    if _creep > 0.0:
        # The wheels roll a little farther, then gently stop in the sand.
        _creep -= delta
        rover.model.drive(delta*0.35*clampf(_creep, 0.0, 1.0))
    _dust_on_rover = move_toward(_dust_on_rover, _dust_target, delta*0.5)
    rover.model.set_dust(maxf(_dust_on_rover, storm*0.25))
    if _cam_yaw_target is float:
        rover.cam_yaw = lerp_angle(rover.cam_yaw, _cam_yaw_target, clampf(delta*0.8, 0.0, 1.0))
    rover.cam_yaw += _orbit_speed*delta
    # Small blue LED, breathing slowly in the dark.
    var pulse := pow(maxf(0.0, sin(_clock*1.9)), 2.0) if _led_on else 0.0
    _led.light_energy = pulse*3.0
    _led_bulb.visible = _led_on
    (_led_bulb.material_override as StandardMaterial3D).albedo_color = Color(0.15,0.35,1.0).lerp(Color(0.6,0.85,1.0), pulse)
    if _sleep_time >= 0.0:
        # The camera eyes blink twice, like a sleepy child, and go out in peace.
        _sleep_time += delta
        var t := _sleep_time
        var glow := 1.0
        if (t > 0.4 and t < 0.75) or (t > 1.35 and t < 1.7):
            glow = 0.0
        elif t >= 1.7:
            glow = clampf(1.0-(t-1.7)/1.6, 0.0, 1.0)*0.7
        rover.model.set_eye_glow(glow)
        rover.head_override = Vector2(0.0, lerpf(0.1, 0.42, clampf(t/3.0, 0.0, 1.0)))
        if t > 3.4:
            _led_on = false
            _battery.value = 0.0


func _update_hud(delta: float) -> void:
    _fade_rect.color.a = _fade
    _flash_rect.color.a = _flash
    _card_title.modulate.a = _card_alpha
    _card_subtitle.modulate.a = _card_alpha
    if _sleep_time < 0.0:
        _battery.value = move_toward(_battery.value, 1.0-storm*0.82-night*0.1, delta*0.5)
    # Waypoint marker: a diamond pinned to point B, clamped to the screen edge.
    var camera := get_viewport().get_camera_3d()
    _marker.visible = goal_active and camera != null and _fade < 0.5
    if not _marker.visible:
        return
    var target := goals[goal_index]+Vector3(0.0, 4.0, 0.0)
    var screen := get_viewport().get_visible_rect().size
    var scale := screen/Vector2(get_viewport().size)
    var point := camera.unproject_position(target)*scale
    if camera.is_position_behind(target):
        # Behind the camera: mirror and push to the nearest side edge.
        point = Vector2(screen.x-point.x, screen.y)
    point = point.clamp(Vector2(60.0, 150.0), screen-Vector2(60.0, 190.0))
    _marker.position = point
    var rover_at: Vector3 = rover.global_position
    var distance := Vector2(target.x-rover_at.x, target.z-rover_at.z).length()
    _marker_label.text = tr("mars_distance") % int(distance)


# ----------------------------------------------------------------------------
#  Construction
# ----------------------------------------------------------------------------

func _play(stream: AudioStream, volume_db: float) -> void:
    var player := AudioStreamPlayer.new()
    player.stream = stream
    player.volume_db = volume_db
    add_child(player)
    player.finished.connect(player.queue_free)
    player.play()


func _label(size: int, color: Color) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color("35152a"))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    return label


func _build_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "StoryHud"
    canvas.layer = 2
    add_child(canvas)

    _flash_rect = ColorRect.new()
    _flash_rect.color = Color(1.0,1.0,1.0,0.0)
    _flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    canvas.add_child(_flash_rect)
    _fade_rect = ColorRect.new()
    _fade_rect.color = Color(0.03,0.01,0.02,0.0)
    _fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    canvas.add_child(_fade_rect)

    # Mission objective and battery, top right.
    var corner := VBoxContainer.new()
    corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    corner.offset_right = -20.0
    corner.offset_top = 18.0
    corner.alignment = BoxContainer.ALIGNMENT_BEGIN
    canvas.add_child(corner)
    _objective_label = _label(20, Color("fff1db"))
    _objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _objective_label.custom_minimum_size = Vector2(460.0, 0.0)
    corner.add_child(_objective_label)
    var battery_row := HBoxContainer.new()
    battery_row.alignment = BoxContainer.ALIGNMENT_END
    corner.add_child(battery_row)
    var battery_label := _label(16, Color("fff1db"))
    battery_label.text = "mars_battery"
    battery_row.add_child(battery_label)
    _battery = ProgressBar.new()
    _battery.min_value = 0.0
    _battery.max_value = 1.0
    _battery.value = 1.0
    _battery.show_percentage = false
    _battery.custom_minimum_size = Vector2(160.0, 16.0)
    _battery.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color("8fd8ff")
    fill.set_corner_radius_all(6)
    var back := StyleBoxFlat.new()
    back.bg_color = Color(0.2,0.08,0.16,0.7)
    back.set_corner_radius_all(6)
    _battery.add_theme_stylebox_override("fill", fill)
    _battery.add_theme_stylebox_override("background", back)
    battery_row.add_child(_battery)

    # Waypoint marker.
    _marker = Control.new()
    _marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _marker.visible = false
    canvas.add_child(_marker)
    var diamond := ColorRect.new()
    diamond.color = Color("ffd76a")
    diamond.size = Vector2(18.0, 18.0)
    diamond.pivot_offset = Vector2(9.0, 9.0)
    diamond.position = Vector2(-9.0, -9.0)
    diamond.rotation = PI/4.0
    _marker.add_child(diamond)
    _marker_label = _label(18, Color("fff1db"))
    _marker_label.position = Vector2(-40.0, 16.0)
    _marker_label.custom_minimum_size = Vector2(80.0, 0.0)
    _marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _marker.add_child(_marker_label)

    # Subtitles, bottom center.
    _subtitle_panel = PanelContainer.new()
    _subtitle_panel.visible = false
    _subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _subtitle_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _subtitle_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _subtitle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _subtitle_panel.offset_bottom = -28.0
    var box := StyleBoxFlat.new()
    box.bg_color = Color(0.13,0.04,0.10,0.78)
    box.set_corner_radius_all(18)
    box.set_content_margin_all(18.0)
    _subtitle_panel.add_theme_stylebox_override("panel", box)
    canvas.add_child(_subtitle_panel)
    var lines := VBoxContainer.new()
    _subtitle_panel.add_child(lines)
    _speaker_label = _label(20, Color("ffd9a0"))
    _speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lines.add_child(_speaker_label)
    _text_label = _label(24, Color("fff6ea"))
    _text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _text_label.custom_minimum_size = Vector2(920.0, 0.0)
    lines.add_child(_text_label)

    # Act title card, center.
    var card := VBoxContainer.new()
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.set_anchors_preset(Control.PRESET_CENTER)
    card.grow_horizontal = Control.GROW_DIRECTION_BOTH
    card.grow_vertical = Control.GROW_DIRECTION_BOTH
    card.offset_top = -170.0
    canvas.add_child(card)
    _card_title = _label(64, Color("fff1db"))
    _card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _card_title.modulate.a = 0.0
    card.add_child(_card_title)
    _card_subtitle = _label(28, Color("ffd9a0"))
    _card_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _card_subtitle.modulate.a = 0.0
    card.add_child(_card_subtitle)


func _build_world_effects() -> void:
    _wind = AudioStreamPlayer.new()
    _wind.name = "Wind"
    _wind.stream = Sfx.wind_loop()
    _wind.volume_db = -24.0
    add_child(_wind)
    _wind.play()
    _voice = AudioStreamPlayer.new()
    _voice.name = "Voice"
    add_child(_voice)

    # Dust storm: streaks of sand blown across the rover.
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    material.billboard_keep_scale = true
    material.vertex_color_use_as_albedo = true
    var wheel_dust: CPUParticles3D = rover.dust
    material.albedo_texture = ((wheel_dust.mesh as QuadMesh).material as StandardMaterial3D).albedo_texture
    var quad := QuadMesh.new()
    quad.size = Vector2(0.28, 0.28)
    quad.material = material
    var fade := Gradient.new()
    fade.set_color(0, Color(0.85,0.45,0.30,0.0))
    fade.add_point(0.2, Color(0.95,0.62,0.45,0.75))
    fade.set_color(2, Color(0.80,0.42,0.28,0.0))
    _storm_particles = CPUParticles3D.new()
    _storm_particles.name = "DustStorm"
    _storm_particles.mesh = quad
    _storm_particles.amount = 1400
    _storm_particles.lifetime = 1.8
    _storm_particles.local_coords = false
    _storm_particles.emitting = false
    _storm_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    _storm_particles.emission_box_extents = Vector3(3.0, 7.0, 26.0)
    _storm_particles.direction = Vector3(1.0, 0.05, 0.15)
    _storm_particles.spread = 8.0
    _storm_particles.initial_velocity_min = 16.0
    _storm_particles.initial_velocity_max = 30.0
    _storm_particles.gravity = Vector3.ZERO
    _storm_particles.scale_amount_min = 0.5
    _storm_particles.scale_amount_max = 1.4
    _storm_particles.color_ramp = fade
    add_child(_storm_particles)

    # Oppy's little blue LED, mounted on the front of the deck.
    _led = OmniLight3D.new()
    _led.name = "BlueLed"
    _led.light_color = Color(0.35,0.62,1.0)
    _led.light_energy = 0.0
    _led.omni_range = 9.0
    rover.add_child(_led)
    _led.position = Vector3(0.0, 0.5, -2.2)
    var bulb_material := StandardMaterial3D.new()
    bulb_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    bulb_material.albedo_color = Color(0.15,0.35,1.0)
    var bulb := SphereMesh.new()
    bulb.radius = 0.07
    bulb.height = 0.14
    bulb.radial_segments = 8
    bulb.rings = 4
    _led_bulb = MeshInstance3D.new()
    _led_bulb.name = "BlueLedBulb"
    _led_bulb.mesh = bulb
    _led_bulb.material_override = bulb_material
    _led_bulb.visible = false
    rover.add_child(_led_bulb)
    _led_bulb.position = Vector3(0.42, 0.16, -0.86)
