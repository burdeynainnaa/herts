class_name SummerThirdPersonController
extends CharacterBody3D

const REQUIRED_ROLES: Array[StringName] = [&"idle", &"walk", &"run", &"jump"]
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"sprint", &"ui_cancel", &"mount_horse"
]

@export_file("*.json") var character_manifest_path: String

@export_category("Movement")
@export var walk_speed: float = 1.45
@export var run_speed: float = 6.0
@export var jump_velocity: float = 3.8
@export var floor_snap_distance: float = 0.3

## Weighted locomotion: the body only moves the way it faces, the heading turns
## at a limited rate that narrows with speed, and speed builds and bleeds off
## over time, so a running Cossack carries momentum, arcs through turns and has
## to plant and pivot to reverse.
@export_category("Momentum")
@export var walk_acceleration: float = 4.2
@export var run_acceleration: float = 5.2
@export var stop_deceleration: float = 9.0
@export var slowdown_deceleration: float = 5.6
## Braking used when the input points well behind a running body.
@export var pivot_deceleration: float = 14.0
## Heading turn rate in degrees per second while standing and at full run.
@export var turn_rate_standing: float = 260.0
@export var turn_rate_running: float = 150.0
## How fast the turn itself builds up and brakes, degrees per second squared,
## standing and at full run. Lower values make turns rounder and heavier.
@export var turn_acceleration_standing: float = 1100.0
@export var turn_acceleration_running: float = 520.0
## Input this far behind the heading (degrees) while above walk speed plants the feet.
@export var pivot_angle: float = 115.0
@export var air_control: float = 0.12
@export_range(0.0, 1.0) var uphill_penalty: float = 0.9
@export_range(0.0, 1.0) var downhill_bonus: float = 0.25

@export_category("Landing")
@export var soft_landing_speed: float = 4.0
@export var hard_landing_speed: float = 7.0
@export var hard_landing_recovery: float = 0.5

@export_category("Body Lean")
@export var max_turn_lean_degrees: float = 7.0
@export var turn_lean_gain: float = 0.008
## Torso (spine) lean against changes in speed and into slopes.
@export var max_torso_lean_degrees: float = 9.0
@export var torso_accel_gain: float = 0.02
@export var torso_slope_gain: float = 0.35
## Lean springs: stiffness and damping ratio (below 1 overshoots and settles).
@export var lean_stiffness: float = 70.0
@export_range(0.05, 2.0) var lean_damping_ratio: float = 0.5

@export_category("Procedural Body")
@export var procedural_body: bool = true
## The camera direction the head follows, up to this angle from the body;
## BodyLayer splits it into head turn first, then a little torso turn.
@export var head_look_max_yaw_degrees: float = 105.0
## Small idle fidgets while standing still: adjusting the hat, shifting from
## foot to foot, glancing about. Seconds between them, min and max.
@export var idle_fidgets: bool = true
@export var fidget_interval: Vector2 = Vector2(4.0, 9.0)
## Landing compression: metres of pelvis dip per m/s of fall speed.
@export var landing_dip_per_speed: float = 0.25
@export var exertion_gain_per_second: float = 0.08
@export var exertion_recovery_per_second: float = 0.04
@export var floor_stick_velocity: float = 0.5
@export var animation_blend_time: float = 0.25
@export var relax_idle_right_arm: bool = false
@export var character_tint: Color = Color.WHITE
@export_file("*.tres") var walk_animation_override: String = "res://assets/models/herts_cossack_reference/walk_stoic.tres"
@export_file("*.tres") var run_animation_override: String = "res://assets/models/herts_cossack_reference/run_sprint.tres"

const WALK_OVERRIDE_CLIP: StringName = &"WalkStoic"
const RUN_OVERRIDE_CLIP: StringName = &"RunSprint"

@export_category("Animation Sync")
@export var walk_clip_ground_speed: float = 1.45
@export var run_clip_ground_speed: float = 6.0
@export var min_animation_speed: float = 0.6
@export var max_animation_speed: float = 1.5

@export_category("Riding")
@export var ride_seat_height: float = 0.455
@export var ride_seat_forward: float = 0.0

@export_category("Camera")
@export var mouse_sensitivity: float = 0.002
@export var camera_height: float = 1.25
@export var camera_distance: float = 2.9
@export var camera_shoulder_offset: float = 0.8
@export var camera_follow_speed: float = 10.0
@export_flags_3d_physics var camera_collision_mask: int = 1
@export var camera_pitch_degrees: float = -10.0

@export_category("Respawn")
@export var respawn_below_y: float = -15.0

@export_category("Required Nodes")
@export_node_path("Node3D") var visual_root_path: NodePath = ^"CharacterRotationRoot"
@export_node_path("Node3D") var camera_yaw_path: NodePath = ^"CameraYaw"
@export_node_path("Node3D") var camera_pitch_path: NodePath = ^"CameraYaw/CameraPitch"
@export_node_path("SpringArm3D") var spring_arm_path: NodePath = ^"CameraYaw/CameraPitch/SpringArm3D"
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"CharacterRotationRoot/Character/Visual/AnimationPlayer"
@export_node_path("Skeleton3D") var skeleton_path: NodePath = ^"CharacterRotationRoot/Character/Visual/Armature/Skeleton3D"

@onready var _visual_root: Node3D = get_node_or_null(visual_root_path) as Node3D
@onready var _camera_yaw: Node3D = get_node_or_null(camera_yaw_path) as Node3D
@onready var _camera_pitch: Node3D = get_node_or_null(camera_pitch_path) as Node3D
@onready var _spring_arm: SpringArm3D = get_node_or_null(spring_arm_path) as SpringArm3D
@onready var _animation_player: AnimationPlayer = get_node_or_null(animation_player_path) as AnimationPlayer

var _gravity: float = 0.0
var _spawn_position: Vector3
var _clips_by_role: Dictionary = {}
var _active_role: StringName = &""
var _idle_arm_modifier: SkeletonModifier3D
var _riding_modifier: SkeletonModifier3D
var _horse: CharacterBody3D
var _mounted: bool = false
var _normal_collision_layer: int
var _normal_collision_mask: int
var _combat: Node
var _ground_speed: float = 0.0
var _yaw_rate: float = 0.0
var _pivoting: bool = false
var _landing_recovery: float = 0.0
var _peak_fall_speed: float = 0.0
var _lean_roll: float = 0.0
var _lean_roll_velocity: float = 0.0
var _torso_lean: float = 0.0
var _torso_lean_velocity: float = 0.0
var _slope_grade: float = 0.0
var _move_speed: float = 0.0
var _dip: float = 0.0
var _dip_velocity: float = 0.0
var _fidget: StringName = &""
var _fidget_time: float = 0.0
var _fidget_length: float = 1.0
var _fidget_timer: float = 5.0
var _fidget_side: float = 1.0
var _last_fidget: StringName = &""
## Per fidget channel: (value, velocity) of its spring.
var _fidget_state: Dictionary = {}
## Spring (natural frequency rad/s, damping ratio) for each fidget channel.
## Every channel gets a soft start and a soft stop; the heavier the moving
## part, the lower the frequency. Ratios below 1 let light parts overshoot a
## touch, the hand at the hat is critically damped so it never pushes through.
const FIDGET_SPRINGS := {
	&"hat": Vector2(5.5, 1.0),
	&"tug": Vector2(16.0, 0.55),
	&"dip": Vector2(6.0, 0.9),
	&"shift": Vector2(4.0, 0.8),
	&"lift_left": Vector2(10.0, 0.7),
	&"lift_right": Vector2(10.0, 0.7),
	&"glance": Vector2(7.0, 0.8),
}
var _locomotion: LocomotionBlend
var _body_layer: BodyLayer
var _ground_ik: GroundIK


func _ready() -> void:
	process_priority = 50
	if not _validate_scene_contract() or not _configure_character_animation():
		return
	var character_mesh := get_node_or_null("CharacterRotationRoot/Character/Visual/Armature/Skeleton3D/char1") as MeshInstance3D
	if character_mesh != null and character_mesh.mesh != null:
		var original_material := character_mesh.mesh.surface_get_material(0) as StandardMaterial3D
		if original_material != null:
			var tinted_material := original_material.duplicate() as StandardMaterial3D
			tinted_material.albedo_color *= character_tint
			character_mesh.set_surface_override_material(0, tinted_material)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_spawn_position = global_position
	_normal_collision_layer = collision_layer
	_normal_collision_mask = collision_mask
	_combat = get_node_or_null("Combat")
	floor_snap_length = floor_snap_distance
	_camera_yaw.top_level = true
	_camera_yaw.global_position = _camera_target_position()
	_camera_pitch.rotation = Vector3(deg_to_rad(camera_pitch_degrees), 0.0, 0.0)
	_spring_arm.spring_length = camera_distance
	_spring_arm.collision_mask = camera_collision_mask
	_spring_arm.add_excluded_object(get_rid())
	var procedural_skeleton := get_node_or_null(skeleton_path) as Skeleton3D
	if procedural_body and procedural_skeleton != null:
		_locomotion = LocomotionBlend.new()
		_locomotion.name = "LocomotionBlend"
		_locomotion.influence = 0.0
		procedural_skeleton.add_child(_locomotion)
		_locomotion.setup(
			_animation_player.get_animation(_clips_by_role[&"idle"]),
			_animation_player.get_animation(_clips_by_role[&"walk"]),
			_animation_player.get_animation(_clips_by_role[&"run"])
		)
	if relax_idle_right_arm:
		var skeleton := get_node_or_null(skeleton_path) as Skeleton3D
		if skeleton == null:
			_reject_contract("Missing skeleton for relaxed idle")
			return
		_idle_arm_modifier = preload("res://scripts/characters/relaxed_idle_arm.gd").new()
		_idle_arm_modifier.influence = 0.0
		skeleton.add_child(_idle_arm_modifier)
	if procedural_body and procedural_skeleton != null:
		_body_layer = BodyLayer.new()
		_body_layer.name = "BodyLayer"
		procedural_skeleton.add_child(_body_layer)
		_ground_ik = GroundIK.new()
		_ground_ik.name = "GroundIK"
		_ground_ik.body = self
		_ground_ik.influence = 0.0
		procedural_skeleton.add_child(_ground_ik)
	var riding_skeleton := get_node_or_null(skeleton_path) as Skeleton3D
	if riding_skeleton != null:
		_riding_modifier = preload("res://scripts/characters/riding_pose.gd").new()
		_riding_modifier.influence = 0.0
		riding_skeleton.add_child(_riding_modifier)
	_play_role(&"idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _riding_modifier != null:
		_riding_modifier.influence = move_toward(
			_riding_modifier.influence, 1.0 if _mounted else 0.0, delta / maxf(animation_blend_time, 0.001)
		)
		_riding_modifier.apply_pose(_riding_modifier.influence)
	if _camera_yaw == null:
		return
	var target := _camera_target_position()
	_camera_yaw.global_position = _camera_yaw.global_position.lerp(target, 1.0 - exp(-camera_follow_speed * delta))
	_update_procedural_layers(delta)
	if _idle_arm_modifier != null:
		var fighting: bool = _combat != null and _combat.owns_animation()
		# Combat keys every arm itself; a relaxed hang on top would drag the
		# sabre arm down through the blows.
		var target_influence := 1.0 if _active_role == &"idle" and not _mounted and not fighting else 0.0
		if _locomotion != null:
			# The stand built from the walk already hangs the arms; this fix
			# was for the shipped idle's raised arms.
			target_influence *= 1.0 - _locomotion.influence
		_idle_arm_modifier.influence = move_toward(
			_idle_arm_modifier.influence, target_influence, delta / maxf(animation_blend_time, 0.001)
		)


## Idle fidgets. A calm stand picks one every few seconds and plays it as a
## 0..1 envelope: the hand rises to the hat, the weight rocks from foot to
## foot, or the head glances to one side. Anything that is not a calm stand
## (walking, combat, mounting) lets the current one fade out at once.
func _update_fidgets(delta: float, fighting: bool) -> void:
	var calm: bool = idle_fidgets and _ground_ik.stand_weight > 0.95 and not fighting and not _mounted
	# The hat needs the head roughly facing the hand: looking away ends it.
	var looking_away := absf(_body_layer.look_yaw_target) > deg_to_rad(30.0)
	if _fidget == &"":
		if calm:
			_fidget_timer -= delta
			if _fidget_timer <= 0.0:
				_start_fidget(looking_away)
		_apply_fidget(0.0, delta)
		return
	var interrupted := not calm or (_fidget == &"hat" and looking_away)
	_fidget_time += delta * (3.0 if interrupted else 1.0)
	var u := _fidget_time / maxf(_fidget_length, 0.01)
	if u >= 1.0 or (interrupted and u >= 0.3):
		_fidget = &""
		_fidget_timer = randf_range(fidget_interval.x, fidget_interval.y)
		_apply_fidget(0.0, delta)
		return
	_apply_fidget(u, delta)


func _start_fidget(looking_away: bool) -> void:
	var choices: Array[StringName] = [&"hat", &"shift", &"glance"]
	choices.erase(_last_fidget)
	if looking_away:
		choices.erase(&"hat")
	_fidget = choices[randi() % choices.size()]
	_last_fidget = _fidget
	_fidget_time = 0.0
	_fidget_side = 1.0 if randf() < 0.5 else -1.0
	match _fidget:
		&"hat":
			_fidget_length = 2.6
		&"shift":
			_fidget_length = 3.0
		&"glance":
			_fidget_length = 2.2


func _apply_fidget(u: float, delta: float) -> void:
	# A plain ramp up, hold and ramp down: the springs below give it its
	# soft start and soft stop.
	var envelope := clampf(u / 0.18, 0.0, 1.0) * clampf((1.0 - u) / 0.22, 0.0, 1.0)
	if u <= 0.0:
		envelope = 0.0
	var hat := 0.0
	var tug := 0.0
	var dip := 0.0
	var shift := 0.0
	var lift_left := 0.0
	var lift_right := 0.0
	var glance := 0.0
	match _fidget:
		&"hat":
			hat = envelope
			tug = sin(u * TAU * 2.5) * envelope * smoothstep(0.3, 0.45, u)
			dip = deg_to_rad(5.0) * envelope
		&"shift":
			# Rock to one side, back through the middle and onto the other
			# foot; the foot that is freed lifts and sets down.
			shift = sin(u * TAU) * _fidget_side
			var raised := clampf((absf(shift) - 0.5) * 2.0, 0.0, 1.0)
			# +shift means weight on the left, which frees the right foot.
			if shift > 0.0:
				lift_right = raised
			else:
				lift_left = raised
		&"glance":
			glance = deg_to_rad(42.0) * _fidget_side * envelope
	_body_layer.hat_reach = _fidget_spring(&"hat", hat, delta)
	_body_layer.hat_tug = _fidget_spring(&"tug", tug, delta)
	_body_layer.head_dip = _fidget_spring(&"dip", dip, delta)
	_body_layer.glance_yaw = _fidget_spring(&"glance", glance, delta)
	_ground_ik.fidget_shift = _fidget_spring(&"shift", shift, delta)
	_ground_ik.fidget_lift = PackedFloat32Array([
		maxf(_fidget_spring(&"lift_left", lift_left, delta), 0.0),
		maxf(_fidget_spring(&"lift_right", lift_right, delta), 0.0),
	])


func _fidget_spring(channel: StringName, target: float, delta: float) -> float:
	var spec: Vector2 = FIDGET_SPRINGS[channel]
	var state: Vector2 = _fidget_state.get(channel, Vector2.ZERO)
	var accel := (target - state.x) * spec.x * spec.x - 2.0 * spec.y * spec.x * state.y
	state.y += accel * delta
	state.x += state.y * delta
	_fidget_state[channel] = state
	return state.x


## Feeds the skeleton modifiers: which layers are on, how fast the stride
## clock runs, where the head looks, how the torso leans and breathes.
func _update_procedural_layers(delta: float) -> void:
	if _locomotion == null:
		return
	var fighting: bool = _combat != null and _combat.owns_animation()
	var grounded := is_on_floor() and not _mounted
	var fade := delta / 0.15
	_locomotion.influence = move_toward(_locomotion.influence, 1.0 if grounded and not fighting else 0.0, fade)
	_locomotion.active = _locomotion.influence > 0.001
	var stick := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	_locomotion.advance(delta, _move_speed, _yaw_rate, stick.length() < 0.05)
	_ground_ik.influence = move_toward(_ground_ik.influence, 1.0 if grounded else 0.0, fade)
	_ground_ik.active = _ground_ik.influence > 0.001

	# Landing compression: the pelvis dips and springs back, feet stay planted.
	var dip_omega := 12.0
	_dip_velocity += (-_dip * dip_omega * dip_omega - 2.0 * 0.55 * dip_omega * _dip_velocity) * delta
	_dip = clampf(_dip + _dip_velocity * delta, -0.3, 0.05)
	_ground_ik.pelvis_extra = _dip
	_ground_ik.stand_weight = (1.0 - _locomotion.move_weight) * _locomotion.influence
	_body_layer.carry_weight = _ground_ik.stand_weight
	_update_fidgets(delta, fighting)
	_ground_ik.stance = PackedFloat32Array([_locomotion.stance_weight(0), _locomotion.stance_weight(1)])

	_body_layer.active = not _mounted
	var exertion_rate := exertion_gain_per_second if _move_speed > walk_speed * 2.0 else -exertion_recovery_per_second
	_body_layer.exertion = clampf(_body_layer.exertion + exertion_rate * delta, 0.0, 1.0)
	_body_layer.torso_lean = _torso_lean

	# The head and upper spine follow the camera, within a human neck's reach;
	# when the camera swings behind, he looks ahead again.
	var look_yaw := 0.0
	var look_pitch := 0.0
	if not fighting and not _mounted:
		var view := _visual_root.global_basis.inverse() * -_camera_pitch.global_basis.z
		var yaw := atan2(-view.x, -view.z)
		if absf(yaw) < deg_to_rad(115.0):
			var reach := deg_to_rad(head_look_max_yaw_degrees)
			look_yaw = clampf(yaw, -reach, reach)
			var pitch := asin(clampf(view.normalized().y, -1.0, 1.0)) - deg_to_rad(camera_pitch_degrees)
			look_pitch = clampf(pitch * 0.7, deg_to_rad(-30.0), deg_to_rad(25.0))
	_body_layer.look_yaw_target = look_yaw
	_body_layer.look_pitch_target = look_pitch


func _camera_target_position() -> Vector3:
	var height := camera_height + (0.5 if _mounted else 0.0)
	return global_position + Vector3.UP * height + _camera_yaw.global_basis.x * camera_shoulder_offset


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_camera_yaw.rotate_y(-event.screen_relative.x * mouse_sensitivity)
		_camera_pitch.rotation.x = clampf(
			_camera_pitch.rotation.x - event.screen_relative.y * mouse_sensitivity,
			deg_to_rad(-65.0), deg_to_rad(45.0)
		)


func _physics_process(delta: float) -> void:
	var fighting: bool = _combat != null and _combat.owns_animation()
	if Input.is_action_just_pressed(&"mount_horse") and not fighting:
		_toggle_mount()
	if _mounted:
		_ride_horse(delta)
		return
	var was_on_floor := is_on_floor()
	if was_on_floor:
		velocity.y = -floor_stick_velocity
	else:
		velocity.y -= _gravity * delta
		_peak_fall_speed = maxf(_peak_fall_speed, -velocity.y)
	if Input.is_action_just_pressed(&"jump") and was_on_floor and not fighting and _landing_recovery <= 0.0:
		velocity.y = jump_velocity
	_landing_recovery = maxf(_landing_recovery - delta, 0.0)

	var input_vector: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var camera_forward: Vector3 = -_camera_yaw.global_transform.basis.z
	var camera_right: Vector3 = _camera_yaw.global_transform.basis.x
	camera_forward.y = 0.0
	camera_right.y = 0.0
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	var movement_direction: Vector3 = camera_right * input_vector.x + camera_forward * -input_vector.y
	if movement_direction.length_squared() > 1.0:
		movement_direction = movement_direction.normalized()

	var previous_speed := _ground_speed
	if fighting:
		_move_for_combat(movement_direction, delta)
	else:
		_move_with_momentum(movement_direction, was_on_floor, delta)

	move_and_slide()
	_after_move(was_on_floor)
	_update_body_lean(fighting, previous_speed, delta)
	if not fighting:
		_update_animation_state()
	if global_position.y < respawn_below_y:
		respawn()


## Heading-driven locomotion. The input only chooses where the body wants to
## face and how fast it wants to go; the body turns toward it at a limited rate
## and always travels along its own heading.
func _move_with_momentum(direction: Vector3, on_floor: bool, delta: float) -> void:
	var input_strength := clampf(direction.length(), 0.0, 1.0)
	var heading := _visual_root.rotation.y
	var control := 1.0 if on_floor else air_control
	var is_running := Input.is_action_pressed(&"sprint")
	var gait_speed := run_speed if is_running else walk_speed
	var target_speed := gait_speed * input_strength
	var turn_gap := 0.0

	if input_strength > 0.05:
		var local_direction: Vector3 = global_basis.inverse() * direction
		var desired_heading := atan2(-local_direction.x, -local_direction.z)
		turn_gap = angle_difference(heading, desired_heading)
		# Planting the feet: a body moving faster than a walk cannot swing
		# straight round, so it brakes hard first and turns once it is slow.
		_pivoting = on_floor and absf(turn_gap) > deg_to_rad(pivot_angle) and _ground_speed > walk_speed * 1.1
		if not _pivoting:
			# Wide turns still cost speed, more the harder the turn.
			target_speed *= lerpf(1.0, 0.55, clampf(absf(turn_gap) / PI, 0.0, 1.0))
		else:
			target_speed = 0.0
		var speed_ratio := clampf(_ground_speed / maxf(run_speed, 0.001), 0.0, 1.0)
		var max_turn := deg_to_rad(lerpf(turn_rate_standing, turn_rate_running, speed_ratio)) * control
		if _pivoting:
			max_turn *= 0.35
		var turn_accel := deg_to_rad(lerpf(turn_acceleration_standing, turn_acceleration_running, speed_ratio)) * control
		# The fastest rate from which the turn can still brake to a stop
		# exactly on the target heading, so it eases out instead of snapping.
		var arrive_rate := sqrt(2.0 * turn_accel * absf(turn_gap))
		var desired_rate := signf(turn_gap) * minf(max_turn, arrive_rate)
		_steer_heading(desired_rate, turn_accel, delta)
	else:
		_pivoting = false
		# No input: the turn already under way coasts to a stop.
		_steer_heading(0.0, deg_to_rad(turn_acceleration_standing) * control, delta)

	if on_floor:
		target_speed *= _slope_factor()
	if _landing_recovery > 0.0:
		target_speed *= 0.35

	var rate: float
	if not on_floor:
		rate = run_acceleration * air_control
	elif _pivoting:
		rate = pivot_deceleration
	elif target_speed > _ground_speed:
		rate = run_acceleration if is_running else walk_acceleration
	elif input_strength <= 0.05:
		rate = stop_deceleration
	else:
		rate = slowdown_deceleration
	_ground_speed = move_toward(_ground_speed, target_speed, rate * delta)

	var forward := global_basis * Vector3(-sin(_visual_root.rotation.y), 0.0, -cos(_visual_root.rotation.y))
	if on_floor:
		velocity.x = forward.x * _ground_speed
		velocity.z = forward.z * _ground_speed
	else:
		# In the air the body keeps the momentum it left the ground with.
		var air_target := forward * _ground_speed
		velocity.x = move_toward(velocity.x, air_target.x, run_acceleration * air_control * delta)
		velocity.z = move_toward(velocity.z, air_target.z, run_acceleration * air_control * delta)


## Turns the heading with angular momentum: the yaw rate builds up and
## bleeds off at a limited acceleration instead of jumping.
func _steer_heading(desired_rate: float, turn_accel: float, delta: float) -> void:
	_yaw_rate = move_toward(_yaw_rate, desired_rate, turn_accel * delta)
	if absf(_yaw_rate) < 0.0001:
		_yaw_rate = 0.0
		return
	_visual_root.rotation.y = wrapf(_visual_root.rotation.y + _yaw_rate * delta, -PI, PI)


## Combat owns facing and decides how far the body may move.
func _move_for_combat(direction: Vector3, delta: float) -> void:
	_pivoting = false
	_yaw_rate = 0.0
	var target_velocity: Vector3 = _combat.filter_velocity(direction * walk_speed)
	velocity.x = move_toward(velocity.x, target_velocity.x, pivot_deceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, pivot_deceleration * delta)
	_ground_speed = Vector2(velocity.x, velocity.z).length()


## Uphill costs speed, downhill gives a little. Measured along the heading.
func _slope_factor() -> float:
	var normal := get_floor_normal()
	var forward := global_basis * Vector3(-sin(_visual_root.rotation.y), 0.0, -cos(_visual_root.rotation.y))
	var grade := -forward.dot(normal)
	_slope_grade = grade
	if grade > 0.0:
		return clampf(1.0 - uphill_penalty * grade, 0.45, 1.0)
	return 1.0 + downhill_bonus * minf(-grade, 0.5)


func _after_move(was_on_floor: bool) -> void:
	# Running into a wall or a rock takes the momentum away instead of
	# leaving the legs pumping in place.
	var real := get_real_velocity()
	var real_speed := Vector2(real.x, real.z).length()
	_move_speed = real_speed
	if is_on_floor() and is_on_wall() and real_speed < _ground_speed:
		_ground_speed = real_speed
	if is_on_floor() and not was_on_floor:
		_dip_velocity -= _peak_fall_speed * landing_dip_per_speed
		if _peak_fall_speed >= hard_landing_speed:
			_ground_speed *= 0.25
			_landing_recovery = hard_landing_recovery
		elif _peak_fall_speed >= soft_landing_speed:
			_ground_speed *= 0.7
			_landing_recovery = 0.12
		_peak_fall_speed = 0.0


## Leans the whole body into turns and against changes in speed, so momentum
## reads on the silhouette.
func _update_body_lean(fighting: bool, previous_speed: float, delta: float) -> void:
	var target_roll := 0.0
	var target_torso := 0.0
	if not fighting and is_on_floor():
		var max_roll := deg_to_rad(max_turn_lean_degrees)
		target_roll = clampf(_yaw_rate * _ground_speed * turn_lean_gain, -max_roll, max_roll)
		var acceleration := (_ground_speed - previous_speed) / maxf(delta, 0.0001)
		var max_torso := deg_to_rad(max_torso_lean_degrees)
		target_torso = clampf(acceleration * torso_accel_gain + _slope_grade * torso_slope_gain, -max_torso, max_torso)
	# Underdamped springs: the body overshoots a little and settles, which
	# reads as mass rather than as a value sliding to its target.
	var omega := sqrt(lean_stiffness)
	var damping := 2.0 * lean_damping_ratio * omega
	_lean_roll_velocity += ((target_roll - _lean_roll) * lean_stiffness - damping * _lean_roll_velocity) * delta
	_lean_roll += _lean_roll_velocity * delta
	_torso_lean_velocity += ((target_torso - _torso_lean) * lean_stiffness - damping * _torso_lean_velocity) * delta
	_torso_lean += _torso_lean_velocity * delta
	_visual_root.rotation.x = 0.0
	_visual_root.rotation.z = _lean_roll


## Puts the Cossack back at the spawn point on foot.
func respawn() -> void:
	if _mounted:
		_mounted = false
		_horse.mounted = false
		collision_layer = _normal_collision_layer
		collision_mask = _normal_collision_mask
		_visual_root.position = Vector3.ZERO
		_spring_arm.spring_length = camera_distance
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_reset_momentum()
	_visual_root.rotation = Vector3.ZERO
	_camera_yaw.global_position = _camera_target_position()
	release_animation()
	_play_role(&"idle")


func _reset_momentum() -> void:
	_ground_speed = 0.0
	_yaw_rate = 0.0
	_pivoting = false
	_landing_recovery = 0.0
	_peak_fall_speed = 0.0
	_lean_roll = 0.0
	_lean_roll_velocity = 0.0
	_torso_lean = 0.0
	_torso_lean_velocity = 0.0
	_dip = 0.0
	_dip_velocity = 0.0
	_slope_grade = 0.0
	_move_speed = 0.0
	if _ground_ik != null:
		_ground_ik.reset()


## Hands the animation back to locomotion after combat played its own clips.
func release_animation() -> void:
	_active_role = &""


func is_mounted() -> bool:
	return _mounted


func idle_clip() -> StringName:
	return _clips_by_role.get(&"idle", &"")


func get_animation_player() -> AnimationPlayer:
	return _animation_player


func get_visual_root() -> Node3D:
	return _visual_root


func get_camera_yaw() -> Node3D:
	return _camera_yaw


func get_camera() -> Camera3D:
	return _spring_arm.get_node_or_null("Camera3D") as Camera3D if _spring_arm != null else null


func get_skeleton() -> Skeleton3D:
	return get_node_or_null(skeleton_path) as Skeleton3D


func _toggle_mount() -> void:
	if _mounted:
		if is_instance_valid(_horse):
			_dismount()
		return
	var nearest_distance := 3.2
	_horse = null
	for candidate in get_tree().get_nodes_in_group(&"rideable_horses"):
		if not candidate is CharacterBody3D or candidate.mounted:
			continue
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			_horse = candidate
	if is_instance_valid(_horse):
		_mounted = true
		_horse.mounted = true
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		_reset_momentum()
		_spring_arm.spring_length = camera_distance + 1.2
		_play_role(&"idle")


func _ride_horse(delta: float) -> void:
	var input_vector := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var forward := -_camera_yaw.global_basis.z
	var right := _camera_yaw.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction := right.normalized() * input_vector.x - forward.normalized() * input_vector.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_horse.ride(direction, Input.is_action_pressed(&"sprint"), delta)
	global_position = _horse.global_position
	var seat_weight: float = _riding_modifier.influence if _riding_modifier != null else 1.0
	var saddle_basis: Basis = _horse.get_visual_global_basis()
	var seat := Vector3(0.0, ride_seat_height + float(_horse.saddle_offset), -ride_seat_forward)
	_visual_root.position = (saddle_basis * seat) * seat_weight
	var saddle_pose := Basis.from_euler(Vector3(
		float(_horse.saddle_pitch) * seat_weight, 0.0, float(_horse.saddle_roll) * seat_weight
	))
	_visual_root.basis = saddle_basis * saddle_pose
	if global_position.y < respawn_below_y:
		_horse.global_position = _spawn_position
		_horse.velocity = Vector3.ZERO
		global_position = _spawn_position


func _dismount() -> void:
	var space := get_world_3d().direct_space_state
	var shape_node := get_node("CollisionShape3D") as CollisionShape3D
	for side in [1.0, -1.0]:
		var offset: Vector3 = _horse.global_basis.x * float(side) * 1.65
		var start: Vector3 = _horse.global_position + offset + Vector3.UP * 2.0
		var ray := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * 4.0, _normal_collision_mask)
		ray.exclude = [get_rid(), _horse.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
			continue
		var landing: Vector3 = hit.position + Vector3.UP * 0.08
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = Transform3D(Basis.IDENTITY, landing + shape_node.position)
		query.collision_mask = _normal_collision_mask
		query.exclude = [get_rid(), _horse.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue
		_mounted = false
		_horse.mounted = false
		_horse.velocity = Vector3.ZERO
		global_position = landing
		collision_layer = _normal_collision_layer
		collision_mask = _normal_collision_mask
		_visual_root.position = Vector3.ZERO
		_visual_root.rotation = Vector3(0.0, _visual_root.rotation.y, 0.0)
		_reset_momentum()
		_spring_arm.spring_length = camera_distance
		return


func _reject_contract(message: String) -> bool:
	push_error("SummerThirdPersonController: " + message)
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)
	return false


func _validate_scene_contract() -> bool:
	if _visual_root == null or _camera_yaw == null or _camera_pitch == null:
		return _reject_contract("Missing visual or camera pivot; check the exported node paths")
	if _spring_arm == null or _animation_player == null:
		return _reject_contract("Missing SpringArm3D or AnimationPlayer; check the exported node paths")
	if character_manifest_path.is_empty():
		return _reject_contract("Set character_manifest_path")
	for action in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			return _reject_contract("Missing input action: %s" % action)
	return true


func _configure_character_animation() -> bool:
	var file := FileAccess.open(character_manifest_path, FileAccess.READ)
	if file == null:
		return _reject_contract("Missing character manifest: %s" % character_manifest_path)
	var manifest = JSON.parse_string(file.get_as_text())
	if not manifest is Dictionary:
		return _reject_contract("Invalid character manifest JSON")
	if manifest.get("status") != "ready" or manifest.get("version") != 2:
		return _reject_contract("Character package is not ready or uses an unsupported version")
	var normalization = manifest.get("normalization", {})
	if not normalization is Dictionary or normalization.get("forwardAxis") != "-Z":
		return _reject_contract("Character package forward axis must be -Z")
	var animations = manifest.get("animations", [])
	if not animations is Array:
		return _reject_contract("Character manifest animations must be an array")
	for entry in animations:
		if not entry is Dictionary:
			continue
		var role := StringName(String(entry.get("semanticRole", "")))
		if role not in REQUIRED_ROLES:
			continue
		var clip := StringName(String(entry.get("name", "")))
		if clip == &"":
			return _reject_contract("Requested character role has no clip: %s" % role)
		if _clips_by_role.has(role) or _clips_by_role.values().has(clip):
			return _reject_contract("Ambiguous character role or reused clip: %s" % role)
		if not _animation_player.has_animation(clip):
			return _reject_contract("Manifest clip is not playable: %s" % clip)
		_clips_by_role[role] = clip
	for role in REQUIRED_ROLES:
		if not _clips_by_role.has(role):
			return _reject_contract("Missing requested character role: %s" % role)
	for role in [&"idle", &"walk", &"run"]:
		_animation_player.get_animation(_clips_by_role[role]).loop_mode = Animation.LOOP_LINEAR
	_animation_player.get_animation(_clips_by_role[&"jump"]).loop_mode = Animation.LOOP_NONE
	_apply_clip_override(walk_animation_override, WALK_OVERRIDE_CLIP, &"walk")
	_apply_clip_override(run_animation_override, RUN_OVERRIDE_CLIP, &"run")
	return true


func _apply_clip_override(path: String, clip: StringName, role: StringName) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var override := load(path) as Animation
	if override == null:
		push_warning("SummerThirdPersonController: animation override is not an animation: %s" % path)
		return
	override.loop_mode = Animation.LOOP_LINEAR
	if not _animation_player.has_animation(clip):
		var library := _animation_player.get_animation_library(&"")
		if library == null:
			push_warning("SummerThirdPersonController: animation player has no default library for %s" % path)
			return
		library.add_animation(clip, override)
	_clips_by_role[role] = clip


func _update_animation_state() -> void:
	if _locomotion != null:
		# The locomotion blend draws walk and run itself on top of this base;
		# the player only holds the idle under it, or the jump in the air.
		_play_role(&"idle" if is_on_floor() else &"jump")
		_animation_player.speed_scale = 1.0
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var next_role: StringName
	if not is_on_floor():
		next_role = &"jump"
	elif horizontal_speed <= 0.05 and absf(_yaw_rate) < 1.5:
		next_role = &"idle"
	elif horizontal_speed > (walk_speed + run_speed) * 0.5:
		next_role = &"run"
	else:
		next_role = &"walk"
	_play_role(next_role)
	_sync_animation_to_ground(maxf(horizontal_speed, absf(_yaw_rate) * 0.25), next_role)


func _sync_animation_to_ground(horizontal_speed: float, role: StringName) -> void:
	var clip_ground_speed := 0.0
	if role == &"walk":
		clip_ground_speed = walk_clip_ground_speed
	elif role == &"run":
		clip_ground_speed = run_clip_ground_speed
	if clip_ground_speed <= 0.001:
		_animation_player.speed_scale = 1.0
		return
	_animation_player.speed_scale = clampf(
		horizontal_speed / clip_ground_speed, min_animation_speed, max_animation_speed
	)


func _play_role(role: StringName) -> void:
	if not _clips_by_role.has(role):
		_reject_contract("Missing requested character role: %s" % role)
		return
	if role == _active_role:
		return
	_animation_player.play(_clips_by_role[role], animation_blend_time)
	_animation_player.advance(0.0)
	_active_role = role

