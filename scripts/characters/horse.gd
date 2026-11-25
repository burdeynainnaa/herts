extends CharacterBody3D

const WALK_LEG_PHASES: Array[float] = [0.25, 0.75, 0.0, 0.5]
const GALLOP_LEG_PHASES: Array[float] = [0.3, 0.42, 0.0, 0.12]

@export var walk_speed: float = 3.2
@export var run_speed: float = 8.0
@export var acceleration: float = 10.0
@export var turn_speed: float = 7.0
@export var walk_stride_length: float = 1.8
@export var run_stride_length: float = 3.4

var mounted: bool = false
var gait: StringName = &"idle"
var gait_phase: float = 0.0
var saddle_offset: float = 0.0
var _gravity: float = 9.8
var _walk_weight: float = 0.0
var _run_weight: float = 0.0
var _idle_time: float = 0.0
var _rig: HorseQuadrupedRig


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	floor_snap_length = 0.4
	var model := $Character as Node3D
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	_rig = HorseQuadrupedRig.new()
	_rig.name = "QuadrupedRig"
	add_child(_rig)
	if _rig.build_from(meshes[0] as MeshInstance3D, self):
		model.visible = false
	else:
		_rig.queue_free()
		_rig = null


func _physics_process(delta: float) -> void:
	if mounted:
		return
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_gait(delta, &"idle")


func ride(direction: Vector3, sprinting: bool, delta: float) -> void:
	var target_speed := run_speed if sprinting else walk_speed
	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	_apply_gravity(delta)
	move_and_slide()
	if direction.length_squared() > 0.0001:
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	var speed := Vector2(velocity.x, velocity.z).length()
	var next_gait: StringName = &"idle"
	if speed > 0.15:
		next_gait = &"run" if sprinting and speed > (walk_speed + run_speed) * 0.5 else &"walk"
	_update_gait(delta, next_gait)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta


func _update_gait(delta: float, next_gait: StringName) -> void:
	gait = next_gait
	var blend: float = 1.0 - exp(-6.0 * delta)
	_walk_weight = lerpf(_walk_weight, 1.0 if gait == &"walk" else 0.0, blend)
	_run_weight = lerpf(_run_weight, 1.0 if gait == &"run" else 0.0, blend)
	var moving: float = clampf(_walk_weight + _run_weight, 0.0, 1.0)
	var run_share: float = _run_weight / maxf(_walk_weight + _run_weight, 0.001)
	var stride: float = lerpf(walk_stride_length, run_stride_length, run_share)
	var speed: float = Vector2(velocity.x, velocity.z).length()
	gait_phase = fposmod(gait_phase + delta * speed / stride, 1.0)
	_idle_time += delta
	if _rig == null:
		saddle_offset = 0.0
		return

	for leg in 4:
		var walk_pose: Vector3 = _leg_pose(fposmod(gait_phase - WALK_LEG_PHASES[leg], 1.0), 0.62, 0.3, 0.75, leg)
		var run_pose: Vector3 = _leg_pose(fposmod(gait_phase - GALLOP_LEG_PHASES[leg], 1.0), 0.36, 0.5, 1.2, leg)
		var pose: Vector3 = walk_pose * _walk_weight + run_pose * _run_weight
		_rig.set_leg(leg, pose.x, pose.y, pose.z)

	var cycle: float = TAU * gait_phase
	var gallop_rock: float = cos(cycle - TAU * 0.05)
	var bob: float = -0.018 * cos(2.0 * cycle) * _walk_weight + 0.05 * cos(cycle - TAU * 0.86) * _run_weight
	var pitch: float = 0.012 * sin(2.0 * cycle) * _walk_weight + 0.06 * gallop_rock * _run_weight
	var roll: float = (0.025 * _walk_weight + 0.012 * _run_weight) * sin(cycle)
	var breathe: float = 0.004 * sin(_idle_time * 1.6) * (1.0 - moving)
	_rig.set_body(Vector3(0.0, bob + breathe, 0.0), pitch, roll)
	var idle_look: float = sin(_idle_time * 0.45) * 0.08 * (1.0 - moving)
	var neck_pitch: float = 0.07 * sin(2.0 * cycle + 0.6) * _walk_weight - 0.1 * gallop_rock * _run_weight + 0.03 * sin(_idle_time * 0.7) * (1.0 - moving)
	_rig.set_neck(neck_pitch, idle_look)
	var tail_swish: float = 0.12 * sin(cycle) * moving + 0.06 * sin(_idle_time * 0.9) * (1.0 - moving)
	_rig.set_tail(-0.35 * _run_weight - 0.05 * _walk_weight, tail_swish)
	saddle_offset = bob


func _leg_pose(local_phase: float, stance: float, amplitude: float, flex: float, leg: int) -> Vector3:
	if local_phase < stance:
		var stance_time: float = local_phase / stance
		var push_off: float = clampf((stance_time - 0.7) / 0.3, 0.0, 1.0)
		return Vector3(lerpf(amplitude, -amplitude, stance_time), 0.0, -push_off * flex * 0.3)
	var swing_time: float = (local_phase - stance) / (1.0 - stance)
	var lift: float = sin(swing_time * PI)
	var swing: float = lerpf(-amplitude, amplitude, 0.5 - 0.5 * cos(swing_time * PI))
	if leg < 2:
		return Vector3(swing + lift * flex * 0.15, -lift * flex, -lift * flex * 0.6)
	return Vector3(swing - lift * flex * 0.25, lift * flex * 0.9, -lift * flex * 0.7)
