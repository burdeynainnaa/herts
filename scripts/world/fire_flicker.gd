extends OmniLight3D

@export var base_energy := 1.35
@export var flicker_strength := 0.22
@export var flicker_speed := 6.5

var _phase := 0.0


func _ready() -> void:
	_phase = fmod(absf(global_position.x * 12.9898 + global_position.z * 78.233 + global_position.y * 37.719), TAU)
	_apply_flicker()


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	_apply_flicker()


func _apply_flicker() -> void:
	var wave := sin(_phase) * 0.55 + sin(_phase * 2.31 + 1.7) * 0.3 + sin(_phase * 5.17 + 0.4) * 0.15
	light_energy = base_energy * (1.0 + wave * flicker_strength)
