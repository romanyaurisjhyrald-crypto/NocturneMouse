extends SceneTree
func _initialize():
    call_deferred("run")

func run():
    var scene = load("res://Main.tscn").instantiate()
    scene.enable_save = false
    scene.enable_sound = false
    root.add_child(scene)
    current_scene = scene
    await create_timer(1.0).timeout
    scene.localization.set_language("en")
    scene.trust = 80
    scene._open_stories()
    var library = scene.story_reader
    assert(library.catalog.get_child_count() == 7)
    var trust_before = scene.trust
    library.open_mars()
    await create_timer(5.0).timeout
    var mission = root.get_node("MarsMission")
    assert(scene.process_mode == Node.PROCESS_MODE_DISABLED and not scene.visible)
    assert(mission.world.own_world_3d and mission.mars.story != null)
    assert(mission.mars.endless_world and mission.mars.story_mode)
    assert(mission.mars.rover.is_on_floor())
    var start: Vector3 = mission.mars.rover.global_position
    var drive := InputEventKey.new()
    drive.physical_keycode = KEY_W
    drive.keycode = KEY_W
    drive.pressed = true
    Input.parse_input_event(drive)
    await create_timer(2.0).timeout
    drive.pressed = false
    Input.parse_input_event(drive)
    assert(mission.mars.rover.global_position.distance_to(start) > 1.0)
    var switch_camera := InputEventKey.new()
    switch_camera.keycode = KEY_TAB
    switch_camera.pressed = true
    Input.parse_input_event(switch_camera)
    await create_timer(0.2).timeout
    assert(mission.mars.overview.current)
    Input.parse_input_event(switch_camera)
    await create_timer(0.2).timeout
    assert(mission.mars.rover.camera.current)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://previews/MarsStoryIntegrated.png")
    # Advance timed dialogue quickly but satisfy every actual waypoint gate.
    mission.mars.story.line_time_scale = 0.01
    for index in range(800):
        var story = mission.mars.story
        if story.goal_active:
            mission.mars.rover.global_position = story.goals[story.goal_index] + Vector3(0, 2, 0)
        if story.is_finished:
            break
        await create_timer(0.05).timeout
    assert(mission.mars.story.is_finished)
    assert(not mission.mars.rover.control_enabled)
    mission.close()
    await create_timer(1.0).timeout
    assert(not root.has_node("MarsMission"))
    assert(scene.visible and scene.process_mode != Node.PROCESS_MODE_DISABLED)
    assert(scene.trust == trust_before)
    scene.localization.set_language("es")
    library.open_mars()
    await create_timer(2.0).timeout
    mission = root.get_node("MarsMission")
    assert(mission.mars.story.steps[0].title == "Dulce Horizonte")
    root.size = Vector2i(540,960)
    await create_timer(0.5).timeout
    assert(mission.frame.scale.x < 1.0)
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    Input.parse_input_event(escape)
    await create_timer(1.0).timeout
    assert(not root.has_node("MarsMission"))
    print("PASS MARS: native launch, isolated world, driving/collision, all four acts and waypoint gates, close/reopen, care state, Spanish, resize, Escape.")
    scene.queue_free()
    await create_timer(0.5).timeout
    quit()
