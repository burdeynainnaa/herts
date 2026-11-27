class_name SabreAttacks
extends RefCounted
## The three sabre blows, keyed by hand in this file and baked into clips for
## whichever skeleton swings them (player and enemy rigs share bone names).
##
## OVERHEAD  a single-arm chop from high behind the head, stepping in.
## SPIN      a full turn on the spot that ends in a wide horizontal sweep;
##           it cuts everything around the fighter.
## THRUST    a deep lunge, front knee bent, back leg long, point first.
##
## Keys are written as poses a person can read: where each arm segment and the
## blade point (and the axis the blade swings about, which sets the edge), how
## far the hips drop, how the spine bends and turns, where each foot stands. Directions are in body space, Vector3(right, up, forward); feet
## are offsets in metres from where they stand in the idle pose. Baking aims
## the bones at those directions and solves the legs so the feet stay put.

const OVERHEAD := &"SabreOverhead"
const SPIN := &"SabreSpin"
const THRUST := &"SabreThrust"
const ALL: Array[StringName] = [OVERHEAD, SPIN, THRUST]

## Gameplay data per blow. Times are clip seconds:
## raised   the blade is cocked (enemies telegraph until here)
## hit      the window in which the blade can strike
## settled  the blow is spent; the fighter may act again
## end      the clip is back at the ready stance
## lunge    when the body is carried forward, and how fast (m/s)
## spin     when the whole body turns once round (SPIN only)
const DATA := {
	OVERHEAD: {
		"raised": 0.38, "hit_start": 0.5, "hit_end": 0.64, "settled": 0.95, "end": 1.25,
		"damage": 1.35, "reach": 2.5, "arc": 45.0, "stamina": 1.2,
		"lunge_start": 0.42, "lunge_end": 0.6, "lunge_speed": 2.4,
		"dust_at": 0.6, "trail_start": 0.46, "trail_end": 0.68,
	},
	SPIN: {
		"raised": 0.3, "hit_start": 0.4, "hit_end": 0.88, "settled": 1.1, "end": 1.45,
		"damage": 0.9, "reach": 2.7, "arc": 180.0, "stamina": 1.4,
		"lunge_start": 0.3, "lunge_end": 0.85, "lunge_speed": 1.0,
		"spin_start": 0.3, "spin_end": 0.74, "dust_at": 0.5, "trail_start": 0.36, "trail_end": 0.9,
	},
	THRUST: {
		"raised": 0.22, "hit_start": 0.3, "hit_end": 0.44, "settled": 0.8, "end": 1.15,
		"damage": 1.15, "reach": 3.2, "arc": 25.0, "stamina": 1.0,
		"lunge_start": 0.22, "lunge_end": 0.38, "lunge_speed": 5.5,
		"dust_at": 0.36, "trail_start": 0.26, "trail_end": 0.46,
	},
}


static func data(clip: StringName) -> Dictionary:
	return DATA.get(clip, DATA[OVERHEAD])


# --- The poses ----------------------------------------------------------------

## Swing axes (body space) for "r_swing": the blade turns about this axis, and
## the cutting edge faces the way the blade travels.
const _DOWNWARD := Vector3(1.0, 0.0, 0.0)  # over the top and down the front
const _ACROSS := Vector3(0.0, -1.0, 0.0)  # flat, from the right across to the left

## The stand the blows start from and settle into: both arms hanging easy,
## sabre held low with the point forward and down, as in the idle.
static func _rest_pose() -> Dictionary:
	return {
		"r_arm": Vector3(0.24, -1.0, 0.05), "r_fore": Vector3(0.05, -0.9, 0.4),
		"r_hand": Vector3(0.17, -0.54, 0.83), "r_swing": _DOWNWARD,
		"l_arm": Vector3(-0.24, -1.0, 0.02), "l_fore": Vector3(-0.03, -1.0, 0.12),
	}


## Every blow follows the same order of effort: hips start the move, the
## chest follows, the arm comes last and the blade lags behind the hand. The
## head counter-turns to keep the eyes on the target, and the free arm stays
## bent and close, working against the sword arm for balance.
static func _keys(clip: StringName) -> Array:
	var rest := _rest_pose()
	match clip:
		OVERHEAD:
			return [
				[0.0, rest],
				# Lift: sword hand rises in front, the point coming up first...
				[0.14, {
					"hips": {"drop": 0.03, "turn": 8.0},
					"spine": {"bend": -3.0, "turn": 10.0},
					"head": {"turn": -10.0},
					"r_arm": Vector3(0.45, -0.1, 0.6), "r_fore": Vector3(0.05, 0.8, 0.55),
					"r_hand": Vector3(0.0, 0.95, 0.3), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.15, -0.5, 0.8), "l_fore": Vector3(0.1, -0.15, 1.0),
					"r_foot": Vector3(0.0, 0.0, -0.06),
				}],
				# ...then laid back over the shoulder as the elbow climbs.
				[0.27, {
					"hips": {"drop": 0.04, "turn": 15.0, "bend": -3.0},
					"spine": {"bend": -9.0, "turn": 17.0},
					"head": {"turn": -18.0, "bend": 4.0},
					"r_arm": Vector3(0.45, 0.6, 0.2), "r_fore": Vector3(0.0, 0.85, -0.35),
					"r_hand": Vector3(0.0, 0.35, -0.95), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.12, -0.3, 0.95), "l_fore": Vector3(0.08, 0.05, 1.0),
					"r_foot": Vector3(0.01, 0.0, -0.1), "l_foot": Vector3(0.0, 0.01, 0.02),
				}],
				# Cocked: elbow high, hand behind the head, blade down the back.
				[0.38, {
					"hips": {"drop": 0.04, "turn": 18.0, "bend": -6.0},
					"spine": {"bend": -12.0, "turn": 20.0},
					"head": {"turn": -22.0, "bend": 8.0},
					"r_arm": Vector3(0.4, 0.85, -0.05), "r_fore": Vector3(-0.05, 0.55, -0.8),
					"r_hand": Vector3(0.0, -0.55, -0.85), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.1, -0.2, 1.0), "l_fore": Vector3(0.05, 0.2, 1.0),
					"r_foot": Vector3(0.02, 0.0, -0.12), "l_foot": Vector3(0.0, 0.02, 0.04),
				}],
				# Driving up out of the cock: elbow leads, blade comes up past vertical.
				[0.45, {
					"hips": {"drop": 0.05, "turn": 12.0, "bend": -2.0},
					"spine": {"bend": -6.0, "turn": 12.0},
					"head": {"turn": -14.0, "bend": 4.0},
					"r_arm": Vector3(0.35, 0.95, 0.1), "r_fore": Vector3(0.0, 0.85, -0.3),
					"r_hand": Vector3(0.0, 0.95, -0.3), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.18, -0.4, 0.8), "l_fore": Vector3(-0.02, -0.15, 0.9),
					"r_foot": Vector3(0.02, 0.0, -0.13), "l_foot": Vector3(-0.01, 0.01, 0.16),
				}],
				# Over the top as the front foot steps in; the guard hand pulls back.
				[0.5, {
					"hips": {"drop": 0.08, "turn": 6.0, "bend": 4.0},
					"spine": {"bend": 4.0, "turn": 4.0},
					"head": {"turn": -6.0},
					"r_arm": Vector3(0.25, 0.95, 0.3), "r_fore": Vector3(0.05, 0.85, 0.5),
					"r_hand": Vector3(0.0, 0.55, 0.85), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.25, -0.6, 0.5), "l_fore": Vector3(-0.1, -0.5, 0.6),
					"r_foot": Vector3(0.02, 0.0, -0.15), "l_foot": Vector3(-0.02, 0.0, 0.3),
				}],
				[0.57, {
					"hips": {"drop": 0.15, "turn": -8.0, "bend": 10.0},
					"spine": {"bend": 16.0, "turn": -10.0},
					"head": {"bend": -10.0, "turn": 8.0},
					"r_arm": Vector3(0.15, 0.3, 1.0), "r_fore": Vector3(0.05, -0.2, 1.0),
					"r_hand": Vector3(0.0, -0.45, 1.0), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.4, -0.7, -0.3), "l_fore": Vector3(-0.15, -0.7, -0.4),
					"r_foot": Vector3(0.03, 0.0, -0.18), "l_foot": Vector3(-0.03, 0.0, 0.38),
				}],
				# Cut through: weight on the front foot, blade low in front.
				[0.64, {
					"hips": {"drop": 0.18, "turn": -10.0, "bend": 14.0},
					"spine": {"bend": 24.0, "turn": -10.0},
					"head": {"bend": -18.0, "turn": 10.0},
					"r_arm": Vector3(0.2, -0.35, 0.95), "r_fore": Vector3(0.05, -0.75, 0.7),
					"r_hand": Vector3(0.0, -0.95, 0.35), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.45, -0.75, -0.4), "l_fore": Vector3(-0.2, -0.6, -0.6),
					"r_foot": Vector3(0.03, 0.0, -0.18), "l_foot": Vector3(-0.03, 0.0, 0.38),
				}],
				[0.82, {
					"hips": {"drop": 0.12, "turn": -5.0, "bend": 8.0},
					"spine": {"bend": 12.0, "turn": -5.0},
					"head": {"bend": -8.0, "turn": 5.0},
					"r_arm": Vector3(0.25, -0.75, 0.6), "r_fore": Vector3(0.05, -0.5, 0.85),
					"r_hand": Vector3(0.05, -0.55, 0.85), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.3, -0.95, -0.1), "l_fore": Vector3(-0.1, -0.9, 0.2),
					"r_foot": Vector3(0.03, 0.0, -0.12), "l_foot": Vector3(-0.03, 0.0, 0.28),
				}],
				[1.25, rest],
			]
		SPIN:
			return [
				[0.0, rest],
				# Wind against the turn: hips and chest twisted right, blade trailing low.
				[0.22, {
					"hips": {"drop": 0.1, "turn": 35.0},
					"spine": {"bend": 6.0, "turn": 30.0},
					"head": {"turn": -45.0},
					"r_arm": Vector3(0.7, -0.3, -0.55), "r_fore": Vector3(0.55, -0.1, -0.8),
					"r_hand": Vector3(0.3, -0.1, -0.95), "r_swing": _ACROSS,
					"l_arm": Vector3(0.25, -0.4, 0.85), "l_fore": Vector3(0.7, -0.1, 0.6),
					"r_foot": Vector3(0.05, 0.0, -0.05), "l_foot": Vector3(-0.05, 0.0, 0.05),
				}],
				# Turning on the spot: sword arm long at chest height, blade trailing,
				# body leaning away from it; the free arm stays bent and tucked.
				[0.4, {
					"hips": {"drop": 0.1},
					"spine": {"bend": 4.0, "turn": 6.0, "tilt": -6.0},
					"head": {"turn": -10.0},
					"r_arm": Vector3(0.95, -0.15, 0.05), "r_fore": Vector3(0.95, -0.05, -0.1),
					"r_hand": Vector3(0.85, 0.0, -0.5), "r_swing": _ACROSS,
					"l_arm": Vector3(-0.6, -0.6, 0.35), "l_fore": Vector3(-0.3, -0.4, 0.8),
				}],
				[0.6, {
					"hips": {"drop": 0.1},
					"spine": {"bend": 4.0, "turn": 4.0, "tilt": -8.0},
					"head": {"turn": -8.0},
					"r_arm": Vector3(0.95, -0.1, 0.2), "r_fore": Vector3(0.95, 0.0, 0.1),
					"r_hand": Vector3(0.95, 0.0, -0.25), "r_swing": _ACROSS,
					"l_arm": Vector3(-0.6, -0.6, 0.3), "l_fore": Vector3(-0.3, -0.4, 0.8),
				}],
				# The turn comes round and the blade sweeps across the front.
				[0.74, {
					"hips": {"drop": 0.12, "turn": -12.0},
					"spine": {"bend": 6.0, "turn": -15.0},
					"head": {"turn": 5.0},
					"r_arm": Vector3(0.55, -0.05, 0.85), "r_fore": Vector3(0.2, 0.0, 1.0),
					"r_hand": Vector3(0.25, 0.0, 0.97), "r_swing": _ACROSS,
					"l_arm": Vector3(-0.6, -0.65, -0.1), "l_fore": Vector3(-0.4, -0.5, -0.6),
				}],
				[0.86, {
					"hips": {"drop": 0.12, "turn": -30.0},
					"spine": {"bend": 8.0, "turn": -32.0},
					"head": {"turn": 30.0},
					"r_arm": Vector3(-0.3, -0.15, 0.95), "r_fore": Vector3(-0.85, -0.05, 0.5),
					"r_hand": Vector3(-0.95, -0.05, 0.15), "r_swing": _ACROSS,
					"l_arm": Vector3(-0.55, -0.8, -0.25), "l_fore": Vector3(-0.3, -0.6, -0.6),
					"r_foot": Vector3(0.04, 0.0, 0.04), "l_foot": Vector3(-0.04, 0.0, -0.04),
				}],
				[1.05, {
					"hips": {"drop": 0.08, "turn": -15.0},
					"spine": {"bend": 6.0, "turn": -18.0},
					"head": {"turn": 15.0},
					"r_arm": Vector3(0.0, -0.75, 0.65), "r_fore": Vector3(-0.3, -0.55, 0.75),
					"r_hand": Vector3(-0.3, -0.45, 0.85), "r_swing": _ACROSS,
					"l_arm": Vector3(-0.3, -0.95, -0.1), "l_fore": Vector3(-0.1, -0.9, 0.2),
				}],
				[1.45, rest],
			]
		THRUST:
			return [
				[0.0, rest],
				# Coil: weight back, sword hand drawn to the hip with the point on
				# the target, free hand reaching out to aim.
				[0.22, {
					"hips": {"drop": 0.1, "turn": 25.0, "bend": -2.0},
					"spine": {"turn": 15.0},
					"head": {"turn": -35.0},
					"r_arm": Vector3(0.35, -0.55, -0.75), "r_fore": Vector3(0.1, 0.05, 1.0),
					"r_hand": Vector3(0.0, 0.05, 1.0), "r_edge": Vector3(0.0, -1.0, 0.0),
					"l_arm": Vector3(-0.1, -0.1, 1.0), "l_fore": Vector3(0.0, 0.2, 1.0),
					"r_foot": Vector3(0.04, 0.0, 0.02), "l_foot": Vector3(-0.02, 0.0, -0.15),
				}],
				# Full lunge: front knee deep, back leg long, free arm swept back.
				[0.36, {
					"hips": {"drop": 0.28, "shift": Vector3(0.0, 0.0, 0.18), "turn": -25.0, "bend": 8.0},
					"spine": {"bend": 8.0, "turn": -15.0},
					"head": {"turn": 35.0, "bend": -6.0},
					"r_arm": Vector3(0.0, 0.06, 1.0), "r_fore": Vector3(0.0, 0.04, 1.0),
					"r_hand": Vector3(0.0, 0.02, 1.0), "r_edge": Vector3(0.0, -1.0, 0.0),
					"l_arm": Vector3(-0.45, -0.2, -0.85), "l_fore": Vector3(-0.2, 0.35, -0.9),
					"r_foot": Vector3(0.06, 0.0, 0.68), "l_foot": Vector3(-0.08, 0.0, -0.38),
				}],
				[0.55, {
					"hips": {"drop": 0.26, "shift": Vector3(0.0, 0.0, 0.16), "turn": -22.0, "bend": 6.0},
					"spine": {"bend": 6.0, "turn": -13.0},
					"head": {"turn": 32.0, "bend": -5.0},
					"r_arm": Vector3(0.05, 0.0, 1.0), "r_fore": Vector3(0.02, 0.0, 1.0),
					"r_hand": Vector3(0.02, -0.02, 1.0), "r_edge": Vector3(0.0, -1.0, 0.0),
					"l_arm": Vector3(-0.45, -0.25, -0.85), "l_fore": Vector3(-0.25, 0.0, -0.95),
					"r_foot": Vector3(0.06, 0.0, 0.68), "l_foot": Vector3(-0.08, 0.0, -0.38),
				}],
				[0.8, {
					"hips": {"drop": 0.12, "shift": Vector3(0.0, 0.0, 0.06), "turn": -6.0, "bend": 3.0},
					"spine": {"bend": 4.0, "turn": -5.0},
					"head": {"turn": 8.0},
					"r_arm": Vector3(0.25, -0.6, 0.75), "r_fore": Vector3(0.05, -0.3, 0.95),
					"r_hand": Vector3(0.1, -0.4, 0.9), "r_swing": _DOWNWARD,
					"l_arm": Vector3(-0.3, -0.95, -0.05), "l_fore": Vector3(-0.05, -0.9, 0.3),
					"r_foot": Vector3(0.05, 0.0, 0.32), "l_foot": Vector3(-0.05, 0.0, -0.15),
				}],
				[1.15, rest],
			]
	return []


# --- Baking -----------------------------------------------------------------------

## Adds the three clips to the player's default library, built for the given
## skeleton. Imported libraries are shared by every instance of a rig, so this
## bakes once per rig. body is the node whose -Z is the fighter's forward;
## grip is the sabre's basis in hand-bone space, so the keys aim the blade
## itself, whatever way the hand holds it.
static func install(player: AnimationPlayer, skeleton: Skeleton3D, body: Node3D, idle_clip: StringName,
		grip: Basis) -> bool:
	var library := player.get_animation_library(&"")
	if library == null:
		push_error("SabreAttacks: AnimationPlayer has no default library")
		return false
	if library.has_animation(OVERHEAD):
		return true
	var idle := player.get_animation(idle_clip)
	if idle == null:
		push_error("SabreAttacks: no idle clip %s to stand in" % idle_clip)
		return false
	var baker := _Baker.new(skeleton, body, idle, grip)
	if not baker.ok:
		return false
	for clip in ALL:
		library.add_animation(clip, baker.bake(_keys(clip), data(clip)["end"]))
	baker.restore()
	return true


class _Baker:
	extends RefCounted

	const SPINE := ["Spine02", "Spine01", "Spine"]
	const BONES := [
		"Hips", "Spine02", "Spine01", "Spine", "neck", "Head",
		"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
	]

	var ok := false
	var _skeleton: Skeleton3D
	var _track_prefix: String
	## Body space (Godot axes: +X right, +Y up, -Z forward) into skeleton space.
	var _to_skeleton: Basis
	var _body_rotation: Basis
	var _bone := {}
	var _base_rotation := {}
	var _base_position := {}
	var _base_global := {}
	var _bend_reference := {}
	## Blade and cutting edge in RightHand bone space (Sabre: blade +Y, edge -Z).
	var _blade_axis := Vector3.UP
	var _edge_axis := Vector3.FORWARD

	func _init(skeleton: Skeleton3D, body: Node3D, idle: Animation, grip: Basis) -> void:
		_skeleton = skeleton
		_blade_axis = (grip * Vector3.UP).normalized()
		_edge_axis = (grip * Vector3.FORWARD).normalized()
		for name in BONES:
			var index := skeleton.find_bone(name)
			if index < 0:
				push_error("SabreAttacks: skeleton has no bone %s" % name)
				return
			_bone[name] = index
		for track in idle.get_track_count():
			var path := String(idle.track_get_path(track))
			if ":" in path:
				_track_prefix = path.get_slice(":", 0)
				break
		if _track_prefix.is_empty():
			push_error("SabreAttacks: idle clip has no bone tracks")
			return
		_to_skeleton = skeleton.global_basis.inverse() * body.global_basis.orthonormalized()
		_body_rotation = _to_skeleton.orthonormalized()
		_sample_base(idle)
		ok = true

	## The idle pose at its first frame is the base every key is built on.
	func _sample_base(idle: Animation) -> void:
		for index in _skeleton.get_bone_count():
			_base_rotation[index] = _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			_base_position[index] = _skeleton.get_bone_rest(index).origin
		for track in idle.get_track_count():
			var path := idle.track_get_path(track)
			var index := _skeleton.find_bone(path.get_concatenated_subnames())
			if index < 0:
				continue
			match idle.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					_base_rotation[index] = idle.rotation_track_interpolate(track, 0.0)
				Animation.TYPE_POSITION_3D:
					_base_position[index] = idle.position_track_interpolate(track, 0.0)
		_apply_base()
		for name in BONES:
			_base_global[name] = _skeleton.get_bone_global_pose(_bone[name])
		# Which way each upper arm's elbow bends in the idle pose, in the bone's
		# own frame, so raised arms keep the elbow hinge the right way round.
		var forward := _dir(Vector3(0.0, 0.0, 1.0))
		for pair in [["RightArm", "RightForeArm"], ["LeftArm", "LeftForeArm"]]:
			var upper: Transform3D = _base_global[pair[0]]
			var lower: Transform3D = _base_global[pair[1]]
			var bend := _perpendicular(lower.basis.y.normalized(), upper.basis.y.normalized())
			if bend.length_squared() < 0.01:
				bend = _perpendicular(forward, upper.basis.y.normalized())
			_bend_reference[pair[0]] = upper.basis.inverse() * bend.normalized()

	func restore() -> void:
		_apply_base()

	func bake(keys: Array, length: float) -> Animation:
		var animation := Animation.new()
		animation.length = length
		animation.loop_mode = Animation.LOOP_NONE
		var rotation_tracks := {}
		for name in BONES:
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath("%s:%s" % [_track_prefix, name]))
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
			rotation_tracks[name] = track
		var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(hips_track, NodePath("%s:Hips" % _track_prefix))
		animation.track_set_interpolation_type(hips_track, Animation.INTERPOLATION_CUBIC)
		for key in keys:
			_pose(key[1])
			for name in BONES:
				animation.rotation_track_insert_key(rotation_tracks[name], key[0], _skeleton.get_bone_pose_rotation(_bone[name]))
			animation.position_track_insert_key(hips_track, key[0], _skeleton.get_bone_pose_position(_bone["Hips"]))
		return animation

	func _apply_base() -> void:
		for index in _skeleton.get_bone_count():
			_skeleton.set_bone_pose_rotation(index, _base_rotation[index])
			_skeleton.set_bone_pose_position(index, _base_position[index])
			_skeleton.set_bone_pose_scale(index, Vector3.ONE)

	func _pose(spec: Dictionary) -> void:
		_apply_base()
		var hips: Dictionary = spec.get("hips", {})
		var hips_pose := _global("Hips")
		hips_pose.origin += _offset(Vector3(0.0, -float(hips.get("drop", 0.0)), 0.0) + hips.get("shift", Vector3.ZERO))
		hips_pose.basis = _turn(hips) * hips_pose.basis
		_set_global("Hips", hips_pose)
		var spine: Dictionary = spec.get("spine", {})
		var share := {}
		for axis in spine:
			share[axis] = float(spine[axis]) / SPINE.size()
		for name in SPINE:
			_rotate(name, share)
		if spec.has("head"):
			_rotate("neck", spec["head"])
		for side in ["r", "l"]:
			var prefix := "Right" if side == "r" else "Left"
			_aim_arm(prefix, spec.get(side + "_arm"), spec.get(side + "_fore"))
			if spec.has(side + "_hand"):
				var edge = spec.get(side + "_edge")
				if edge == null and spec.has(side + "_swing"):
					# The edge leads: it faces the way the blade turns about the swing axis.
					edge = (spec[side + "_swing"] as Vector3).cross((spec[side + "_hand"] as Vector3).normalized())
				_aim(prefix + "Hand", _dir(spec[side + "_hand"]), _edge_axis, _dir(edge) if edge != null else Vector3.ZERO, _blade_axis)
		for side in ["r", "l"]:
			var prefix := "Right" if side == "r" else "Left"
			_place_leg(prefix, spec.get(side + "_foot", Vector3.ZERO))

	# Body-space helpers ---------------------------------------------------------

	func _dir(body: Vector3) -> Vector3:
		return (_body_rotation * Vector3(body.x, body.y, -body.z)).normalized()

	func _offset(body_metres: Vector3) -> Vector3:
		return _to_skeleton * Vector3(body_metres.x, body_metres.y, -body_metres.z)

	## turn: toward the right; bend: forward; tilt: top toward the right. Degrees.
	func _turn(angles: Dictionary) -> Basis:
		var body := Basis(Vector3.UP, deg_to_rad(-float(angles.get("turn", 0.0))))
		body *= Basis(Vector3.RIGHT, deg_to_rad(-float(angles.get("bend", 0.0))))
		body *= Basis(Vector3.BACK, deg_to_rad(-float(angles.get("tilt", 0.0))))
		return _body_rotation * body * _body_rotation.inverse()

	func _global(name: String) -> Transform3D:
		return _skeleton.get_bone_global_pose(_bone[name])

	func _set_global(name: String, pose: Transform3D) -> void:
		_skeleton.set_bone_global_pose(_bone[name], pose)
		_skeleton.force_update_bone_child_transform(_bone[name])

	func _rotate(name: String, angles: Dictionary) -> void:
		var pose := _global(name)
		pose.basis = _turn(angles) * pose.basis
		_set_global(name, pose)

	## Points a bone's local axis (+Y, toward its child, unless given) along
	## direction. When reference and pole are given, also rolls the bone about
	## that axis so its local reference axis faces the pole.
	func _aim(name: String, direction: Vector3, reference := Vector3.ZERO, pole := Vector3.ZERO,
			axis := Vector3.UP) -> void:
		var pose := _global(name)
		var along := (pose.basis * axis).normalized()
		var basis := pose.basis
		if along.dot(direction) < -0.999:
			var across := _perpendicular(pose.basis.x.normalized(), along)
			if across.length_squared() < 0.01:
				across = _perpendicular(pose.basis.z.normalized(), along)
			basis = Basis(across.normalized(), PI) * basis
		else:
			basis = Basis(Quaternion(along, direction)) * basis
		if reference != Vector3.ZERO and pole != Vector3.ZERO:
			var have := _perpendicular((basis * reference).normalized(), direction)
			var want := _perpendicular(pole, direction)
			if have.length_squared() > 0.0001 and want.length_squared() > 0.0001:
				basis = Basis(direction, have.signed_angle_to(want, direction)) * basis
		pose.basis = basis.orthonormalized()
		_set_global(name, pose)

	func _aim_arm(prefix: String, upper, lower) -> void:
		if upper == null:
			return
		var upper_dir := _dir(upper)
		var bend := Vector3.ZERO
		if lower != null:
			bend = _perpendicular(_dir(lower), upper_dir)
		if bend.length_squared() > 0.01:
			_aim(prefix + "Arm", upper_dir, _bend_reference[prefix + "Arm"], bend)
		else:
			_aim(prefix + "Arm", upper_dir)
		if lower != null:
			_aim(prefix + "ForeArm", _dir(lower))

	## Two-bone leg: puts the ankle at its idle spot plus the offset, knee
	## toward the toes, foot flat and pointing where it pointed in idle.
	func _place_leg(prefix: String, foot_offset: Vector3) -> void:
		var upper := prefix + "UpLeg"
		var lower := prefix + "Leg"
		var foot := prefix + "Foot"
		var base_foot: Transform3D = _base_global[foot]
		var target := base_foot.origin + _offset(foot_offset)
		var hip := _global(upper).origin
		var thigh := (_skeleton.get_bone_rest(_bone[lower]).origin).length()
		var shin := (_skeleton.get_bone_rest(_bone[foot]).origin).length()
		var to_target := target - hip
		var reach := clampf(to_target.length(), 0.05, (thigh + shin) * 0.999)
		var axis := to_target.normalized()
		var side := 1.0 if prefix == "Right" else -1.0
		var pole := _perpendicular(_dir(Vector3(0.12 * side, 0.0, 1.0)), axis).normalized()
		var cos_hip := clampf((thigh * thigh + reach * reach - shin * shin) / (2.0 * thigh * reach), -1.0, 1.0)
		var knee := hip + axis * thigh * cos_hip + pole * thigh * sqrt(1.0 - cos_hip * cos_hip)
		var ankle := hip + axis * reach
		var forward := _dir(Vector3(0.0, 0.0, 1.0))
		var thigh_reference: Basis = (_base_global[upper] as Transform3D).basis
		var shin_reference: Basis = (_base_global[lower] as Transform3D).basis
		_aim(upper, (knee - hip).normalized(), thigh_reference.inverse() * forward, pole)
		_aim(lower, (ankle - knee).normalized(), shin_reference.inverse() * forward, pole)
		var pose := _global(foot)
		pose.basis = base_foot.basis
		_set_global(foot, pose)

	static func _perpendicular(vector: Vector3, axis: Vector3) -> Vector3:
		return vector - axis * vector.dot(axis)
