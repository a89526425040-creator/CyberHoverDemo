extends Node
class_name FlightInput

static var held := {
    "forward": false, "back": false, "left": false,
    "right": false, "up": false, "down": false
}

static func set_action(action: String, pressed: bool) -> void:
    held[action] = pressed

static func axis(negative: String, positive: String) -> float:
    return float(held.get(positive, false)) - float(held.get(negative, false))
