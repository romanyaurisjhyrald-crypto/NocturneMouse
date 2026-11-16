extends CanvasLayer
## Runs the native story in its own 3D world while preserving the care scene.
var host: Node
var world: SubViewport
var mars: Node3D
var frame: SubViewportContainer
var previous_process_mode: int
var previous_visible: bool
var closing := false

func _ready() -> void:
    layer = 100
    previous_process_mode = host.process_mode
    previous_visible = host.visible
    host.process_mode = Node.PROCESS_MODE_DISABLED
    host.hide()
    var backdrop := ColorRect.new()
    backdrop.color = Color("170c19")
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(backdrop)
    frame = SubViewportContainer.new()
    frame.size = Vector2(1280, 800)
    add_child(frame)
    world = SubViewport.new()
    world.size = Vector2i(1280, 800)
    world.own_world_3d = true
    world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    frame.add_child(world)
    mars = preload("res://stories/mars/main.tscn").instantiate()
    world.add_child(mars)
    var back := Button.new()
    back.text = "mars_back"
    back.position = Vector2(18, 18)
    back.custom_minimum_size = Vector2(200, 40)
    back.pressed.connect(close)
    add_child(back)
    get_viewport().size_changed.connect(_resize)
    _resize()

func _resize() -> void:
    # Preserve readable cinematic HUD proportions, including portrait windows.
    var available := get_viewport().get_visible_rect().size
    var factor := minf(available.x / 1280.0, available.y / 800.0)
    frame.scale = Vector2.ONE * factor
    frame.position = (available - Vector2(1280, 800) * factor) * 0.5

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        close()

func close() -> void:
    if closing:
        return
    closing = true
    # Free the streamed world and its worker tasks before restoring the host.
    call_deferred("_finish_close")

func _finish_close() -> void:
    world.remove_child(mars)
    mars.free()
    if is_instance_valid(host):
        host.process_mode = previous_process_mode
        host.visible = previous_visible
    queue_free()
