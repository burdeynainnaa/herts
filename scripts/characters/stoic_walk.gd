class_name StoicWalk
extends RefCounted

## Rebuilds a character's Walk clip into a calmer, heavier gait:
## quiet pelvis, restrained arm swing, and a shoulder girdle that counter-rotates
## against the stride. The source clip is never modified.

const OUT_CLIP := &"WalkStoic"

const HIP_BONE := &"Hips"
const CHEST_BONE := &"Spine"
const NECK_BONE := &"neck"

## Source motion each part keeps, 1.0 meaning untouched.
## Hips rotation as (pitch, yaw, roll); translation as (side sway, bob, fore-aft).
const HIP_ROTATION_KEEP := Vector3(0.70, 0.25, 0.35)
const HIP_TRANSLATION_KEEP := Vector3(0.22, 0.80, 0.45)

const SPINE_CHAIN_KEEP := 0.55
const NECK_KEEP := 0.75
const HEAD_KEEP := 0.80
const SHOULDER_KEEP := 0.90
const UPPER_ARM_KEEP := 0.42
const FOREARM_KEEP := 0.45
const HAND_KEEP := 0.40

## Extra shoulder twist, as a fraction of the source pelvis twist.
const CHEST_COUNTER_YAW := 0.50
## How much of that extra twist the neck gives back, so the head stays level.
const NECK_COUNTER_KEEP := 0.45

const YAW_SAMPLES := 240


static func build(skeleton: Skeleton3D, source: Animation) -> Animation:
	var out := source.duplicate(true) as Animation
	if out == null:
		return null
	var hips_track := _find_rotation_track(out, HIP_BONE)
	var hips_mean := Quaternion.IDENTITY
	var hips_yaw := PackedFloat64Array()
	if hips_track >= 0:
		hips_mean = _mean_rotation(out, hips_track)
		hips_yaw = _sample_hips_yaw(out, hips_track, hips_mean)
	var chest_up := _up_axis_local(skeleton, CHEST_BONE)
	var neck_up := _up_axis_local(skeleton, NECK_BONE)
	for track in out.get_track_count():
		var bone := _track_bone(out, track)
		match out.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				var mean := _mean_rotation(out, track)
				var previous := Quaternion.IDENTITY
				for key in out.track_get_key_count(track):
					var time := out.track_get_key_time(track, key)
					var value: Quaternion = out.track_get_key_value(track, key)
					var kept: Quaternion
					if bone == HIP_BONE:
						kept = _keep_delta_axes(value, mean, HIP_ROTATION_KEEP)
					else:
						kept = _keep_delta(value, mean, _rotation_keep(bone))
					var extra_yaw := -CHEST_COUNTER_YAW * _hips_yaw_at(hips_yaw, out, time)
					if bone == CHEST_BONE:
						kept = kept * Quaternion(chest_up, extra_yaw)
					elif bone == NECK_BONE:
						kept = kept * Quaternion(neck_up, -NECK_COUNTER_KEEP * extra_yaw)
					if key > 0 and kept.dot(previous) < 0.0:
						kept = Quaternion(-kept.x, -kept.y, -kept.z, -kept.w)
					out.track_set_key_value(track, key, kept)
					previous = kept
			Animation.TYPE_POSITION_3D:
				if bone != HIP_BONE:
					continue
				var center := _mean_position(out, track)
				for key in out.track_get_key_count(track):
					var value: Vector3 = out.track_get_key_value(track, key)
					var offset := value - center
					var kept := center + Vector3(
						offset.x * HIP_TRANSLATION_KEEP.x,
						offset.y * HIP_TRANSLATION_KEEP.y,
						offset.z * HIP_TRANSLATION_KEEP.z
					)
					out.track_set_key_value(track, key, kept)
	out.loop_mode = Animation.LOOP_LINEAR
	out.resource_name = OUT_CLIP
	return out


static func _rotation_keep(bone: StringName) -> float:
	match bone:
		&"Spine02", &"Spine01", &"Spine":
			return SPINE_CHAIN_KEEP
		&"neck":
			return NECK_KEEP
		&"Head":
			return HEAD_KEEP
		&"LeftShoulder", &"RightShoulder":
			return SHOULDER_KEEP
		&"LeftArm", &"RightArm":
			return UPPER_ARM_KEEP
		&"LeftForeArm", &"RightForeArm":
			return FOREARM_KEEP
		&"LeftHand", &"RightHand":
			return HAND_KEEP
	return 1.0


static func _keep_delta(value: Quaternion, mean: Quaternion, keep: float) -> Quaternion:
	if keep >= 0.999:
		return value
	return mean * Quaternion.IDENTITY.slerp(mean.inverse() * value, keep)


static func _keep_delta_axes(value: Quaternion, mean: Quaternion, keep: Vector3) -> Quaternion:
	var euler := (mean.inverse() * value).get_euler()
	var kept := Quaternion.from_euler(Vector3(euler.x * keep.x, euler.y * keep.y, euler.z * keep.z))
	return mean * kept


static func _up_axis_local(skeleton: Skeleton3D, bone: StringName) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return Vector3.UP
	return (skeleton.get_bone_global_rest(index).basis.inverse() * Vector3.UP).normalized()


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


static func _mean_position(animation: Animation, track: int) -> Vector3:
	var count := animation.track_get_key_count(track)
	if count == 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for key in count:
		sum += animation.track_get_key_value(track, key) as Vector3
	return sum / float(count)


static func _sample_hips_yaw(animation: Animation, track: int, mean: Quaternion) -> PackedFloat64Array:
	var samples := PackedFloat64Array()
	var length := maxf(animation.length, 0.0001)
	for index in YAW_SAMPLES + 1:
		var time := length * float(index) / float(YAW_SAMPLES)
		var value := _sample_rotation(animation, track, time)
		samples.append((mean.inverse() * value).get_euler().y)
	return samples


static func _hips_yaw_at(samples: PackedFloat64Array, animation: Animation, time: float) -> float:
	var count := samples.size()
	if count < 2:
		return 0.0
	var length := maxf(animation.length, 0.0001)
	var x := clampf(time / length, 0.0, 1.0) * float(count - 1)
	var index := int(floor(x))
	if index >= count - 1:
		return samples[count - 1]
	return lerpf(samples[index], samples[index + 1], x - float(index))


static func _sample_rotation(animation: Animation, track: int, time: float) -> Quaternion:
	var count := animation.track_get_key_count(track)
	if count == 0:
		return Quaternion.IDENTITY
	var first_time := animation.track_get_key_time(track, 0)
	var last_time := animation.track_get_key_time(track, count - 1)
	if time <= first_time:
		return animation.track_get_key_value(track, 0)
	if time >= last_time:
		return animation.track_get_key_value(track, count - 1)
	var next := 1
	while next < count and animation.track_get_key_time(track, next) < time:
		next += 1
	var previous := next - 1
	var start_time := animation.track_get_key_time(track, previous)
	var end_time := animation.track_get_key_time(track, next)
	var from: Quaternion = animation.track_get_key_value(track, previous)
	var to: Quaternion = animation.track_get_key_value(track, next)
	if to.dot(from) < 0.0:
		to = Quaternion(-to.x, -to.y, -to.z, -to.w)
	if is_equal_approx(start_time, end_time):
		return from
	return from.slerp(to, clampf((time - start_time) / (end_time - start_time), 0.0, 1.0))
