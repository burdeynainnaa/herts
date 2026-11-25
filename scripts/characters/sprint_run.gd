class_name SprintRun
extends RefCounted

## Rebuilds a character's Run clip into a sprint: a shorter cycle (higher cadence),
## a torso that leans into the stride and a head that stays level. The source clip is
## never modified.

const OUT_CLIP := &"RunSprint"

## Cycle time as a fraction of the source, so 0.80 plays the gait 1.25x as fast.
const TIME_SCALE := 0.80
## Thigh swing kept; the source stride already reads as a sprint, so it is only
## trimmed when the faster cycle would make the step outrun the movement speed.
const LEG_KEEP := 1.0
## Extra forward lean: a little from the pelvis, the rest spread over the spine.
const HIPS_PITCH_DEGREES := 4.0
const SPINE_LEAN_DEGREES := 12.0
## Share of that lean the neck and head give back, to keep the head up.
const HEAD_COUNTER := 0.55

const SPINE_BONES: Array[StringName] = [&"Spine", &"Spine01", &"Spine02"]
const HEAD_BONES: Array[StringName] = [&"neck", &"Head"]
const LEG_BONES: Array[StringName] = [&"LeftUpLeg", &"RightUpLeg"]
const HIP_BONE: StringName = &"Hips"


static func build(skeleton: Skeleton3D, source: Animation) -> Animation:
	var out := source.duplicate(true) as Animation
	if out == null:
		return null
	_retime(out, TIME_SCALE)
	_lean_torso(out, skeleton)
	_trim_leg_swing(out)
	out.loop_mode = Animation.LOOP_LINEAR
	out.resource_name = OUT_CLIP
	return out


## Squeezes every key in time, which raises the step rate and shortens the loop.
static func _retime(animation: Animation, scale: float) -> void:
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			var time := animation.track_get_key_time(track, key)
			animation.track_set_key_time(track, key, time * scale)
	animation.length = animation.length * scale


## Pitches the spine forward and gives part of it back in the neck, so the character
## leans into the run while still looking ahead. The pelvis and legs are untouched.
static func _lean_torso(out: Animation, skeleton: Skeleton3D) -> void:
	var hips_track := _find_rotation_track(out, HIP_BONE)
	if hips_track >= 0:
		_turn_in_place(out, hips_track, _world_axis(skeleton, HIP_BONE, Vector3.RIGHT), deg_to_rad(HIPS_PITCH_DEGREES))
	var spine_step := deg_to_rad(SPINE_LEAN_DEGREES) / float(SPINE_BONES.size())
	var lean_total := HIPS_PITCH_DEGREES + SPINE_LEAN_DEGREES
	var head_step := -deg_to_rad(lean_total) * HEAD_COUNTER / float(HEAD_BONES.size())
	for track in out.get_track_count():
		if out.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := _track_bone(out, track)
		if bone in SPINE_BONES:
			_turn_in_place(out, track, _world_axis(skeleton, bone, Vector3.RIGHT), spine_step)
		elif bone in HEAD_BONES:
			_turn_in_place(out, track, _world_axis(skeleton, bone, Vector3.RIGHT), head_step)


static func _trim_leg_swing(out: Animation) -> void:
	for bone in LEG_BONES:
		var track := _find_rotation_track(out, bone)
		if track < 0:
			continue
		var mean := _mean_rotation(out, track)
		var previous := Quaternion.IDENTITY
		for key in out.track_get_key_count(track):
			var value: Quaternion = out.track_get_key_value(track, key)
			var kept: Quaternion = mean * Quaternion.IDENTITY.slerp(mean.inverse() * value, LEG_KEEP)
			if key > 0 and kept.dot(previous) < 0.0:
				kept = Quaternion(-kept.x, -kept.y, -kept.z, -kept.w)
			out.track_set_key_value(track, key, kept)
			previous = kept


## Rotates the bone's whole chain about a world axis, keeping the rotation in place.
static func _turn_in_place(animation: Animation, track: int, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var turn := Quaternion(axis.normalized(), angle)
	var previous := Quaternion.IDENTITY
	for key in animation.track_get_key_count(track):
		var value: Quaternion = animation.track_get_key_value(track, key)
		var turned: Quaternion = turn * value
		if key > 0 and turned.dot(previous) < 0.0:
			turned = Quaternion(-turned.x, -turned.y, -turned.z, -turned.w)
		animation.track_set_key_value(track, key, turned)
		previous = turned


static func _world_axis(skeleton: Skeleton3D, bone: StringName, world_axis: Vector3) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return world_axis
	var parent := skeleton.get_bone_parent(index)
	if parent < 0:
		return world_axis.normalized()
	return (skeleton.get_bone_global_rest(parent).basis.inverse() * world_axis).normalized()


static func _track_bone(animation: Animation, track: int) -> StringName:
	return StringName(String(animation.track_get_path(track).get_concatenated_subnames()))


static func _find_rotation_track(animation: Animation, bone: StringName) -> int:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D and _track_bone(animation, track) == bone:
			return track
	return -1


static func _mean_rotation(animation: Animation, track: int) -> Quaternion:
	var count := animation.track_get_key_count(track)
	if count == 0:
		return Quaternion.IDENTITY
	var reference: Quaternion = animation.track_get_key_value(track, 0)
	var acc := Vector4.ZERO
	for key in count:
		var value: Quaternion = animation.track_get_key_value(track, key)
		if value.dot(reference) < 0.0:
			value = Quaternion(-value.x, -value.y, -value.z, -value.w)
		acc += Vector4(value.x, value.y, value.z, value.w)
	var mean := Quaternion(acc.x, acc.y, acc.z, acc.w)
	return mean.normalized() if mean.length_squared() > 0.000001 else reference
