extends RigidBody3D

@export var hover_height := 1.4
@export var hover_spring := 24000.0
@export var hover_damping := 6000.0
@export var forward_thrust := 14000.0
@export var lateral_thrust := 10000.0
@export var vertical_thrust := 18000.0
@export var air_drag := 0.38
@export var max_speed := 40.0
@export var upright_gain := 4.5
@export var upright_damping := 2.0

var model_pivot: Node3D

func _ready() -> void:
    model_pivot = get_node_or_null("ModelPivot")

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var down := event.pressed and not event.echo
        match event.keycode:
            KEY_W: FlightInput.set_action("forward", down)
            KEY_S: FlightInput.set_action("back", down)
            KEY_A: FlightInput.set_action("left", down)
            KEY_D: FlightInput.set_action("right", down)
            KEY_SPACE: FlightInput.set_action("up", down)
            KEY_CTRL: FlightInput.set_action("down", down)

func _physics_process(delta: float) -> void:
    var ground := _ground_distance()
    if ground >= 0.0 and ground < hover_height * 3.0:
        var vertical_speed := linear_velocity.dot(Vector3.UP)
        var lift := maxf(0.0, (hover_height - ground) * hover_spring - vertical_speed * hover_damping)
        apply_central_force(Vector3.UP * lift)

    var f := FlightInput.axis("back", "forward")
    var s := FlightInput.axis("left", "right")
    var v := FlightInput.axis("down", "up")
    apply_central_force(-global_transform.basis.z * f * forward_thrust)
    apply_central_force(global_transform.basis.x * s * lateral_thrust)
    apply_central_force(Vector3.UP * v * vertical_thrust)

    apply_central_force(-linear_velocity * air_drag * mass)
    var speed := linear_velocity.length()
    if speed > max_speed:
        apply_central_force(-linear_velocity.normalized() * (speed - max_speed) * mass * 2.0)

    var correction := global_transform.basis.y.cross(Vector3.UP)
    apply_torque(correction * mass * upright_gain - angular_velocity * mass * upright_damping)

    if model_pivot:
        model_pivot.rotation.x = lerp(model_pivot.rotation.x, -f * 0.18, delta * 3.0)
        model_pivot.rotation.z = lerp(model_pivot.rotation.z, -s * 0.18, delta * 3.0)

func _ground_distance() -> float:
    var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 10.0)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    return global_position.distance_to(hit.position) if not hit.is_empty() else -1.0
