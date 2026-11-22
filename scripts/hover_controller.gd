extends RigidBody3D

# Inertial hover flight controller.
# Inputs define target velocity; forces accelerate the rigid body toward it.
# This keeps acceleration bounded and avoids instant velocity changes.

@export var max_forward_speed := 42.0
@export var max_reverse_speed := 20.0
@export var max_lateral_speed := 17.0
@export var velocity_response := 1.9
@export var max_forward_acceleration := 7.5
@export var max_lateral_acceleration := 6.0
@export var input_ramp_forward := 1.35
@export var input_ramp_strafe := 1.8

@export var altitude_climb_rate := 5.0
@export var altitude_hold_gain := 2.0
@export var altitude_hold_damping := 3.2
@export var max_vertical_acceleration := 10.0

@export var yaw_rate := 0.62
@export var yaw_torque := 8500.0
@export var attitude_gain := 9000.0
@export var attitude_damping := 7800.0
@export var max_pitch := 0.12
@export var max_bank := 0.22

var model_pivot: Node3D
var smoothed_forward := 0.0
var smoothed_strafe := 0.0
var smoothed_vertical := 0.0
var model_pitch := 0.0
var model_roll := 0.0
var target_model_pitch := 0.0
var target_model_roll := 0.0
var target_altitude := 1.5

func _ready() -> void:
    model_pivot = get_node_or_null("ModelPivot")
    gravity_scale = 1.0
    can_sleep = false
    target_altitude = global_position.y
    # Keep the physics body authoritative; visual attitude is updated per rendered frame.
    physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

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

    # Smooth the pilot's command before it reaches the flight controller.
    smoothed_forward = move_toward(smoothed_forward, forward_input, input_ramp_forward * delta)
    smoothed_strafe = move_toward(smoothed_strafe, strafe_input, input_ramp_strafe * delta)
    smoothed_vertical = move_toward(smoothed_vertical, vertical_input, 2.0 * delta)

    _apply_velocity_controller()
    _update_altitude_target(delta)
    _apply_altitude_hold()
    _apply_attitude_controller()

    # The body is interpolated by Godot. Only the cosmetic model tilt is updated
    # in _process so it does not step at the fixed physics frequency.
    target_model_pitch = -smoothed_forward * max_pitch
    target_model_roll = -smoothed_strafe * max_bank

func _process(delta: float) -> void:
    if not is_instance_valid(model_pivot):
        return
    var blend := 1.0 - exp(-7.0 * delta)
    model_pitch = lerpf(model_pitch, target_model_pitch, blend)
    model_roll = lerpf(model_roll, target_model_roll, blend)
    model_pivot.rotation = Vector3(model_pitch, 0.0, model_roll)

func _apply_velocity_controller() -> void:
    var basis := global_transform.basis.orthonormalized()
    var local_velocity: Vector3 = basis.inverse() * linear_velocity

    # The imported hovercraft nose is local +Z. Reverse speed is intentionally lower.
    var desired_forward_speed := smoothed_forward * (max_forward_speed if smoothed_forward >= 0.0 else max_reverse_speed)
    var desired_lateral_speed := smoothed_strafe * max_lateral_speed

    # Velocity error becomes bounded acceleration. Releasing the stick requests
    # a gradual stop; it does not teleport velocity to zero.
    var forward_acceleration := clampf(
        (desired_forward_speed - local_velocity.z) * velocity_response,
        -max_forward_acceleration,
        max_forward_acceleration
    )
    var lateral_acceleration := clampf(
        (desired_lateral_speed - local_velocity.x) * velocity_response,
        -max_lateral_acceleration,
        max_lateral_acceleration
    )

    var local_acceleration := Vector3(lateral_acceleration, 0.0, forward_acceleration)
    apply_central_force(basis * local_acceleration * mass)

func _update_altitude_target(delta: float) -> void:
    target_altitude = maxf(0.8, target_altitude + smoothed_vertical * altitude_climb_rate * delta)

func _apply_altitude_hold() -> void:
    # Lift balances gravity continuously; a PD correction holds the selected altitude.
    var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale
    var altitude_error := target_altitude - global_position.y
    var correction_acceleration := altitude_error * altitude_hold_gain - linear_velocity.y * altitude_hold_damping
    correction_acceleration = clampf(correction_acceleration, -max_vertical_acceleration, max_vertical_acceleration)
    var lift_force := mass * (gravity + correction_acceleration)
    apply_central_force(Vector3.UP * maxf(0.0, lift_force))

func _apply_attitude_controller() -> void:
    var basis := global_transform.basis.orthonormalized()
    var local_angular: Vector3 = basis.inverse() * angular_velocity

    # Maintain a yaw-only heading reference while spring-dampers keep pitch and bank controlled.
    var heading_basis := Basis(Vector3.UP, global_rotation.y)
    var relative_basis: Basis = heading_basis.inverse() * basis
    var attitude := relative_basis.get_euler()

    var desired_yaw_rate := -smoothed_strafe * yaw_rate
    var yaw_control := (desired_yaw_rate - local_angular.y) * yaw_torque
    var desired_pitch := -smoothed_forward * max_pitch
    var desired_roll := -smoothed_strafe * max_bank

    var pitch_control := (desired_pitch - attitude.x) * attitude_gain - local_angular.x * attitude_damping
    var roll_control := (desired_roll - attitude.z) * attitude_gain - local_angular.z * attitude_damping
    var yaw_damping := -local_angular.y * attitude_damping * 0.22

    apply_torque(basis * Vector3(pitch_control, yaw_control + yaw_damping, roll_control))
