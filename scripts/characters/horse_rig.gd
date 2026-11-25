class_name HorseQuadrupedRig
extends Skeleton3D

const FRONT_KNEE_HEIGHT: float = 0.40
const HIND_HOCK_HEIGHT: float = 0.47
const FETLOCK_HEIGHT: float = 0.15
const LEG_TOP_HEIGHT: float = 0.62
const LEG_BLEND_HEIGHT: float = 0.86
const BODY_PIVOT: Vector3 = Vector3(0.0, 1.0, 0.1)
const NECK_PIVOT: Vector3 = Vector3(0.0, 1.12, -0.5)
const TAIL_PIVOT: Vector3 = Vector3(0.0, 1.18, 0.95)

var root_bone: int = -1
var body_bone: int = -1
var neck_bone: int = -1
var tail_bone: int = -1
var upper_bones: Array[int] = []
var lower_bones: Array[int] = []
var hoof_bones: Array[int] = []
var mesh_instance: MeshInstance3D


func build_from(source: MeshInstance3D, space: Node3D) -> bool:
	if source == null or source.mesh == null or source.skin == null:
		return false
	var source_skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
	if source_skeleton == null:
		return false
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var old_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var old_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = vertices.size()
	if count == 0 or old_bones.size() < count:
		return false
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		normals = arrays[Mesh.ARRAY_NORMAL]
	var tangents := PackedFloat32Array()
	if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
		tangents = arrays[Mesh.ARRAY_TANGENT]
	var per_vertex: int = int(float(old_bones.size()) / float(count))
	var to_space: Transform3D = space.global_transform.affine_inverse() * source_skeleton.global_transform
	var binds: Array[Transform3D] = []
	for bind in source.skin.get_bind_count():
		var source_bone: int = source_skeleton.find_bone(String(source.skin.get_bind_name(bind)))
		if source_bone < 0:
			source_bone = source.skin.get_bind_bone(bind)
		binds.append(to_space * source_skeleton.get_bone_global_rest(source_bone) * source.skin.get_bind_pose(bind))

	var points := PackedVector3Array()
	points.resize(count)
	var new_normals := PackedVector3Array()
	new_normals.resize(normals.size())
	var new_tangents := PackedFloat32Array()
	new_tangents.resize(tangents.size())
	var has_normals: bool = normals.size() == count
	var has_tangents: bool = tangents.size() == count * 4
	for index in count:
		var point := Vector3.ZERO
		var normal := Vector3.ZERO
		var tangent := Vector3.ZERO
		for slot in per_vertex:
			var weight: float = old_weights[index * per_vertex + slot]
			if weight <= 0.0:
				continue
			var bind_transform: Transform3D = binds[old_bones[index * per_vertex + slot]]
			point += (bind_transform * vertices[index]) * weight
			if has_normals:
				normal += (bind_transform.basis * normals[index]) * weight
			if has_tangents:
				var source_tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
				tangent += (bind_transform.basis * source_tangent) * weight
		points[index] = point
		if has_normals:
			new_normals[index] = normal.normalized()
		if has_tangents:
			tangent = tangent.normalized()
			new_tangents[index * 4] = tangent.x
			new_tangents[index * 4 + 1] = tangent.y
			new_tangents[index * 4 + 2] = tangent.z
			new_tangents[index * 4 + 3] = tangents[index * 4 + 3]

	_build_skeleton(points)

	var new_bones := PackedInt32Array()
	new_bones.resize(count * 4)
	var new_weights := PackedFloat32Array()
	new_weights.resize(count * 4)
	for index in count:
		_write_influences(_influences_for(points[index]), index, new_bones, new_weights)

	var new_arrays: Array = arrays.duplicate()
	new_arrays[Mesh.ARRAY_VERTEX] = points
	if has_normals:
		new_arrays[Mesh.ARRAY_NORMAL] = new_normals
	if has_tangents:
		new_arrays[Mesh.ARRAY_TANGENT] = new_tangents
	new_arrays[Mesh.ARRAY_BONES] = new_bones
	new_arrays[Mesh.ARRAY_WEIGHTS] = new_weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	mesh.surface_set_material(0, source.get_active_material(0))

	var skin := Skin.new()
	for bone in get_bone_count():
		skin.add_named_bind(get_bone_name(bone), get_bone_global_rest(bone).affine_inverse())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HorseMesh"
	mesh_instance.mesh = mesh
	mesh_instance.skin = skin
	mesh_instance.cast_shadow = source.cast_shadow
	add_child(mesh_instance)
	mesh_instance.skeleton = mesh_instance.get_path_to(self)
	reset_bone_poses()
	return true


func set_leg(leg: int, upper: float, lower: float, hoof: float) -> void:
	set_bone_pose_rotation(upper_bones[leg], Quaternion(Vector3.RIGHT, upper))
	set_bone_pose_rotation(lower_bones[leg], Quaternion(Vector3.RIGHT, lower))
	set_bone_pose_rotation(hoof_bones[leg], Quaternion(Vector3.RIGHT, hoof))


func set_body(offset: Vector3, pitch: float, roll: float) -> void:
	set_bone_pose_position(body_bone, get_bone_rest(body_bone).origin + offset)
	set_bone_pose_rotation(body_bone, Quaternion.from_euler(Vector3(pitch, 0.0, roll)))


func set_neck(pitch: float, yaw: float) -> void:
	set_bone_pose_rotation(neck_bone, Quaternion.from_euler(Vector3(pitch, yaw, 0.0)))


func set_tail(pitch: float, yaw: float) -> void:
	set_bone_pose_rotation(tail_bone, Quaternion.from_euler(Vector3(pitch, yaw, 0.0)))


func _build_skeleton(points: PackedVector3Array) -> void:
	clear_bones()
	upper_bones.clear()
	lower_bones.clear()
	hoof_bones.clear()
	var sums: Array[Vector3] = []
	var counts: Array[int] = []
	for slot in 12:
		sums.append(Vector3.ZERO)
		counts.append(0)
	for point in points:
		var leg: int = _leg_of(point)
		if leg < 0:
			continue
		var knee: float = FRONT_KNEE_HEIGHT if leg < 2 else HIND_HOCK_HEIGHT
		var band: int = -1
		if point.y > LEG_TOP_HEIGHT - 0.07 and point.y < LEG_TOP_HEIGHT:
			band = 0
		elif absf(point.y - knee) < 0.03:
			band = 1
		elif absf(point.y - FETLOCK_HEIGHT) < 0.03:
			band = 2
		if band >= 0:
			sums[leg * 3 + band] += point
			counts[leg * 3 + band] += 1

	root_bone = _add_bone("Root", -1, Vector3.ZERO)
	body_bone = _add_bone("Body", root_bone, BODY_PIVOT)
	neck_bone = _add_bone("Neck", body_bone, NECK_PIVOT)
	tail_bone = _add_bone("Tail", body_bone, TAIL_PIVOT)
	var leg_names: Array[String] = ["FrontLeft", "FrontRight", "HindLeft", "HindRight"]
	for leg in 4:
		var fallback := Vector3(-0.17 if leg % 2 == 0 else 0.17, 0.0, -0.38 if leg < 2 else 0.62)
		var top: Vector3 = _band_center(sums, counts, leg * 3, fallback)
		var knee_center: Vector3 = _band_center(sums, counts, leg * 3 + 1, top)
		var fetlock_center: Vector3 = _band_center(sums, counts, leg * 3 + 2, knee_center)
		var top_origin := Vector3(top.x, 0.98, top.z)
		if leg >= 2:
			top_origin = Vector3(top.x, 1.02, top.z + 0.08)
		var knee_height: float = FRONT_KNEE_HEIGHT if leg < 2 else HIND_HOCK_HEIGHT
		var upper: int = _add_bone(leg_names[leg] + "Upper", root_bone, top_origin)
		var lower: int = _add_bone(leg_names[leg] + "Lower", upper, Vector3(knee_center.x, knee_height, knee_center.z))
		var hoof: int = _add_bone(leg_names[leg] + "Hoof", lower, Vector3(fetlock_center.x, FETLOCK_HEIGHT, fetlock_center.z))
		upper_bones.append(upper)
		lower_bones.append(lower)
		hoof_bones.append(hoof)


func _add_bone(bone_name: String, parent: int, global_origin: Vector3) -> int:
	var bone: int = add_bone(bone_name)
	var parent_origin := Vector3.ZERO
	if parent >= 0:
		parent_origin = get_bone_global_rest(parent).origin
		set_bone_parent(bone, parent)
	set_bone_rest(bone, Transform3D(Basis.IDENTITY, global_origin - parent_origin))
	return bone


func _band_center(sums: Array[Vector3], counts: Array[int], slot: int, fallback: Vector3) -> Vector3:
	if counts[slot] == 0:
		return fallback
	return sums[slot] / float(counts[slot])


func _leg_of(point: Vector3) -> int:
	if point.y > LEG_BLEND_HEIGHT:
		return -1
	var side: int = 1 if point.x > 0.0 else 0
	if point.z > -0.75 and point.z < -0.02:
		return side
	if point.z > 0.2 and point.z < 0.95:
		return 2 + side
	return -1


func _leg_membership(leg: int, point: Vector3) -> float:
	var zone: float = 0.0
	if leg < 2:
		zone = _ramp(-0.74, -0.64, point.z) * _ramp(-0.04, -0.14, point.z)
	else:
		zone = _ramp(0.22, 0.32, point.z) * _ramp(0.94, 0.91, point.z)
	var height: float = _ramp(LEG_BLEND_HEIGHT, LEG_TOP_HEIGHT, point.y)
	var side: float = 1.0
	if point.y > LEG_TOP_HEIGHT - 0.04:
		side = _ramp(0.02, 0.1, absf(point.x))
	return zone * height * side


func _influences_for(point: Vector3) -> Dictionary:
	var influences: Dictionary = {}
	var leg: int = _leg_of(point)
	var membership: float = 0.0
	if leg >= 0:
		membership = _leg_membership(leg, point)
	if membership > 0.0:
		var knee: float = FRONT_KNEE_HEIGHT if leg < 2 else HIND_HOCK_HEIGHT
		var lower: float = _ramp(knee + 0.04, knee - 0.04, point.y)
		var hoof: float = _ramp(FETLOCK_HEIGHT + 0.03, FETLOCK_HEIGHT - 0.03, point.y)
		_add_influence(influences, upper_bones[leg], membership * (1.0 - lower))
		_add_influence(influences, lower_bones[leg], membership * lower * (1.0 - hoof))
		_add_influence(influences, hoof_bones[leg], membership * lower * hoof)
	var rest: float = 1.0 - membership
	var neck: float = _ramp(-0.5, -0.74, point.z) * _ramp(0.62, 0.8, point.y)
	var tail: float = _ramp(0.9, 0.96, point.z)
	_add_influence(influences, neck_bone, rest * neck)
	_add_influence(influences, tail_bone, rest * (1.0 - neck) * tail)
	_add_influence(influences, body_bone, rest * (1.0 - neck) * (1.0 - tail))
	return influences


func _add_influence(influences: Dictionary, bone: int, weight: float) -> void:
	if weight > 0.0001:
		influences[bone] = float(influences.get(bone, 0.0)) + weight


func _write_influences(influences: Dictionary, index: int, bones: PackedInt32Array, weights: PackedFloat32Array) -> void:
	var ordered: Array[int] = []
	for key in influences.keys():
		ordered.append(int(key))
	ordered.sort_custom(_heavier.bind(influences))
	var used: int = mini(4, ordered.size())
	var total: float = 0.0
	for slot in used:
		total += float(influences[ordered[slot]])
	for slot in 4:
		var offset: int = index * 4 + slot
		if slot < used and total > 0.0:
			bones[offset] = ordered[slot]
			weights[offset] = float(influences[ordered[slot]]) / total
		elif slot == 0:
			bones[offset] = body_bone
			weights[offset] = 1.0
		else:
			bones[offset] = 0
			weights[offset] = 0.0


func _heavier(first: int, second: int, influences: Dictionary) -> bool:
	return float(influences[first]) > float(influences[second])


func _ramp(from: float, to: float, value: float) -> float:
	var amount: float = clampf((value - from) / (to - from), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)
