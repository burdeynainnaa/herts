@tool
class_name Sabre
extends MeshInstance3D
## A curved Cossack sabre (shablia) built in code: blade, cross-guard and grip.
## Local space: the grip centre is the origin, the blade runs along +Y and
## curves toward -Z (the back of the blade is +Z, the cutting edge -Z).

@export var blade_length: float = 0.82:
	set(value):
		blade_length = value
		_rebuild()
@export var blade_curve: float = 0.07:
	set(value):
		blade_curve = value
		_rebuild()
@export var steel_color: Color = Color(0.74, 0.76, 0.78):
	set(value):
		steel_color = value
		_rebuild()
@export var grip_color: Color = Color(0.22, 0.12, 0.07):
	set(value):
		grip_color = value
		_rebuild()
@export var brass_color: Color = Color(0.72, 0.55, 0.25):
	set(value):
		brass_color = value
		_rebuild()

## How long a point of the blade trail lingers, in seconds.
@export var trail_lifetime: float = 0.16
@export var trail_color: Color = Color(1.0, 0.93, 0.8, 0.32)

var _steel: StandardMaterial3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: Array = []
var _trailing: bool = false


func _ready() -> void:
	_rebuild()
	set_process(false)


## Starts drawing a fading ribbon behind the blade: the swing's motion arc.
func start_trail() -> void:
	if Engine.is_editor_hint():
		return
	if _trail == null:
		_trail_mesh = ImmediateMesh.new()
		_trail = MeshInstance3D.new()
		_trail.name = "Trail"
		_trail.top_level = true
		_trail.mesh = _trail_mesh
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		_trail.material_override = material
		add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY
	_trailing = true
	set_process(true)


func stop_trail() -> void:
	_trailing = false


func _process(delta: float) -> void:
	for point in _trail_points:
		point[2] += delta
	while not _trail_points.is_empty() and _trail_points[0][2] > trail_lifetime:
		_trail_points.pop_front()
	if _trailing:
		_trail_points.append([to_global(Vector3(0.0, 0.45, -blade_curve * 0.2)), tip_global_position(), 0.0])
	_trail_mesh.clear_surfaces()
	if _trail_points.size() >= 2:
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for point in _trail_points:
			var fade := 1.0 - float(point[2]) / trail_lifetime
			var inner := trail_color
			inner.a *= fade * 0.1
			var outer := trail_color
			outer.a *= fade
			_trail_mesh.surface_set_color(inner)
			_trail_mesh.surface_add_vertex(point[0])
			_trail_mesh.surface_set_color(outer)
			_trail_mesh.surface_add_vertex(point[1])
		_trail_mesh.surface_end()
	elif not _trailing:
		set_process(false)


## Brief bright glint on the steel: the enemy telegraph before a strike.
func glint(strength: float = 2.5, seconds: float = 0.35) -> void:
	if _steel == null:
		return
	_steel.emission_enabled = true
	_steel.emission = Color(1.0, 0.86, 0.55)
	_steel.emission_energy_multiplier = strength
	var tween := create_tween()
	tween.tween_property(_steel, "emission_energy_multiplier", 0.0, seconds)


## World-space point near the tip, used for hit effects.
func tip_global_position() -> Vector3:
	return to_global(Vector3(0.0, 0.1 + blade_length * 0.8, -blade_curve * 0.6))


func _rebuild() -> void:
	var mesh_out := ArrayMesh.new()
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = steel_color
	_steel.metallic = 0.9
	_steel.roughness = 0.28
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = grip_color
	grip_mat.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = brass_color
	brass.metallic = 0.7
	brass.roughness = 0.4
	_add_surface(mesh_out, _blade_arrays(), _steel)
	_add_surface(mesh_out, _box_arrays(Vector3(0.0, 0.06, 0.0), Vector3(0.022, 0.02, 0.13)), brass)
	_add_surface(mesh_out, _box_arrays(Vector3(0.0, -0.03, 0.006), Vector3(0.024, 0.13, 0.03)), grip_mat)
	_add_surface(mesh_out, _box_arrays(Vector3(0.0, -0.1, 0.018), Vector3(0.028, 0.03, 0.05)), brass)
	mesh = mesh_out
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _add_surface(target: ArrayMesh, arrays: Array, material: Material) -> void:
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.surface_set_material(target.get_surface_count() - 1, material)


func _blade_arrays() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 14
	var base_y := 0.07
	var rows: Array = []
	for i in segments + 1:
		var t := float(i) / segments
		var y := base_y + t * blade_length
		var bend := -blade_curve * t * t
		var width := lerpf(0.034, 0.012, pow(t, 1.6))
		if i == segments:
			width = 0.0
		var spine := 0.0045 * (1.0 - t * 0.7)
		# back of blade (+Z side), edge (-Z side); thickness along X
		var back_l := Vector3(-spine, y, bend + width * 0.5)
		var back_r := Vector3(spine, y, bend + width * 0.5)
		var edge := Vector3(0.0, y + (0.02 if i == segments else 0.0), bend - width * 0.5)
		rows.append([back_l, back_r, edge])
	for i in segments:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		_quad(st, a[0], b[0], b[2], a[2])  # left face
		_quad(st, a[2], b[2], b[1], a[1])  # right face
		_quad(st, a[1], b[1], b[0], a[0])  # spine
	st.generate_normals()
	return st.commit_to_arrays()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _box_arrays(center: Vector3, size: Vector3) -> Array:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += center
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays
