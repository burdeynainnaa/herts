class_name GroundIK
extends SkeletonModifier3D
## Puts the animated feet on the real ground. Each foot keeps its animated
## height above the ground, measured from the terrain right under it instead
## of the flat plane the clip was made on. The pelvis drops so the lower foot
## can reach, both legs are re-solved with an analytic two-bone IK that keeps
## the animated knee direction, and planted feet roll and pitch to the slope.

@export var max_step_height: float = 0.5
@export var max_pelvis_drop: float = 0.45
@export var foot_follow_speed: float = 18.0
@export var pelvis_follow_speed: float = 10.0
@export var max_foot_tilt_degrees: float = 32.0
## Ankle height of a flat planted foot, and the height above it at which the
## foot stops following the slope.
@export var ankle_height: float = 0.11
@export var tilt_release_height: float = 0.14
@export_flags_3d_physics var ground_mask: int = 1

## The body whose origin is the clip's ground plane.
var body: CharacterBody3D
## Extra pelvis offset in metres (landing compression), set by the controller.
var pelvis_extra: float = 0.0
## How firmly each foot is planted (0 = left, 1 = right), set by the
## controller from the stride phase. A planted foot is pinned to the spot
## where it touched down until it lifts.
var stance := PackedFloat32Array([0.0, 0.0])
## A pinned foot further than this from its animated spot is let go.
@export var max_lock_distance: float = 0.4

var _legs: Array = []
var _pelvis: int = -1
var _foot_offsets := PackedFloat32Array([0.0, 0.0])
var _pelvis_offset: float = 0.0
var _last_ticks: int = 0
var _locks: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _locked: Array[bool] = [false, false]


func _ready() -> void:
	var skeleton := get_skeleton()
	_pelvis = skeleton.find_bone("Hips")
	for side in ["Left", "Right"]:
		var leg := [
			skeleton.find_bone(side + "UpLeg"), skeleton.find_bone(side + "Leg"),
			skeleton.find_bone(side + "Foot")
		]
		if leg.min() < 0 or _pelvis < 0:
			push_error("GroundIK needs Hips and the UpLeg/Leg/Foot chain on both sides")
			active = false
			return
		_legs.append(leg)


## Snaps the smoothing state, e.g. after a teleport or dismount.
func reset() -> void:
	_foot_offsets = PackedFloat32Array([0.0, 0.0])
	_pelvis_offset = 0.0
	_locked = [false, false]


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or body == null or _legs.is_empty():
		return
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_ticks) / 1000000.0, 0.0, 0.1)
	_last_ticks = now

	var to_world := skeleton.global_transform
	var to_skeleton := to_world.affine_inverse()
	var space := body.get_world_3d().direct_space_state
	var ground_y := body.global_position.y
	var feet_world: Array[Vector3] = []
	var foot_bases: Array[Basis] = []
	var normals: Array[Vector3] = []
	var heights: Array[float] = []

	for i in _legs.size():
		var foot: int = _legs[i][2]
		var foot_pose := skeleton.get_bone_global_pose(foot)
		var foot_world := to_world * foot_pose.origin
		feet_world.append(foot_world)
		foot_bases.append(foot_pose.basis)
		heights.append(foot_world.y - ground_y)
		var target := 0.0
		var normal := Vector3.UP
		var from := Vector3(foot_world.x, ground_y + max_step_height + 0.2, foot_world.z)
		var query := PhysicsRayQueryParameters3D.create(
			from, Vector3(foot_world.x, ground_y - max_step_height - 0.2, foot_world.z), ground_mask
		)
		query.exclude = [body.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			target = clampf((hit.position as Vector3).y - ground_y, -max_step_height, max_step_height)
			normal = hit.normal
		_foot_offsets[i] = lerpf(_foot_offsets[i], target, 1.0 - exp(-foot_follow_speed * delta))
		normals.append(normal)

	var pelvis_target := clampf(minf(minf(_foot_offsets[0], _foot_offsets[1]), 0.0), -max_pelvis_drop, 0.0)
	_pelvis_offset = lerpf(_pelvis_offset, pelvis_target, 1.0 - exp(-pelvis_follow_speed * delta))

	var hips := skeleton.get_bone_global_pose(_pelvis)
	hips.origin += to_skeleton.basis * (Vector3.UP * (_pelvis_offset + pelvis_extra))
	skeleton.set_bone_global_pose(_pelvis, hips)
	skeleton.force_update_bone_child_transform(_pelvis)

	var max_tilt := deg_to_rad(max_foot_tilt_degrees)
	for i in _legs.size():
		var leg: Array = _legs[i]
		var target_world: Vector3 = feet_world[i] + Vector3.UP * _foot_offsets[i]
		var plant_weight: float = stance[i]
		if plant_weight > 0.01:
			if not _locked[i] or _locks[i].distance_to(target_world) > max_lock_distance:
				_locks[i] = target_world
				_locked[i] = true
			var pinned := Vector3(_locks[i].x, target_world.y, _locks[i].z)
			target_world = target_world.lerp(pinned, plant_weight)
		else:
			_locked[i] = false
		_solve_two_bone(skeleton, leg[0], leg[1], leg[2], to_skeleton * target_world)
		# Planted feet lie on the slope; a swinging foot keeps its clip angle.
		var lift: float = heights[i] - ankle_height
		var plant := 1.0 - clampf(lift / maxf(tilt_release_height, 0.001), 0.0, 1.0)
		var up_skeleton := (to_skeleton.basis * Vector3.UP).normalized()
		var normal_skeleton := (to_skeleton.basis * normals[i]).normalized()
		var tilt := Quaternion(up_skeleton, normal_skeleton)
		var angle := tilt.get_angle()
		if angle > max_tilt:
			tilt = Quaternion.IDENTITY.slerp(tilt, max_tilt / angle)
		tilt = Quaternion.IDENTITY.slerp(tilt, plant)
		var foot_pose := skeleton.get_bone_global_pose(leg[2])
		foot_pose.basis = Basis(tilt) * foot_bases[i]
		skeleton.set_bone_global_pose(leg[2], foot_pose)
		skeleton.force_update_bone_child_transform(leg[2])


## Two-bone IK in skeleton space (after Daniel Holden's formulation): bends
## the knee to reach the distance, then swings the whole chain to the target.
## The bend plane comes from the animated pose, so the knee points where the
## clip pointed it.
static func _solve_two_bone(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3) -> void:
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(end).origin
	var length_ab := a.distance_to(b)
	var length_cb := b.distance_to(c)
	if length_ab < 0.0001 or length_cb < 0.0001:
		return
	var length_at := clampf(a.distance_to(target), 0.01, (length_ab + length_cb) * 0.999)

	var ac := (c - a).normalized()
	var ab := (b - a).normalized()
	var ba := (a - b).normalized()
	var bc := (c - b).normalized()
	var at := (target - a).normalized()

	var ac_ab_0 := acos(clampf(ac.dot(ab), -1.0, 1.0))
	var ba_bc_0 := acos(clampf(ba.dot(bc), -1.0, 1.0))
	var ac_at_0 := acos(clampf(ac.dot(at), -1.0, 1.0))
	var ac_ab_1 := acos(clampf(
		(length_cb * length_cb - length_ab * length_ab - length_at * length_at) / (-2.0 * length_ab * length_at), -1.0, 1.0
	))
	var ba_bc_1 := acos(clampf(
		(length_at * length_at - length_ab * length_ab - length_cb * length_cb) / (-2.0 * length_ab * length_cb), -1.0, 1.0
	))

	var axis0 := ac.cross(ab)
	if axis0.length_squared() < 0.000001:
		# Straight leg: bend in the plane of the knee's forward (+Z) direction.
		axis0 = ac.cross(Vector3(0.0, 0.0, 1.0))
		if axis0.length_squared() < 0.000001:
			return
	axis0 = axis0.normalized()
	var axis1 := ac.cross(at)

	var lower_pose := skeleton.get_bone_global_pose(lower)
	lower_pose.basis = Basis(Quaternion(axis0, ba_bc_1 - ba_bc_0)) * lower_pose.basis
	skeleton.set_bone_global_pose(lower, lower_pose)
	skeleton.force_update_bone_child_transform(lower)

	var swing := Quaternion(axis0, ac_ab_1 - ac_ab_0)
	if axis1.length_squared() > 0.000001:
		swing = Quaternion(axis1.normalized(), ac_at_0) * swing
	var upper_pose := skeleton.get_bone_global_pose(upper)
	upper_pose.basis = Basis(swing) * upper_pose.basis
	skeleton.set_bone_global_pose(upper, upper_pose)
	skeleton.force_update_bone_child_transform(upper)
