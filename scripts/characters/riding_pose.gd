extends SkeletonModifier3D

var _bones: Dictionary = {}


func _ready() -> void:
	var skeleton := get_skeleton()
	for bone_name in [&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"RightUpLeg", &"RightLeg", &"RightFoot", &"LeftArm", &"LeftForeArm", &"LeftHand", &"RightArm", &"RightForeArm", &"RightHand"]:
		_bones[bone_name] = skeleton.find_bone(bone_name)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	_align_bone(skeleton, &"LeftUpLeg", &"LeftLeg", Vector3(0.45, -0.40, 1.0))
	_align_bone(skeleton, &"RightUpLeg", &"RightLeg", Vector3(-0.45, -0.40, 1.0))
	_align_bone(skeleton, &"LeftLeg", &"LeftFoot", Vector3(0.10, -1.0, -0.15))
	_align_bone(skeleton, &"RightLeg", &"RightFoot", Vector3(-0.10, -1.0, -0.15))
	_align_bone(skeleton, &"LeftArm", &"LeftForeArm", Vector3(0.32, -0.85, 0.5))
	_align_bone(skeleton, &"RightArm", &"RightForeArm", Vector3(-0.32, -0.85, 0.5))
	_align_bone(skeleton, &"LeftForeArm", &"LeftHand", Vector3(-0.12, -0.28, 1.0))
	_align_bone(skeleton, &"RightForeArm", &"RightHand", Vector3(0.12, -0.28, 1.0))


func _align_bone(skeleton: Skeleton3D, bone_name: StringName, child_name: StringName, target: Vector3) -> void:
	var bone: int = _bones.get(bone_name, -1)
	var child: int = _bones.get(child_name, -1)
	if bone < 0 or child < 0:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var direction := skeleton.get_bone_global_pose(child).origin - pose.origin
	if direction.length_squared() < 0.0001:
		return
	pose.basis = Basis(Quaternion(direction.normalized(), target.normalized())) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
	skeleton.force_update_bone_child_transform(bone)
