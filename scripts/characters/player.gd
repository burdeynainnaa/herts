class_name SummerThirdPersonController
extends CharacterBody3D

const REQUIRED_ROLES: Array[StringName] = [&"idle", &"walk", &"run", &"jump"]
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back", &"jump", &"sprint", &"ui_cancel"
]

@export_file("*.json") var character_manifest_path: String

@export_category("Movement")
@export var walk_speed: float = 1.45
@export var run_speed: float = 4.7
@export var acceleration: float = 14.0
@export var jump_velocity: float = 3.8
@export var turn_speed: float = 12.0
@export var floor_snap_distance: float = 0.3
@export var floor_stick_velocity: float = 0.5
@export var animation_blend_time: float = 0.25
@export var relax_idle_right_arm: bool = false
@export var character_tint: Color = Color.WHITE
@export_file("*.tres") var walk_animation_override: String = "res://assets/models/herts_cossack_reference/walk_stoic.tres"

const WALK_OVERRIDE_CLIP: StringName = &"WalkStoic"

@export_category("Animation Sync")
@export var walk_clip_ground_speed: float = 1.45
@export var run_clip_ground_speed: float = 4.7
@export var min_animation_speed: float = 0.6
@export var max_animation_speed: float = 1.5

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


func _ready() -> void:
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
	floor_snap_length = floor_snap_distance
	_camera_yaw.top_level = true
	_camera_yaw.global_position = _camera_target_position()
	_camera_pitch.rotation = Vector3(deg_to_rad(camera_pitch_degrees), 0.0, 0.0)
	_spring_arm.spring_length = camera_distance
	_spring_arm.collision_mask = camera_collision_mask
	_spring_arm.add_excluded_object(get_rid())
	if relax_idle_right_arm:
		var skeleton := get_node_or_null(skeleton_path) as Skeleton3D
		if skeleton == null:
			_reject_contract("Missing skeleton for relaxed idle")
			return
		_idle_arm_modifier = preload("res://scripts/characters/relaxed_idle_arm.gd").new()
		_idle_arm_modifier.influence = 0.0
		skeleton.add_child(_idle_arm_modifier)
	_play_role(&"idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _camera_yaw == null:
		return
	var target := _camera_target_position()
	_camera_yaw.global_position = _camera_yaw.global_position.lerp(target, 1.0 - exp(-camera_follow_speed * delta))
	if _idle_arm_modifier != null:
		var target_influence := 1.0 if _active_role == &"idle" else 0.0
		_idle_arm_modifier.influence = move_toward(
			_idle_arm_modifier.influence, target_influence, delta / maxf(animation_blend_time, 0.001)
		)


func _camera_target_position() -> Vector3:
	return global_position + Vector3.UP * camera_height + _camera_yaw.global_basis.x * camera_shoulder_offset


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
	var was_on_floor := is_on_floor()
	if was_on_floor:
		velocity.y = -floor_stick_velocity
	else:
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed(&"jump") and was_on_floor:
		velocity.y = jump_velocity

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

	var is_sprinting: bool = Input.is_action_pressed(&"sprint")
	var target_speed: float = run_speed if is_sprinting else walk_speed
	var target_velocity: Vector3 = movement_direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	move_and_slide()
	_turn_visual_toward(movement_direction, delta)
	_update_animation_state()
	if global_position.y < respawn_below_y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		_camera_yaw.global_position = _camera_target_position()
		_play_role(&"idle")


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
	_apply_walk_override()
	return true


func _apply_walk_override() -> void:
	if walk_animation_override.is_empty() or not ResourceLoader.exists(walk_animation_override):
		return
	var override := load(walk_animation_override) as Animation
	if override == null:
		push_warning("SummerThirdPersonController: walk animation override is not an animation: %s" % walk_animation_override)
		return
	override.loop_mode = Animation.LOOP_LINEAR
	if not _animation_player.has_animation(WALK_OVERRIDE_CLIP):
		var library := _animation_player.get_animation_library(&"")
		if library == null:
			push_warning("SummerThirdPersonController: animation player has no default library for the walk override")
			return
		library.add_animation(WALK_OVERRIDE_CLIP, override)
	_clips_by_role[&"walk"] = WALK_OVERRIDE_CLIP


func _update_animation_state() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var next_role: StringName
	if not is_on_floor():
		next_role = &"jump"
	elif horizontal_speed <= 0.05:
		next_role = &"idle"
	elif horizontal_speed > (walk_speed + run_speed) * 0.5:
		next_role = &"run"
	else:
		next_role = &"walk"
	_play_role(next_role)
	_sync_animation_to_ground(horizontal_speed, next_role)


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


func _turn_visual_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var local_direction: Vector3 = global_transform.basis.inverse() * direction
	var target_yaw := atan2(-local_direction.x, -local_direction.z)
	var weight := 1.0 - exp(-turn_speed * delta)
	_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_yaw, weight)
