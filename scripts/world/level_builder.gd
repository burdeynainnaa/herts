extends RefCounted

const ASSET_PATH := "res://assets/library/survival-camp/"
const WORLD_MIN_X := -100.0
const WORLD_MAX_X := 100.0
const WORLD_MIN_Z := -155.0
const WORLD_MAX_Z := 35.0
const TERRAIN_STEP := 2.5

static func river_center(z: float) -> float:
	return -48.0 + 40.0 * (1.0 - smoothstep(-100.0, 15.0, z)) + 8.0 * sin(z * 0.055)


static func river_width(z: float) -> float:
	return 12.0 + 4.0 * (0.5 + 0.5 * sin(z * 0.026 + 0.8))


static func terrain_height(x: float, z: float) -> float:
	var ridge := 7.0 * smoothstep(-20.0, 10.0, z)
	var undulation := 0.25 * sin(x * 0.11 + z * 0.07) + 0.18 * cos(z * 0.19 - x * 0.08)
	undulation += 0.8 * (1.0 - smoothstep(-110.0, -65.0, z)) * (0.5 + 0.5 * sin(x * 0.04 + z * 0.03))
	var height := 0.75 + ridge + undulation
	var village_x := smoothstep(4.0, 10.0, x) * (1.0 - smoothstep(52.0, 60.0, x))
	var village_z := smoothstep(-70.0, -62.0, z) * (1.0 - smoothstep(-27.0, -18.0, z))
	height = lerpf(height, 0.75, village_x * village_z)
	var bank_distance := absf(x - river_center(z)) - river_width(z)
	var channel := 1.0 - smoothstep(-1.0, 5.0, bank_distance)
	height = lerpf(height, -0.85, channel)
	return height


static func _owned(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root


static func _material(color: Color, vertex_colors := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = vertex_colors
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)


static func _terrain_color(x: float, z: float, shade: float) -> Color:
	var rock := smoothstep(7.0, 10.0, z) * (1.0 - smoothstep(14.0, 18.0, z)) * (1.0 - smoothstep(2.0, 5.0, absf(x)))
	var grass := Color(0.25, 0.32, 0.16).lerp(Color(0.43, 0.44, 0.24), shade)
	var earth := Color(0.25, 0.26, 0.25).lerp(Color(0.41, 0.40, 0.37), shade)
	return grass.lerp(earth, rock * 0.9)


static func _build_terrain(world: Node3D, root: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x_count := int((WORLD_MAX_X - WORLD_MIN_X) / TERRAIN_STEP)
	var z_count := int((WORLD_MAX_Z - WORLD_MIN_Z) / TERRAIN_STEP)
	for x_index in range(x_count):
		for z_index in range(z_count):
			var x := WORLD_MIN_X + x_index * TERRAIN_STEP
			var z := WORLD_MIN_Z + z_index * TERRAIN_STEP
			var a := Vector3(x, terrain_height(x, z), z)
			var b := Vector3(x + TERRAIN_STEP, terrain_height(x + TERRAIN_STEP, z), z)
			var c := Vector3(x, terrain_height(x, z + TERRAIN_STEP), z + TERRAIN_STEP)
			var d := Vector3(x + TERRAIN_STEP, terrain_height(x + TERRAIN_STEP, z + TERRAIN_STEP), z + TERRAIN_STEP)
			var shade := 0.5 + 0.5 * sin(x * 0.47 + z * 0.26) * cos(z * 0.31 - x * 0.16)
			var color := _terrain_color(x, z, shade)
			_triangle(surface, a, b, c, color)
			_triangle(surface, b, d, c, color.lightened(0.025))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	var ground := StaticBody3D.new()
	ground.name = "WalkableTerrain"
	_owned(world, ground, root)
	var visual := MeshInstance3D.new()
	visual.name = "LowPolyTerrain"
	visual.mesh = mesh
	_owned(ground, visual, root)
	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	var terrain_shape := mesh.create_trimesh_shape()
	terrain_shape.backface_collision = true
	collision.shape = terrain_shape
	_owned(ground, collision, root)


static func _build_river(world: Node3D, root: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(95):
		var z := WORLD_MIN_Z + segment * 2.0
		var next_z := z + 2.0
		var left := Vector3(river_center(z) - river_width(z), 0.28, z)
		var right := Vector3(river_center(z) + river_width(z), 0.28, z)
		var next_left := Vector3(river_center(next_z) - river_width(next_z), 0.28, next_z)
		var next_right := Vector3(river_center(next_z) + river_width(next_z), 0.28, next_z)
		var water_color := Color(0.018, 0.060, 0.085).lerp(Color(0.035, 0.11, 0.15), 0.5 + 0.5 * sin(z * 0.12))
		_triangle(surface, left, right, next_left, water_color)
		_triangle(surface, right, next_right, next_left, water_color)
	surface.generate_normals()
	var mesh := surface.commit()
	var water_material := _material(Color.WHITE, true)
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.roughness = 0.3
	water_material.metallic = 0.0
	mesh.surface_set_material(0, water_material)
	var water := MeshInstance3D.new()
	water.name = "WindingRiver"
	water.mesh = mesh
	_owned(world, water, root)
	var ripples := SurfaceTool.new()
	ripples.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 9245
	for index in range(700):
		var z := random.randf_range(WORLD_MIN_Z, WORLD_MAX_Z)
		var x := river_center(z) + random.randf_range(-river_width(z) * 0.85, river_width(z) * 0.85)
		var length := random.randf_range(0.4, 2.4)
		var color := Color(0.54, 0.58, 0.57).lerp(Color(0.76, 0.57, 0.42), random.randf())
		var a := Vector3(x, 0.30, z)
		var b := Vector3(x + length, 0.30, z + 0.05)
		var c := Vector3(x, 0.30, z + 0.07)
		_triangle(ripples, a, b, c, color)
	ripples.generate_normals()
	var ripple_mesh := ripples.commit()
	ripple_mesh.surface_set_material(0, _material(Color.WHITE, true))
	var highlights := MeshInstance3D.new()
	highlights.name = "RiverHighlights"
	highlights.mesh = ripple_mesh
	_owned(world, highlights, root)


static func _grass_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := [Color(0.72, 0.70, 0.43), Color(0.86, 0.80, 0.50), Color(0.55, 0.62, 0.34), Color(0.92, 0.85, 0.54)]
	for blade in range(11):
		var angle := blade * TAU / 11.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * (0.08 + (blade % 3) * 0.055)
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.055
		var tip := offset + Vector3(sin(angle) * 0.18, 0.65 + (blade % 4) * 0.12, cos(angle) * 0.18)
		var color: Color = colors[blade % colors.size()]
		surface.set_color(color.darkened(0.38))
		surface.add_vertex(offset - side)
		surface.set_color(color.darkened(0.24))
		surface.add_vertex(offset + side)
		surface.set_color(color)
		surface.add_vertex(tip)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	return mesh


static func _flower_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for flower in range(3):
		var offset := Vector3((flower - 1) * 0.23, 0.0, (flower % 2) * 0.18)
		var height := 0.69 + flower * 0.09
		var stem_color := Color(0.27, 0.39, 0.16)
		_triangle(surface, offset + Vector3(-0.012, 0, 0), offset + Vector3(0.012, 0, 0), offset + Vector3(0, height, 0), stem_color)
		for petal in range(5):
			var angle := petal * TAU / 5.0
			var next_angle := (petal + 1) * TAU / 5.0
			var center := offset + Vector3(0, height, 0)
			var edge := center + Vector3(cos(angle) * 0.085, 0.045, sin(angle) * 0.085)
			var next_edge := center + Vector3(cos(next_angle) * 0.085, 0.045, sin(next_angle) * 0.085)
			_triangle(surface, center, edge, next_edge, Color(0.74 + 0.04 * petal, 0.035, 0.045))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	return mesh


static func _build_field(world: Node3D, root: Node) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 53137
	var grass_transforms: Array[Transform3D] = []
	var flower_transforms: Array[Transform3D] = []
	for index in range(65000):
		var x := random.randf_range(-65.0, 68.0)
		var z := random.randf_range(-85.0, 31.0)
		if absf(x - river_center(z)) < river_width(z) + 4.0:
			continue
		if x > 8.0 and x < 54.0 and z < -25.0 and z > -70.0:
			continue
		if absf(x) < 2.0 and z > 10.0 and z < 14.0:
			continue
		var scale_value := random.randf_range(0.75, 1.15) if z > 9.0 else random.randf_range(0.55, 0.85)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value, scale_value))
		var position := Vector3(x, terrain_height(x, z) - 0.04, z)
		grass_transforms.append(Transform3D(basis, position))
		if random.randf() < 0.14 and z > -57.0:
			flower_transforms.append(Transform3D(basis, position))
	_add_multimesh(world, root, "TallGrass", _grass_mesh(), grass_transforms)
	_add_multimesh(world, root, "RedPoppies", _flower_mesh(), flower_transforms)


static func _add_multimesh(parent: Node, root: Node, node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in range(transforms.size()):
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owned(parent, instance, root)


static func _rock_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := [Vector3(-1, 0, -0.7), Vector3(-0.35, -0.05, -1), Vector3(0.65, 0, -0.8), Vector3(1, 0, 0), Vector3(0.55, 0, 0.8), Vector3(-0.6, 0, 0.85)]
	var top := Vector3(0.1, 0.8, 0.0)
	for index in range(ring.size()):
		var color := Color(0.48, 0.40, 0.33).lightened(index * 0.025)
		_triangle(surface, ring[index], ring[(index + 1) % ring.size()], top, color)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	return mesh


static func _build_rocks(world: Node3D, root: Node) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 8432
	var transforms: Array[Transform3D] = []
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := [Vector2(-2.5, 10.2), Vector2(-1.6, 9.4), Vector2(1.0, 9.5), Vector2(2.8, 10.7), Vector2(2.3, 13.5), Vector2(0.6, 14.6), Vector2(-1.9, 14.0)]
	var center := Vector3(0.0, terrain_height(0.0, 12.0) + 0.035, 12.0)
	for index in range(outline.size()):
		var first: Vector2 = outline[index]
		var second: Vector2 = outline[(index + 1) % outline.size()]
		var first_point := Vector3(first.x, terrain_height(first.x, first.y) + 0.035, first.y)
		var second_point := Vector3(second.x, terrain_height(second.x, second.y) + 0.035, second.y)
		_triangle(cap, center, first_point, second_point, Color(0.13, 0.15, 0.15).lightened(index * 0.008))
	cap.generate_normals()
	var cap_mesh := cap.commit()
	cap_mesh.surface_set_material(0, _material(Color.WHITE, true))
	var ledge := MeshInstance3D.new()
	ledge.name = "SpawnRockLedge"
	ledge.mesh = cap_mesh
	_owned(world, ledge, root)
	for point in [Vector3(-7, 0, 12), Vector3(-5, 0, 8), Vector3(-2, 0, 8), Vector3(3, 0, 8), Vector3(5, 0, 8), Vector3(8, 0, 12), Vector3(-9, 0, 5), Vector3(7, 0, 4)]:
		var size := random.randf_range(1.1, 2.2)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(size * 1.5, size * 0.5, size))
		transforms.append(Transform3D(basis, Vector3(point.x, terrain_height(point.x, point.z) - 0.22, point.z)))
	for index in range(90):
		var x := random.randf_range(-62.0, 65.0)
		var z := random.randf_range(-58.0, 28.0)
		if absf(x - river_center(z)) < river_width(z) + 3.0 or (absf(x) < 5.0 and z > 7.0 and z < 20.0):
			continue
		if x > 7.0 and x < 53.0 and z < -25.0 and z > -70.0:
			continue
		var size := random.randf_range(0.5, 2.0)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(size * 1.4, size * 0.55, size))
		transforms.append(Transform3D(basis, Vector3(x, terrain_height(x, z) - 0.1, z)))
	_add_multimesh(world, root, "RidgeAndFieldRocks", _rock_mesh(), transforms)


static func _instance_model(parent: Node, root: Node, resource: PackedScene, node_name: String, position: Vector3, yaw: float = 0.0, scale_value: float = 1.0) -> Node3D:
	var model := resource.instantiate() as Node3D
	model.name = node_name
	model.position = position
	model.rotation.y = yaw
	model.scale = Vector3.ONE * scale_value
	_owned(parent, model, root)
	return model


static func _wall_collider(parent: Node, root: Node, node_name: String, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	_owned(parent, body, root)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_owned(body, collision, root)


static func _canopy_lobe(surface: SurfaceTool, center: Vector3, radii: Vector3, offset: float) -> void:
	var segments := 8
	var rings := 4
	for ring in range(rings):
		var lower_angle := -PI * 0.5 + PI * ring / rings
		var upper_angle := -PI * 0.5 + PI * (ring + 1) / rings
		for segment in range(segments):
			var angle := TAU * segment / segments
			var next_angle := TAU * (segment + 1) / segments
			var variation := 0.88 + 0.14 * sin(segment * 2.7 + ring * 1.3 + offset)
			var next_variation := 0.88 + 0.14 * sin((segment + 1) * 2.7 + ring * 1.3 + offset)
			var lower := center + Vector3(cos(angle) * cos(lower_angle) * radii.x * variation, sin(lower_angle) * radii.y, sin(angle) * cos(lower_angle) * radii.z * variation)
			var lower_next := center + Vector3(cos(next_angle) * cos(lower_angle) * radii.x * next_variation, sin(lower_angle) * radii.y, sin(next_angle) * cos(lower_angle) * radii.z * next_variation)
			var upper := center + Vector3(cos(angle) * cos(upper_angle) * radii.x * variation, sin(upper_angle) * radii.y, sin(angle) * cos(upper_angle) * radii.z * variation)
			var upper_next := center + Vector3(cos(next_angle) * cos(upper_angle) * radii.x * next_variation, sin(upper_angle) * radii.y, sin(next_angle) * cos(upper_angle) * radii.z * next_variation)
			var shade := 0.5 + 0.5 * sin(segment * 1.7 + ring * 2.2 + offset)
			var color := Color(0.14, 0.23, 0.12).lerp(Color(0.32, 0.39, 0.19), shade)
			_triangle(surface, lower, upper, lower_next, color)
			_triangle(surface, lower_next, upper, upper_next, color.lightened(0.04))


static func _broadleaf_tree_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(7):
		var angle := TAU * segment / 7.0
		var next_angle := TAU * (segment + 1) / 7.0
		var base := Vector3(cos(angle) * 0.34, 0, sin(angle) * 0.34)
		var base_next := Vector3(cos(next_angle) * 0.34, 0, sin(next_angle) * 0.34)
		var top := Vector3(cos(angle) * 0.17, 5.2, sin(angle) * 0.17)
		var top_next := Vector3(cos(next_angle) * 0.17, 5.2, sin(next_angle) * 0.17)
		var bark := Color(0.25, 0.20, 0.15).lightened(segment * 0.015)
		_triangle(surface, base, top, base_next, bark)
		_triangle(surface, base_next, top, top_next, bark)
	_canopy_lobe(surface, Vector3(0, 6.2, 0), Vector3(2.5, 2.1, 2.3), 0.2)
	_canopy_lobe(surface, Vector3(-1.65, 5.0, 0.3), Vector3(1.7, 1.6, 1.7), 2.1)
	_canopy_lobe(surface, Vector3(1.65, 5.2, -0.15), Vector3(1.8, 1.7, 1.7), 4.3)
	_canopy_lobe(surface, Vector3(0, 5.1, 1.5), Vector3(1.7, 1.5, 1.5), 6.3)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	return mesh


static func _build_broadleaf_forest(parent: Node3D, root: Node) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 50439
	var transforms: Array[Transform3D] = []
	for index in range(260):
		var x: float
		var z: float
		if index < 145:
			z = random.randf_range(-118.0, -24.0)
			x = maxf(-98.0, river_center(z) - river_width(z) - random.randf_range(4.0, 34.0))
		else:
			z = random.randf_range(-150.0, -84.0)
			x = random.randf_range(-98.0, 98.0)
			if absf(x - river_center(z)) < river_width(z) + 5.0:
				continue
		var scale_value := random.randf_range(0.95, 1.6)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value, scale_value))
		transforms.append(Transform3D(basis, Vector3(x, terrain_height(x, z) - 0.1, z)))
	_add_multimesh(parent, root, "BroadleafForest", _broadleaf_tree_mesh(), transforms)


static func _build_village(world: Node3D, root: Node) -> void:
	var village := Node3D.new()
	village.name = "PalisadeVillage"
	_owned(world, village, root)
	var wall: PackedScene = load(ASSET_PATH + "log-wall.glb")
	var cabin: PackedScene = load(ASSET_PATH + "cabin.glb")
	var tower: PackedScene = load(ASSET_PATH + "stronghold-tower.glb")
	var gate: PackedScene = load(ASSET_PATH + "gate.glb")
	for segment in range(19):
		var x := 9.0 + segment * 2.1
		_instance_model(village, root, wall, "FrontWall%02d" % segment, Vector3(x, 0.75, -25.0))
	for segment in range(17):
		var z := -27.1 - segment * 2.1
		_instance_model(village, root, wall, "SideWall%02d" % segment, Vector3(48.0, 0.75, z), PI / 2.0)
	for segment in range(18):
		var x := 10.0 + segment * 2.1
		_instance_model(village, root, wall, "BackWall%02d" % segment, Vector3(x, 0.75, -63.0))
	for segment in range(17):
		var z := -27.1 - segment * 2.1
		_instance_model(village, root, wall, "RiverSideWall%02d" % segment, Vector3(8.0, 0.75, z), PI / 2.0)
	_instance_model(village, root, tower, "WestWatchtower", Vector3(9.0, 0.75, -25.0))
	_instance_model(village, root, tower, "EastWatchtower", Vector3(46.0, 0.75, -25.0))
	_instance_model(village, root, gate, "VillageGate", Vector3(29.0, 0.75, -25.3))
	var huts := [Vector3(16, 0.75, -34), Vector3(27, 0.75, -36), Vector3(39, 0.75, -35), Vector3(17, 0.75, -48), Vector3(30, 0.75, -51), Vector3(41, 0.75, -49), Vector3(22, 0.75, -59)]
	for index in range(huts.size()):
		_instance_model(village, root, cabin, "TimberHut%02d" % index, huts[index], (index % 3 - 1) * 0.15, 1.05 + (index % 2) * 0.12)
	_wall_collider(village, root, "FrontWallCollision", Vector3(28.5, 2.0, -25.0), Vector3(40.0, 2.5, 0.55))
	_wall_collider(village, root, "WestWallCollision", Vector3(8.0, 2.0, -44.0), Vector3(0.55, 2.5, 38.0))
	_wall_collider(village, root, "EastWallCollision", Vector3(48.0, 2.0, -44.0), Vector3(0.55, 2.5, 38.0))
	_wall_collider(village, root, "BackWallCollision", Vector3(28.0, 2.0, -63.0), Vector3(40.0, 2.5, 0.55))


static func _build_trees(world: Node3D, root: Node) -> void:
	var trees := Node3D.new()
	trees.name = "RiverbankAndDistantTreeline"
	_owned(world, trees, root)
	var tree: PackedScene = load(ASSET_PATH + "birch.glb")
	var bush: PackedScene = load(ASSET_PATH + "bush.glb")
	var random := RandomNumberGenerator.new()
	random.seed = 7162
	for index in range(65):
		var x: float
		var z: float
		if index < 60:
			x = random.randf_range(-100.0, 100.0)
			z = random.randf_range(-142.0, -94.0)
		else:
			z = random.randf_range(-105.0, -12.0)
			var side := -1.0 if index % 2 == 0 else 1.0
			x = river_center(z) + side * (river_width(z) + random.randf_range(6.0, 17.0))
			if x > 4.0 and x < 58.0 and z > -72.0:
				continue
		var height := terrain_height(x, z)
		_instance_model(trees, root, tree, "Tree%03d" % index, Vector3(x, height, z), random.randf_range(0.0, TAU), random.randf_range(0.9, 1.5))
	for index in range(20):
		var z := random.randf_range(-100.0, -26.0)
		var x := river_center(z) - river_width(z) - random.randf_range(3.0, 12.0)
		_instance_model(trees, root, bush, "Bush%02d" % index, Vector3(x, terrain_height(x, z), z), random.randf_range(0.0, TAU), random.randf_range(0.8, 1.5))
	_build_broadleaf_forest(trees, root)


static func _build_atmosphere(world: Node3D, root: Node) -> void:
	var atmosphere := Node3D.new()
	atmosphere.name = "MeadowAtmosphere"
	_owned(world, atmosphere, root)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.78, 0.59, 0.24))
	gradient.set_color(1, Color(1.0, 0.78, 0.59, 0.0))
	var mist_texture := GradientTexture2D.new()
	mist_texture.width = 256
	mist_texture.height = 64
	mist_texture.fill = GradientTexture2D.FILL_RADIAL
	mist_texture.fill_from = Vector2(0.5, 0.5)
	mist_texture.fill_to = Vector2(0.5, 0.0)
	mist_texture.gradient = gradient
	var random := RandomNumberGenerator.new()
	random.seed = 3447
	for index in range(14):
		var x := random.randf_range(-18.0, 40.0)
		var z := random.randf_range(-34.0, -6.0)
		var mist := Sprite3D.new()
		mist.name = "GroundMist%02d" % index
		mist.texture = mist_texture
		mist.pixel_size = random.randf_range(0.028, 0.045)
		mist.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mist.position = Vector3(x, terrain_height(x, z) + random.randf_range(0.7, 1.3), z)
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_owned(atmosphere, mist, root)
	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(32, 4.5, 29)
	particle_material.direction = Vector3(0.4, 0.7, 0.15)
	particle_material.spread = 45.0
	particle_material.initial_velocity_min = 0.15
	particle_material.initial_velocity_max = 0.5
	particle_material.gravity = Vector3(0, 0.02, 0)
	particle_material.scale_min = 0.6
	particle_material.scale_max = 1.3
	particle_material.color = Color(1.0, 0.27, 0.08, 0.65)
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.025, 0.025)
	var particle_draw := StandardMaterial3D.new()
	particle_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_draw.vertex_color_use_as_albedo = true
	particle_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_draw
	var embers := GPUParticles3D.new()
	embers.name = "DriftingEmbers"
	embers.position = Vector3(3, 7, -8)
	embers.amount = 70
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	embers.visibility_aabb = AABB(Vector3(-40, -9, -38), Vector3(80, 22, 76))
	embers.process_material = particle_material
	embers.draw_pass_1 = particle_mesh
	_owned(atmosphere, embers, root)


static func _lighting(root: Node3D) -> void:
	var sun := root.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-7.0, 172.0, 0.0)
	sun.light_color = Color(1.0, 0.66, 0.43)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://scripts/world/sunset_sky.gdshader")
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.52, 0.48, 0.45)
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.49, 0.31, 0.26)
	environment.fog_density = 0.004
	environment.fog_sky_affect = 0.05
	(root.get_node("WorldEnvironment") as WorldEnvironment).environment = environment


static func build(root: Node3D) -> void:
	var old_ground := root.get_node_or_null("TestGround")
	if old_ground != null:
		root.remove_child(old_ground)
		old_ground.free()
	var old_world := root.get_node_or_null("FirstLevel")
	if old_world != null:
		root.remove_child(old_world)
		old_world.free()
	var world := Node3D.new()
	world.name = "FirstLevel"
	_owned(root, world, root)
	_build_terrain(world, root)
	_build_river(world, root)
	_build_field(world, root)
	_build_rocks(world, root)
	_build_village(world, root)
	_build_trees(world, root)
	_build_atmosphere(world, root)
	_lighting(root)
	var player := root.get_node("Player") as CharacterBody3D
	player.position = Vector3(0.0, terrain_height(0.0, 12.0) + 0.12, 12.0)
	player.set("camera_distance", 3.1)
	player.set("camera_height", 1.65)
	player.set("camera_pitch_degrees", -10.0)
	player.set("character_tint", Color(0.57, 0.62, 0.67))
