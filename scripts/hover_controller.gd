extends RigidBody3D

# Four-point suspension and inertial flight model.
@export var hover_height := 1.4
@export var suspension_frequency := 2.5
@export var suspension_damping := 0.92
@export var forward_thrust := 12500.0
@export var lateral_thrust := 7200.0
@export var vertical_thrust := 15000.0
@export var forward_drag := 0.12
@export var lateral_drag := 1.05
@export var vertical_drag := 0.32
@export var max_speed := 42.0
@export var yaw_torque := 9500.0
@export var attitude_gain := 12500.0
@export var attitude_damping := 7200.0
@export var max_pitch := 0.16
@export var max_bank := 0.28

var model_pivot: Node3D
var smoothed_forward := 0.0
var smoothed_strafe := 0.0
var smoothed_vertical := 0.0
var model_pitch := 0.0
var model_roll := 0.0

const SUSPENSION_POINTS := [
    Vector3(-0.88, 0.12, -1.55),
    Vector3(0.88, 0.12, -1.55),
    Vector3(-0.88, 0.12, 1.55),
    Vector3(0.88, 0.12, 1.55)
]

func _ready() -> void:
    model_pivot = get_node_or_null("ModelPivot")
    gravity_scale = 1.0
    can_sleep = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var down: bool = event.pressed and not event.echo
        match event.keycode:
            KEY_W: FlightInput.set_action("forward", down)
            KEY_S: FlightInput.set_action("back", down)
            KEY_A: FlightInput.set_action("left", down)
            KEY_D: FlightInput.set_action("right", down)
            KEY_SPACE: FlightInput.set_action("up", down)
            KEY_CTRL: FlightInput.set_action("down", down)

func _physics_process(delta: float) -> void:
    var forward_input := clampf(FlightInput.axis("back", "forward"), -1.0, 1.0)
    var strafe_input := clampf(FlightInput.axis("left", "right"), -1.0, 1.0)
    var vertical_input := clampf(FlightInput.axis("down", "up"), -1.0, 1.0)

    # Smooth acceleration and release, rather than instant full-power switching.
    smoothed_forward = move_toward(smoothed_forward, forward_input, delta * 1.8)
    smoothed_strafe = move_toward(smoothed_strafe, strafe_input, delta * 2.8)
    smoothed_vertical = move_toward(smoothed_vertical, vertical_input, delta * 2.2)

    _apply_four_point_suspension()
    _apply_flight_forces()
    _apply_attitude_control(delta)

    if model_pivot:
        model_pitch = lerp(model_pitch, -smoothed_forward * 0.045, minf(delta * 3.0, 1.0))
        model_roll = lerp(model_roll, -smoothed_strafe * 0.055, minf(delta * 3.0, 1.0))
        model_pivot.rotation.x = model_pitch
        model_pivot.rotation.z = model_roll

func _apply_four_point_suspension() -> void:
    var state := get_world_3d().direct_space_state
    var omega := TAU * suspension_frequency
    var spring_k := mass * omega * omega / float(SUSPENSION_POINTS.size())
    var damper_c := 2.0 * suspension_damping * mass * omega / float(SUSPENSION_POINTS.size())
    var support_force := mass * float(ProjectSettings.get_setting("physics/3d/default_gravity")) / float(SUSPENSION_POINTS.size())

    for local_point in SUSPENSION_POINTS:
        var world_offset: Vector3 = global_transform.basis * local_point
        var ray_start: Vector3 = global_position + world_offset
        var ray_end: Vector3 = ray_start + Vector3.DOWN * (hover_height + 1.8)
        var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
        query.exclude = [get_rid()]
        var hit := state.intersect_ray(query)
        if hit.is_empty():
            continue

        var distance: float = ray_start.distance_to(hit.position)
        if distance > hover_height + 0.35:
            continue

        var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(world_offset)
        var vertical_speed: float = point_velocity.dot(Vector3.UP)
        var compression: float = hover_height - distance
        var lift: float = support_force + compression * spring_k - vertical_speed * damper_c
        lift = clampf(lift, 0.0, support_force * 4.0)
        apply_force(Vector3.UP * lift, world_offset)

func _apply_flight_forces() -> void:
    var basis := global_transform.basis
    apply_central_force(-basis.z * smoothed_forward * forward_thrust)
    apply_central_force(basis.x * smoothed_strafe * lateral_thrust)
    apply_central_force(Vector3.UP * smoothed_vertical * vertical_thrust)

    # Preserve forward momentum while gently suppressing sideways skating.
    var local_velocity: Vector3 = basis.inverse() * linear_velocity
    var local_drag := Vector3(
        local_velocity.x * lateral_drag,
        local_velocity.y * vertical_drag,
        local_velocity.z * forward_drag
    )
    apply_central_force(-(basis * local_drag) * mass)

    var speed := linear_velocity.length()
    if speed > max_speed:
        var excess := speed - max_speed
        apply_central_force(-linear_velocity.normalized() * excess * mass * 1.4)

func _apply_attitude_control(delta: float) -> void:
    var basis := global_transform.basis
    var local_angular: Vector3 = basis.inverse() * angular_velocity
    var speed_factor := clampf(linear_velocity.length() / 9.0, 0.22, 1.0)

    # Horizontal stick steers the nose; the craft banks naturally into turns.
    var desired_yaw_rate := -smoothed_strafe * 0.72 * speed_factor
    var yaw_control := (desired_yaw_rate - local_angular.y) * yaw_torque
    var desired_pitch_rate := -smoothed_forward * max_pitch
    var desired_roll_rate := -smoothed_strafe * max_bank
    var pitch_control := (desired_pitch_rate - local_angular.x) * attitude_gain
    var roll_control := (desired_roll_rate - local_angular.z) * attitude_gain

    # Light self-leveling only: it no longer locks the body upright.
    var up_error_local: Vector3 = basis.inverse() * basis.y.cross(Vector3.UP)
    var level_torque := Vector3(up_error_local.x, 0.0, up_error_local.z) * attitude_gain * 0.22
    var damping_torque := -local_angular * attitude_damping * 0.45
    var local_torque := Vector3(pitch_control, yaw_control, roll_control) + level_torque + damping_torque
    apply_torque(basis * local_torque)
