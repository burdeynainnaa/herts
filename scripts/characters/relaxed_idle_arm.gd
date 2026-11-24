extends SkeletonModifier3D

var _left_arm: int = -1
var _left_forearm: int = -1
var _left_hand: int = -1
var _right_arm: int = -1
var _right_forearm: int = -1
var _right_hand: int = -1


func _ready() -> void:
	var skeleton := get_skeleton()
	_left_arm = skeleton.find_bone("LeftArm")
	_left_forearm = skeleton.find_bone("LeftForeArm")
	_left_hand = skeleton.find_bone("LeftHand")
	_right_arm = skeleton.find_bone("RightArm")
	_right_forearm = skeleton.find_bone("RightForeArm")
	_right_hand = skeleton.find_bone("RightHand")
	if min(_left_arm, _left_forearm, _left_hand, _right_arm, _right_forearm, _right_hand) < 0:
		push_error("Relaxed idle requires the character's arm and hand bones")
		active = false


func _process_modification() -> void:
	var skeleton := get_skeleton()
	_align_bone(skeleton, _left_arm, _left_forearm, Vector3(0.24, -1.0, 0.02), 0.18)
	_align_bone(skeleton, _right_arm, _right_forearm, Vector3(-0.24, -1.0, 0.02), 0.18)
	_align_bone(skeleton, _left_forearm, _left_hand, Vector3(0.03, -1.0, 0.12), 0.12)
	_align_bone(skeleton, _right_forearm, _right_hand, Vector3(-0.03, -1.0, 0.12), 0.12)


func _align_bone(skeleton: Skeleton3D, bone: int, child: int, target: Vector3, motion_weight: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var direction := skeleton.get_bone_global_pose(child).origin - pose.origin
	if direction.length_squared() < 0.0001:
		return
	var desired_direction := target.normalized().slerp(direction.normalized(), motion_weight)
	var correction := Quaternion(direction.normalized(), desired_direction)
	pose.basis = Basis(correction) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
	skeleton.force_update_bone_child_transform(bone)
