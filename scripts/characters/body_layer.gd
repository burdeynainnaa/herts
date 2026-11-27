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

var _chain: PackedInt32Array = []
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
