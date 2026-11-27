class_name PlayerCombat
extends Node
## The Cossack's sabre fighting, as a child of the player controller.
##
## Attack (LMB): three sabre blows that chain when pressed again during the
## follow-through: an overhead chop, a spinning sweep that cuts all around, and
## a lunging thrust (SabreAttacks). Guard (hold RMB): blocks blows from the front at a
## stamina cost. Pressing guard just before a blow lands parries it and staggers
## the attacker; striking a staggered, wounded enemy executes it and refills
## stamina. The controller asks this node whether it owns the animation and how
## fast the body may move.

signal stamina_changed(current: float, maximum: float)
signal announce(text: String)
signal died
signal respawned

enum State { IDLE, ATTACK, GUARD, STAGGER, DEAD }

@export_category("Sabre")
@export var attack_damage: float = 22.0
## The blows in combo order; each press during a follow-through moves one on.
@export var combo: Array[StringName] = [SabreAttacks.OVERHEAD, SabreAttacks.SPIN, SabreAttacks.THRUST]
@export var attack_speed: float = 1.15
@export var chained_attack_start: float = 0.08
@export var soft_lock_range: float = 7.0

@export_category("Guard")
@export var parry_window: float = 0.22
@export var parry_cooldown: float = 0.55
@export var guard_arc_degrees: float = 100.0
@export var guard_break_stagger: float = 0.9

@export_category("Stamina")
@export var max_stamina: float = 100.0
@export var attack_cost: float = 16.0
@export var block_cost: float = 22.0
@export var stamina_regen: float = 30.0
@export var guard_stamina_regen: float = 10.0
@export var stamina_regen_delay: float = 0.9

@export_category("Death")
@export var respawn_delay: float = 3.5

var state: State = State.IDLE
var stamina: float = 0.0

@onready var health: Health = $Health

var _player: SummerThirdPersonController
var _anim: AnimationPlayer
var _visual_root: Node3D
var _body_pivot: Node3D
var _camera: Camera3D
var _sabre: Sabre
var _combo_index: int = 0
var _clip: StringName = &""
var _dust_raised: bool = false
var _previous_clip_time: float = 0.0
var _body_yaw: float = 0.0
var _combo_buffered: bool = false
var _hit_targets: Array[Node] = []
var _attack_target: Node3D
var _guard_started_ms: int = -100000
var _last_guard_press_ms: int = -100000
var _stamina_delay: float = 0.0
var _stagger_left: float = 0.0
var _trauma: float = 0.0
var _flinch_tween: Tween
var _recapture_frame: int = -10


func _ready() -> void:
	_player = get_parent() as SummerThirdPersonController
	if _player == null:
		push_error("PlayerCombat must be a child of the player controller")
		set_physics_process(false)
		return
	_player.add_to_group(&"player")
	stamina = max_stamina
	health.died.connect(_on_died)
	await _player.ready
	_anim = _player.get_animation_player()
	_visual_root = _player.get_visual_root()
	_body_pivot = _visual_root.get_node_or_null("Character") as Node3D
	_camera = _player.get_camera()
	var skeleton := _player.get_skeleton()
	if _anim == null or skeleton == null:
		push_error("PlayerCombat: player has no AnimationPlayer or skeleton")
		set_physics_process(false)
		return
	_sabre = CombatKit.arm_with_sabre(skeleton)
	if not CombatKit.install_clips(_anim, skeleton, _visual_root, _player.idle_clip(), _sabre.transform.basis):
		push_error("PlayerCombat: could not install sabre clips")
		set_physics_process(false)
		return
	if _body_pivot != null:
		_body_yaw = _body_pivot.rotation.y
	stamina_changed.emit(stamina, max_stamina)


# --- Controller contract -----------------------------------------------------

func owns_animation() -> bool:
	return state != State.IDLE


func blocks_jump() -> bool:
	return state != State.IDLE


func filter_velocity(desired: Vector3) -> Vector3:
	match state:
		State.IDLE:
			return desired
		State.ATTACK:
			var t := _clip_time()
			var blow := SabreAttacks.data(_clip)
			if t >= blow["lunge_start"] and t <= blow["lunge_end"]:
				if _attack_target == null or not is_instance_valid(_attack_target) or _flat_distance(_attack_target) > 1.3:
					return _facing() * float(blow["lunge_speed"])
			return Vector3.ZERO
		_:
			return Vector3.ZERO


func is_alive() -> bool:
	return state != State.DEAD


func sabre() -> Sabre:
	return _sabre


# --- Input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# A click on a released mouse only recaptures it (the controller does that);
	# it is not a sabre blow. _input runs before the controller's handler.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_recapture_frame = Engine.get_physics_frames()


func _poll_input() -> void:
	if not _can_fight():
		return
	if Input.is_action_just_pressed(&"attack") and _recapture_frame < Engine.get_physics_frames() - 1:
		_request_attack()
	if Input.is_action_just_pressed(&"block"):
		_request_guard()
	elif state == State.IDLE and Input.is_action_pressed(&"block"):
		_guard_started_ms = -100000
		_enter_guard()


func _request_attack() -> void:
	match state:
		State.IDLE, State.GUARD:
			_start_attack(false)
		State.ATTACK:
			if _clip_time() >= _blow("hit_start") and _combo_index < combo.size() - 1:
				_combo_buffered = true


func _request_guard() -> void:
	var now := Time.get_ticks_msec()
	var spamming := now - _last_guard_press_ms < int(parry_cooldown * 1000.0)
	_last_guard_press_ms = now
	if state == State.ATTACK and _clip_time() < _blow("hit_end") + 0.15:
		return
	if state in [State.IDLE, State.ATTACK, State.GUARD]:
		_guard_started_ms = -100000 if spamming else now
		_enter_guard()


func _can_fight() -> bool:
	return state != State.DEAD and not _player.is_mounted() and _player.is_on_floor()


# --- Per frame -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_poll_input()
	_update_stamina(delta)
	match state:
		State.ATTACK:
			_update_attack(delta)
		State.GUARD:
			if not Input.is_action_pressed(&"block") or not _can_fight():
				_return_to_idle()
			else:
				_face_nearest_threat(delta)
		State.STAGGER:
			_stagger_left -= delta
			if _stagger_left <= 0.0:
				_return_to_idle()


func _process(delta: float) -> void:
	if _camera == null:
		return
	_trauma = maxf(_trauma - delta * 2.2, 0.0)
	var shake := _trauma * _trauma
	var t := Time.get_ticks_msec() * 0.001
	_camera.h_offset = shake * 0.12 * sin(t * 47.0)
	_camera.v_offset = shake * 0.09 * sin(t * 59.0 + 1.3)


func _update_stamina(delta: float) -> void:
	if state == State.DEAD:
		return
	if _stamina_delay > 0.0:
		_stamina_delay -= delta
		return
	var rate := guard_stamina_regen if state == State.GUARD else stamina_regen
	if state == State.ATTACK:
		rate = 0.0
	if stamina < max_stamina and rate > 0.0:
		_set_stamina(stamina + rate * delta)


func _spend_stamina(amount: float) -> void:
	_set_stamina(stamina - amount)
	_stamina_delay = stamina_regen_delay


func _set_stamina(value: float) -> void:
	stamina = clampf(value, 0.0, max_stamina)
	stamina_changed.emit(stamina, max_stamina)


# --- Attack --------------------------------------------------------------------

func _start_attack(chained: bool) -> void:
	_combo_index = (_combo_index + 1) if chained else 0
	var clip: StringName = combo[_combo_index]
	var cost := attack_cost * float(SabreAttacks.data(clip)["stamina"])
	if stamina < cost * 0.5:
		announce.emit("Бракує сил")
		_combo_index = 0
		_combo_buffered = false
		return
	_end_attack_effects()
	_clip = clip
	_combo_buffered = false
	_dust_raised = false
	_previous_clip_time = 0.0
	_hit_targets.clear()
	_spend_stamina(cost)
	_attack_target = _pick_target()
	state = State.ATTACK
	_anim.speed_scale = attack_speed
	_anim.play(_clip, 0.06 if chained else 0.1)
	_anim.seek(chained_attack_start if chained else 0.0, true)


func _update_attack(delta: float) -> void:
	var t := _clip_time()
	var blow := SabreAttacks.data(_clip)
	if t < float(blow["hit_start"]):
		_turn_toward_target(delta, 16.0)
	_spin_body(t, blow)
	if _sabre != null:
		if t >= float(blow["trail_start"]) and t <= float(blow["trail_end"]):
			_sabre.start_trail()
		else:
			_sabre.stop_trail()
	if not _dust_raised and t >= float(blow["dust_at"]):
		_dust_raised = true
		CombatKit.burst(get_tree().current_scene, _player.global_position + _facing() * 0.4 + Vector3.UP * 0.05,
			Color(0.42, 0.35, 0.25), 26, 2.2, 0.03, 5.0)
	# Overlap rather than containment, so a long frame cannot skip the window.
	if t >= float(blow["hit_start"]) and _previous_clip_time <= float(blow["hit_end"]):
		_sweep_hits(blow)
	_previous_clip_time = t
	if Input.is_action_pressed(&"block") and t > float(blow["hit_end"]) + 0.15:
		_enter_guard()
		return
	if _combo_buffered and t >= float(blow["hit_end"]) + 0.12:
		_start_attack(true)
		return
	if t >= float(blow["settled"]) or not _anim.is_playing():
		_combo_index = 0
		_return_to_idle()


## The spinning sweep turns the whole body once round; the visual root keeps
## its heading, so aim and hit arcs are unaffected.
func _spin_body(t: float, blow: Dictionary) -> void:
	if _body_pivot == null or not blow.has("spin_start"):
		return
	var turn := inverse_lerp(float(blow["spin_start"]), float(blow["spin_end"]), t)
	_body_pivot.rotation.y = _body_yaw + TAU * smoothstep(0.0, 1.0, clampf(turn, 0.0, 1.0))


func _end_attack_effects() -> void:
	if _sabre != null:
		_sabre.stop_trail()
	if _body_pivot != null:
		_body_pivot.rotation.y = _body_yaw


func _sweep_hits(blow: Dictionary) -> void:
	var origin := _player.global_position
	var forward := _facing()
	for enemy in CombatKit.living_enemies(get_tree(), origin):
		if enemy in _hit_targets:
			continue
		if not CombatKit.in_strike_arc(origin, forward, enemy.global_position, float(blow["reach"]), float(blow["arc"])):
			continue
		_hit_targets.append(enemy)
		var result: String = enemy.take_hit(_player, attack_damage * float(blow["damage"]))
		_on_attack_result(enemy, result)


func _on_attack_result(enemy: Node3D, result: String) -> void:
	var chest := enemy.global_position + Vector3.UP * 1.25
	match result:
		"blocked":
			CombatKit.burst(get_tree().current_scene, _sabre_point(chest), Color(1.0, 0.78, 0.35), 16, 4.0, 0.02, 4.0)
			_add_trauma(0.35)
			CombatKit.hit_stop(get_tree(), 0.05, 0.1)
			_spend_stamina(6.0)
			_flinch(0.12, 6.0)
			_combo_index = combo.size()
			_combo_buffered = false
		"hit":
			CombatKit.burst(get_tree().current_scene, chest, Color(0.45, 0.02, 0.02), 22, 3.2)
			_add_trauma(0.4)
			CombatKit.hit_stop(get_tree(), 0.07)
		"killed":
			CombatKit.burst(get_tree().current_scene, chest, Color(0.45, 0.02, 0.02), 36, 4.0)
			_add_trauma(0.55)
			CombatKit.hit_stop(get_tree(), 0.12)
			announce.emit("Ворога здолано")
		"executed":
			CombatKit.burst(get_tree().current_scene, chest, Color(0.45, 0.02, 0.02), 60, 5.0)
			_add_trauma(0.8)
			CombatKit.hit_stop(get_tree(), 0.22, 0.15)
			_set_stamina(max_stamina)
			health.heal(10.0)
			announce.emit("Страта!")


func _pick_target() -> Node3D:
	var origin := _player.global_position
	var view_forward := -_player.get_camera_yaw().global_basis.z
	for enemy in CombatKit.living_enemies(get_tree(), origin):
		if CombatKit.in_strike_arc(origin, view_forward, enemy.global_position, soft_lock_range, 70.0):
			return enemy
	return null


func _turn_toward_target(delta: float, speed: float) -> void:
	var direction: Vector3
	if _attack_target != null and is_instance_valid(_attack_target):
		direction = _attack_target.global_position - _player.global_position
	else:
		var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if input.length_squared() < 0.01:
			return
		var yaw := _player.get_camera_yaw().global_basis
		direction = yaw.x * input.x + yaw.z * input.y
	_face(direction, 1.0 - exp(-speed * delta))


## While guarding, the Cossack squares up to the closest fighter in reach, so
## the guard covers whoever is about to strike.
func _face_nearest_threat(delta: float) -> void:
	var enemies := CombatKit.living_enemies(get_tree(), _player.global_position)
	if enemies.is_empty() or _flat_distance(enemies[0]) > 4.5:
		return
	for enemy in enemies:
		if _flat_distance(enemy) > 4.5:
			break
		if enemy.has_method("is_attacking") and enemy.is_attacking():
			_face(enemy.global_position - _player.global_position, 1.0 - exp(-14.0 * delta))
			return
	_face(enemies[0].global_position - _player.global_position, 1.0 - exp(-10.0 * delta))


func _face(direction: Vector3, weight: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_yaw, weight)


# --- Guard and being hit -------------------------------------------------------

func _enter_guard() -> void:
	if state == State.GUARD:
		return
	_end_attack_effects()
	state = State.GUARD
	_anim.speed_scale = 0.6
	_anim.play(CombatKit.GUARD, 0.1)
	_anim.seek(0.15, true)


## Called by an enemy when its blow lands. Returns "parried", "blocked",
## "guard_broken", "hit" or "ignored" so the attacker can react.
func receive_hit(attacker: Node3D, damage: float) -> String:
	if state == State.DEAD:
		return "ignored"
	var to_attacker := attacker.global_position - _player.global_position
	var facing_attacker := CombatKit.in_strike_arc(
		_player.global_position, _facing(), attacker.global_position, 100.0, guard_arc_degrees * 0.5 + 10.0
	)
	var spark_at := _sabre_point(_player.global_position + Vector3.UP * 1.4)
	if state == State.GUARD and facing_attacker:
		_face(to_attacker, 1.0)
		if Time.get_ticks_msec() - _guard_started_ms <= int(parry_window * 1000.0):
			CombatKit.burst(get_tree().current_scene, spark_at, Color(1.0, 0.85, 0.45), 40, 6.0, 0.025, 3.0)
			_add_trauma(0.45)
			CombatKit.hit_stop(get_tree(), 0.16, 0.08)
			_set_stamina(stamina + 12.0)
			announce.emit("Парирування!")
			return "parried"
		_spend_stamina(block_cost)
		CombatKit.burst(get_tree().current_scene, spark_at, Color(1.0, 0.75, 0.3), 18, 4.0, 0.02, 4.0)
		_add_trauma(0.3)
		if stamina <= 0.0:
			health.apply_damage(damage * 0.5, attacker)
			announce.emit("Захист пробито")
			_stagger(guard_break_stagger)
			return "guard_broken"
		_flinch(0.1, 4.0)
		return "blocked"
	health.apply_damage(damage, attacker)
	CombatKit.burst(get_tree().current_scene, _player.global_position + Vector3.UP * 1.3, Color(0.45, 0.02, 0.02), 20, 3.0)
	_add_trauma(0.6)
	if not health.is_dead():
		_stagger(0.35)
	return "hit"


func _stagger(seconds: float) -> void:
	_end_attack_effects()
	state = State.STAGGER
	_stagger_left = seconds
	_combo_buffered = false
	_anim.speed_scale = 1.0
	_anim.play(_player.idle_clip(), 0.12)
	_flinch(0.18, 12.0)


func _flinch(seconds: float, degrees: float) -> void:
	if _body_pivot == null:
		return
	if _flinch_tween != null:
		_flinch_tween.kill()
	_flinch_tween = create_tween()
	_flinch_tween.tween_property(_body_pivot, "rotation:x", deg_to_rad(degrees), seconds * 0.35)
	_flinch_tween.tween_property(_body_pivot, "rotation:x", 0.0, seconds * 0.65)


func _return_to_idle() -> void:
	_end_attack_effects()
	state = State.IDLE
	_anim.speed_scale = 1.0
	_player.release_animation()


func _on_died(_source: Node) -> void:
	_end_attack_effects()
	state = State.DEAD
	_combo_buffered = false
	_anim.speed_scale = 1.0
	_anim.play(_player.idle_clip(), 0.2)
	_anim.pause()
	_add_trauma(0.7)
	if _flinch_tween != null:
		_flinch_tween.kill()
	var fall := create_tween()
	fall.tween_property(_body_pivot, "rotation:x", deg_to_rad(84.0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	announce.emit("Вас убито")
	died.emit()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	_body_pivot.rotation.x = 0.0
	health.reset()
	_set_stamina(max_stamina)
	_player.respawn()
	_return_to_idle()
	respawned.emit()
	get_tree().call_group(&"enemy", &"reset_encounter")


# --- Helpers -------------------------------------------------------------------

func _clip_time() -> float:
	if _anim == null or _clip == &"" or _anim.current_animation != String(_clip):
		return 100.0
	return _anim.current_animation_position


func _blow(key: String) -> float:
	return float(SabreAttacks.data(_clip)[key])


func _facing() -> Vector3:
	return -_visual_root.global_basis.z.normalized()


func _flat_distance(node: Node3D) -> float:
	var offset := node.global_position - _player.global_position
	offset.y = 0.0
	return offset.length()


func _sabre_point(fallback: Vector3) -> Vector3:
	return _sabre.tip_global_position() if _sabre != null else fallback


func _add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)
