class_name BodyLayer
extends SkeletonModifier3D
## Procedural upper body on top of the clips: the head and spine turn toward
## where the camera looks, the torso leans into slopes and against changes in
## speed, and the chest breathes harder after exertion. All angles are applied
## in skeleton space around each bone's own pivot, so they work on any clip.

## Fractions of the look yaw and pitch taken by each bone, lowest first.
const LOOK_CHAIN: Array[StringName] = [&"Spine02", &"Spine01", &"Spine", &"neck", &"Head"]
const LOOK_YAW_SHARE: Array[float] = [0.1, 0.12, 0.13, 0.25, 0.4]
const LOOK_PITCH_SHARE: Array[float] = [0.0, 0.1, 0.15, 0.3, 0.45]
const LEAN_SHARE: Array[float] = [0.45, 0.35, 0.2, 0.0, 0.0]

## Look direction in radians (yaw: + turns left; pitch: + looks up).
var look_yaw: float = 0.0
var look_pitch: float = 0.0
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

	# The skeleton faces +Z, so yaw is about +Y and a forward lean (or a
	# downward look) is a positive turn about +X.
	for i in _chain.size():
		var pitch := -look_pitch * LOOK_PITCH_SHARE[i] + torso_lean * LEAN_SHARE[i]
		if i == 1 or i == 2:
			pitch -= breath * 0.5
		var turn := Basis(Vector3.UP, look_yaw * LOOK_YAW_SHARE[i]) * Basis(Vector3.RIGHT, pitch)
		var pose := skeleton.get_bone_global_pose(_chain[i])
		pose.basis = turn * pose.basis
		skeleton.set_bone_global_pose(_chain[i], pose)
		skeleton.force_update_bone_child_transform(_chain[i])
	_relax_shoulders(skeleton)
	_carry_sword(skeleton)


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
