extends Node3D

var vehicle: RigidBody3D
var camera: Camera3D
var telemetry: Label
var diagnostic_label: Label
var diagnostic_visible := false
var diagnostic_frames := 0
var diagnostic_jerk_events := 0
var diagnostic_angular_events := 0
var diagnostic_frame_events := 0
var diagnostic_max_frame_ms := 0.0
var diagnostic_max_jerk := 0.0
var diagnostic_max_angular_accel := 0.0
var diagnostic_prev_velocity := Vector3.ZERO
var diagnostic_prev_acceleration := Vector3.ZERO
var diagnostic_prev_angular_velocity := Vector3.ZERO
var diagnostic_prev_camera_position := Vector3.ZERO
var diagnostic_velocity_ready := false
var diagnostic_camera_ready := false
var diagnostic_camera_speed := 0.0
var diagnostic_max_camera_speed := 0.0
var engine_effects: Array[CPUParticles3D] = []


class TouchJoystick extends Control:
    var finger_index := -1
    var mouse_held := false
    var axis_value := Vector2.ZERO
    var outer_radius := 82.0

    func _ready() -> void:
        custom_minimum_size = Vector2(190, 190)
        mouse_filter = Control.MOUSE_FILTER_STOP
        queue_redraw()

    func _draw() -> void:
        var center := size * 0.5
        draw_circle(center, outer_radius, Color(0.015, 0.04, 0.08, 0.72))
        draw_arc(center, outer_radius, 0.0, TAU, 64, Color(0.08, 0.78, 1.0, 0.95), 4.0, true)
        draw_circle(center, 39.0, Color(0.12, 0.25, 0.34, 0.9))
        draw_arc(center, 39.0, 0.0, TAU, 48, Color(0.25, 0.85, 1.0, 0.9), 2.0, true)
        draw_circle(center + axis_value * 61.0, 27.0, Color(0.05, 0.65, 0.9, 0.95))
        draw_arc(center + axis_value * 61.0, 27.0, 0.0, TAU, 40, Color(0.65, 0.95, 1.0), 2.0, true)

    func _gui_input(event: InputEvent) -> void:
        if event is InputEventScreenTouch:
            if event.pressed and finger_index == -1:
                finger_index = event.index
                _update_axis(event.position)
                accept_event()
            elif not event.pressed and event.index == finger_index:
                finger_index = -1
                _clear_axis()
                accept_event()
        elif event is InputEventScreenDrag and event.index == finger_index:
            _update_axis(event.position)
            accept_event()
        elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
            mouse_held = event.pressed
            if mouse_held:
                _update_axis(event.position)
            else:
                _clear_axis()
            accept_event()
        elif event is InputEventMouseMotion and mouse_held:
            _update_axis(event.position)
            accept_event()

    func _update_axis(point: Vector2) -> void:
        var offset := point - size * 0.5
        axis_value = (offset / outer_radius).limit_length(1.0)
        FlightInput.set_axis("forward", maxf(0.0, -axis_value.y))
        FlightInput.set_axis("back", maxf(0.0, axis_value.y))
        FlightInput.set_axis("left", maxf(0.0, -axis_value.x))
        FlightInput.set_axis("right", maxf(0.0, axis_value.x))
        queue_redraw()

    func _clear_axis() -> void:
        axis_value = Vector2.ZERO
        FlightInput.set_action("forward", false)
        FlightInput.set_action("back", false)
        FlightInput.set_action("left", false)
        FlightInput.set_action("right", false)
        FlightInput.set_axis("forward", 0.0)
        FlightInput.set_axis("back", 0.0)
        FlightInput.set_axis("left", 0.0)
        FlightInput.set_axis("right", 0.0)
        queue_redraw()


class HoldTouchButton extends Control:
    var action_name := ""
    var caption := ""
    var finger_index := -1
    var mouse_held := false
    var is_pressed := false

    func setup(action: String, text_value: String) -> void:
        action_name = action
        caption = text_value
        custom_minimum_size = Vector2(94, 82)
        mouse_filter = Control.MOUSE_FILTER_STOP

    func _draw() -> void:
        var center := size * 0.5
        var fill := Color(0.0, 0.52, 0.72, 0.95) if is_pressed else Color(0.015, 0.055, 0.09, 0.82)
        draw_circle(center, 37.0, fill)
        draw_arc(center, 37.0, 0.0, TAU, 48, Color(0.12, 0.82, 1.0), 3.0, true)
        draw_string(ThemeDB.fallback_font, Vector2(center.x, center.y + 7.0), caption, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 20, Color(0.9, 0.98, 1.0))

    func _gui_input(event: InputEvent) -> void:
        if event is InputEventScreenTouch:
            if event.pressed and finger_index == -1:
                finger_index = event.index
                _set_pressed(true)
                accept_event()
            elif not event.pressed and event.index == finger_index:
                finger_index = -1
                _set_pressed(false)
                accept_event()
        elif event is InputEventScreenDrag and event.index == finger_index:
            accept_event()
        elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
            mouse_held = event.pressed
            _set_pressed(mouse_held)
            accept_event()

    func _set_pressed(value: bool) -> void:
        is_pressed = value
        FlightInput.set_action(action_name, value)
        queue_redraw()

    func _exit_tree() -> void:
        FlightInput.set_action(action_name, false)

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
    box.size = Vector3(500, 1, 500)
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
        strip_mesh.size = Vector3(0.15, 0.04, 480) if i < 2 else Vector3(480, 0.04, 0.15)
        strip.mesh = strip_mesh
        var glow := StandardMaterial3D.new()
        glow.albedo_color = Color(0.02, 0.65, 0.9)
        glow.emission_enabled = true
        glow.emission = Color(0.02, 0.45, 0.9)
        glow.emission_energy_multiplier = 2.0
        strip.material_override = glow
        strip.position = [Vector3(-240, 0.03, 0), Vector3(240, 0.03, 0), Vector3(0, 0.03, -240), Vector3(0, 0.03, 240)][i]
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

    _create_engine_effects(pivot)
    var collision := CollisionShape3D.new()
    var collision_shape := BoxShape3D.new()
    collision_shape.size = Vector3(2.2, 0.65, 4.2)
    collision.shape = collision_shape
    collision.position.y = 0.1
    vehicle.add_child(collision)

func _create_engine_effects(pivot: Node3D) -> void:
    # The source model has exactly TWO rear exhaust nozzles.
    # Cylinder and Cylinder.028 are the small, matching nozzle-end meshes
    # on the left and right. Cylinder.001 / Cylinder.026 are body panels,
    # not exhausts, and must never receive particles.
    var nozzle_names := ["Cylinder", "Cylinder.028"]
    for nozzle_name in nozzle_names:
        var nozzle := pivot.find_child(nozzle_name, true, false) as Node3D
        if nozzle == null:
            push_error("Rear engine nozzle not found in imported hovercraft: " + nozzle_name)
            continue
        _add_engine_plume(nozzle)

func _add_engine_plume(nozzle: Node3D) -> void:
    # Parent the emitter directly to the nozzle so its origin follows the
    # actual imported mesh transform. This avoids guessed offsets on the hull.
    var particles := CPUParticles3D.new()
    particles.name = "BlueExhaust_" + nozzle.name
    particles.position = Vector3.ZERO
    particles.rotation = Vector3.ZERO
    particles.amount = 56
    particles.lifetime = 0.48
    particles.local_coords = false
    particles.emitting = false
    particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -4.0), Vector3(4.0, 4.0, 8.0))

    # The hovercraft's rear is local -Z; exhaust streams backward from each nozzle.
    particles.direction = Vector3(0.0, 0.0, -1.0)
    particles.spread = 9.0
    particles.initial_velocity_min = 4.5
    particles.initial_velocity_max = 7.5
    particles.gravity = Vector3.ZERO
    particles.damping_min = 0.0
    particles.damping_max = 0.0
    particles.scale_amount_min = 0.13
    particles.scale_amount_max = 0.27
    particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
    particles.emission_sphere_radius = 0.07

    var gradient := Gradient.new()
    gradient.set_color(0, Color(0.72, 0.96, 1.0, 0.98))
    gradient.add_point(0.35, Color(0.10, 0.68, 1.0, 0.88))
    gradient.add_point(0.72, Color(0.025, 0.30, 1.0, 0.48))
    gradient.add_point(1.0, Color(0.015, 0.10, 0.72, 0.0))
    particles.color_ramp = gradient

    var quad := QuadMesh.new()
    quad.size = Vector2(0.38, 0.38)
    var flame_material := StandardMaterial3D.new()
    flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    flame_material.vertex_color_use_as_albedo = true
    flame_material.emission_enabled = true
    flame_material.emission = Color(0.08, 0.48, 1.0)
    flame_material.emission_energy_multiplier = 2.2
    quad.material = flame_material
    particles.mesh = quad
    nozzle.add_child(particles)
    engine_effects.append(particles)

func _update_engine_effects() -> void:
    if engine_effects.is_empty() or not is_instance_valid(vehicle):
        return
    var speed_ratio := clampf(vehicle.linear_velocity.length() / 30.0, 0.0, 1.0)
    var forward_power := absf(float(vehicle.get("smoothed_forward")))
    var strafe_power := absf(float(vehicle.get("smoothed_strafe")))
    var vertical_power := absf(float(vehicle.get("smoothed_vertical")))
    var input_power := maxf(forward_power, maxf(strafe_power, vertical_power))
    var active := speed_ratio > 0.025 or input_power > 0.06
    var intensity := clampf(maxf(speed_ratio, input_power) * 1.35, 0.12, 1.0)
    for particles in engine_effects:
        if is_instance_valid(particles):
            particles.emitting = active
            particles.speed_scale = lerpf(0.65, 1.65, intensity)

var is_portrait := false
var free_camera_mode := false
var camera_distance := 10.0
var camera_min_distance := 4.0
var camera_max_distance := 24.0
var free_camera_speed := 12.0
var free_camera_yaw := 0.0
var free_camera_pitch := -0.18
var free_camera_drag_index := -1
var free_camera_last_touch := Vector2.ZERO
var free_camera_mouse_drag := false
var joystick_control: TouchJoystick
var camera_mode_button: Button
var camera_zoom_label: Label

func _make_camera() -> void:
    camera = Camera3D.new()
    camera.name = "ChaseCamera"
    camera.current = true
    camera.fov = 68
    add_child(camera)
    # Start behind and above the hovercraft so the complete vehicle is visible.
    camera.global_position = Vector3(0, 8.0, -14.0)
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
    diagnostic_label = Label.new()
    diagnostic_label.visible = false
    diagnostic_label.add_theme_font_size_override("font_size", 15)
    diagnostic_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
    panel.add_child(diagnostic_label)

    # Left: analog movement joystick. Right: independent altitude hold buttons.
    var joystick := TouchJoystick.new()
    joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    joystick.position = Vector2(24, -214)
    layer.add_child(joystick)

    var lift_controls := VBoxContainer.new()
    lift_controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    lift_controls.position = Vector2(-122, -205)
    lift_controls.add_theme_constant_override("separation", 12)
    layer.add_child(lift_controls)

    var up_button := HoldTouchButton.new()
    up_button.setup("up", "▲")
    lift_controls.add_child(up_button)
    var down_button := HoldTouchButton.new()
    down_button.setup("down", "▼")
    lift_controls.add_child(down_button)

    # Camera controls grouped at the upper-right, below the orientation switch.
    var camera_controls := HBoxContainer.new()
    camera_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    camera_controls.position = Vector2(-250, 82)
    camera_controls.add_theme_constant_override("separation", 8)
    layer.add_child(camera_controls)

    var zoom_in := Button.new()
    zoom_in.text = "+"
    zoom_in.tooltip_text = "Приблизить камеру"
    zoom_in.custom_minimum_size = Vector2(64, 58)
    zoom_in.pressed.connect(_zoom_camera.bind(-1.5))
    camera_controls.add_child(zoom_in)

    var zoom_out := Button.new()
    zoom_out.text = "−"
    zoom_out.tooltip_text = "Отдалить камеру"
    zoom_out.custom_minimum_size = Vector2(64, 58)
    zoom_out.pressed.connect(_zoom_camera.bind(1.5))
    camera_controls.add_child(zoom_out)

    camera_mode_button = Button.new()
    camera_mode_button.text = "КАМЕРА"
    camera_mode_button.tooltip_text = "Включить свободную камеру"
    camera_mode_button.custom_minimum_size = Vector2(116, 58)
    camera_mode_button.pressed.connect(_toggle_free_camera)
    camera_controls.add_child(camera_mode_button)

    var diagnostic_button := Button.new()
    diagnostic_button.text = "ДИАГ"
    diagnostic_button.tooltip_text = "Показать диагностику движения"
    diagnostic_button.custom_minimum_size = Vector2(92, 58)
    diagnostic_button.pressed.connect(_toggle_diagnostics)
    camera_controls.add_child(diagnostic_button)



func _toggle_diagnostics() -> void:
    diagnostic_visible = not diagnostic_visible
    diagnostic_label.visible = diagnostic_visible
    if diagnostic_visible:
        diagnostic_frames = 0
        diagnostic_jerk_events = 0
        diagnostic_angular_events = 0
        diagnostic_frame_events = 0
        diagnostic_max_frame_ms = 0.0
        diagnostic_max_jerk = 0.0
        diagnostic_max_angular_accel = 0.0
        diagnostic_max_camera_speed = 0.0
        diagnostic_velocity_ready = false
        diagnostic_camera_ready = false
        diagnostic_label.text = "ДИАГНОСТИКА: сбор данных..."

func _toggle_screen_orientation(button: Button) -> void:
    is_portrait = not is_portrait
    if is_portrait:
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
        button.text = "АЛЬБОМНАЯ ОРИЕНТАЦИЯ"
    else:
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
        button.text = "ПОРТРЕТНАЯ ОРИЕНТАЦИЯ"

func _zoom_camera(change: float) -> void:
    camera_distance = clampf(camera_distance + change, camera_min_distance, camera_max_distance)
    if camera_zoom_label:
        camera_zoom_label.text = "Камера: %.1f м" % camera_distance

func _toggle_free_camera() -> void:
    free_camera_mode = not free_camera_mode
    if free_camera_mode:
        free_camera_yaw = camera.global_rotation.y
        free_camera_pitch = camera.global_rotation.x
        camera_mode_button.text = "ВОЗВРАТ"
        camera_mode_button.tooltip_text = "Вернуть камеру за ховер"
        vehicle.set_physics_process(false)
        telemetry.text = "Свободная камера: джойстик — движение, свайп — обзор"
    else:
        camera_mode_button.text = "КАМЕРА"
        camera_mode_button.tooltip_text = "Включить свободную камеру"
        vehicle.set_physics_process(true)
        FlightInput.held["forward"] = false
        FlightInput.held["back"] = false
        FlightInput.held["left"] = false
        FlightInput.held["right"] = false
        FlightInput.held["up"] = false
        FlightInput.held["down"] = false

func _unhandled_input(event: InputEvent) -> void:
    if not free_camera_mode:
        return
    if event is InputEventScreenTouch:
        if event.pressed and free_camera_drag_index == -1:
            free_camera_drag_index = event.index
            free_camera_last_touch = event.position
        elif not event.pressed and event.index == free_camera_drag_index:
            free_camera_drag_index = -1
    elif event is InputEventScreenDrag and event.index == free_camera_drag_index:
        var delta_pos: Vector2 = event.position - free_camera_last_touch
        free_camera_last_touch = event.position
        _rotate_free_camera(delta_pos)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        free_camera_mouse_drag = event.pressed
    elif event is InputEventMouseMotion and free_camera_mouse_drag:
        _rotate_free_camera(event.relative)

func _rotate_free_camera(delta_pos: Vector2) -> void:
    free_camera_yaw -= delta_pos.x * 0.004
    free_camera_pitch = clampf(free_camera_pitch - delta_pos.y * 0.004, -1.35, 1.1)

func _process(delta: float) -> void:
    if not is_instance_valid(vehicle):
        return
    if free_camera_mode:
        var move := Vector3(
            FlightInput.axis("left", "right"),
            FlightInput.axis("down", "up"),
            -FlightInput.axis("back", "forward")
        )
        var basis := Basis(Vector3.UP, free_camera_yaw) * Basis(Vector3.RIGHT, free_camera_pitch)
        camera.global_position += (basis * move) * free_camera_speed * delta
        camera.global_basis = basis
        _update_diagnostics(delta)
        return

    # Follow the interpolated physics transform so camera motion stays in sync
    # with rendered rigid-body motion instead of sampling between physics ticks.
    var vehicle_transform := vehicle.get_global_transform_interpolated()
    # The imported hovercraft's nose points along local +Z; its rear is local -Z.
    # Keep the chase camera behind the rear edge, with a small elevated racing-game view.
    var rear_offset := 2.25
    var vertical_offset := 6.0
    var horizontal_offset := sqrt(maxf(camera_distance * camera_distance - vertical_offset * vertical_offset, 0.1))
    var target := vehicle_transform.origin + Vector3(0, 0.65, 0)

    # Follow heading only. Do not rotate the chase-camera offset with pitch/bank:
    # otherwise every acceleration tilt moves the camera vertically and sideways.
    var flat_forward := vehicle_transform.basis.z
    flat_forward.y = 0.0
    if flat_forward.length_squared() < 0.001:
        flat_forward = Vector3.BACK
    flat_forward = flat_forward.normalized()
    var flat_right := Vector3.UP.cross(flat_forward).normalized()
    var desired := vehicle_transform.origin + Vector3.UP * vertical_offset - flat_forward * (rear_offset + horizontal_offset)
    # Position follows the interpolated body directly; orientation is damped
    # independently to avoid tiny heading changes being amplified as camera jitter.
    camera.global_position = desired
    var desired_camera_transform := camera.global_transform.looking_at(target, Vector3.UP)
    var camera_blend := 1.0 - exp(-10.0 * delta)
    camera.global_basis = camera.global_basis.slerp(desired_camera_transform.basis, camera_blend).orthonormalized()
    _update_engine_effects()
    telemetry.text = "Скорость: %.1f м/с   Высота: %.1f м" % [vehicle.linear_velocity.length(), vehicle.global_position.y]
    _update_diagnostics(delta)

func _update_diagnostics(delta: float) -> void:
    if delta <= 0.000001:
        return
    var frame_ms := delta * 1000.0
    diagnostic_max_frame_ms = maxf(diagnostic_max_frame_ms, frame_ms)
    if frame_ms > 25.0:
        diagnostic_frame_events += 1
    diagnostic_frames += 1

    var current_velocity := vehicle.linear_velocity
    var current_angular := vehicle.angular_velocity
    var acceleration := Vector3.ZERO
    var jerk := 0.0
    var angular_acceleration := 0.0
    if diagnostic_velocity_ready:
        acceleration = (current_velocity - diagnostic_prev_velocity) / delta
        jerk = (acceleration - diagnostic_prev_acceleration).length() / delta
        angular_acceleration = (current_angular - diagnostic_prev_angular_velocity).length() / delta
        diagnostic_max_jerk = maxf(diagnostic_max_jerk, jerk)
        diagnostic_max_angular_accel = maxf(diagnostic_max_angular_accel, angular_acceleration)
        if jerk > 18.0:
            diagnostic_jerk_events += 1
        if angular_acceleration > 0.7:
            diagnostic_angular_events += 1
    diagnostic_prev_velocity = current_velocity
    diagnostic_prev_acceleration = acceleration
    diagnostic_prev_angular_velocity = current_angular
    diagnostic_velocity_ready = true

    if diagnostic_camera_ready:
        diagnostic_camera_speed = camera.global_position.distance_to(diagnostic_prev_camera_position) / delta
        diagnostic_max_camera_speed = maxf(diagnostic_max_camera_speed, diagnostic_camera_speed)
    diagnostic_prev_camera_position = camera.global_position
    diagnostic_camera_ready = true

    if diagnostic_visible:
        diagnostic_label.text = (
            "ДИАГНОСТИКА ДВИЖЕНИЯ  |  кадров: %d\n" % diagnostic_frames +
            "FPS: %.1f   кадр: %.1f мс   макс.: %.1f мс\n" % [1.0 / delta, frame_ms, diagnostic_max_frame_ms] +
            "Скорость XYZ: %.2f / %.2f / %.2f м/с\n" % [current_velocity.x, current_velocity.y, current_velocity.z] +
            "Ускорение: %.2f м/с²   рывок: %.1f м/с³ (макс. %.1f)\n" % [acceleration.length(), jerk, diagnostic_max_jerk] +
            "Угл. скорость: %.3f рад/с   угл. ускорение: %.2f (макс. %.2f)\n" % [current_angular.length(), angular_acceleration, diagnostic_max_angular_accel] +
            "Камера: %.2f м/с   макс.: %.2f м/с\n" % [diagnostic_camera_speed, diagnostic_max_camera_speed] +
            "Срабатывания: рывок %d | вращение %d | кадр >25мс: %d\n" % [diagnostic_jerk_events, diagnostic_angular_events, diagnostic_frame_events] +
            "Порог: рывок >18 м/с³; угл. ускорение >0.7 рад/с²"
        )
