# CyberHoverDemo

Godot 4 Android hovercraft flight demo.

## Project status

This repository was just created and is currently being initialized. The original Blender model and its texture archive must be added under `assets/source/` and `assets/textures/` before the Blender-to-GLB export and APK workflow can produce the intended vehicle.

## Planned controls
- W/S: forward/reverse thrust
- A/D: lateral thrust
- Space/Ctrl: vertical thrust

The flight controller uses rigid-body forces, gravity, aerodynamic drag, and a spring-damper hover system.
