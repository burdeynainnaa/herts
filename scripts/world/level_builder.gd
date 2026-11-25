extends RefCounted

const ASSET_PATH := "res://assets/library/survival-camp/"
const WORLD_MIN_X := -100.0
const WORLD_MAX_X := 100.0
const WORLD_MIN_Z := -155.0
const WORLD_MAX_Z := 35.0
const TERRAIN_STEP := 2.5
const WATER_LEVEL := 0.28
const ISLAND_CENTER_Z := -69.0
const ISLAND_HALF_LENGTH := 32.0
const ISLAND_HALF_WIDTH := 10.0
const ROAD_MAIN := [
	Vector2(43.3, -155.0), Vector2(42.1, -146.8), Vector2(35.3, -115.9),
	Vector2(30.3, -97.3), Vector2(23.3, -83.8), Vector2(14.7, -69.9),
	Vector2(8.7, -61.4), Vector2(5.0, -55.4), Vector2(3.4, -47.4),
	Vector2(4.3, -36.3), Vector2(7.6, -30.2), Vector2(14.0, -23.0),
	Vector2(19.5, -19.1), Vector2(26.6, -16.1), Vector2(36.0, -14.5),
	Vector2(45.3, -11.0), Vector2(55.5, -4.1), Vector2(61.3, 2.9),
	Vector2(67.4, 12.3), Vector2(74.0, 24.0), Vector2(79.9, 34.4)
]
const ROAD_GATE := [Vector2(26.6, -16.1), Vector2(28.0, -20.5), Vector2(28.5, -25.8)]
const STRONGHOLD_RISE_OUTLINE := [
	Vector2(120.0, -70.0), Vector2(68.0, -70.0), Vector2(41.0, -69.0),
	Vector2(24.0, -68.0), Vector2(17.0, -65.0), Vector2(12.0, -60.0),
	Vector2(8.0, -49.0), Vector2(7.0, -39.0), Vector2(8.0, -35.0),
	Vector2(14.0, -29.0), Vector2(26.0, -21.0), Vector2(34.0, -13.0),
	Vector2(46.0, -2.0), Vector2(57.0, 11.5), Vector2(67.0, 22.0),
	Vector2(76.0, 34.0), Vector2(90.0, 50.0), Vector2(120.0, 50.0)
]

static func river_center(z: float) -> float:
	return -51.0 + 40.0 * (1.0 - smoothstep(-100.0, 15.0, z)) + 8.0 * sin(z * 0.055)


static func river_width(z: float) -> float:
	return 17.0 + 4.0 * (0.5 + 0.5 * sin(z * 0.026 + 0.8))


static func island_center(z: float) -> float:
	return river_center(z) - 1.5


static func island_weight(x: float, z: float) -> float:
	var along := (z - ISLAND_CENTER_Z) / ISLAND_HALF_LENGTH
	var across := (x - island_center(z)) / ISLAND_HALF_WIDTH
	return 1.0 - smoothstep(0.78, 1.06, sqrt(along * along + across * across))


static func stronghold_elevation(x: float, z: float) -> float:
	if x < -3.0 or z < -80.0:
		return 0.0
	var point := Vector2(x, z)
	var outline := PackedVector2Array(STRONGHOLD_RISE_OUTLINE)
	var weight := 1.0
	if not Geometry2D.is_point_in_polygon(point, outline):
		var nearest := INF
		for index in range(outline.size()):
			var first := outline[index]
			var edge := outline[(index + 1) % outline.size()] - first
			var amount := clampf((point - first).dot(edge) / edge.length_squared(), 0.0, 1.0)
			nearest = minf(nearest, point.distance_squared_to(first + edge * amount))
		weight = 1.0 - smoothstep(0.0, 10.0, sqrt(nearest))
	var bank_distance := absf(x - river_center(z)) - river_width(z)
	return 1.8 * weight * smoothstep(1.0, 7.0, bank_distance)


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
	var island_height := 0.86 + 0.09 * sin(x * 0.25 + z * 0.12)
	height = lerpf(height, island_height, island_weight(x, z))
	return height + stronghold_elevation(x, z)


static func terrain_surface_height(x: float, z: float) -> float:
	x = clampf(x, WORLD_MIN_X, WORLD_MAX_X - 0.001)
	z = clampf(z, WORLD_MIN_Z, WORLD_MAX_Z - 0.001)
	var cell_x := WORLD_MIN_X + floorf((x - WORLD_MIN_X) / TERRAIN_STEP) * TERRAIN_STEP
	var cell_z := WORLD_MIN_Z + floorf((z - WORLD_MIN_Z) / TERRAIN_STEP) * TERRAIN_STEP
	var across := (x - cell_x) / TERRAIN_STEP
	var along := (z - cell_z) / TERRAIN_STEP
	var a := terrain_height(cell_x, cell_z)
	var b := terrain_height(cell_x + TERRAIN_STEP, cell_z)
	var c := terrain_height(cell_x, cell_z + TERRAIN_STEP)
	var d := terrain_height(cell_x + TERRAIN_STEP, cell_z + TERRAIN_STEP)
	if across + along <= 1.0:
		return a + (b - a) * across + (c - a) * along
	return d + (c - d) * (1.0 - across) + (b - d) * (1.0 - along)


static func _distance_to_road(point: Vector2) -> float:
	var closest := INF
	for route in [ROAD_MAIN, ROAD_GATE]:
		for index in range(route.size() - 1):
			var first: Vector2 = route[index]
			var second: Vector2 = route[index + 1]
			var edge := second - first
			var amount := clampf((point - first).dot(edge) / edge.length_squared(), 0.0, 1.0)
			closest = minf(closest, point.distance_squared_to(first + edge * amount))
	return sqrt(closest)


static func _road_curve(points: Array) -> Curve2D:
	var curve := Curve2D.new()
	curve.bake_interval = 0.3
	for index in range(points.size()):
		var previous: Vector2 = points[maxi(index - 1, 0)]
		var next: Vector2 = points[mini(index + 1, points.size() - 1)]
		var tangent := (next - previous) * 0.18
		curve.add_point(points[index], -tangent, tangent)
	return curve


static func _road_point(point: Vector2, lift: float) -> Vector3:
	var x := clampf(point.x, WORLD_MIN_X, WORLD_MAX_X)
	var z := clampf(point.y, WORLD_MIN_Z, WORLD_MAX_Z)
	return Vector3(x, terrain_surface_height(x, z) + lift, z)


static func _road_strip(surface: SurfaceTool, points: Array, width: float, lift: float) -> void:
	var curve := _road_curve(points)
	var length := curve.get_baked_length()
	var count := ceili(length / 0.65)
	var noise := FastNoiseLite.new()
	noise.seed = 9182
	noise.frequency = 0.16
	noise.fractal_octaves = 3
	var rows: Array = []
	for index in range(count + 1):
		var distance := length * index / count
		var center := curve.sample_baked(distance)
		var before := curve.sample_baked(maxf(0.0, distance - 0.25))
		var after := curve.sample_baked(minf(length, distance + 0.25))
		var direction := (after - before).normalized()
		var side := Vector2(-direction.y, direction.x)
		var row := []
		var left_width := width * 0.5 * (1.0 + noise.get_noise_2d(distance, 15.0) * 0.27)
		var right_width := width * 0.5 * (1.0 + noise.get_noise_2d(distance, 60.0) * 0.27)
		for column in range(9):
			var across := float(column) / 4.0 - 1.0
			var offset := across * (left_width if across < 0.0 else right_width)
			var point := center + side * offset
			var variation := noise.get_noise_2d(point.x * 1.5, point.y * 1.5)
			var earth := Color(0.36, 0.29, 0.20).lerp(Color(0.46, 0.37, 0.25), clampf(0.5 + variation * 0.65, 0.0, 1.0))
			var edge_alpha := 1.0 - smoothstep(0.48, 1.0, absf(across))
			earth.a = edge_alpha * clampf(0.88 + variation * 0.16, 0.7, 0.98)
			row.append([_road_point(point, lift), earth])
		rows.append(row)
	for index in range(count):
		for column in range(8):
			for vertex in [rows[index][column], rows[index + 1][column], rows[index][column + 1], rows[index][column + 1], rows[index + 1][column], rows[index + 1][column + 1]]:
				surface.set_color(vertex[1])
				surface.add_vertex(vertex[0])


static func _filter_road_multimesh(instance: MultiMeshInstance3D, clearance: float) -> bool:
	var old := instance.multimesh
	var retained: Array[int] = []
	for index in range(old.instance_count):
		var position := old.get_instance_transform(index).origin
		if _distance_to_road(Vector2(position.x, position.z)) >= clearance:
			retained.append(index)
	if retained.size() == old.instance_count:
		return false
	var replacement := MultiMesh.new()
	replacement.transform_format = old.transform_format
	replacement.use_colors = old.use_colors
	replacement.use_custom_data = old.use_custom_data
	replacement.mesh = old.mesh
	replacement.instance_count = retained.size()
	for index in range(retained.size()):
		var source := retained[index]
		replacement.set_instance_transform(index, old.get_instance_transform(source))
		if old.use_colors:
			replacement.set_instance_color(index, old.get_instance_color(source))
		if old.use_custom_data:
			replacement.set_instance_custom_data(index, old.get_instance_custom_data(source))
	instance.multimesh = replacement
	return true


static func build_road(root: Node3D) -> void:
	var world := root.get_node("FirstLevel") as Node3D
	var old_road := world.get_node_or_null("StrongholdRoad")
	if old_road != null:
		old_road.free()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_road_strip(surface, ROAD_MAIN, 3.4, 0.055)
	_road_strip(surface, ROAD_GATE, 3.0, 0.065)
	surface.generate_normals()
	var road := MeshInstance3D.new()
	road.name = "StrongholdRoad"
	road.mesh = surface.commit()
	var trail_material := _material(Color.WHITE, true)
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	road.mesh.surface_set_material(0, trail_material)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owned(world, road, root)
	for node_name in ["TallGrass", "RedPoppies"]:
		var instance := world.get_node_or_null(node_name) as MultiMeshInstance3D
		if instance != null:
			_filter_road_multimesh(instance, 1.8)
	var rocks := world.get_node_or_null("RidgeAndFieldRocks") as MultiMeshInstance3D
	if rocks != null and _filter_road_multimesh(rocks, 5.0):
		add_rock_collision(world, root)
	var trees := world.get_node_or_null("RiverbankAndDistantTreeline")
	if trees != null:
		for child in trees.get_children():
			if child is MultiMeshInstance3D and child.name == "BroadleafForest":
				_filter_road_multimesh(child, 5.5)
			elif child is Node3D and (child.name.begins_with("Tree") or child.name.begins_with("Bush")):
				var position: Vector3 = child.position
				if _distance_to_road(Vector2(position.x, position.z)) < 5.5:
					child.free()


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
	var color := grass.lerp(earth, rock * 0.9)
	if absf(x - river_center(z)) < river_width(z) + 8.0:
		var height := terrain_height(x, z)
		var beach := smoothstep(WATER_LEVEL - 0.2, WATER_LEVEL + 0.1, height) * (1.0 - smoothstep(WATER_LEVEL + 0.35, WATER_LEVEL + 1.2, height))
		color = color.lerp(Color(0.48, 0.42, 0.29), beach * 0.8)
	return color


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
			var color_a := _terrain_color(a.x, a.z, shade)
			var color_b := _terrain_color(b.x, b.z, shade)
			var color_c := _terrain_color(c.x, c.z, shade)
			var color_d := _terrain_color(d.x, d.z, shade)
			for pair in [[a, color_a], [b, color_b], [c, color_c], [b, color_b], [d, color_d], [c, color_c]]:
				surface.set_color(pair[1])
				surface.add_vertex(pair[0])
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
		var left := Vector3(river_center(z) - river_width(z) - 7.0, WATER_LEVEL, z)
		var right := Vector3(river_center(z) + river_width(z) + 7.0, WATER_LEVEL, z)
		var next_left := Vector3(river_center(next_z) - river_width(next_z) - 7.0, WATER_LEVEL, next_z)
		var next_right := Vector3(river_center(next_z) + river_width(next_z) + 7.0, WATER_LEVEL, next_z)
		var water_color := Color(0.022, 0.075, 0.11).lerp(Color(0.035, 0.105, 0.14), 0.5 + 0.5 * sin(z * 0.035))
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
	for index in range(220):
		var z := random.randf_range(WORLD_MIN_Z, WORLD_MAX_Z)
		var x := river_center(z) + random.randf_range(-river_width(z) * 0.85, river_width(z) * 0.85)
		if terrain_surface_height(x, z) > WATER_LEVEL - 0.05:
			continue
		var length := random.randf_range(0.4, 2.4)
		var color := Color(0.22, 0.31, 0.34).lerp(Color(0.46, 0.38, 0.31), random.randf())
		var a := Vector3(x, WATER_LEVEL + 0.02, z)
		var b := Vector3(x + length, WATER_LEVEL + 0.02, z + 0.05)
		var c := Vector3(x, WATER_LEVEL + 0.02, z + 0.045)
		_triangle(ripples, a, b, c, color)
	ripples.generate_normals()
	var ripple_mesh := ripples.commit()
	ripple_mesh.surface_set_material(0, _material(Color.WHITE, true))
	var highlights := MeshInstance3D.new()
	highlights.name = "RiverHighlights"
	highlights.mesh = ripple_mesh
	_owned(world, highlights, root)
	_build_shores(world, root)


static func _waterline_x(z: float, land_x: float, water_x: float) -> float:
	for iteration in range(12):
		var middle := (land_x + water_x) * 0.5
		if terrain_surface_height(middle, z) > WATER_LEVEL:
			land_x = middle
		else:
			water_x = middle
	return land_x


static func _append_shore(surface: SurfaceTool, faces: PackedVector3Array, previous_edge: Vector3, previous_beach: Vector3, edge: Vector3, beach: Vector3) -> void:
	var sand := Color(0.48, 0.42, 0.30)
	_triangle(surface, previous_edge, previous_beach, edge, sand)
	_triangle(surface, previous_beach, beach, edge, sand.lightened(0.025))
	var bottom_a := Vector3(previous_edge.x, -4.0, previous_edge.z)
	var bottom_b := Vector3(edge.x, -4.0, edge.z)
	var top_a := Vector3(previous_edge.x, 14.0, previous_edge.z)
	var top_b := Vector3(edge.x, 14.0, edge.z)
	faces.append_array(PackedVector3Array([bottom_a, top_a, bottom_b, bottom_b, top_a, top_b]))


static func _build_shores(world: Node3D, root: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var step := TERRAIN_STEP * 0.25
	for island in [false, true]:
		for side in [-1.0, 1.0]:
			var previous_valid := false
			var previous_edge := Vector3.ZERO
			var previous_beach := Vector3.ZERO
			for segment in range(int((WORLD_MAX_Z - WORLD_MIN_Z) / step) + 1):
				var z := WORLD_MIN_Z + segment * step
				if island and terrain_surface_height(island_center(z), z) <= WATER_LEVEL:
					previous_valid = false
					continue
				var land_x: float = island_center(z) if island else river_center(z) + side * (river_width(z) + 7.0)
				var water_x: float = river_center(z) + side * river_width(z) * 0.78
				var shore_x := _waterline_x(z, land_x, water_x)
				var land_direction: float = -side if island else side
				var edge_x := shore_x + land_direction * 0.08
				var beach_x := shore_x + land_direction * 1.35
				var edge := Vector3(edge_x, terrain_surface_height(edge_x, z) + 0.025, z)
				var beach := Vector3(beach_x, terrain_surface_height(beach_x, z) + 0.025, z)
				if previous_valid:
					_append_shore(surface, faces, previous_edge, previous_beach, edge, beach)
				previous_edge = edge
				previous_beach = beach
				previous_valid = true
	surface.generate_normals()
	var sand_mesh := surface.commit()
	sand_mesh.surface_set_material(0, _material(Color.WHITE, true))
	var shore := MeshInstance3D.new()
	shore.name = "RiverShoreline"
	shore.mesh = sand_mesh
	_owned(world, shore, root)
	var body := StaticBody3D.new()
	body.name = "WaterBoundary"
	body.collision_layer = 4
	body.collision_mask = 0
	_owned(world, body, root)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.name = "ShorelineBarrier"
	collider.shape = shape
	_owned(body, collider, root)


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
	add_rock_collision(world, root)


static func add_rock_collision(world: Node3D, root: Node) -> void:
	var existing := world.get_node_or_null("RockCollision")
	if existing != null:
		existing.free()
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	_owned(world, body, root)
	var rocks := world.get_node("RidgeAndFieldRocks") as MultiMeshInstance3D
	var rock_faces := PackedVector3Array()
	var mesh_faces := rocks.multimesh.mesh.get_faces()
	for index in range(rocks.multimesh.instance_count):
		var rock_transform := rocks.transform * rocks.multimesh.get_instance_transform(index)
		for vertex in mesh_faces:
			rock_faces.append(rock_transform * vertex)
	var rock_shape := ConcavePolygonShape3D.new()
	rock_shape.set_faces(rock_faces)
	rock_shape.backface_collision = true
	var rock_collider := CollisionShape3D.new()
	rock_collider.name = "FieldRocks"
	rock_collider.shape = rock_shape
	_owned(body, rock_collider, root)
	var ledge := world.get_node("SpawnRockLedge") as MeshInstance3D
	var ledge_faces := PackedVector3Array()
	for vertex in ledge.mesh.get_faces():
		ledge_faces.append(ledge.transform * vertex)
	var ledge_shape := ConcavePolygonShape3D.new()
	ledge_shape.set_faces(ledge_faces)
	ledge_shape.backface_collision = true
	var ledge_collider := CollisionShape3D.new()
	ledge_collider.name = "SpawnLedge"
	ledge_collider.shape = ledge_shape
	_owned(body, ledge_collider, root)


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


static func _canopy_lobe(surface: SurfaceTool, center: Vector3, radii: Vector3, offset: float, island_foliage := false) -> void:
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
			var dark := Color(0.10, 0.28, 0.10) if island_foliage else Color(0.14, 0.23, 0.12)
			var light := Color(0.27, 0.46, 0.20) if island_foliage else Color(0.32, 0.39, 0.19)
			var color := dark.lerp(light, shade)
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


static func _island_tree_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(7):
		var angle := TAU * segment / 7.0
		var next_angle := TAU * (segment + 1) / 7.0
		var base := Vector3(cos(angle) * 0.25, 0, sin(angle) * 0.25)
		var base_next := Vector3(cos(next_angle) * 0.25, 0, sin(next_angle) * 0.25)
		var top := Vector3(cos(angle) * 0.13, 3.4, sin(angle) * 0.13)
		var top_next := Vector3(cos(next_angle) * 0.13, 3.4, sin(next_angle) * 0.13)
		var bark := Color(0.22, 0.20, 0.15).lightened(segment * 0.012)
		_triangle(surface, base, top, base_next, bark)
		_triangle(surface, base_next, top, top_next, bark)
	_canopy_lobe(surface, Vector3(0, 3.6, 0), Vector3(2.3, 1.8, 2.2), 0.8, true)
	_canopy_lobe(surface, Vector3(-1.5, 2.8, 0.25), Vector3(1.65, 1.5, 1.6), 2.7, true)
	_canopy_lobe(surface, Vector3(1.45, 3.0, -0.2), Vector3(1.7, 1.55, 1.6), 4.5, true)
	_canopy_lobe(surface, Vector3(0, 2.7, 1.35), Vector3(1.55, 1.4, 1.45), 6.8, true)
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


static func _build_island_vegetation(parent: Node3D, root: Node) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 74152
	var trees: Array[Transform3D] = []
	var grasses: Array[Transform3D] = []
	for index in range(65):
		var z := random.randf_range(ISLAND_CENTER_Z - 25.0, ISLAND_CENTER_Z + 25.0)
		var along := (z - ISLAND_CENTER_Z) / ISLAND_HALF_LENGTH
		var width := ISLAND_HALF_WIDTH * sqrt(maxf(0.0, 1.0 - along * along))
		var x := island_center(z) + random.randf_range(-0.68, 0.68) * width
		var height := terrain_surface_height(x, z)
		if height < WATER_LEVEL + 0.3:
			continue
		var size := random.randf_range(0.75, 1.18)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3(size * 1.08, size * 0.86, size * 1.08))
		trees.append(Transform3D(basis, Vector3(x, height - 0.05, z)))
	for index in range(900):
		var z := random.randf_range(ISLAND_CENTER_Z - 29.0, ISLAND_CENTER_Z + 29.0)
		var along := (z - ISLAND_CENTER_Z) / ISLAND_HALF_LENGTH
		var width := ISLAND_HALF_WIDTH * sqrt(maxf(0.0, 1.0 - along * along))
		var x := island_center(z) + random.randf_range(-0.82, 0.82) * width
		var height := terrain_surface_height(x, z)
		if height < WATER_LEVEL + 0.2:
			continue
		var size := random.randf_range(0.35, 0.65)
		var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
		grasses.append(Transform3D(basis, Vector3(x, height - 0.03, z)))
	_add_multimesh(parent, root, "IslandTrees", _island_tree_mesh(), trees)
	_add_multimesh(parent, root, "IslandUnderstory", _grass_mesh(), grasses)


static func _village_road(village: Node3D, root: Node) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(15):
		var near_z := -25.0 - segment * 2.0
		var far_z := near_z - 2.0
		var left := 26.6 + 0.25 * sin(segment * 0.6)
		var right := 31.4 + 0.25 * sin(segment * 0.6)
		var next_left := 26.6 + 0.25 * sin((segment + 1) * 0.6)
		var next_right := 31.4 + 0.25 * sin((segment + 1) * 0.6)
		var a := Vector3(left, terrain_surface_height(left, near_z) + 0.045, near_z)
		var b := Vector3(right, terrain_surface_height(right, near_z) + 0.045, near_z)
		var c := Vector3(next_left, terrain_surface_height(next_left, far_z) + 0.045, far_z)
		var d := Vector3(next_right, terrain_surface_height(next_right, far_z) + 0.045, far_z)
		var earth := Color(0.34, 0.27, 0.19).lightened(0.015 * (segment % 3))
		_triangle(surface, a, b, c, earth)
		_triangle(surface, b, d, c, earth)
	var center := Vector3(29.0, terrain_surface_height(29.0, -43.0) + 0.055, -43.0)
	for segment in range(16):
		var angle := TAU * segment / 16.0
		var next_angle := TAU * (segment + 1) / 16.0
		var first := Vector2(29.0 + cos(angle) * 7.0, -43.0 + sin(angle) * 5.4)
		var second := Vector2(29.0 + cos(next_angle) * 7.0, -43.0 + sin(next_angle) * 5.4)
		_triangle(surface, center, Vector3(first.x, terrain_surface_height(first.x, first.y) + 0.055, first.y), Vector3(second.x, terrain_surface_height(second.x, second.y) + 0.055, second.y), Color(0.35, 0.28, 0.20).lightened(0.01 * (segment % 3)))
	surface.generate_normals()
	var road := MeshInstance3D.new()
	road.name = "PackedEarthCourtyard"
	road.mesh = surface.commit()
	road.mesh.surface_set_material(0, _material(Color.WHITE, true))
	_owned(village, road, root)


static func _tower_log_wall() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 0.16
	for row in range(16):
		var height := radius + row * 0.31
		for side in range(8):
			var angle := TAU * side / 8.0
			var next_angle := TAU * (side + 1) / 8.0
			var first := Vector3(0, height + cos(angle) * radius, sin(angle) * radius)
			var second := Vector3(0, height + cos(next_angle) * radius, sin(next_angle) * radius)
			var left := Vector3(-1.78, 0, 0)
			var right := Vector3(1.78, 0, 0)
			var wood := Color(0.29, 0.19, 0.12).lightened(0.012 * (row % 4) + 0.008 * side)
			_triangle(surface, left + first, right + first, left + second, wood)
			_triangle(surface, right + first, right + second, left + second, wood)
			_triangle(surface, left + Vector3(0, height, 0), left + second, left + first, wood.lightened(0.08))
			_triangle(surface, right + Vector3(0, height, 0), right + first, right + second, wood.lightened(0.08))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material(Color.WHITE, true))
	return mesh


static func _tower_wall(village: Node3D, root: Node, mesh: Mesh, node_name: String, position: Vector3, yaw: float) -> void:
	var wall := MeshInstance3D.new()
	wall.name = node_name
	wall.mesh = mesh
	wall.position = position
	wall.rotation.y = yaw
	_owned(village, wall, root)


static func _fort_tower(village: Node3D, root: Node, tower: PackedScene, log_wall: Mesh, node_name: String, center: Vector3) -> void:
	_instance_model(village, root, tower, node_name, center)
	for side in range(4):
		var yaw := side * PI / 2.0
		var outward := Vector3(sin(yaw), 0.0, cos(yaw)) * 1.72
		_tower_wall(village, root, log_wall, "%sLogWall%d" % [node_name, side], center + outward, yaw)
	_wall_collider(village, root, node_name + "Collision", center + Vector3(0, 2.5, 0), Vector3(3.4, 5.0, 3.4))


static func _build_village(world: Node3D, root: Node) -> void:
	var village := Node3D.new()
	village.name = "PalisadeVillage"
	_owned(world, village, root)
	var wall: PackedScene = load(ASSET_PATH + "log-wall.glb")
	var cabin: PackedScene = load(ASSET_PATH + "cabin.glb")
	var tower: PackedScene = load(ASSET_PATH + "stronghold-tower.glb")
	var tower_wall := _tower_log_wall()
	var center := Vector2(28.5, -44.0)
	var radius := 19.0
	var segment_count := 58
	for segment in range(segment_count):
		if segment == 0 or segment == segment_count - 1:
			continue
		var angle := TAU * (segment + 0.5) / segment_count
		var x := center.x + sin(angle) * radius
		var z := center.y + cos(angle) * radius
		var ground := terrain_surface_height(x, z) - 0.04
		var panel := _instance_model(village, root, wall, "CircularWall%02d" % segment, Vector3(x, ground, z), angle)
		panel.scale.y = 1.4
		var collision_name := "CircularWall%02dCollision" % segment
		_wall_collider(village, root, collision_name, Vector3(x, ground + 1.7, z), Vector3(2.12, 3.4, 0.55))
		(village.get_node(collision_name) as StaticBody3D).rotation.y = angle
	for index in range(4):
		var angle := [PI / 3.0, 2.0 * PI / 3.0, -2.0 * PI / 3.0, -PI / 3.0][index] as float
		var x := center.x + sin(angle) * radius
		var z := center.y + cos(angle) * radius
		_fort_tower(village, root, tower, tower_wall, "Watchtower%02d" % index, Vector3(x, terrain_surface_height(x, z) - 0.04, z))
	var gate_position := Vector3(center.x, terrain_surface_height(center.x, -25.0), -25.0)
	_instance_model(village, root, tower, "OpenGatehouse", gate_position)
	_tower_wall(village, root, tower_wall, "GatehouseWestWall", gate_position + Vector3(-1.72, 0, 0), PI / 2.0)
	_tower_wall(village, root, tower_wall, "GatehouseEastWall", gate_position + Vector3(1.72, 0, 0), PI / 2.0)
	_wall_collider(village, root, "GateWestPostCollision", gate_position + Vector3(-1.72, 2.5, 0), Vector3(0.35, 5.0, 3.5))
	_wall_collider(village, root, "GateEastPostCollision", gate_position + Vector3(1.72, 2.5, 0), Vector3(0.35, 5.0, 3.5))
	_village_road(village, root)
	var huts := [Vector3(20, 0.75, -34), Vector3(37, 0.75, -34), Vector3(16.5, 0.75, -44), Vector3(40.5, 0.75, -44), Vector3(21, 0.75, -53), Vector3(36, 0.75, -53), Vector3(28.5, 0.75, -56)]
	for index in range(huts.size()):
		var yaw := (index % 3 - 1) * 0.15
		var hut_scale := 1.05 + (index % 2) * 0.12
		var hut: Vector3 = huts[index]
		hut.y = terrain_surface_height(hut.x, hut.z)
		_instance_model(village, root, cabin, "TimberHut%02d" % index, hut, yaw, hut_scale)
		var collision_name := "TimberHut%02dCollision" % index
		_wall_collider(village, root, collision_name, hut + Vector3(0, 1.5, 0), Vector3(5.6, 3.0, 5.0) * hut_scale)
		(village.get_node(collision_name) as StaticBody3D).rotation.y = yaw
	var stronghold_assets := "res://assets/library/survival-camp-stronghold/"
	_instance_model(village, root, load(stronghold_assets + "wood-storage.glb"), "FirewoodShelter", Vector3(20.0, terrain_surface_height(20.0, -39.0), -39.0), 0.3)
	_instance_model(village, root, load(stronghold_assets + "anvil.glb"), "SmithAnvil", Vector3(22.0, terrain_surface_height(22.0, -40.0), -40.0), -0.3)
	_instance_model(village, root, load(stronghold_assets + "crock-pot.glb"), "CourtyardCauldron", Vector3(23.5, terrain_surface_height(23.5, -43.0), -43.0))
	_instance_model(village, root, load(stronghold_assets + "torch.glb"), "WestGateTorch", Vector3(25.0, terrain_surface_height(25.0, -24.1), -24.1))
	_instance_model(village, root, load(stronghold_assets + "torch.glb"), "EastGateTorch", Vector3(33.0, terrain_surface_height(33.0, -24.1), -24.1))


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
		if absf(x - river_center(z)) < river_width(z) + 1.0:
			continue
		var height := terrain_height(x, z)
		_instance_model(trees, root, tree, "Tree%03d" % index, Vector3(x, height, z), random.randf_range(0.0, TAU), random.randf_range(0.9, 1.5))
	for index in range(20):
		var z := random.randf_range(-100.0, -26.0)
		var x := river_center(z) - river_width(z) - random.randf_range(3.0, 12.0)
		_instance_model(trees, root, bush, "Bush%02d" % index, Vector3(x, terrain_height(x, z), z), random.randf_range(0.0, TAU), random.randf_range(0.8, 1.5))
	_build_broadleaf_forest(trees, root)
	_build_island_vegetation(trees, root)


static func rebuild_river_landscape(root: Node3D) -> void:
	var world := root.get_node("FirstLevel") as Node3D
	for node_name in ["WalkableTerrain", "WindingRiver", "RiverHighlights", "RiverShoreline", "WaterBoundary", "TallGrass", "RedPoppies", "SpawnRockLedge", "RidgeAndFieldRocks", "RockCollision", "RiverbankAndDistantTreeline"]:
		var old_node := world.get_node_or_null(node_name)
		if old_node != null:
			old_node.free()
	_build_terrain(world, root)
	_build_river(world, root)
	_build_field(world, root)
	_build_rocks(world, root)
	_build_trees(world, root)
	build_road(root)
	var player := root.get_node("Player") as CharacterBody3D
	player.collision_mask |= 4


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
	build_road(root)
	_build_atmosphere(world, root)
	_lighting(root)
	var player := root.get_node("Player") as CharacterBody3D
	player.collision_mask |= 4
	player.position = Vector3(0.0, terrain_height(0.0, 12.0) + 0.12, 12.0)
	player.set("camera_distance", 3.1)
	player.set("camera_height", 1.65)
	player.set("camera_pitch_degrees", -10.0)
	player.set("character_tint", Color(0.57, 0.62, 0.67))
