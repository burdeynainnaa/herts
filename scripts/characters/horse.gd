extends CharacterBody3D

const WALK_LEG_PHASES: Array[float] = [0.25, 0.75, 0.0, 0.5]
const GALLOP_LEG_PHASES: Array[float] = [0.3, 0.42, 0.0, 0.12]
const HOOF_LEG_ORDER: Array[int] = [0, 1, 3, 2]
const HOOF_FALLBACK_OFFSETS: Array[Vector3] = [
	Vector3(-0.17, 0.0, -0.38),
	Vector3(0.17, 0.0, -0.38),
	Vector3(0.17, 0.0, 0.62),
	Vector3(-0.17, 0.0, 0.62),
]
const SUPPORT_PROBE_REACH: float = 0.8
const MAX_SUPPORT_TILT_DEGREES: float = 45.0

@export var walk_speed: float = 3.2
@export var run_speed: float = 8.0
@export var acceleration: float = 10.0
@export var turn_speed: float = 7.0
@export var walk_stride_length: float = 1.8
@export var run_stride_length: float = 3.4
@export var slope_align_speed: float = 10.0
@export var rig_static_model: bool = false
@export var trim_ground_artifacts: bool = false
@export_range(0.5, 2.0, 0.01) var model_scale: float = 1.0

var mounted: bool = false
var gait: StringName = &"idle"
var gait_phase: float = 0.0
var saddle_offset: float = 0.0
var saddle_pitch: float = 0.0
var saddle_roll: float = 0.0
var _gravity: float = 9.8
var _walk_weight: float = 0.0
var _run_weight: float = 0.0
var _idle_time: float = 0.0
var _rig: HorseQuadrupedRig
var _visual: Node3D


func _ready() -> void:
	add_to_group(&"rideable_horses")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	floor_snap_length = 0.4
	_visual = get_node_or_null(^"Visual") as Node3D
	if _visual == null:
		return
	var model := _visual.get_node_or_null(^"Character") as Node3D
	if model == null:
		return
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	_rig = HorseQuadrupedRig.new()
	_rig.name = "QuadrupedRig"
	_visual.add_child(_rig)
	var tail_source := model.find_child("Tail", true, false) as MeshInstance3D if rig_static_model else null
	if _rig.build_from(meshes[0] as MeshInstance3D, self, rig_static_model, trim_ground_artifacts, tail_source):
		_rig.scale = Vector3.ONE * model_scale
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
	_update_slope_tilt(delta)
	_update_gait(delta, &"idle")


func ride(direction: Vector3, sprinting: bool, delta: float) -> void:
	var target_speed := run_speed if sprinting else walk_speed
	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_slope_tilt(delta)
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


func _update_slope_tilt(delta: float) -> void:
	if _visual == null:
		return
	var weight: float = 1.0 - exp(-slope_align_speed * delta)
	_visual.quaternion = _visual.quaternion.slerp(_tilt_basis_for(_support_up()).get_rotation_quaternion(), weight)


func _support_up() -> Vector3:
	var space := get_world_3d().direct_space_state
	var horse_basis := global_transform.basis
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for offset in _hoof_offsets():
		var origin: Vector3 = global_position + horse_basis * (offset + Vector3.UP * SUPPORT_PROBE_REACH)
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin - Vector3.UP * SUPPORT_PROBE_REACH * 2.0, collision_mask, [get_rid()]
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if normal.dot(Vector3.UP) < 0.2:
			continue
		points.append(hit["position"])
		normals.append(normal)
	var up := Vector3.ZERO
	if points.size() >= 3:
		var center := Vector3.ZERO
		for point in points:
			center += point
		center /= float(points.size())
		for index in points.size():
			var next: Vector3 = points[(index + 1) % points.size()]
			up += (points[index] - center).cross(next - center)
	if up.length_squared() < 0.000001:
		for normal in normals:
			up += normal
	if up.length_squared() < 0.000001:
		return get_floor_normal() if is_on_floor() else Vector3.UP
	up = up.normalized()
	if up.y < 0.0:
		up = -up
	return _limit_support_tilt(up)


func _limit_support_tilt(up: Vector3) -> Vector3:
	var angle: float = up.angle_to(Vector3.UP)
	var limit: float = deg_to_rad(MAX_SUPPORT_TILT_DEGREES)
	if angle <= limit:
		return up
	return Vector3.UP.slerp(up, limit / angle)


func _hoof_offsets() -> Array[Vector3]:
	if _rig == null or _rig.hoof_bones.size() < 4:
		return HOOF_FALLBACK_OFFSETS
	var offsets: Array[Vector3] = []
	for leg in HOOF_LEG_ORDER:
		var origin: Vector3 = _rig.get_bone_global_rest(_rig.hoof_bones[leg]).origin
		offsets.append(Vector3(origin.x, 0.0, origin.z) * model_scale)
	return offsets


func _tilt_basis_for(up: Vector3) -> Basis:
	var local_up: Vector3 = (global_transform.basis.inverse() * up).normalized()
	var forward: Vector3 = Vector3.FORWARD - local_up * Vector3.FORWARD.dot(local_up)
	if forward.length_squared() < 0.0001:
		return Basis.IDENTITY
	forward = forward.normalized()
	var back: Vector3 = -forward
	return Basis(local_up.cross(back), local_up, back)


func get_visual_global_basis() -> Basis:
	if _visual == null:
		return global_transform.basis
	return global_transform.basis * _visual.basis


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
		saddle_pitch = 0.0
		saddle_roll = 0.0
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
	if _rig.separate_tail:
		tail_swish = 0.25 * sin(cycle) * moving + 0.18 * sin(_idle_time * 0.9) * (1.0 - moving)
	_rig.set_tail(-0.35 * _run_weight - 0.05 * _walk_weight, tail_swish)
	saddle_offset = bob * model_scale + (model_scale - 1.0) * HorseQuadrupedRig.BODY_PIVOT.y
	saddle_pitch = pitch
	saddle_roll = roll


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
