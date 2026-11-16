@tool
extends Node3D
## Attach to an empty Node3D. Rebuild affects only our GeneratedMars child.
## Imported mode uses the Blender-authored geometry; procedural mode uses FastNoiseLite.

@export var use_blender_layout: bool = true
@export var terrain_seed: int = 42
@export_range(48.0, 320.0, 1.0) var terrain_size: float = 144.0
@export_range(24, 160, 1) var resolution: int = 72
@export_range(1, 20, 1) var crater_count: int = 6
@export_range(10, 15, 1) var rock_count: int = 13
@export_range(0.0, 12.0, 0.1) var relief: float = 4.5
@export var add_demo_rover: bool = true
@export var rebuild: bool = false:
    set(value):
        if value and is_inside_tree() and not _rebuild_pending:
            _rebuild_pending = true
            call_deferred("generate")

@export_group("Endless planet")
## Streams procedural terrain chunks around the rover instead of one fixed tile.
@export var endless_world: bool = false
@export_range(64.0, 256.0, 1.0) var chunk_size: float = 128.0
@export_range(8, 64, 1) var chunk_resolution: int = 32
## Visible radius in chunks. 7 chunks of 128 m is about 900 m to the horizon.
@export_range(2, 12, 1) var view_chunks: int = 7
@export_range(0.0, 80.0, 0.5) var hill_height: float = 24.0
@export_range(0.0, 200.0, 1.0) var mountain_height: float = 70.0
## Plays the four-act story "Sweet Horizon" on the endless planet (see story.gd).
@export var story_mode: bool = false

const CRATER_CELL: float = 256.0
const CRATER_REACH: float = 110.0   # largest crater radius (60) times its 1.7 falloff, rounded up
const JELLY_SHADER = preload("res://stories/mars/mars_jelly.gdshader")
const OUTLINE_SHADER = preload("res://stories/mars/outline.gdshader")
var generated: Node3D
var noise := FastNoiseLite.new()
var craters: Array[Vector4] = []
var ground: MeshInstance3D
var rocks: Array[MeshInstance3D] = []
var rover: CharacterBody3D
var overview: Camera3D
var _rebuild_pending: bool = false
# Endless planet state
var hill_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()
var chunk_root: Node3D
var _chunks: Dictionary = {}        # Vector2i -> MeshInstance3D
var _pending: Dictionary = {}       # Vector2i -> WorkerThreadPool task id
var _done: Array = []               # [key, generation, arrays] pushed by worker threads
var _mutex := Mutex.new()
var _generation: int = 0
var _last_center := Vector2i(999999, 999999)
var _ground_material: ShaderMaterial
var _rock_material: ShaderMaterial
# Kept so the story can animate the weather.
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var story: Node

func _ready() -> void:
    generate()

func _exit_tree() -> void:
    _stop_endless()

func generate() -> void:
    _rebuild_pending = false
    _stop_endless()
    var old := get_node_or_null("GeneratedMars")
    if old != null:
        remove_child(old)
        old.queue_free()
    generated = Node3D.new()
    generated.name = "GeneratedMars"
    add_child(generated)
    rocks.clear()
    ground = null
    rover = null
    story = null
    noise.seed = terrain_seed
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = 0.025
    noise.fractal_octaves = 3
    _prepare_craters()
    var imported := false
    if endless_world:
        _start_endless()
    elif use_blender_layout and ResourceLoader.exists("res://stories/mars/assets/Mars.blend.glb"):
        var packed := load("res://stories/mars/assets/Mars.blend.glb") as PackedScene
        if packed != null:
            var layout := packed.instantiate()
            layout.name = "BlenderLayout"
            generated.add_child(layout)
            _configure_import(layout)
            imported = ground != null
    if not imported and not endless_world:
        _build_terrain()
        _build_rocks()
    _build_environment()
    _build_overview()
    if not Engine.is_editor_hint() and add_demo_rover:
        rover = preload("res://stories/mars/rover.gd").new()
        rover.name = "DemoRover"
        generated.add_child(rover)
        rover.position = Vector3(0.0, 18.0, 43.0 if imported else terrain_size*0.3)
        rover.set("spawn_point", rover.position)
        rover.set("boundary", 68.0 if imported else terrain_size*0.47)
        if endless_world:
            # No edges: spawn on the surface and start in the third-person camera.
            rover.position = Vector3(0.0, planet_height(0.0, 0.0)+3.0, 0.0)
            rover.set("spawn_point", rover.position)
            rover.set("boundary", INF)
            rover.set("kill_depth", -5000.0)
            (rover.get_node("Camera3D") as Camera3D).make_current()
            if story_mode:
                story = preload("res://stories/mars/story.gd").new()
                story.name = "Story"
                story.call("setup", self, rover)
                generated.add_child(story)

func _material(is_rock: bool) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = JELLY_SHADER
    material.set_shader_parameter("is_rock", is_rock)
    var outline := ShaderMaterial.new()
    outline.shader = OUTLINE_SHADER
    outline.set_shader_parameter("radial_normals", is_rock)
    outline.set_shader_parameter("outline_width", 0.065 if is_rock else 0.012)
    material.next_pass = outline
    return material

func _configure_import(node: Node) -> void:
    if node is MeshInstance3D:
        var instance := node as MeshInstance3D
        var is_rock := String(instance.name).begins_with("Rock_")
        instance.material_override = _material(is_rock)
        if is_rock:
            rocks.append(instance)
            _rock_collision(instance)
        else:
            ground = instance
            ground.create_trimesh_collision()
    # Snapshot: collision children added above do not recursively create geometry.
    for child in node.get_children():
        _configure_import(child)

func _prepare_craters() -> void:
    craters.clear()
    var rng := RandomNumberGenerator.new()
    rng.seed = terrain_seed
    for index in crater_count:
        var radius := rng.randf_range(terrain_size*0.045, terrain_size*0.095)
        var margin := terrain_size*0.5-radius*1.8
        craters.append(Vector4(rng.randf_range(-margin,margin),rng.randf_range(-margin,margin),radius,rng.randf_range(0.20,0.29)))

func height_at(x: float, z: float) -> float:
    var height := noise.get_noise_2d(x,z)*relief
    height += sin(x*0.105+z*0.045)*1.15+sin(z*0.19-x*0.025)*0.65
    for crater in craters:
        var q := Vector2(x-crater.x,z-crater.y).length()/crater.z
        if q < 1.7:
            height -= crater.z*crater.w*pow(maxf(0.0,1.0-q*q),2.0)
            height += crater.z*0.12*exp(-pow((q-1.0)/0.18,2.0))
    return height

func surface_height(x: float, z: float) -> float:
    # Exact interpolation of the procedural collision triangles, not smooth noise.
    var gx := clampf((x/terrain_size+0.5)*resolution,0.0,resolution-0.0001)
    var gz := clampf((z/terrain_size+0.5)*resolution,0.0,resolution-0.0001)
    var ix := floorf(gx)
    var iz := floorf(gz)
    var u := gx-ix
    var v := gz-iz
    var step := terrain_size/resolution
    var px := (ix/resolution-0.5)*terrain_size
    var pz := (iz/resolution-0.5)*terrain_size
    var a := height_at(px,pz)
    var b := height_at(px+step,pz)
    var c := height_at(px,pz+step)
    var d := height_at(px+step,pz+step)
    if u+v <= 1.0:
        return a+(b-a)*u+(c-a)*v
    return d+(c-d)*(1.0-u)+(b-d)*(1.0-v)

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    # Godot uses clockwise winding. A single normal is shared only inside this face.
    var normal := (c-a).cross(b-a).normalized()
    for point in [a,b,c]:
        st.set_normal(normal)
        st.set_uv(Vector2(point.x,point.z)/terrain_size+Vector2(0.5,0.5))
        st.add_vertex(point)

func _build_terrain() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var step := terrain_size/resolution
    for z in resolution:
        for x in resolution:
            var px := (float(x)/resolution-0.5)*terrain_size
            var pz := (float(z)/resolution-0.5)*terrain_size
            var a := Vector3(px,height_at(px,pz),pz)
            var b := Vector3(px+step,height_at(px+step,pz),pz)
            var c := Vector3(px,height_at(px,pz+step),pz+step)
            var d := Vector3(px+step,height_at(px+step,pz+step),pz+step)
            _triangle(st,a,b,c)
            _triangle(st,b,d,c)
    ground = MeshInstance3D.new()
    ground.name = "Terrain"
    ground.mesh = st.commit()
    ground.material_override = _material(false)
    generated.add_child(ground)
    ground.create_trimesh_collision()

func _rock_mesh(index: int, radius: float) -> ArrayMesh:
    var sphere := SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    sphere.radial_segments = 10
    sphere.rings = 5
    var source := SurfaceTool.new()
    source.create_from(sphere,0)
    source.deindex()
    var arrays := source.commit_to_arrays()
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_smooth_group(-1)
    for point in vertices:
        # Continuous deformation keeps equal positions joined after deindexing.
        var distortion := 1.0+noise.get_noise_3d(point.x*45.0+index*7.0,point.y*45.0,point.z*45.0)*0.22
        st.add_vertex(point*distortion*Vector3(radius,radius*0.8,radius))
    st.generate_normals()
    return st.commit()

func _build_rocks() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = terrain_seed+731
    # Distributed sectors guarantee the requested count and a free central route.
    for index in rock_count:
        var angle := TAU*(float(index)+rng.randf_range(-0.22,0.22))/rock_count
        var distance := terrain_size*rng.randf_range(0.19,0.38)
        var x := cos(angle)*distance
        var z := sin(angle)*distance
        var radius := rng.randf_range(2.0,4.3)*terrain_size/144.0
        var instance := MeshInstance3D.new()
        instance.name = "Rock_%02d"%index
        instance.mesh = _rock_mesh(index,radius)
        instance.material_override = _material(true)
        generated.add_child(instance)
        instance.position = Vector3(x,surface_height(x,z)+radius*0.35,z)
        rocks.append(instance)
        _rock_collision(instance)

func _rock_collision(instance: MeshInstance3D) -> void:
    var body := StaticBody3D.new()
    body.name = "RockBody"
    var collision := CollisionShape3D.new()
    collision.shape = instance.mesh.create_convex_shape()
    instance.add_child(body)
    body.add_child(collision)

func _build_environment() -> void:
    var world := WorldEnvironment.new()
    world.name = "MarsEnvironment"
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var palette := ProceduralSkyMaterial.new()
    palette.sky_top_color = Color("b94064")
    palette.sky_horizon_color = Color("ffba91")
    palette.ground_horizon_color = Color("f58d7d")
    palette.ground_bottom_color = Color("6c183c")
    palette.sky_curve = 0.3
    sky.sky_material = palette
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("ce8fba")
    env.ambient_light_energy = 0.32
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = true
    env.glow_intensity = 0.45
    env.glow_bloom = 0.06
    env.glow_hdr_threshold = 1.4
    if endless_world:
        # Aerial haze in the sky's own colors: distant ridges fade into the horizon.
        env.fog_enabled = true
        env.fog_light_color = Color("ffba91")
        env.fog_density = 0.0024
        env.fog_aerial_perspective = 1.0
        env.fog_sky_affect = 0.0
    world.environment = env
    environment = env
    sky_material = palette
    generated.add_child(world)
    var sun := DirectionalLight3D.new()
    sun.name = "WarmSun"
    sun.rotation_degrees = Vector3(-38.0,-32.0,0.0)
    sun.light_color = Color("ffdab3")
    sun.light_energy = 1.3
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 240.0
    self.sun = sun
    generated.add_child(sun)

func _build_overview() -> void:
    overview = Camera3D.new()
    overview.name = "OverviewCamera"
    overview.far = 600.0
    overview.projection = Camera3D.PROJECTION_ORTHOGONAL
    overview.size = 152.0
    generated.add_child(overview)
    overview.position = Vector3(95.0,95.0,115.0)
    overview.look_at(Vector3.ZERO)
    overview.current = true
    if endless_world:
        overview.projection = Camera3D.PROJECTION_PERSPECTIVE
        overview.fov = 55.0
        overview.far = 4000.0
        _place_overview()

func _place_overview() -> void:
    # High aerial view centered on the rover (or the origin before it exists).
    var focus := rover.global_position if is_instance_valid(rover) and rover.is_inside_tree() else Vector3(0.0, planet_height(0.0,0.0), 0.0)
    overview.position = focus+Vector3(150.0,190.0,210.0)
    overview.look_at(focus)

func _unhandled_key_input(event: InputEvent) -> void:
    if Engine.is_editor_hint():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_TAB and is_instance_valid(rover):
            var chase := rover.get_node("Camera3D") as Camera3D
            if overview.current: chase.make_current()
            else:
                if endless_world: _place_overview()
                overview.make_current()
        elif event.keycode == KEY_R:
            use_blender_layout = false
            terrain_seed += 1
            generate()

# ----------------------------------------------------------------------------
#  Endless planet: chunks streamed around the rover, built on worker threads
# ----------------------------------------------------------------------------

func _start_endless() -> void:
    hill_noise.seed = terrain_seed+101
    hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    hill_noise.frequency = 0.0022
    hill_noise.fractal_octaves = 4
    mountain_noise.seed = terrain_seed+202
    mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    mountain_noise.frequency = 0.0009
    mountain_noise.fractal_octaves = 2
    # Same shader and colors as the small map; only the altitude range that the
    # palette is spread over grows with the taller relief.
    _ground_material = _material(false)
    _ground_material.set_shader_parameter("height_min", -hill_height-8.0)
    _ground_material.set_shader_parameter("height_max", hill_height+mountain_height*0.45)
    _rock_material = _material(true)
    chunk_root = Node3D.new()
    chunk_root.name = "Chunks"
    generated.add_child(chunk_root)
    _last_center = Vector2i(999999, 999999)
    # The ground under the spawn point must exist, with collision, on frame one.
    var near := 2 if Engine.is_editor_hint() else 1
    for cz in range(-near, near+1):
        for cx in range(-near, near+1):
            _finalize_chunk(Vector2i(cx,cz), _chunk_arrays(cx,cz))
    ground = _chunks[Vector2i(0,0)]
    _update_collision(Vector2i(0,0))

func _stop_endless() -> void:
    for task_id in _pending.values():
        WorkerThreadPool.wait_for_task_completion(task_id)
    _pending.clear()
    _mutex.lock()
    _done.clear()
    _mutex.unlock()
    _chunks.clear()
    chunk_root = null
    _generation += 1

func _cell_craters(cx: int, cz: int) -> Array[Vector4]:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(Vector3i(cx, cz, terrain_seed))
    var out: Array[Vector4] = []
    for index in rng.randi_range(0, maxi(1, crater_count/3)):
        var radius := rng.randf_range(7.0, 22.0)
        if rng.randf() < 0.25:
            radius = rng.randf_range(30.0, 60.0)
        var center := Vector2((cx+rng.randf())*CRATER_CELL, (cz+rng.randf())*CRATER_CELL)
        var depth := rng.randf_range(0.20, 0.29)
        if center.length() > radius*1.7+30.0:   # keep the landing site clear
            out.append(Vector4(center.x, center.y, radius, depth))
    return out

func _craters_near(from: Vector2, to: Vector2) -> Array[Vector4]:
    var out: Array[Vector4] = []
    for cz in range(floori((from.y-CRATER_REACH)/CRATER_CELL), floori((to.y+CRATER_REACH)/CRATER_CELL)+1):
        for cx in range(floori((from.x-CRATER_REACH)/CRATER_CELL), floori((to.x+CRATER_REACH)/CRATER_CELL)+1):
            out.append_array(_cell_craters(cx, cz))
    return out

func _planet_height(x: float, z: float, near_craters: Array[Vector4]) -> float:
    # The small-map dunes, plus rolling hills, plus rare mountain ranges.
    var height := noise.get_noise_2d(x,z)*relief
    height += sin(x*0.105+z*0.045)*1.15+sin(z*0.19-x*0.025)*0.65
    height += hill_noise.get_noise_2d(x,z)*hill_height
    var range_mask := smoothstep(0.12, 0.65, mountain_noise.get_noise_2d(x,z))
    height += range_mask*range_mask*mountain_height*(0.75+0.25*hill_noise.get_noise_2d(x*2.3+91.0,z*2.3-37.0))
    for crater in near_craters:
        var q := Vector2(x-crater.x,z-crater.y).length()/crater.z
        if q < 1.7:
            height -= crater.z*crater.w*pow(maxf(0.0,1.0-q*q),2.0)
            height += crater.z*0.12*exp(-pow((q-1.0)/0.18,2.0))
    return height

## Smooth terrain height of the endless planet at a world position.
func planet_height(x: float, z: float) -> float:
    return _planet_height(x, z, _craters_near(Vector2(x,z), Vector2(x,z)))

func _chunk_arrays(cx: int, cz: int) -> Dictionary:
    # Pure data, safe to run on a worker thread. Grid positions are derived from
    # global cell indices so neighbouring chunks share identical edge vertices.
    var n := chunk_resolution
    var step := chunk_size/n
    var near_craters := _craters_near(Vector2(cx,cz)*chunk_size, Vector2(cx+1,cz+1)*chunk_size)
    var heights := PackedFloat32Array()
    heights.resize((n+1)*(n+1))
    for j in n+1:
        for i in n+1:
            heights[j*(n+1)+i] = _planet_height((cx*n+i)*step, (cz*n+j)*step, near_craters)
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    vertices.resize(n*n*6)
    normals.resize(n*n*6)
    var k := 0
    for j in n:
        for i in n:
            var x0 := (cx*n+i)*step
            var z0 := (cz*n+j)*step
            var a := Vector3(x0, heights[j*(n+1)+i], z0)
            var b := Vector3(x0+step, heights[j*(n+1)+i+1], z0)
            var c := Vector3(x0, heights[(j+1)*(n+1)+i], z0+step)
            var d := Vector3(x0+step, heights[(j+1)*(n+1)+i+1], z0+step)
            var n1 := (c-a).cross(b-a).normalized()
            var n2 := (c-b).cross(d-b).normalized()
            vertices[k] = a; vertices[k+1] = b; vertices[k+2] = c
            vertices[k+3] = b; vertices[k+4] = d; vertices[k+5] = c
            normals[k] = n1; normals[k+1] = n1; normals[k+2] = n1
            normals[k+3] = n2; normals[k+4] = n2; normals[k+5] = n2
            k += 6
    return {"vertices": vertices, "normals": normals}

func _chunk_task(key: Vector2i, generation: int) -> void:
    var data := _chunk_arrays(key.x, key.y)
    _mutex.lock()
    _done.append([key, generation, data])
    _mutex.unlock()

func _finalize_chunk(key: Vector2i, data: Dictionary) -> void:
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = data.vertices
    arrays[Mesh.ARRAY_NORMAL] = data.normals
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var chunk := MeshInstance3D.new()
    chunk.name = "Chunk_%d_%d" % [key.x, key.y]
    chunk.mesh = mesh
    chunk.material_override = _ground_material
    chunk.set_meta("faces", data.vertices)
    chunk_root.add_child(chunk)
    _chunks[key] = chunk
    _chunk_rocks(key, chunk)

func _chunk_rocks(key: Vector2i, chunk: MeshInstance3D) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(Vector3i(key.x, key.y, terrain_seed+731))
    var near_craters := _craters_near(Vector2(key)*chunk_size, Vector2(key+Vector2i.ONE)*chunk_size)
    for index in rng.randi_range(0, 3):
        var x := (key.x+rng.randf())*chunk_size
        var z := (key.y+rng.randf())*chunk_size
        var radius := rng.randf_range(1.6, 5.0)
        if rng.randf() < 0.12:
            radius = rng.randf_range(8.0, 16.0)   # the odd house-sized boulder
        var variant := rng.randi_range(0, 999)
        if Vector2(x,z).length() < radius+16.0:
            continue
        var instance := MeshInstance3D.new()
        instance.name = "Rock_%02d" % index
        instance.mesh = _rock_mesh(variant, radius)
        instance.material_override = _rock_material
        chunk.add_child(instance)
        instance.position = Vector3(x, _planet_height(x,z,near_craters)+radius*0.3, z)
        rocks.append(instance)

func _update_collision(center: Vector2i) -> void:
    # Only the 3x3 chunks around the rover need physics.
    for cz in range(center.y-1, center.y+2):
        for cx in range(center.x-1, center.x+2):
            var chunk: MeshInstance3D = _chunks.get(Vector2i(cx,cz))
            if chunk == null or chunk.has_node("Body"):
                continue
            var body := StaticBody3D.new()
            body.name = "Body"
            var collision := CollisionShape3D.new()
            var shape := ConcavePolygonShape3D.new()
            shape.set_faces(chunk.get_meta("faces"))
            collision.shape = shape
            body.add_child(collision)
            chunk.add_child(body)
            for child in chunk.get_children():
                if child is MeshInstance3D:
                    _rock_collision(child)

func _process(_delta: float) -> void:
    if not endless_world or chunk_root == null or Engine.is_editor_hint():
        return
    var focus := rover.global_position if is_instance_valid(rover) else Vector3.ZERO
    var center := Vector2i(floori(focus.x/chunk_size), floori(focus.z/chunk_size))
    if center != _last_center:
        _last_center = center
        _stream_chunks(center)
    # Turn finished worker results into nodes, a few per frame to avoid hitches.
    for budget in 3:
        _mutex.lock()
        var item = _done.pop_front() if not _done.is_empty() else null
        _mutex.unlock()
        if item == null:
            break
        var key: Vector2i = item[0]
        if _pending.has(key):
            WorkerThreadPool.wait_for_task_completion(_pending[key])
            _pending.erase(key)
        if item[1] == _generation and not _chunks.has(key) and (key-_last_center).length() <= view_chunks+1.5:
            _finalize_chunk(key, item[2])
            if absi(key.x-_last_center.x) <= 1 and absi(key.y-_last_center.y) <= 1:
                _update_collision(_last_center)

func _stream_chunks(center: Vector2i) -> void:
    for key in _chunks.keys():
        if (key-center).length() > view_chunks+1.5:
            var chunk: MeshInstance3D = _chunks[key]
            for child in chunk.get_children():
                if child is MeshInstance3D:
                    rocks.erase(child)
            chunk.queue_free()
            _chunks.erase(key)
    var wanted: Array[Vector2i] = []
    for cz in range(center.y-view_chunks, center.y+view_chunks+1):
        for cx in range(center.x-view_chunks, center.x+view_chunks+1):
            var key := Vector2i(cx,cz)
            if (key-center).length() <= view_chunks and not _chunks.has(key) and not _pending.has(key):
                wanted.append(key)
    wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a-center).length_squared() < (b-center).length_squared())
    for key in wanted:
        _pending[key] = WorkerThreadPool.add_task(_chunk_task.bind(key, _generation))
    _update_collision(center)
