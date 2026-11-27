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
@export var ankle_height: float = 0.123
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
## 0 = walking, 1 = standing; set by the controller. A standing body puts
## both feet flat on the ground and a little wider than the walk's track.
var stand_weight: float = 0.0
## Extra half-width of the standing stance, in metres per foot.
@export var stand_spread: float = 0.045

## Idle fidget, set by the controller: shifting weight from foot to foot.
## fidget_shift is -1 .. +1 (+1 = weight on the left leg); the hips slide
## over the weighted leg and tilt a little while the other foot is free.
## fidget_lift is how far each foot (left, right) is raised, 0 .. 1; a raised
## foot comes up and a little forward, then goes back down in place.
var fidget_shift: float = 0.0
var fidget_lift := PackedFloat32Array([0.0, 0.0])
@export var fidget_hip_shift: float = 0.03
@export var fidget_hip_roll_degrees: float = 2.5
@export var fidget_lift_height: float = 0.035
@export var fidget_lift_forward: float = 0.03

## Sole clearance. The ankle ray alone lets the toe or heel poke through a
## step or a slope, so each foot also samples the ground a heel's and a toe's
## reach away and is raised until its sole clears both.
@export var heel_reach: float = 0.07
@export var toe_reach: float = 0.19
@export var sole_margin: float = 0.006
@export var clearance_follow_speed: float = 24.0
## The foot bone's "up" in bone space, read from the rest pose, where the
## foot stands flat (this rig's foot bone does not point along the foot).
var _sole_axes: Array[Vector3] = []
## How far past the slope the clip's foot may be pitched and still be swung
## flat onto the ground.
@export var sole_pitch_allowance_degrees: float = 40.0

var _clearance := PackedFloat32Array([0.0, 0.0])
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
		var rest_basis := skeleton.get_bone_global_rest(leg[2]).basis.orthonormalized()
		_sole_axes.append((rest_basis.inverse() * Vector3.UP).normalized())


## Snaps the smoothing state, e.g. after a teleport or dismount.
func reset() -> void:
	_foot_offsets = PackedFloat32Array([0.0, 0.0])
	_clearance = PackedFloat32Array([0.0, 0.0])
	_pelvis_offset = 0.0
	_locked = [false, false]


## Ground height at a point, relative to the body's ground plane.
func _ground_at(space: PhysicsDirectSpaceState3D, point: Vector3, ground_y: float, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, ground_y + max_step_height + 0.2, point.z),
		Vector3(point.x, ground_y - max_step_height - 0.2, point.z), ground_mask
	)
	query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return clampf((hit.position as Vector3).y - ground_y, -max_step_height, max_step_height)


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
	var heel_ground: Array[float] = []
	var toe_ground: Array[float] = []

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
		var forward := to_world.basis * Vector3(0.0, 0.0, 1.0)
		forward.y = 0.0
		forward = forward.normalized()
		heel_ground.append(_ground_at(space, foot_world - forward * heel_reach, ground_y, target))
		toe_ground.append(_ground_at(space, foot_world + forward * toe_reach, ground_y, target))

	var pelvis_target := clampf(minf(minf(_foot_offsets[0], _foot_offsets[1]), 0.0), -max_pelvis_drop, 0.0)
	_pelvis_offset = lerpf(_pelvis_offset, pelvis_target, 1.0 - exp(-pelvis_follow_speed * delta))

	var hips := skeleton.get_bone_global_pose(_pelvis)
	hips.origin += to_skeleton.basis * (Vector3.UP * (_pelvis_offset + pelvis_extra))
	if absf(fidget_shift) > 0.001:
		# The skeleton's +X is the character's left, +Z forward.
		hips.origin += Vector3(1.0, 0.0, 0.0) * (fidget_hip_shift * fidget_shift) * 100.0
		hips.basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(fidget_hip_roll_degrees) * fidget_shift) * hips.basis
	skeleton.set_bone_global_pose(_pelvis, hips)
	skeleton.force_update_bone_child_transform(_pelvis)

	var max_tilt := deg_to_rad(max_foot_tilt_degrees)
	for i in _legs.size():
		var leg: Array = _legs[i]
		var target_world: Vector3 = feet_world[i] + Vector3.UP * _foot_offsets[i]
		if stand_weight > 0.001:
			var planted_y := ground_y + _foot_offsets[i] + ankle_height
			target_world.y = lerpf(target_world.y, planted_y, stand_weight)
			# The skeleton's +X is the character's left.
			var outward := Vector3(1.0 if i == 0 else -1.0, 0.0, 0.0)
			target_world += (to_world.basis * outward).normalized() * stand_spread * stand_weight
		if fidget_lift[i] > 0.001:
			target_world += Vector3.UP * fidget_lift_height * fidget_lift[i]
			target_world += (to_world.basis * Vector3(0.0, 0.0, 1.0)).normalized() * fidget_lift_forward * fidget_lift[i]
		# Sole clearance: lift the foot until heel and toe both clear the ground.
		var lift_now: float = heights[i] - ankle_height
		var plant_now := maxf(1.0 - clampf(lift_now / maxf(tilt_release_height, 0.001), 0.0, 1.0), stand_weight)
		var flat_forward := to_world.basis * Vector3(0.0, 0.0, 1.0)
		flat_forward.y = 0.0
		flat_forward = flat_forward.normalized()
		var slope := clampf(-normals[i].dot(flat_forward) / maxf(normals[i].y, 0.2), -tan(max_tilt), tan(max_tilt)) * plant_now
		var sole_at_ankle := target_world.y - ground_y - ankle_height
		var need := maxf(
			heel_ground[i] - (sole_at_ankle - heel_reach * slope),
			toe_ground[i] - (sole_at_ankle + toe_reach * slope)
		) + sole_margin
		_clearance[i] = lerpf(_clearance[i], maxf(need, 0.0), 1.0 - exp(-clearance_follow_speed * delta))
		if need > _clearance[i]:
			_clearance[i] = need
		target_world.y += _clearance[i]
		var plant_weight: float = stance[i]
		if plant_weight > 0.01:
			if not _locked[i] or _locks[i].distance_to(target_world) > max_lock_distance:
				_locks[i] = target_world
				_locked[i] = true
			var pinned := Vector3(_locks[i].x, target_world.y, _locks[i].z)
			target_world = target_world.lerp(pinned, plant_weight)
		else:
			_locked[i] = false
		solve_two_bone(skeleton, leg[0], leg[1], leg[2], to_skeleton * target_world)
		# Planted feet lie on the slope; a swinging foot keeps its clip angle.
		var lift: float = heights[i] - ankle_height
		var plant := 1.0 - clampf(lift / maxf(tilt_release_height, 0.001), 0.0, 1.0)
		plant = maxf(plant, stand_weight)
		# Lay the sole on the ground: swing the animated sole normal onto the
		# ground normal; the clip's own foot pitch is not flat.
		var sole := (foot_bases[i] * _sole_axes[i]).normalized()
		var normal_skeleton := (to_skeleton.basis * normals[i]).normalized()
		var tilt := Quaternion(sole, normal_skeleton)
		var angle := tilt.get_angle()
		var limit := max_tilt + deg_to_rad(sole_pitch_allowance_degrees)
		if angle > limit:
			tilt = Quaternion.IDENTITY.slerp(tilt, limit / angle)
		tilt = Quaternion.IDENTITY.slerp(tilt, plant)
		var foot_pose := skeleton.get_bone_global_pose(leg[2])
		foot_pose.basis = Basis(tilt) * foot_bases[i]
		skeleton.set_bone_global_pose(leg[2], foot_pose)
		skeleton.force_update_bone_child_transform(leg[2])


## Two-bone IK in skeleton space (after Daniel Holden's formulation): bends
## the knee to reach the distance, then swings the whole chain to the target.
## The bend plane comes from the animated pose, so the knee points where the
## clip pointed it.
static func solve_two_bone(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3) -> void:
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
