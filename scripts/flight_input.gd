extends Node
class_name FlightInput

static var held := {
    "forward": false, "back": false, "left": false,
    "right": false, "up": false, "down": false
}

static var analog := {
    "forward": 0.0, "back": 0.0, "left": 0.0,
    "right": 0.0, "up": 0.0, "down": 0.0
}

static func set_action(action: String, pressed: bool) -> void:
    held[action] = pressed

static func set_axis(action: String, value: float) -> void:
    if analog.has(action):
        analog[action] = clampf(value, 0.0, 1.0)

static func axis(negative: String, positive: String) -> float:
    var digital := float(held.get(positive, false)) - float(held.get(negative, false))
    var analog_value := float(analog.get(positive, 0.0)) - float(analog.get(negative, 0.0))
    return clampf(digital + analog_value, -1.0, 1.0)
