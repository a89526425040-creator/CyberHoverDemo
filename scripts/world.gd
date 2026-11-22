extends Node3D

var vehicle: RigidBody3D
var camera: Camera3D
var telemetry: Label

func _ready() -> void:
    _make_environment()
    _make_pad()
    _make_vehicle()
    _make_camera()
    _make_hud()

func _make_environment() -> void:
    var env_node := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.015, 0.035, 0.09)
    sky_mat.sky_horizon_color = Color(0.08, 0.2, 0.3)
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.35, 0.48, 0.65)
    env.ambient_light_energy = 0.7
    env.glow_enabled = true
    env_node.environment = env
    add_child(env_node)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -28, 0)
    sun.shadow_enabled = true
    add_child(sun)

func _make_pad() -> void:
    var floor := StaticBody3D.new()
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(100, 1, 100)
    mesh.mesh = box
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.035, 0.055, 0.08)
    mat.metallic = 0.65
    mat.roughness = 0.38
    mesh.material_override = mat
    mesh.position.y = -0.5
    floor.add_child(mesh)
    var shape := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = box.size
    shape.shape = box_shape
    shape.position.y = -0.5
    floor.add_child(shape)
    add_child(floor)
    for i in range(4):
        var strip := MeshInstance3D.new()
        var strip_mesh := BoxMesh.new()
        strip_mesh.size = Vector3(0.15, 0.04, 84) if i < 2 else Vector3(84, 0.04, 0.15)
        strip.mesh = strip_mesh
        var glow := StandardMaterial3D.new()
        glow.albedo_color = Color(0.02, 0.65, 0.9)
        glow.emission_enabled = true
        glow.emission = Color(0.02, 0.45, 0.9)
        glow.emission_energy_multiplier = 2.0
        strip.material_override = glow
        strip.position = [Vector3(-42, 0.03, 0), Vector3(42, 0.03, 0), Vector3(0, 0.03, -42), Vector3(0, 0.03, 42)][i]
        add_child(strip)

func _make_vehicle() -> void:
    vehicle = RigidBody3D.new()
    vehicle.name = "HoverVehicle"
    vehicle.position = Vector3(0, 1.5, 0)
    vehicle.mass = 1800.0
    vehicle.linear_damp = 0.08
    vehicle.angular_damp = 1.8
    vehicle.can_sleep = false
    vehicle.set_script(load("res://scripts/hover_controller.gd"))
    add_child(vehicle)

    var pivot := Node3D.new()
    pivot.name = "ModelPivot"
    vehicle.add_child(pivot)
    var model_path := "res://assets/hovercar.glb"
    if ResourceLoader.exists(model_path):
        var packed := load(model_path) as PackedScene
        if packed:
            pivot.add_child(packed.instantiate())
    else:
        var body := MeshInstance3D.new()
        var body_mesh := BoxMesh.new()
        body_mesh.size = Vector3(2.4, 0.7, 4.5)
        body.mesh = body_mesh
        var body_mat := StandardMaterial3D.new()
        body_mat.albedo_color = Color(0.08, 0.16, 0.22)
        body_mat.metallic = 0.8
        body_mat.emission_enabled = true
        body_mat.emission = Color(0.0, 0.25, 0.45)
        body.material_override = body_mat
        pivot.add_child(body)

    var collision := CollisionShape3D.new()
    var collision_shape := BoxShape3D.new()
    collision_shape.size = Vector3(2.2, 0.65, 4.2)
    collision.shape = collision_shape
    collision.position.y = 0.1
    vehicle.add_child(collision)

func _make_camera() -> void:
    camera = Camera3D.new()
    camera.current = true
    camera.fov = 72
    add_child(camera)
    camera.global_position = Vector3(0, 4.5, 9)

func _make_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := VBoxContainer.new()
    panel.position = Vector2(22, 18)
    layer.add_child(panel)
    var heading := Label.new()
    heading.text = "CYBER HOVER // FLIGHT TEST"
    heading.add_theme_font_size_override("font_size", 22)
    heading.add_theme_color_override("font_color", Color(0.15, 0.85, 1))
    panel.add_child(heading)
    telemetry = Label.new()
    telemetry.text = "W/S — вперёд/назад | A/D — в стороны | SPACE/CTRL — вверх/вниз"
    telemetry.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
    panel.add_child(telemetry)
    var row := HBoxContainer.new()
    row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    row.position = Vector2(-560, -150)
    layer.add_child(row)
    _add_touch_button(row, "◀", "left")
    _add_touch_button(row, "▶", "right")
    _add_touch_button(row, "▲", "forward")
    _add_touch_button(row, "▼", "back")
    _add_touch_button(row, "LIFT +", "up")
    _add_touch_button(row, "LIFT −", "down")

func _add_touch_button(parent: Control, caption: String, action: String) -> void:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(82, 72)
    button.button_down.connect(func(): FlightInput.set_action(action, true))
    button.button_up.connect(func(): FlightInput.set_action(action, false))
    parent.add_child(button)

func _process(delta: float) -> void:
    if not is_instance_valid(vehicle):
        return
    var target := vehicle.global_position + Vector3(0, 0.7, 0)
    var desired := vehicle.global_position + vehicle.global_transform.basis * Vector3(0, 3.6, 9.0)
    camera.global_position = camera.global_position.lerp(desired, minf(delta * 3.0, 1.0))
    camera.look_at(target, Vector3.UP)
    telemetry.text = "Скорость: %.1f м/с   Высота: %.1f м" % [vehicle.linear_velocity.length(), vehicle.global_position.y]
