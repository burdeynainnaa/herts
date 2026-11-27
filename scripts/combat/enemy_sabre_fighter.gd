class_name EnemySabreFighter
extends CharacterBody3D
## Basic enemy from the design board: a Tatar sabre fighter. Weak and readable,
## meant to be the first fight. It closes in, circles at sword's length, then
## raises the sabre (the blade glints) and chops. A parry staggers it; a
## staggered, wounded fighter can be executed. Only one fighter in the
## encounter attacks at a time. Each attack is one of the three sabre blows
## (SabreAttacks), drawn at random.

signal health_changed(current: float, maximum: float)
signal defeated

enum State { IDLE, CHASE, CIRCLE, WINDUP, STRIKE, RECOVER, GUARD, STAGGER, DEAD }

@export var display_name: String = "Татарин-шабельник"
@export var character_tint: Color = Color(0.62, 0.36, 0.3)
@export var sabre_steel: Color = Color(0.62, 0.62, 0.6)

@export_category("Senses")
@export var aggro_range: float = 16.0
@export var give_up_range: float = 30.0

@export_category("Movement")
@export var walk_speed: float = 1.4
@export var run_speed: float = 4.2
@export var circle_speed: float = 0.9
@export var stand_off_distance: float = 2.2
@export var turn_speed: float = 8.0

@export_category("Attack")
@export var damage: float = 14.0
@export var reach: float = 2.6
@export var arc_degrees: float = 55.0
@export var attack_cooldown_min: float = 1.8
@export var attack_cooldown_max: float = 3.2
@export var windup_speed: float = 0.55
@export var strike_speed: float = 1.05
@export var recover_speed: float = 1.0

@export_category("Defence")
@export var guard_chance: float = 0.3
@export var guard_seconds: float = 0.9
@export var parry_stagger_seconds: float = 1.6
@export var execute_below_ratio: float = 0.5

static var _attack_token: Node = null

var state: State = State.IDLE

@onready var health: Health = $Health
@onready var _visual_root: Node3D = $CharacterRotationRoot
@onready var _body_pivot: Node3D = $CharacterRotationRoot/Character
@onready var _anim: AnimationPlayer = $CharacterRotationRoot/Character/Visual/AnimationPlayer
@onready var _skeleton: Skeleton3D = $CharacterRotationRoot/Character/Visual/Armature/Skeleton3D

var _player: Node3D
var _player_combat: PlayerCombat
var _gravity: float = 9.8
var _home: Transform3D
var _cooldown: float = 1.5
var _state_time: float = 0.0
var _circle_sign: float = 1.0
var _sabre: Sabre
var _struck: bool = false
var _clip: StringName = &""
var _react_tween: Tween
var _blow_clip: StringName = SabreAttacks.OVERHEAD
var _body_yaw: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	_home = global_transform
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	floor_snap_length = 0.3
	for clip in [&"Idle", &"Walk", &"Run"]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_sabre = CombatKit.arm_with_sabre(_skeleton, sabre_steel)
	CombatKit.install_clips(_anim, _skeleton, _visual_root, &"Idle", _sabre.transform.basis)
	_body_yaw = _body_pivot.rotation.y
	_tint_body()
	health.changed.connect(func(current: float, maximum: float) -> void: health_changed.emit(current, maximum))
	health.died.connect(_on_died)
	_circle_sign = 1.0 if randf() < 0.5 else -1.0
	_play(&"Idle")
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player != null:
		_player_combat = _player.get_node_or_null("Combat") as PlayerCombat


func is_alive() -> bool:
	return state != State.DEAD


func is_engaged() -> bool:
	return state not in [State.IDLE, State.DEAD]


func is_staggered() -> bool:
	return state == State.STAGGER


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.STRIKE


# --- Brain -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.5
	var move := Vector3.ZERO
	var to_player := _flat_to_player()
	var distance := to_player.length()
	var player_alive := _player_combat != null and _player_combat.is_alive()
	match state:
		State.IDLE:
			if player_alive and distance < aggro_range:
				_set_state(State.CHASE)
		State.CHASE:
			if not player_alive or distance > give_up_range:
				_disengage()
			elif distance <= stand_off_distance + 0.4:
				_set_state(State.CIRCLE)
			else:
				var speed := run_speed if distance > 6.0 else walk_speed
				move = to_player.normalized() * speed
				_play(&"Run" if speed > walk_speed else &"Walk")
				_face(to_player, delta)
		State.CIRCLE:
			if not player_alive:
				_disengage()
			elif distance > stand_off_distance + 1.6:
				_set_state(State.CHASE)
			else:
				_face(to_player, delta)
				var side := Vector3.UP.cross(to_player.normalized()) * _circle_sign
				if _drifting_out_of_view(side):
					_circle_sign = -_circle_sign
					side = -side
				var keep := to_player.normalized() * (distance - stand_off_distance) * 1.5
				move = side * circle_speed + keep
				_play(&"Walk")
				_cooldown -= delta
				if _cooldown <= 0.0 and distance <= reach + 0.3 and _take_token():
					_start_windup()
				elif _state_time > 2.5:
					_circle_sign = -_circle_sign
					_state_time = 0.0
		State.WINDUP:
			_face(to_player, delta * 0.8)
			if _clip_time() >= _blow("raised"):
				_set_state(State.STRIKE)
				_anim.speed_scale = strike_speed
				_struck = false
		State.STRIKE:
			var t := _clip_time()
			_strike_effects(t)
			if t >= _blow("lunge_start") and t <= _blow("lunge_end") and distance > 1.3:
				move = _facing() * minf(_blow("lunge_speed"), 3.5)
			if not _struck and t >= _blow("hit_start"):
				_struck = true
				_land_blow()
			if state == State.STRIKE and t >= _blow("hit_end") + 0.1:
				_set_state(State.RECOVER)
				_anim.speed_scale = recover_speed
		State.RECOVER:
			_strike_effects(_clip_time())
			if _clip_time() >= _blow("settled"):
				_end_strike_effects()
				_release_token()
				_cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
				_set_state(State.CIRCLE)
		State.GUARD:
			_face(to_player, delta)
			if _state_time >= guard_seconds:
				_set_state(State.CIRCLE)
		State.STAGGER:
			if _state_time >= parry_stagger_seconds:
				_cooldown = randf_range(attack_cooldown_min, attack_cooldown_max) * 0.6
				_set_state(State.CIRCLE)
		State.DEAD:
			pass
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func _start_windup() -> void:
	_set_state(State.WINDUP)
	_blow_clip = SabreAttacks.ALL.pick_random()
	_anim.speed_scale = windup_speed
	_anim.play(_blow_clip, 0.15)
	_anim.seek(0.0, true)
	_clip = _blow_clip
	_sabre.glint()


func _land_blow() -> void:
	if _player_combat == null or not _player_combat.is_alive():
		return
	var blow := SabreAttacks.data(_blow_clip)
	var blow_reach := maxf(reach, float(blow["reach"]) - 0.3)
	var blow_arc := maxf(arc_degrees, float(blow["arc"]))
	if not CombatKit.in_strike_arc(global_position, _facing(), _player.global_position, blow_reach, blow_arc):
		return
	var result := _player_combat.receive_hit(self, damage * float(blow["damage"]))
	if result == "parried":
		_release_token()
		_enter_stagger()
	elif result == "blocked" or result == "guard_broken":
		_flinch(-6.0, 0.25)


# --- Being hit ---------------------------------------------------------------------

## Called by the player's sabre. Returns "blocked", "hit", "killed" or "executed".
func take_hit(attacker: Node3D, amount: float) -> String:
	if state == State.DEAD:
		return "ignored"
	if state == State.STAGGER and health.ratio() <= execute_below_ratio:
		health.apply_damage(health.current, attacker)
		return "executed"
	var can_guard := state in [State.CIRCLE, State.CHASE, State.GUARD, State.RECOVER]
	if state == State.GUARD or (can_guard and randf() < guard_chance):
		if state != State.GUARD:
			_enter_guard()
		_face((attacker.global_position - global_position), 1.0)
		_flinch(-5.0, 0.2)
		return "blocked"
	if state == State.STAGGER:
		amount *= 1.6
	health.apply_damage(amount, attacker)
	if health.is_dead():
		return "killed"
	if state == State.WINDUP and _clip_time() < 0.6:
		_release_token()
		_set_state(State.CIRCLE)
		_cooldown = attack_cooldown_min
		_play(&"Idle", 0.08)
	_flinch(-11.0, 0.3)
	if state in [State.IDLE, State.CHASE]:
		_set_state(State.CIRCLE)
	return "hit"


func _enter_guard() -> void:
	_end_strike_effects()
	_set_state(State.GUARD)
	_anim.speed_scale = 0.6
	_anim.play(CombatKit.GUARD, 0.1)
	_anim.seek(0.15, true)
	_clip = CombatKit.GUARD


func _enter_stagger() -> void:
	_end_strike_effects()
	_set_state(State.STAGGER)
	_anim.speed_scale = 1.0
	_play(&"Idle", 0.1)
	_flinch(-16.0, 0.6)


func _on_died(_source: Node) -> void:
	_release_token()
	_end_strike_effects()
	_set_state(State.DEAD)
	collision_layer = 0
	_anim.speed_scale = 1.0
	_play(&"Idle", 0.15)
	_anim.pause()
	if _react_tween != null:
		_react_tween.kill()
	var fall := create_tween()
	fall.tween_property(_body_pivot, "rotation:x", deg_to_rad(86.0), 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	defeated.emit()


## Puts the fighter back where it started, alive. Called when the player respawns.
func reset_encounter() -> void:
	_release_token()
	_end_strike_effects()
	health.reset()
	collision_layer = 8
	global_transform = _home
	velocity = Vector3.ZERO
	_body_pivot.rotation = Vector3(0.0, _body_yaw, 0.0)
	_visual_root.rotation = Vector3.ZERO
	_cooldown = 1.5
	_anim.speed_scale = 1.0
	_clip = &""
	_set_state(State.IDLE)
	_play(&"Idle")


func _disengage() -> void:
	_release_token()
	_end_strike_effects()
	_set_state(State.IDLE)
	_play(&"Idle")


# --- Helpers -----------------------------------------------------------------------

func _set_state(next: State) -> void:
	state = next
	_state_time = 0.0


func _play(clip: StringName, blend: float = 0.2) -> void:
	if _clip == clip and _anim.is_playing():
		return
	_clip = clip
	_anim.speed_scale = 1.0
	_anim.play(clip, blend)


func _clip_time() -> float:
	if _anim.current_animation != String(_blow_clip):
		return 100.0
	return _anim.current_animation_position


func _blow(key: String) -> float:
	return float(SabreAttacks.data(_blow_clip)[key])


## Blade trail and, for the spinning sweep, the body's turn on the spot.
func _strike_effects(t: float) -> void:
	if t >= _blow("trail_start") and t <= _blow("trail_end"):
		_sabre.start_trail()
	else:
		_sabre.stop_trail()
	var blow := SabreAttacks.data(_blow_clip)
	if blow.has("spin_start"):
		var turn := clampf(inverse_lerp(float(blow["spin_start"]), float(blow["spin_end"]), t), 0.0, 1.0)
		_body_pivot.rotation.y = _body_yaw + TAU * smoothstep(0.0, 1.0, turn)


func _end_strike_effects() -> void:
	if _sabre != null:
		_sabre.stop_trail()
	_body_pivot.rotation.y = _body_yaw


func _take_token() -> bool:
	if _attack_token != null and is_instance_valid(_attack_token) and _attack_token != self:
		return false
	_attack_token = self
	return true


func _release_token() -> void:
	if _attack_token == self:
		_attack_token = null


func _flat_to_player() -> Vector3:
	if _player == null:
		return Vector3.FORWARD * 1000.0
	var offset := _player.global_position - global_position
	offset.y = 0.0
	return offset


func _facing() -> Vector3:
	return -_visual_root.global_basis.z.normalized()


## Circling stays in the half of the circle the player's camera looks at, so a
## fighter never wanders behind the camera where it cannot be read or parried.
func _drifting_out_of_view(side: Vector3) -> bool:
	if _player == null or not _player.has_method("get_camera_yaw"):
		return false
	var view: Vector3 = -(_player.get_camera_yaw() as Node3D).global_basis.z
	view.y = 0.0
	var from_player := -_flat_to_player()
	if view.length_squared() < 0.001 or from_player.length_squared() < 0.001:
		return false
	var angle := absf(view.signed_angle_to(from_player, Vector3.UP))
	if angle < deg_to_rad(55.0):
		return false
	var next := absf(view.signed_angle_to(from_player + side * 0.2, Vector3.UP))
	return next > angle


func _face(direction: Vector3, delta_or_weight: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	var weight := 1.0 if delta_or_weight >= 1.0 else 1.0 - exp(-turn_speed * delta_or_weight)
	_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_yaw - rotation.y, weight)


func _flinch(degrees: float, seconds: float) -> void:
	if _react_tween != null:
		_react_tween.kill()
	_react_tween = create_tween()
	_react_tween.tween_property(_body_pivot, "rotation:x", deg_to_rad(-degrees), seconds * 0.3)
	_react_tween.tween_property(_body_pivot, "rotation:x", 0.0, seconds * 0.7)


func _tint_body() -> void:
	var mesh := _skeleton.get_node_or_null("char1") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	var original := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if original == null:
		return
	var tinted := original.duplicate() as StandardMaterial3D
	tinted.albedo_color *= character_tint
	mesh.set_surface_override_material(0, tinted)
