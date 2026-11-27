class_name BodyLayer
extends SkeletonModifier3D
## Procedural upper body on top of the clips: the head and spine turn toward
## where the camera looks, the torso leans into slopes and against changes in
## speed, and the chest breathes harder after exertion. All angles are applied
## in skeleton space around each bone's own pivot, so they work on any clip.

## Fractions of the look pitch, and of the head's and the torso's share of
## the look yaw, taken by each bone, lowest first.
const LOOK_CHAIN: Array[StringName] = [&"Spine02", &"Spine01", &"Spine", &"neck", &"Head"]
const HEAD_YAW_SHARE: Array[float] = [0.0, 0.0, 0.0, 0.4, 0.6]
const TORSO_YAW_SHARE: Array[float] = [0.2, 0.3, 0.5, 0.0, 0.0]
const LOOK_PITCH_SHARE: Array[float] = [0.0, 0.1, 0.15, 0.3, 0.45]
const LEAN_SHARE: Array[float] = [0.45, 0.35, 0.2, 0.0, 0.0]

## Where the camera looks, relative to the body, in radians (yaw: + turns
## left; pitch: + looks up). The head and torso follow it on their own.
var look_yaw_target: float = 0.0
var look_pitch_target: float = 0.0
## Added to the look yaw for a moment: the idle glance.
var glance_yaw: float = 0.0

## Head-first looking. The head and neck do the turning up to a comfortable
## angle; past it the upper body joins in a little, slower than the head, so
## the head leads and the torso trails. The most the neck alone can turn is
## head_yaw_max_degrees, the most the torso adds is torso_yaw_max_degrees.
@export var head_yaw_comfort_degrees: float = 32.0
@export var torso_yaw_share: float = 0.5
@export var torso_yaw_max_degrees: float = 38.0
@export var head_yaw_max_degrees: float = 70.0
## Spring settings (natural frequency in rad/s, damping ratio) that give the
## look some mass: the head accelerates and settles with a hint of overshoot,
## the torso is heavier and slower and trails behind.
@export var head_spring := Vector2(12.0, 0.8)
@export var torso_spring := Vector2(5.5, 0.95)
@export var pitch_spring := Vector2(10.0, 0.9)
var _head_yaw: float = 0.0
var _head_yaw_velocity: float = 0.0
var _torso_yaw: float = 0.0
var _torso_yaw_velocity: float = 0.0
var _look_pitch: float = 0.0
var _look_pitch_velocity: float = 0.0
var _head_neutral_basis := Basis.IDENTITY

## Idle fidget, set by the controller: the free left hand rises to adjust
## the hat (0 = hanging, 1 = at the brim).
var hat_reach: float = 0.0
## Hat tug: a small back-and-forth of the hand at the brim.
var hat_tug: float = 0.0
## Head dips while the hand is up.
var head_dip: float = 0.0
## Where the wrist goes, relative to the forehead (centimetres, skeleton
## space: +X is the character's left, +Y up, +Z forward): out to the left and
## forward, so the fingers land on the front of the brim.
@export var hat_wrist_offset: Vector3 = Vector3(8.0, 0.0, 8.0)
## Torso pitch in radians (+ leans forward), from slope and acceleration.
var torso_lean: float = 0.0
## 0 = rested, 1 = winded after a long run.
var exertion: float = 0.0

## Relaxed shoulders: the clips carry the shoulder joints level with the
## base of the neck (a shrug). Each clavicle is lowered until its shoulder
## joint sits this far below the neck base, in centimetres along the chest's
## up axis; the upper arm is counter-turned so the clip's arm swing is kept.
@export var shoulder_depth_below_neck: float = 7.0
## Largest drop applied in one frame's pose, in centimetres.
@export var max_shoulder_drop: float = 10.0
@export_range(0.0, 1.0) var shoulder_relax: float = 1.0

## Sword carry while standing: the sword hand turns so the sabre points
## forward and down instead of across the legs. Set by the controller
## (0 = walking, the clip's arm swing; 1 = standing).
var carry_weight: float = 0.0
## Where a carried blade points, in skeleton space: forward (+Z), down, and
## a little out to the right (-X).
@export var carry_blade_direction: Vector3 = Vector3(-0.2, -0.65, 1.0)
## Share of the turn the forearm takes by rolling about its own axis; the
## wrist bends the rest.
const CARRY_FOREARM_SHARE := 0.6

var _chain: PackedInt32Array = []
var _neck: int = -1
var _chest: int = -1
## [clavicle, upper arm] per side.
var _shoulders: Array = []
var _right_forearm: int = -1
var _right_hand: int = -1
var _left_arm: int = -1
var _left_forearm: int = -1
var _left_hand: int = -1
var _head_top: int = -1
var _head_front: int = -1
var _breath_phase: float = 0.0
var _last_ticks: int = 0


func _ready() -> void:
	var skeleton := get_skeleton()
	for bone_name in LOOK_CHAIN:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			push_error("BodyLayer needs bone %s" % bone_name)
			active = false
			return
		_chain.append(bone)
	_neck = skeleton.find_bone("neck")
	_chest = skeleton.find_bone("Spine")
	_right_forearm = skeleton.find_bone("RightForeArm")
	_right_hand = skeleton.find_bone("RightHand")
	_left_arm = skeleton.find_bone("LeftArm")
	_left_forearm = skeleton.find_bone("LeftForeArm")
	_left_hand = skeleton.find_bone("LeftHand")
	_head_top = skeleton.find_bone("head_end")
	_head_front = skeleton.find_bone("headfront")
	for side in ["Left", "Right"]:
		var clavicle := skeleton.find_bone(side + "Shoulder")
		var upper := skeleton.find_bone(side + "Arm")
		if clavicle >= 0 and upper >= 0:
			_shoulders.append([clavicle, upper])


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _chain.is_empty():
		return
	var now := Time.get_ticks_usec()
	var delta := clampf((now - _last_ticks) / 1000000.0, 0.0, 0.1)
	_last_ticks = now
	# Rested: ~15 breaths a minute, barely visible. Winded: ~40, deep.
	var breath_rate := lerpf(0.25, 0.68, exertion)
	_breath_phase = fposmod(_breath_phase + breath_rate * delta, 1.0)
	var breath := sin(_breath_phase * TAU) * deg_to_rad(lerpf(0.7, 2.6, exertion))

	# Split the look between head and torso: the head takes everything up to
	# the comfort angle, then the torso takes a share of what is left over.
	var total := look_yaw_target + glance_yaw
	var excess := maxf(absf(total) - deg_to_rad(head_yaw_comfort_degrees), 0.0)
	var torso_goal := signf(total) * minf(excess * torso_yaw_share, deg_to_rad(torso_yaw_max_degrees))
	var head_limit := deg_to_rad(head_yaw_max_degrees)
	var head_goal := clampf(total - torso_goal, -head_limit, head_limit)
	var head_state := _spring(_head_yaw, _head_yaw_velocity, head_goal, head_spring, delta)
	_head_yaw = head_state.x
	_head_yaw_velocity = head_state.y
	var torso_state := _spring(_torso_yaw, _torso_yaw_velocity, torso_goal, torso_spring, delta)
	_torso_yaw = torso_state.x
	_torso_yaw_velocity = torso_state.y
	var pitch_state := _spring(_look_pitch, _look_pitch_velocity, look_pitch_target, pitch_spring, delta)
	_look_pitch = pitch_state.x
	_look_pitch_velocity = pitch_state.y
	_head_neutral_basis = skeleton.get_bone_global_pose(_chain[_chain.size() - 1]).basis

	# The skeleton faces +Z, so yaw is about +Y and a forward lean (or a
	# downward look) is a positive turn about +X.
	for i in _chain.size():
		var pitch := -_look_pitch * LOOK_PITCH_SHARE[i] + torso_lean * LEAN_SHARE[i]
		if i == 1 or i == 2:
			pitch -= breath * 0.5
		if i >= 3:
			pitch += head_dip * (0.4 if i == 3 else 0.6)
		var yaw := _head_yaw * HEAD_YAW_SHARE[i] + _torso_yaw * TORSO_YAW_SHARE[i]
		var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var pose := skeleton.get_bone_global_pose(_chain[i])
		pose.basis = turn * pose.basis
		skeleton.set_bone_global_pose(_chain[i], pose)
		skeleton.force_update_bone_child_transform(_chain[i])
	_relax_shoulders(skeleton)
	_carry_sword(skeleton)
	_reach_hat(skeleton)


## Second-order spring step: returns (value, velocity). spec = (natural
## frequency, damping ratio); a ratio below 1 overshoots a little.
static func _spring(value: float, velocity: float, target: float, spec: Vector2, delta: float) -> Vector2:
	var omega := spec.x
	var accel := (target - value) * omega * omega - 2.0 * spec.y * omega * velocity
	velocity += accel * delta
	return Vector2(value + velocity * delta, velocity)


## Raises the free left hand to the brim of the hat with two-bone IK; the
## elbow bends the way the clip's arm already bends.
func _reach_hat(skeleton: Skeleton3D) -> void:
	if hat_reach <= 0.001 or _left_arm < 0 or _head_top < 0 or _head_front < 0:
		return
	var top := skeleton.get_bone_global_pose(_head_top).origin
	var front := skeleton.get_bone_global_pose(_head_front).origin
	var forehead := top.lerp(front, 0.5)
	# The offset was set for a head that faces front; express it in the head's
	# own frame so the hand goes with the hat when the head turns.
	var head_basis := skeleton.get_bone_global_pose(_chain[_chain.size() - 1]).basis
	var local_offset := _head_neutral_basis.inverse() * (hat_wrist_offset + Vector3(0.0, 1.0, 0.0) * hat_tug * 2.0)
	var wrist_goal := forehead + head_basis * local_offset
	# With the head turned well away from the hand there is no natural way to
	# reach the hat, so the hand lets go.
	var turned_away := smoothstep(deg_to_rad(28.0), deg_to_rad(52.0), absf(_head_yaw))
	var reach := clampf(hat_reach, 0.0, 1.0) * (1.0 - turned_away)
	if reach <= 0.001:
		return
	var wrist := skeleton.get_bone_global_pose(_left_hand).origin
	var goal := wrist.lerp(wrist_goal, reach)
	GroundIK.solve_two_bone(skeleton, _left_arm, _left_forearm, _left_hand, goal)


## Aims a carried sabre forward and down: the forearm rolls about its own
## axis as far as that helps, then the wrist swings the rest. The blade's
## direction in hand space is read from the sabre the hand holds.
func _carry_sword(skeleton: Skeleton3D) -> void:
	if carry_weight <= 0.001 or _right_forearm < 0 or _right_hand < 0:
		return
	var sabre := skeleton.get_node_or_null("RightHandSabre/Sabre") as Node3D
	if sabre == null:
		return
	var blade_in_hand := sabre.transform.basis.y.normalized()
	var wanted := carry_blade_direction.normalized()
	var forearm := skeleton.get_bone_global_pose(_right_forearm)
	var hand := skeleton.get_bone_global_pose(_right_hand)
	var roll_axis := (hand.origin - forearm.origin).normalized()
	var roll := _twist_to(hand.basis * blade_in_hand, wanted, roll_axis) * carry_weight * CARRY_FOREARM_SHARE
	forearm.basis = Basis(roll_axis, roll) * forearm.basis
	skeleton.set_bone_global_pose(_right_forearm, forearm)
	skeleton.force_update_bone_child_transform(_right_forearm)
	hand = skeleton.get_bone_global_pose(_right_hand)
	var blade := (hand.basis * blade_in_hand).normalized()
	var swing := Quaternion.IDENTITY.slerp(Quaternion(blade, wanted), carry_weight)
	hand.basis = Basis(swing) * hand.basis
	skeleton.set_bone_global_pose(_right_hand, hand)
	skeleton.force_update_bone_child_transform(_right_hand)


## Signed angle about axis that turns current toward wanted, both projected
## onto the plane across the axis.
static func _twist_to(current: Vector3, wanted: Vector3, axis: Vector3) -> float:
	var a := (current - axis * current.dot(axis))
	var b := (wanted - axis * wanted.dot(axis))
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return 0.0
	a = a.normalized()
	b = b.normalized()
	return clampf(atan2(axis.dot(a.cross(b)), a.dot(b)), -deg_to_rad(110.0), deg_to_rad(110.0))


func _relax_shoulders(skeleton: Skeleton3D) -> void:
	if shoulder_relax <= 0.0 or _neck < 0 or _chest < 0:
		return
	var up := skeleton.get_bone_global_pose(_chest).basis.y.normalized()
	var neck := skeleton.get_bone_global_pose(_neck).origin
	for pair in _shoulders:
		var clavicle: int = pair[0]
		var upper: int = pair[1]
		var pivot := skeleton.get_bone_global_pose(clavicle).origin
		var joint := skeleton.get_bone_global_pose(upper).origin
		var depth := (neck - joint).dot(up)
		var drop := clampf(shoulder_depth_below_neck - depth, 0.0, max_shoulder_drop) * shoulder_relax
		if drop <= 0.01:
			continue
		var reach := joint - pivot
		if reach.length_squared() < 0.0001:
			continue
		var lowered := (reach - up * drop).normalized() * reach.length()
		var swing := Quaternion(reach.normalized(), lowered.normalized())
		var clavicle_pose := skeleton.get_bone_global_pose(clavicle)
		var arm_basis := skeleton.get_bone_global_pose(upper).basis
		clavicle_pose.basis = Basis(swing) * clavicle_pose.basis
		skeleton.set_bone_global_pose(clavicle, clavicle_pose)
		skeleton.force_update_bone_child_transform(clavicle)
		# Keep the upper arm pointing where the clip pointed it.
		var arm_pose := skeleton.get_bone_global_pose(upper)
		arm_pose.basis = arm_basis
		skeleton.set_bone_global_pose(upper, arm_pose)
		skeleton.force_update_bone_child_transform(upper)
