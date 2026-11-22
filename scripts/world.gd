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
    camera.name = "ChaseCamera"
    camera.current = true
    camera.fov = 68
    add_child(camera)
    # Start behind and above the hovercraft so the complete vehicle is visible.
    camera.global_position = Vector3(0, 8.0, 14.0)
    camera.look_at(Vector3(0, 1.5, 0), Vector3.UP)

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
    telemetry.text = "Управление расположено слева"
    telemetry.add_theme_color_override("font_color", Color(0.85, 0.92, 1))
    panel.add_child(telemetry)

    # All flight controls are grouped on the left side of the screen.
    var controls := VBoxContainer.new()
    controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    controls.position = Vector2(20, -330)
    controls.add_theme_constant_override("separation", 8)
    layer.add_child(controls)

    var directions := GridContainer.new()
    directions.columns = 3
    directions.add_theme_constant_override("h_separation", 7)
    directions.add_theme_constant_override("v_separation", 7)
    controls.add_child(directions)
    _add_control_spacer(directions)
    _add_touch_button(directions, "▲", "forward")
    _add_control_spacer(directions)
    _add_touch_button(directions, "◀", "left")
    _add_control_spacer(directions)
    _add_touch_button(directions, "▶", "right")
    _add_control_spacer(directions)
    _add_touch_button(directions, "▼", "back")
    _add_control_spacer(directions)

    var lift_row := HBoxContainer.new()
    lift_row.add_theme_constant_override("separation", 7)
    controls.add_child(lift_row)
    _add_touch_button(lift_row, "LIFT +", "up")
    _add_touch_button(lift_row, "LIFT −", "down")

    var orientation_button := Button.new()
    orientation_button.text = "ПОВЕРНУТЬ ЭКРАН"
    orientation_button.custom_minimum_size = Vector2(210, 54)
    orientation_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    orientation_button.position = Vector2(-230, 18)
    orientation_button.pressed.connect(_toggle_screen_orientation.bind(orientation_button))
    layer.add_child(orientation_button)

func _add_control_spacer(parent: GridContainer) -> void:
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(76, 66)
    parent.add_child(spacer)

func _add_touch_button(parent: Control, caption: String, action: String) -> void:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(76, 66)
    button.focus_mode = Control.FOCUS_NONE
    button.button_down.connect(func(): FlightInput.set_action(action, true))
    button.button_up.connect(func(): FlightInput.set_action(action, false))
    parent.add_child(button)

var is_portrait := false

func _toggle_screen_orientation(button: Button) -> void:
    is_portrait = not is_portrait
    if is_portrait:
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
        button.text = "АЛЬБОМНАЯ ОРИЕНТАЦИЯ"
    else:
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
        button.text = "ПОРТРЕТНАЯ ОРИЕНТАЦИЯ"

func _process(delta: float) -> void:
    if not is_instance_valid(vehicle):
        return
    # Camera follows from behind and above, using the hovercraft's own heading.
    var target := vehicle.global_position + Vector3(0, 0.9, 0)
    # The imported hovercraft faces +Z, so its rear is along -Z.
    # Keep the camera farther back and higher to show the complete silhouette.
    var desired := vehicle.global_position + vehicle.global_transform.basis * Vector3(0, 9.0, -19.0)
    camera.global_position = camera.global_position.lerp(desired, minf(delta * 3.5, 1.0))
    camera.look_at(target, Vector3.UP)
    telemetry.text = "Скорость: %.1f м/с   Высота: %.1f м" % [vehicle.linear_velocity.length(), vehicle.global_position.y]
