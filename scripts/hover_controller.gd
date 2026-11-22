extends RigidBody3D

# Four-point suspension and inertial flight model.
@export var altitude_climb_rate := 6.0
@export var altitude_hold_gain := 2.2
@export var altitude_hold_damping := 2.8
@export var max_vertical_acceleration := 12.0
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
var target_altitude := 1.5

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
    target_altitude = global_position.y

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

    target_altitude = maxf(0.8, target_altitude + smoothed_vertical * altitude_climb_rate * delta)
    _apply_altitude_hold()
    _apply_flight_forces()
    _apply_attitude_control(delta)

    if model_pivot:
        model_pitch = lerp(model_pitch, smoothed_forward * 0.045, minf(delta * 3.0, 1.0))
        model_roll = lerp(model_roll, smoothed_strafe * 0.055, minf(delta * 3.0, 1.0))
        model_pivot.rotation.x = model_pitch
        model_pivot.rotation.z = model_roll

func _apply_altitude_hold() -> void:
    # Continuous lift balances gravity at every altitude, not only near the ground.
    # The target altitude moves while UP/DOWN is held and stays fixed after release.
    var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale
    var altitude_error := target_altitude - global_position.y
    var vertical_speed := linear_velocity.y
    var correction_acceleration := altitude_error * altitude_hold_gain - vertical_speed * altitude_hold_damping
    correction_acceleration = clampf(correction_acceleration, -max_vertical_acceleration, max_vertical_acceleration)
    var lift_force := mass * (gravity + correction_acceleration)
    apply_central_force(Vector3.UP * maxf(0.0, lift_force))

func _apply_flight_forces() -> void:
    var basis := global_transform.basis
    # The imported hovercraft's nose points along local +Z.
    # Positive forward input must accelerate along +Z.
    apply_central_force(basis.z * smoothed_forward * forward_thrust)
    # Screen-right is local +X for this vehicle.
    apply_central_force(basis.x * smoothed_strafe * lateral_thrust)

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

func _apply_attitude_control(_delta: float) -> void:
    var basis := global_transform.basis
    var local_angular: Vector3 = basis.inverse() * angular_velocity
    var speed_factor := clampf(linear_velocity.length() / 9.0, 0.22, 1.0)

    # Separate heading from pitch and bank so the craft can lean without drifting over.
    var heading_basis := Basis(Vector3.UP, global_rotation.y)
    var relative_basis: Basis = heading_basis.inverse() * basis
    var attitude := relative_basis.get_euler()

    # Positive yaw rotates this -Z-facing craft to the left; invert the strafe sign so left input turns left.
	var desired_yaw_rate := -smoothed_strafe * 0.72 * speed_factor
    var yaw_control := (desired_yaw_rate - local_angular.y) * yaw_torque

    # Stick deflection sets a bank/pitch angle; spring-damper control returns smoothly to level.
    var desired_pitch := smoothed_forward * max_pitch
    var desired_roll := smoothed_strafe * max_bank
    var pitch_control := (desired_pitch - attitude.x) * attitude_gain - local_angular.x * attitude_damping
    var roll_control := (desired_roll - attitude.z) * attitude_gain - local_angular.z * attitude_damping
    var yaw_damping := -local_angular.y * attitude_damping * 0.25

    apply_torque(basis * Vector3(pitch_control, yaw_control + yaw_damping, roll_control))
