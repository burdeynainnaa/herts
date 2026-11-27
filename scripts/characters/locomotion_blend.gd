class_name LocomotionBlend
extends SkeletonModifier3D
## Distance-matched locomotion. A stand pose, walk and run are blended by
## speed, with walk and run on one shared stride phase. The phase advances by
## the distance the body actually travels divided by the stride length, so the
## planted foot moves with the ground at every speed, and the walk and run feet
## stay in step while they blend into a jog.
##
## The shipped idle is a wide, staggered stance with the hips back and the arms
## raised, nothing like the walk, so standing is built from the walk instead:
## the walk's average posture, with only the idle's breathing and sway layered
## on the upper body. Stopping finishes the step: the stride runs on to the
## moment the feet pass each other and settles into the stand from there.

## Metres the body covers in one full walk or run cycle (measured from the
## planted foot of each clip).
@export var walk_stride: float = 1.45
@export var run_stride: float = 3.6
## Cycle fraction by which the run's foot contacts lag the walk's.
@export var run_phase_offset: float = 0.27
## Speeds that bracket the walk-to-run blend.
@export var blend_walk_speed: float = 1.6
@export var blend_run_speed: float = 4.6
## Below this speed the stride fades into the idle.
@export var idle_fade_speed: float = 0.8
## Stepping on the spot while turning: stride metres per radian of turn.
@export var turn_step_distance: float = 0.28
## Seconds the body takes to settle from a stride into the stand.
@export var settle_time: float = 0.35
## Stride cycles per second while finishing the last step of a stop.
@export var settle_cadence: float = 1.1
## Walk phases where the feet pass each other (measured from the clip); a
## stop settles at whichever comes next.
const SETTLE_PHASES: Array[float] = [0.07, 0.55]
## How much of the idle clip's own motion (relative to its average) the stand
## keeps, per body region. The legs keep none: they stand still.
const IDLE_SWAY_TORSO := 1.0
const IDLE_SWAY_ARMS := 0.35
const IDLE_SWAY_HIPS := 0.5

var phase: float = 0.0
## 0 = idle, 1 = full locomotion.
var move_weight: float = 0.0
## 0 = walk, 1 = run.
var run_weight: float = 0.0

var _idle: Animation
var _walk: Animation
var _run: Animation
var _idle_time: float = 0.0
## bone index -> [idle tracks, walk tracks, run tracks]; each [pos, rot, scale].
var _tracks: Dictionary = {}
## bone index -> [walk mean rotation, walk mean position, idle mean rotation,
## idle mean position, idle sway share].
var _stand: Dictionary = {}


func setup(idle: Animation, walk: Animation, run: Animation) -> void:
	_idle = idle
	_walk = walk
	_run = run
	_tracks.clear()
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		_tracks[bone] = [_find_tracks(idle, bone_name), _find_tracks(walk, bone_name), _find_tracks(run, bone_name)]
	_build_stand(skeleton)


func _build_stand(skeleton: Skeleton3D) -> void:
	_stand.clear()
	for bone in _tracks:
		var sets: Array = _tracks[bone]
		var rest := skeleton.get_bone_rest(bone)
		var bone_name := skeleton.get_bone_name(bone)
		var share := 0.0
		if bone_name == "Hips":
			share = IDLE_SWAY_HIPS
		elif bone_name.begins_with("Spine") or bone_name in ["neck", "Head"]:
			share = IDLE_SWAY_TORSO
		elif bone_name.contains("Shoulder") or bone_name.contains("Arm") or bone_name.contains("Hand"):
			share = IDLE_SWAY_ARMS
		_stand[bone] = [
			_mean_rotation(_walk, sets[1], rest.basis.get_rotation_quaternion()),
			_mean_position(_walk, sets[1], rest.origin),
			_mean_rotation(_idle, sets[0], rest.basis.get_rotation_quaternion()),
			_mean_position(_idle, sets[0], rest.origin),
			share,
		]


static func _mean_rotation(animation: Animation, tracks: Array, fallback: Quaternion) -> Quaternion:
	if animation == null or tracks[1] < 0:
		return fallback
	var samples := 48
	var first := animation.rotation_track_interpolate(tracks[1], 0.0)
	var sum := Vector4.ZERO
	for i in samples:
		var q := animation.rotation_track_interpolate(tracks[1], animation.length * i / samples)
		if q.dot(first) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	sum = sum.normalized()
	return Quaternion(sum.x, sum.y, sum.z, sum.w)


static func _mean_position(animation: Animation, tracks: Array, fallback: Vector3) -> Vector3:
	if animation == null or tracks[0] < 0:
		return fallback
	var samples := 48
	var sum := Vector3.ZERO
	for i in samples:
		sum += animation.position_track_interpolate(tracks[0], animation.length * i / samples)
	return sum / samples


## Moves the shared clock. speed is the body's real ground speed; yaw_rate
## (rad/s) makes the feet step while turning on the spot; stopping is true
## once the player has let go of the stick.
func advance(delta: float, speed: float, yaw_rate: float, stopping: bool = false) -> void:
	var turn_speed := absf(yaw_rate) * turn_step_distance
	var effective := maxf(speed, turn_speed)
	var target := smoothstep(0.0, 1.0, clampf(effective / maxf(idle_fade_speed, 0.001), 0.0, 1.0))
	if target >= move_weight:
		move_weight = target
	else:
		# Settle over a fixed time rather than with the speed, so the last
		# step has time to land.
		move_weight = move_toward(move_weight, target, delta / maxf(settle_time, 0.01))
	run_weight = smoothstep(blend_walk_speed, blend_run_speed, speed)
	var stride := lerpf(walk_stride, run_stride, run_weight)
	var step := effective / maxf(stride, 0.01) * delta
	if stopping and move_weight > 0.001:
		var remaining := _phase_to_settle()
		step = minf(maxf(step, settle_cadence * delta), remaining)
	phase = fposmod(phase + step, 1.0)
	if _idle != null:
		_idle_time = fposmod(_idle_time + delta, maxf(_idle.length, 0.01))


## Cycle fraction still to go before the feet next pass each other.
func _phase_to_settle() -> float:
	var best := 1.0
	for target in SETTLE_PHASES:
		var ahead := fposmod(target - phase, 1.0)
		if ahead < 0.004:
			return 0.0
		best = minf(best, ahead)
	return best


## How firmly a foot (0 = left, 1 = right) is planted right now, 0..1. The
## contact windows were measured from the clips: the left heel lands at 0.28
## of the walk cycle and lifts at 0.72; the run's contact is shorter. The
## weight eases in and out so the ground IK can pin the foot without a pop.
func stance_weight(side: int) -> float:
	var start := 0.28 + 0.5 * side
	var length := lerpf(0.44, 0.16, run_weight)
	var t := fposmod(phase - start, 1.0) / length
	if t >= 1.0:
		return 0.0
	return smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.7, 1.0, t)) * move_weight * influence


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _walk == null or _tracks.is_empty():
		return
	var walk_time := phase * _walk.length
	var run_time := fposmod(phase + run_phase_offset, 1.0) * _run.length
	for bone in _tracks:
		var sets: Array = _tracks[bone]
		var rest := skeleton.get_bone_rest(bone)
		var rest_rotation := rest.basis.get_rotation_quaternion()
		var walk_rot := _rotation(_walk, sets[1], walk_time, rest_rotation)
		var run_rot := _rotation(_run, sets[2], run_time, rest_rotation)
		var idle_rot := _stand_rotation(bone, sets[0])
		var moving_rot := walk_rot.slerp(run_rot, run_weight)
		skeleton.set_bone_pose_rotation(bone, idle_rot.slerp(moving_rot, move_weight))
		var walk_pos := _position(_walk, sets[1], walk_time, rest.origin)
		var run_pos := _position(_run, sets[2], run_time, rest.origin)
		var idle_pos := _stand_position(bone, sets[0])
		skeleton.set_bone_pose_position(bone, idle_pos.lerp(walk_pos.lerp(run_pos, run_weight), move_weight))


## The stand: the walk's average rotation, plus the idle clip's motion
## around its own average, scaled per body region.
func _stand_rotation(bone: int, idle_tracks: Array) -> Quaternion:
	var stand: Array = _stand[bone]
	var base: Quaternion = stand[0]
	var share: float = stand[4]
	if share <= 0.0 or _idle == null or idle_tracks[1] < 0:
		return base
	var idle_now := _idle.rotation_track_interpolate(idle_tracks[1], _idle_time)
	var sway: Quaternion = (stand[2] as Quaternion).inverse() * idle_now
	return base * Quaternion.IDENTITY.slerp(sway, share)


func _stand_position(bone: int, idle_tracks: Array) -> Vector3:
	var stand: Array = _stand[bone]
	var base: Vector3 = stand[1]
	var share: float = stand[4]
	if share <= 0.0 or _idle == null or idle_tracks[0] < 0:
		return base
	return base + (_idle.position_track_interpolate(idle_tracks[0], _idle_time) - (stand[3] as Vector3)) * share


static func _find_tracks(animation: Animation, bone_name: String) -> Array:
	var found := [-1, -1, -1]
	if animation == null:
		return found
	for track in animation.get_track_count():
		var path := String(animation.track_get_path(track))
		if not path.ends_with(":" + bone_name):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				found[0] = track
			Animation.TYPE_ROTATION_3D:
				found[1] = track
			Animation.TYPE_SCALE_3D:
				found[2] = track
	return found


static func _rotation(animation: Animation, tracks: Array, time: float, fallback: Quaternion) -> Quaternion:
	if animation == null or tracks[1] < 0:
		return fallback
	return animation.rotation_track_interpolate(tracks[1], time)


static func _position(animation: Animation, tracks: Array, time: float, fallback: Vector3) -> Vector3:
	if animation == null or tracks[0] < 0:
		return fallback
	return animation.position_track_interpolate(tracks[0], time)
