extends SkeletonModifier3D

var _bones: Dictionary = {}


func _ready() -> void:
	active = false
	var skeleton := get_skeleton()
	for bone_name in [&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"RightUpLeg", &"RightLeg", &"RightFoot", &"LeftArm", &"LeftForeArm", &"LeftHand", &"RightArm", &"RightForeArm", &"RightHand"]:
		_bones[bone_name] = skeleton.find_bone(bone_name)


func apply_pose(weight: float) -> void:
	if weight <= 0.001:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_align_bone(skeleton, &"LeftUpLeg", &"LeftLeg", Vector3(0.68, -0.60, 0.42), weight)
	_align_bone(skeleton, &"RightUpLeg", &"RightLeg", Vector3(-0.68, -0.60, 0.42), weight)
	_align_bone(skeleton, &"LeftLeg", &"LeftFoot", Vector3(-0.20, -1.0, -0.06), weight)
	_align_bone(skeleton, &"RightLeg", &"RightFoot", Vector3(0.20, -1.0, -0.06), weight)
	_align_bone(skeleton, &"LeftArm", &"LeftForeArm", Vector3(0.30, -0.92, 0.24), weight)
	_align_bone(skeleton, &"RightArm", &"RightForeArm", Vector3(-0.30, -0.92, 0.24), weight)
	_align_bone(skeleton, &"LeftForeArm", &"LeftHand", Vector3(-0.10, -0.45, 0.88), weight)
	_align_bone(skeleton, &"RightForeArm", &"RightHand", Vector3(0.10, -0.45, 0.88), weight)


func _align_bone(skeleton: Skeleton3D, bone_name: StringName, child_name: StringName, target: Vector3, weight: float) -> void:
	var bone: int = _bones.get(bone_name, -1)
	var child: int = _bones.get(child_name, -1)
	if bone < 0 or child < 0:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var direction := skeleton.get_bone_global_pose(child).origin - pose.origin
	if direction.length_squared() < 0.0001:
		return
	var wanted := direction.normalized().slerp(target.normalized(), clampf(weight, 0.0, 1.0))
	pose.basis = Basis(Quaternion(direction.normalized(), wanted)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
	skeleton.force_update_bone_child_transform(bone)
