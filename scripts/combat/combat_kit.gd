class_name CombatKit
extends RefCounted
## Shared combat helpers: borrowed sabre clips, the sabre in the right hand,
## hit effects and hit-stop. Player and enemies use the same pieces.

## The Herts Cossack rig ships only locomotion; the Cossack warrior rig has the
## same 24-bone skeleton plus a high guard. The guard is copied into any
## AnimationPlayer that drives that skeleton, and the three sabre blows
## (SabreAttacks) are baked for it.
const CLIP_SOURCE := "res://assets/models/cossack_warrior/rig.glb"
const GUARD := &"SabreGuard"
const _SOURCE_NAMES := {GUARD: &"Block1"}

static var _clips: Dictionary = {}


## grip is the sabre's basis in RightHand space (see arm_with_sabre).
static func install_clips(player: AnimationPlayer, skeleton: Skeleton3D, body: Node3D, idle_clip: StringName,
		grip: Basis) -> bool:
	if _clips.is_empty():
		var scene := load(CLIP_SOURCE) as PackedScene
		if scene == null:
			push_error("CombatKit: missing clip source %s" % CLIP_SOURCE)
			return false
		var source := scene.instantiate()
		var source_player := source.find_children("*", "AnimationPlayer", true, false)
		if source_player.is_empty():
			source.free()
			push_error("CombatKit: clip source has no AnimationPlayer")
			return false
		for clip in _SOURCE_NAMES:
			var anim := (source_player[0] as AnimationPlayer).get_animation(_SOURCE_NAMES[clip])
			if anim == null:
				source.free()
				push_error("CombatKit: clip source has no %s" % _SOURCE_NAMES[clip])
				return false
			_clips[clip] = anim.duplicate(true)
		source.free()
		(_clips[GUARD] as Animation).loop_mode = Animation.LOOP_PINGPONG
	var library := player.get_animation_library(&"")
	if library == null:
		return false
	for clip in _clips:
		if not library.has_animation(clip):
			library.add_animation(clip, _clips[clip])
	return SabreAttacks.install(player, skeleton, body, idle_clip, grip)


## Puts a sabre in the right hand of a character's skeleton.
static func arm_with_sabre(skeleton: Skeleton3D, steel: Color = Color(0.74, 0.76, 0.78)) -> Sabre:
	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandSabre"
	attachment.bone_name = "RightHand"
	skeleton.add_child(attachment)
	var sabre := Sabre.new()
	sabre.name = "Sabre"
	sabre.steel_color = steel
	# Bone space is in centimetres (the armature is scaled 0.01). The blade
	# leaves the fist along the finger axis (+Y), edge forward.
	sabre.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 100.0), Vector3(0.0, 8.0, 0.0))
	attachment.add_child(sabre)
	return sabre


## One-shot burst of small particles: blood on flesh, sparks on steel.
static func burst(world: Node, position: Vector3, color: Color, amount: int = 18, speed: float = 3.0,
		size: float = 0.022, gravity: float = 9.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.55
	particles.explosiveness = 0.95
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.gravity = Vector3.DOWN * gravity
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	var dot := SphereMesh.new()
	dot.radius = size
	dot.height = size * 2.0
	dot.radial_segments = 6
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if color.get_luminance() > 0.5:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 3.0
	dot.material = material
	particles.mesh = dot
	world.add_child(particles)
	particles.global_position = position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Freezes the game for a moment so a hit lands with weight.
static func hit_stop(tree: SceneTree, seconds: float = 0.06, time_scale: float = 0.05) -> void:
	if tree == null:
		return
	Engine.time_scale = time_scale
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0


## Living enemies, nearest first.
static func living_enemies(tree: SceneTree, from: Vector3) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in tree.get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy != null and enemy.has_method("is_alive") and enemy.is_alive():
			result.append(enemy)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	return result


## True when target stands within reach and inside the cone in front of origin.
static func in_strike_arc(origin: Vector3, forward: Vector3, target: Vector3, reach: float,
		half_angle_degrees: float) -> bool:
	var offset := target - origin
	offset.y = 0.0
	var distance := offset.length()
	if distance > reach:
		return false
	if distance < 0.4:
		return true
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	return flat_forward.angle_to(offset / distance) <= deg_to_rad(half_angle_degrees)
