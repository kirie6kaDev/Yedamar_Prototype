extends Node3D

const WIDTH: int = 609
const DEPTH: int = 385
const STEP: float = 16000.0 / 3072.0
const ORIGIN := Vector2(2000.0, 3166.666666666667)
const ENV_PATH := "res://assets/environment/"
const NATURE := "nature-kit/"
const TOWN := "fantasy-town-kit/"
const CITY_LAYOUT = preload("res://scripts/city_world.gd")
const NATURE_VISUALS = preload("res://scripts/nature_visuals.gd")

var bounds := Rect2(ORIGIN, Vector2(608.0 * STEP, 384.0 * STEP))
var objects: Dictionary = {}
var obstacles: Array[Dictionary] = []
var heights := PackedFloat32Array()
var _regions: Image
var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}
var _parts: Dictionary = {}
var _batches: Dictionary = {}
var _paths: Array = []
var _clearings: Array[Dictionary] = []
var _terrain_material: ShaderMaterial
var _stone: StandardMaterial3D
var _timber: StandardMaterial3D
var _metal: StandardMaterial3D
var _straw: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 782941
	var bytes := FileAccess.get_file_as_bytes("res://data/terrain.r16")
	if bytes.size() != WIDTH * DEPTH * 2:
		push_error("Terrain R16 must contain 609 × 385 unsigned 16-bit samples.")
		return
	heights.resize(WIDTH * DEPTH)
	for i in heights.size():
		heights[i] = float(bytes.decode_u16(i * 2)) * 0.025 - 220.0
	var region_texture: Texture2D = load("res://data/regions.png") as Texture2D
	_regions = region_texture.get_image()
	if _regions.is_compressed():
		_regions.decompress()
	_paths = JSON.parse_string(FileAccess.get_file_as_string(ENV_PATH + "paths.json"))
	_stone = _material(Color("#8e968b"))
	_timber = _material(Color("#674a32"))
	_metal = _material(Color("#535b58"))
	_straw = _material(Color("#c2a15a"))
	_clearings = [
		{"p": Vector2(4031, 4385), "r": 72.0},
		{"p": Vector2(3510, 3698), "r": 93.0},
		{"p": Vector2(2771, 4354), "r": 44.0},
		{"p": Vector2(4562, 3740), "r": 23.0},
		{"p": Vector2(3312, 4333), "r": 15.0},
		{"p": Vector2(3988, 4395), "r": 17.0},
		{"p": Vector2(3660, 4050), "r": 20.0},
		{"p": Vector2(4510, 3820), "r": 20.0},
		{"p": Vector2(2735, 4320), "r": 15.0},
		{"p": Vector2(3920, 4300), "r": 28.0},
		{"p": Vector2(3850, 4230), "r": 8.0},
		{"p": Vector2(3710, 4080), "r": 8.0},
		{"p": Vector2(4050, 3910), "r": 8.0},
		{"p": Vector2(3190, 4260), "r": 8.0},
	]
	_clearings.append_array(CITY_LAYOUT.STATIC_CLEARINGS)
	_build_light()
	_build_terrain()
	_build_paths()
	_build_farm()
	# Ardenholm and its walkable interiors are built by City before navigation.
	_build_mine()
	_build_glade()
	_build_herbalist()
	_build_interactables()
	_scatter_landscape()
	_flush_batches()
	_finalize_approaches()
	print("World ready: ", objects.size(), " interactions, ", obstacles.size(), " obstacles, ", _batches.size(), " foliage groups.")


func sample_height(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var fx: float = clampf((x - ORIGIN.x) / STEP, 0.0, WIDTH - 1.00001)
	var fz: float = clampf((z - ORIGIN.y) / STEP, 0.0, DEPTH - 1.00001)
	var ix: int = floori(fx)
	var iz: int = floori(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var a: float = lerpf(heights[iz * WIDTH + ix], heights[iz * WIDTH + ix + 1], tx)
	var b: float = lerpf(heights[(iz + 1) * WIDTH + ix], heights[(iz + 1) * WIDTH + ix + 1], tx)
	return lerpf(a, b, tz)


func _point(x: float, z: float, offset: float = 0.0) -> Vector3:
	return Vector3(x, sample_height(x, z) + offset, z)


func _normal(x: float, z: float) -> Vector3:
	return Vector3(sample_height(x - STEP, z) - sample_height(x + STEP, z), 2.0 * STEP, sample_height(x, z - STEP) - sample_height(x, z + STEP)).normalized()


func _region(x: float, z: float) -> int:
	var ix: int = clampi(roundi((x - ORIGIN.x) / STEP), 0, WIDTH - 1)
	var iz: int = clampi(roundi((z - ORIGIN.y) / STEP), 0, DEPTH - 1)
	return roundi(_regions.get_pixel(ix, iz).r * 255.0)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	return mat


func _build_light() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "DayNightEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6e9ba9")
	sky_mat.sky_horizon_color = Color("#c6d3b4")
	sky_mat.ground_horizon_color = Color("#c6d3b4")
	sky_mat.ground_bottom_color = Color("#64725c")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c6d7ca")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("#a6bda7")
	env.fog_density = 0.00025
	env.fog_sky_affect = 0.2
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("#fff0c6")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 230.0
	sun.shadow_bias = 0.035
	add_child(sun)


func _terrain_color(x: float, z: float, h: float, n: Vector3) -> Color:
	var variation: float = (sin(x * 0.017 + cos(z * 0.013) * 2.1) + cos(z * 0.021 - sin(x * 0.008))) * 0.5
	var grass: Color = Color("#617b49").lerp(Color("#899952"), 0.50 + variation * 0.3)
	if _region(x, z) == 1:
		grass = grass.lerp(Color("#526c43"), 0.5)
	var slope: float = 1.0 - n.y
	grass = grass.lerp(Color("#898773"), smoothstep(0.10, 0.37, slope))
	if h < 7.0:
		grass = grass.lerp(Color("#b6ad7d"), 1.0 - smoothstep(0.0, 7.0, h))
	if h < 0.0:
		grass = Color("#687d72")
	for clearing: Dictionary in _clearings:
		var distance: float = Vector2(x, z).distance_to(clearing.p)
		var radius: float = float(clearing.r)
		if distance < radius and clearing.p == Vector2(3510, 3698):
			grass = grass.lerp(Color("#a59c7d"), (1.0 - smoothstep(45.0, radius, distance)) * 0.8)
	return grass


func _build_terrain() -> void:
	var ground_shader := Shader.new()
	ground_shader.code = """
shader_type spatial;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float broad = noise(world_position.xz * 0.15);
	float fine = noise(world_position.xz * 2.4);
	vec3 natural_color = pow(COLOR.rgb, vec3(1.55));
	ALBEDO = natural_color * (0.86 + 0.20 * broad + 0.07 * fine);
	ROUGHNESS = 1.0;
}
"""
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = ground_shader
	for oz in range(0, DEPTH - 1, 64):
		for ox in range(0, WIDTH - 1, 64):
			var nx: int = mini(64, WIDTH - 1 - ox) + 1
			var nz: int = mini(64, DEPTH - 1 - oz) + 1
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var indices := PackedInt32Array()
			vertices.resize(nx * nz)
			normals.resize(nx * nz)
			colors.resize(nx * nz)
			for row in nz:
				for col in nx:
					var x: float = ORIGIN.x + (ox + col) * STEP
					var z: float = ORIGIN.y + (oz + row) * STEP
					var h: float = heights[(oz + row) * WIDTH + ox + col]
					var id: int = row * nx + col
					vertices[id] = Vector3(x, h, z)
					normals[id] = _normal(x, z)
					colors[id] = _terrain_color(x, z, h, normals[id])
			for row in nz - 1:
				for col in nx - 1:
					var i: int = row * nx + col
					indices.append_array(PackedInt32Array([i, i + 1, i + nx, i + 1, i + nx + 1, i + nx]))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.material_override = _terrain_material
			node.name = "Terrain_%d_%d" % [ox, oz]
			add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.name = "Ground"
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = WIDTH
	shape.map_depth = DEPTH
	shape.map_data = heights
	collision.shape = shape
	body.position = Vector3(ORIGIN.x + (WIDTH - 1) * STEP * 0.5, 0.0, ORIGIN.y + (DEPTH - 1) * STEP * 0.5)
	body.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(collision)
	add_child(body)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size.x + 200, bounds.size.y + 200)
	water.mesh = plane
	water.position = Vector3(bounds.get_center().x, 0, bounds.get_center().y)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color("#468a92")
	water_mat.roughness = 0.31
	water_mat.metallic = 0.12
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _build_paths() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying vec2 road_world;
void vertex() { road_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	if (road_world.x>3220.0 && road_world.x<3800.0 && road_world.y>3390.0 && road_world.y<3970.0) { discard; }
	float grain = fract(sin(dot(UV * vec2(29.1, 4711.7), vec2(127.1, 311.7))) * 43758.5453);
	float edge = smoothstep(0.0, 0.16, UV.x) * smoothstep(0.0, 0.16, 1.0-UV.x);
	ALBEDO = mix(vec3(0.34,0.29,0.18), vec3(0.49,0.40,0.25), grain * 0.20 + 0.7);
	ROUGHNESS = 1.0;
	ALPHA = edge * 0.96;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for path: Dictionary in _paths:
		var points: Array = path.points
		var width: float = float(path.width)
		var sampled: Array[Vector2] = []
		for i in points.size() - 1:
			var a := Vector2(points[i][0], points[i][1])
			var b := Vector2(points[i + 1][0], points[i + 1][1])
			var count: int = maxi(1, ceili(a.distance_to(b) / 2.7))
			for j in count:
				sampled.append(a.lerp(b, float(j) / count))
		sampled.append(Vector2(points[-1][0], points[-1][1]))
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		for i in sampled.size():
			var tangent: Vector2 = (sampled[mini(i + 1, sampled.size() - 1)] - sampled[maxi(i - 1, 0)]).normalized()
			var side := Vector2(-tangent.y, tangent.x) * width * 0.5
			for k in 2:
				var p: Vector2 = sampled[i] + side * (-1.0 if k == 0 else 1.0)
				verts.append(_point(p.x, p.y, 0.10))
				norms.append(_normal(p.x, p.y))
				uvs.append(Vector2(float(k), float(i) * 0.3))
			if i > 0:
				var n: int = i * 2
				idx.append_array(PackedInt32Array([n - 2, n, n - 1, n - 1, n, n + 1]))
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var road := MeshInstance3D.new()
		road.name = "Path_" + str(path.id)
		road.mesh = mesh
		road.material_override = mat
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(road)


func _load_model(asset: String) -> PackedScene:
	if not _models.has(asset):
		_models[asset] = load(ENV_PATH + asset + ".glb") as PackedScene
	return _models[asset]


func _model(asset: String, parent: Node3D, local: Vector3, factor: Vector3 = Vector3.ONE, angle: float = 0.0) -> Node3D:
	var packed: PackedScene = _load_model(asset)
	if packed == null:
		return Node3D.new()
	var node: Node3D = NATURE_VISUALS.instantiate(asset,packed)
	if asset.begins_with(TOWN+"roof"):
		var roof_material:=ShaderMaterial.new()
		roof_material.shader=load("res://assets/visuals/roof_tiles.gdshader")
		roof_material.set_shader_parameter("base_color",Color("#79513f"))
		var roof_parts:Array=node.find_children("*","MeshInstance3D",true,false)
		if node is MeshInstance3D:roof_parts.append(node)
		for part:MeshInstance3D in roof_parts:part.material_override=roof_material
	node.position = local
	node.scale = factor
	node.rotation.y = angle
	parent.add_child(node)
	return node


func _prop(asset: String, x: float, z: float, scale_value: float, angle: float = 0.0, obstacle_radius: float = 0.0) -> Node3D:
	var node: Node3D = _model(asset, self, _point(x, z, 0.05 * scale_value if asset.begins_with(NATURE) else 0.0), Vector3.ONE * scale_value, angle)
	if obstacle_radius > 0.0:
		obstacles.append({"position": _point(x, z), "radius": obstacle_radius})
	return node


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node


func _house(x: float, z: float, angle: float, size: float = 7.5, levels: int = 1, timber: bool = false) -> void:
	var house := Node3D.new()
	house.name = "TimberHouse" if timber else "ArdenholmHouse"
	house.position = _point(x, z)
	house.rotation.y = angle
	add_child(house)
	var support: float = 0.0
	for dx: float in [-size * 0.5, size * 0.5]:
		for dz: float in [-size * 0.5, size * 0.5]:
			var ground: float = sample_height(x + dx, z + dz)
			support = maxf(support, ground - house.position.y)
	house.position.y += support
	_box(house, Vector3(0, -1.0, 0), Vector3(size * 1.01, 2.1, size * 1.01), _stone)
	var wood: String = "wall-wood" if timber else "wall"
	for floor_index in levels:
		for side in 4:
			var wall: String = wood + "-window-shutters"
			if side == 0 and floor_index == 0:
				wall = wood + "-door"
			_model(TOWN + wall, house, Vector3(0, floor_index * 3.1, 0), Vector3(size, 3.1, size), side * PI * 0.5)
	_model(TOWN + ("roof-point" if levels > 1 else "roof-gable"), house, Vector3(0, 3.1 * levels, 0), Vector3(size, size * 0.72, size))
	_model(TOWN + "chimney", house, Vector3(-size * 0.2, 3.1 * levels + size * 0.23, 0), Vector3(1.7, 2.8, 1.7))
	_model(TOWN + "lantern", house, Vector3(size * 0.52, 1.8, 1.3), Vector3.ONE * 1.0, PI)
	_warm_light(house, Vector3(size * 0.57, 2.15, 1.3), 1.4, 13.0)
	obstacles.append({"position": _point(x, z), "radius": size * 0.76})


func _build_farm() -> void:
	_house(4045, 4365, PI * 0.5, 11.0, 1, true)
	_house(4071, 4382, PI, 9.0, 1, true)
	_house(3998, 4357, -PI * 0.5, 7.0, 1, true)
	_prop(TOWN + "cart", 4055, 4381, 3.1, -0.7, 1.8)
	_prop(NATURE + "log_stack", 4049, 4374, 4.0, 0.2, 1.5)
	_prop(NATURE + "stump_round", 4056, 4377, 2.1, 0.0)
	for field_index in 3:
		var x: float = 4003.0 + field_index * 25.0
		var z: float = 4411.0
		_field_patch(Vector2(x, z), Vector2(19, 22))
		for row in 12:
			for col in 8:
				var px: float = x - 8.5 + col * 2.4 + _rng.randf_range(-0.1, 0.1)
				var pz: float = z - 10.0 + row * 1.8
				var crop: String = "crops_wheatStageB" if field_index != 1 else "crops_leafsStageB"
				_batch(NATURE + crop, px, pz, _rng.randf_range(1.25, 1.75), _rng.randf() * TAU, 210.0)
		for i in 9:
			_prop(NATURE + "fence_simple", x - 9 + i * 2.4, 4424, 2.4)
	for i in 8:
		var p: Vector3 = _point(4066 + (i % 4) * 1.7, 4366 + (i / 4) * 1.6)
		var hay := _cylinder(self, p + Vector3.UP * 0.62, 0.64, 1.4, _straw)
		hay.rotation.z = PI * 0.5
	_prop(NATURE + "plant_bushLarge", 4085, 4376, 7.5, 0.0, 1.1)
	_prop(NATURE + "tree_oak", 3976, 4369, 8.8, 0.4, 0.8)
	_prop(NATURE + "tree_detailed", 4081, 4408, 8.0, 1.7, 0.8)
	_prop(NATURE + "tree_oak", 4058, 4342, 8.4, 0.8, 0.8)
	_prop(NATURE + "tree_oak", 3982, 4383, 8.2, 1.5, 0.8)
	_prop(NATURE + "tree_small", 3990, 4410, 7.5, 2.4, 0.6)
	_prop(NATURE + "plant_bushDetailed", 3984, 4387, 5.8)
	for i in 350:
		var px: float = _rng.randf_range(3975, 4090)
		var pz: float = _rng.randf_range(4340, 4432)
		if (pz > 4398 and pz < 4425 and px > 3992 and px < 4072) or _distance_to_paths(Vector2(px,pz)) < 3.0:
			continue
		var asset: String = "grass_large" if i % 4 else "flower_yellowA"
		_batch(NATURE + asset, px, pz, _rng.randf_range(1.3, 2.5), _rng.randf()*TAU, 180.0)


func _field_patch(center: Vector2, size: Vector2) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var count_x: int = ceili(size.x / 2.0) + 1
	var count_z: int = ceili(size.y / 2.0) + 1
	for iz in count_z:
		for ix in count_x:
			var x: float = center.x + (float(ix) / (count_x - 1) - 0.5) * size.x
			var z: float = center.y + (float(iz) / (count_z - 1) - 0.5) * size.y
			verts.append(_point(x, z, 0.12))
			norms.append(_normal(x, z))
			colors.append(Color("#685237").lerp(Color("#927553"), 0.5 + sin(float(ix) * PI * 0.8) * 0.35))
			if ix < count_x - 1 and iz < count_z - 1:
				var n: int = iz * count_x + ix
				idx.append_array(PackedInt32Array([n, n + 1, n + count_x, n + 1, n + count_x + 1, n + count_x]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _terrain_material
	add_child(node)


func _build_town() -> void:
	# Sixteen compact houses sit around a walkable market square.
	for row in 4:
		for side in [-1, 1]:
			var x: float = 3510.0 + side * (25.0 + (row % 2) * 5.0)
			var z: float = 3656.0 + row * 24.0
			_house(x, z, 0.0 if side < 0 else PI, _rng.randf_range(7.5, 10.2), 2 if row % 3 == 0 else 1, row % 3 == 1)
	for side in [-1, 1]:
		for col in 4:
			var x: float = 3473.0 + col * 24.0
			var z: float = 3698.0 + side * 66.0
			_house(x, z, side * PI * 0.5, _rng.randf_range(7.5, 9.5), 1 + (col % 2), col == 1)
	for side in [-1, 1]:
		for i in 3:
			_prop(TOWN + ("stall-red" if i % 2 == 0 else "stall-green"), 3510 + side * 12, 3684 + i * 12, 2.8, PI * 0.5 * side, 1.8)
	_prop(TOWN + "fountain-round", 3510, 3679, 2.8, 0.0, 2.8)
	_prop(TOWN + "fountain-center", 3510, 3679, 2.0)
	_prop(TOWN + "cart", 3523, 3730, 3.2, 0.6, 1.9)
	for i in 6:
		_prop(NATURE + "tree_oak", 3451 if i % 2 == 0 else 3570, 3656 + (i / 2) * 34, 8.0 + i * 0.32, i * 0.8, 0.8)
	for x: float in [3496.0, 3524.0]:
		_prop(TOWN + "banner-red", x, 3747, 3.4, PI * 0.5)
		_prop(TOWN + "pillar-wood", x, 3747, 3.4, 0.0, 0.7)


func _build_mine() -> void:
	# The model's cliff front faces +Z. A dark recess and timber supports make the entrance readable.
	var entrance := Node3D.new()
	entrance.position = _point(2760, 4340)
	entrance.rotation.y = -0.35
	add_child(entrance)
	_model(NATURE + "cliff_cave_stone", entrance, Vector3(0, 0.55, -5.5), Vector3(14, 10, 14))
	_box(entrance, Vector3(0, 2.1, 1.55), Vector3(4.8, 4.2, 0.35), _material(Color("#191d19")))
	for side in [-1, 1]:
		_box(entrance, Vector3(side * 2.3, 2.25, 2.0), Vector3(0.45, 4.5, 0.55), _timber)
	_box(entrance, Vector3(0, 4.35, 2.0), Vector3(5.4, 0.5, 0.65), _timber)
	_prop(NATURE + "rock_tallB", 2747, 4336, 8.0, 0.2, 3.5)
	_prop(NATURE + "rock_largeC", 2776, 4334, 7.5, 1.2, 3.0)
	obstacles.append({"position": _point(2760, 4336), "radius": 5.8})
	_prop(NATURE + "tent_detailedOpen", 2794, 4350, 7.5, -0.7, 3.0)
	_prop(NATURE + "log_stack", 2788, 4359, 4.0, 0.5, 1.5)
	_prop(TOWN + "cart", 2777, 4349, 3.3, 0.5, 1.9)
	for i in 9:
		_prop(NATURE + "rock_largeA", 2748 + _rng.randf_range(-15, 20), 4316 + _rng.randf_range(-8, 10), _rng.randf_range(4.0, 7.0), _rng.randf() * TAU, 1.2)
	_prop(NATURE + "tent_detailedOpen", 2337, 3917, 6.0, -0.5, 2.4)
	_prop(NATURE + "log_stack", 2326, 3911, 4.0, 1.0, 1.4)


func _build_glade() -> void:
	_prop(NATURE + "tent_detailedOpen", 4574, 3743, 5.6, 1.1, 2.5)
	_prop(NATURE + "log", 4558, 3731, 4.0, 0.8)
	_prop(NATURE + "log", 4554, 3736, 4.0, 2.0)
	for i in 12:
		var a: float = float(i) * TAU / 12.0
		_prop(NATURE + ("tree_oak" if i % 2 == 0 else "tree_pineTallA_detailed"), 4562 + cos(a) * 27, 3740 + sin(a) * 27, _rng.randf_range(8.0, 11.0), a)


func _warm_light(parent: Node3D, local: Vector3, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = local
	light.light_color = Color("#ffd08b")
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	light.add_to_group("night_lights")
	parent.add_child(light)


func _build_herbalist() -> void:
	_house(3909, 4285, PI * 0.5, 7.5, 1, true)
	_prop(TOWN + "stall-green", 3927, 4294, 3.1, PI * 0.5, 1.65)
	_prop(NATURE + "log_stack", 3932, 4289, 3.2, 1.3, 1.1)
	_prop(NATURE + "tree_oak", 3896, 4288, 8.5, 1.1, 0.7)
	_prop(NATURE + "tree_small", 3935, 4307, 7.0, 0.5, 0.5)
	_field_patch(Vector2(3911, 4310), Vector2(8, 6))
	_field_patch(Vector2(3923, 4313), Vector2(8, 6))
	_warm_light(self, _point(3924, 4295, 2.7), 1.7, 15.0)
	for i in 35:
		var px: float = 3901 + _rng.randf() * 34
		var pz: float = 4278 + _rng.randf() * 43
		_batch(NATURE + ("flower_purpleA" if i % 2 else "grass_leafs"), px, pz, _rng.randf_range(1.8,3.0), _rng.randf()*TAU, 180.0)


func _cauldron_visual(root: Node3D) -> void:
	_model(NATURE + "campfire_stones", root, Vector3(0, 0.12, 0), Vector3.ONE * 2.7)
	_model(NATURE + "campfire_logs", root, Vector3(0, 0.12, 0), Vector3.ONE * 1.7)
	var flame: StandardMaterial3D = _material(Color("#eb9c3d"))
	flame.emission_enabled = true
	flame.emission = Color("#c2531c")
	for i in 3:
		var angle: float = i * TAU / 3.0
		_cylinder(root, Vector3(cos(angle)*0.48, 0.36, sin(angle)*0.48), 0.10, 0.7, _metal, 0.08)
		_cylinder(root, Vector3(cos(angle)*0.25, 0.30, sin(angle)*0.25), 0.13, 0.38, flame, 0.02)
	# A revolved open vessel has an actual rim and visible liquid surface.
	var profile: Array[Vector2] = [Vector2(0.22,0.49),Vector2(0.52,0.58),Vector2(0.66,0.87),Vector2(0.59,1.20),Vector2(0.48,1.20),Vector2(0.43,0.78)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in profile.size()-1:
		for segment in 20:
			var angle: float = segment*TAU/20
			var next_angle: float = (segment+1)*TAU/20
			var a := Vector3(cos(angle)*profile[ring].x,profile[ring].y,sin(angle)*profile[ring].x)
			var b := Vector3(cos(next_angle)*profile[ring].x,profile[ring].y,sin(next_angle)*profile[ring].x)
			var c := Vector3(cos(angle)*profile[ring+1].x,profile[ring+1].y,sin(angle)*profile[ring+1].x)
			var d := Vector3(cos(next_angle)*profile[ring+1].x,profile[ring+1].y,sin(next_angle)*profile[ring+1].x)
			for vertex: Vector3 in [a,c,b,b,c,d]:
				st.add_vertex(vertex)
	st.generate_normals()
	var pot := MeshInstance3D.new()
	pot.mesh = st.commit()
	var iron: StandardMaterial3D = _material(Color("#354e48"))
	iron.metallic = 0.55
	iron.cull_mode = BaseMaterial3D.CULL_DISABLED
	pot.material_override = iron
	root.add_child(pot)
	var liquid: StandardMaterial3D = _material(Color("#5fbd87"))
	liquid.roughness = 0.18
	liquid.emission_enabled = true
	liquid.emission = Color("#1f5837")
	liquid.emission_energy_multiplier = 0.2
	_cylinder(root, Vector3(0,1.13,0),0.49,0.025,liquid)
	var handle: TorusMesh = TorusMesh.new()
	handle.inner_radius = 0.56
	handle.outer_radius = 0.61
	var handle_node := MeshInstance3D.new()
	handle_node.mesh = handle
	handle_node.material_override = iron
	handle_node.position.y = 1.15
	handle_node.rotation.x = PI*0.5
	root.add_child(handle_node)
	_warm_light(root, Vector3(0,0.7,0),1.8,8.0)


func spawn_interactable(id: String, type: String, display_name: String, pos: Vector3, description: String) -> Node3D:
	if objects.has(id):
		return objects[id].node
	var root := Node3D.new()
	root.name = id.validate_node_name()
	root.position = _point(pos.x, pos.z)
	add_child(root)
	var radius: float = 0.85
	var collision_height: float = 1.25
	match type:
		"branch":
			_model(NATURE + "log", root, Vector3(0, 0.07, 0), Vector3(0.60, 0.7, 1.7), _rng.randf() * TAU)
			collision_height = 0.65
		"stone":
			_model(NATURE + "rock_smallA", root, Vector3(0, 0.1, 0), Vector3.ONE * 2.4, _rng.randf() * TAU)
			collision_height = 0.8
		"ore":
			_model(NATURE + "rock_largeC", root, Vector3(0, 0.16, 0), Vector3.ONE * 3.2, _rng.randf() * TAU)
			for i in 4:
				var crystal: MeshInstance3D = _cylinder(root, Vector3(_rng.randf_range(-0.6, 0.6), 0.48, _rng.randf_range(-0.6, 0.6)), 0.16, 0.55, _material(Color("#7aabba")), 0.06)
				crystal.rotation.z = _rng.randf_range(-0.7, 0.7)
			radius = 1.4
		"herb":
			for i in 4:
				_model(NATURE + "flower_purpleA", root, Vector3(_rng.randf_range(-0.4, 0.4), 0.10, _rng.randf_range(-0.4, 0.4)), Vector3.ONE * 2.4, _rng.randf() * TAU)
			radius = 1.0
		"mint":
			for i in 5:
				_model(NATURE + "grass_leafs", root, Vector3(_rng.randf_range(-0.32,0.32),0.13,_rng.randf_range(-0.32,0.32)), Vector3.ONE*2.6, _rng.randf()*TAU)
			radius = 0.8
			collision_height = 0.95
		"lavender":
			for i in 5:
				_model(NATURE + "flower_purpleA", root, Vector3(_rng.randf_range(-0.28,0.28),0.13,_rng.randf_range(-0.28,0.28)), Vector3(1.9,3.0,1.9), _rng.randf()*TAU)
			radius = 0.85
			collision_height = 1.0
		"hay":
			var bale: MeshInstance3D = _cylinder(root,Vector3(0,0.45,0),0.45,1.1,_straw)
			bale.rotation.z = PI*0.5
			for band_x: float in [-0.34,0.34]:
				var band: MeshInstance3D = _cylinder(root,Vector3(band_x,0.45,0),0.46,0.055,_timber)
				band.rotation.z = PI*0.5
			radius = 0.8
			collision_height = 1.0
		"carrot":
			for i in 3:
				_model(NATURE + "crop_carrot", root, Vector3((i-1)*0.21,0.12,0), Vector3.ONE*2.1, _rng.randf()*TAU)
			radius = 0.65
			collision_height = 0.75
		"cauldron":
			_cauldron_visual(root)
			radius = 1.1
			collision_height = 1.8
		"berry":
			_model(NATURE + "plant_bushDetailed", root, Vector3(0, 0.2, 0), Vector3.ONE * 4.0)
			for i in 9:
				var berry: MeshInstance3D = _cylinder(root, Vector3(_rng.randf_range(-0.45, 0.45), _rng.randf_range(0.5, 0.85), _rng.randf_range(-0.4, 0.4)), 0.08, 0.11, _material(Color("#9b3345")))
				berry.rotation.x = PI * 0.5
		"bush":
			_model(NATURE + "plant_bushLarge", root, Vector3(0, 0.36, 0), Vector3.ONE * 8.4)
			radius = 1.7
			collision_height = 2.2
		"well":
			_model(TOWN + "fountain-round", root, Vector3.ZERO, Vector3.ONE * 1.1)
			_box(root, Vector3(-1, 1.1, 0), Vector3(0.13, 2.2, 0.13), _timber)
			_box(root, Vector3(1, 1.1, 0), Vector3(0.13, 2.2, 0.13), _timber)
			_model(TOWN + "roof-gable", root, Vector3(0, 2.0, 0), Vector3(2.6, 1.5, 2.3))
			radius = 1.6
			collision_height = 2.3
		"campfire":
			_model(NATURE + "campfire_stones", root, Vector3(0, 0.15, 0), Vector3.ONE * 3.0)
			_model(NATURE + "campfire_logs", root, Vector3(0, 0.12, 0), Vector3.ONE * 2.3)
			var flame_material: StandardMaterial3D = _material(Color("#efa245"))
			flame_material.emission_enabled = true
			flame_material.emission = Color("#d25c22")
			_cylinder(root, Vector3(0, 0.48, 0), 0.32, 0.75, flame_material, 0.025)
			var glow := OmniLight3D.new()
			glow.light_color = Color("#ffb75b")
			glow.light_energy = 1.5
			glow.omni_range = 8
			glow.position.y = 1.4
			root.add_child(glow)
			radius = 1.5
		"barrel":
			_cylinder(root, Vector3(0, 0.66, 0), 0.52, 1.32, _timber, 0.48)
			for h: float in [0.18, 1.12]:
				_cylinder(root, Vector3(0, h, 0), 0.535, 0.10, _metal)
			radius = 0.8
			collision_height = 1.5
		"crate":
			_box(root, Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), _timber)
			for h: float in [0.1, 1.1]:
				_box(root, Vector3(0, h, 0), Vector3(1.24, 0.15, 1.24), _straw)
		"npc":
			_npc_visual(root, id)
			radius = 0.75
			collision_height = 2.1
		"exit":
			_model(TOWN + "banner-red", root, Vector3.ZERO, Vector3.ONE * 3.5)
			radius = 1.6
			collision_height = 3.0
		_:
			_model(NATURE + "sign", root, Vector3(0, 0.2, 0), Vector3.ONE * 4.0)
			radius = 1.1
			collision_height = 1.8
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("object_id", id)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = collision_height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = collision_height * 0.5
	body.add_child(collision)
	root.add_child(body)
	var approach: Vector3 = _point(pos.x, pos.z + _approach_distance(type))
	objects[id] = {"id": id, "type": type, "name": display_name, "description": description, "position": root.position, "approach": approach, "surface_radius": radius, "node": root}
	return root


func _npc_visual(root: Node3D, id: String) -> void:
	var actor:Node3D=preload("res://scripts/character_visual.gd").build("villager",{"gender":"female" if id in ["farmer","herbalist"] else "male","outfit":"guard" if id=="guard" else "peasant"})
	actor.scale=Vector3.ONE*(1.78/1.84)
	actor.rotation.y = -0.5 if id == "farmer" else 1.2
	root.add_child(actor)
	for child: Node in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh_name: String = str(child.name).to_lower()
		if mesh_name.contains("sword") or mesh_name.contains("axe") or mesh_name.contains("shield") or mesh_name.contains("crossbow") or mesh_name.contains("dagger") or mesh_name.contains("knife") or mesh_name.contains("throwable") or mesh_name.contains("spell") or mesh_name.contains("staff"):
			(child as MeshInstance3D).hide()
	for player: Node in actor.find_children("*", "AnimationPlayer", true, false):
		for animation_name: StringName in (player as AnimationPlayer).get_animation_list():
			if str(animation_name).ends_with("Idle"):
				(player as AnimationPlayer).get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
				(player as AnimationPlayer).play(animation_name)
				return


func _spawn(id: String, type: String, title: String, x: float, z: float, description: String) -> void:
	spawn_interactable(id, type, title, _point(x, z), description)


func _build_interactables() -> void:
	_spawn("farmer", "npc", "Марта · хозяйка фермы", 4031, 4385, "Марта ведёт своё хозяйство рядом с Арденхольмом. Ей нужны крепкие руки и весть от шахтёров.")
	_spawn("guard", "npc", "Ролан · страж Арденхольма", 3510, 3698, "Страж держит дорогу к городу под наблюдением и знает о недавних налётах.")
	_spawn("miner", "npc", "Борен · шахтёр", 2771, 4354, "Шахтёр ждёт у входа в штольню. На его рукавах блестит рудная пыль.")
	_spawn("herbalist", "npc", "Элла · травница", 3920, 4300, "Элла выращивает мяту и лаванду на дороге к Арденхольму. Она обучает приготовлению зелий у своего котла.")
	_spawn("cauldron", "cauldron", "Алхимический котёл Эллы", 3925, 4303, "В чугунном котле тихо кипит настой. После урока травницы здесь можно смешивать целебные зелья и отвары бодрости.")
	_spawn("waypost_1", "sign", "Зарубки у старой развилки", 3847, 4226, "На столбе вырезан знак листа. Ниже приписка: «Вторую метку ищи у северного поворота тракта».")
	_spawn("waypost_2", "sign", "Записка дорожного сборщика", 3706, 4084, "Под дощечкой спрятана записка: «Лекарские припасы шли через лесную заставу. Проверь знак на дороге к Эйвару».")
	_spawn("forest_waypost", "sign", "Лесная застава", 4050, 3910, "На старом указателе знак травницы. Следы колёс сворачивают к востоку, а связка бирок помечена знаком шахт.")
	_spawn("mine_waypost", "sign", "Пограничный камень шахт", 3186, 4256, "На дощечке шахтёрское клеймо. У подножия осталась отметка о доставке лекарских припасов.")
	_spawn("delivery_crate", "crate", "Ящик дорожных припасов", 4054, 3915, "В закрытом ящике лежат перевязочные материалы и мешочки сушёных трав. На крышке — знакомая метка Эллы.")
	_spawn("farm_well", "well", "Колодец фермы", 4024, 4391, "Колодезная вода утоляет жажду. Здесь можно набрать запас.")
	_spawn("town_well", "well", "Городской колодец", 3514, 3707, "Чистая вода у рыночной площади.")
	_spawn("farm_campfire", "campfire", "Очаг у фермы", 4016, 4385, "У огня можно отдохнуть, приготовить еду и перевязать раны.")
	_spawn("mine_campfire", "campfire", "Костёр шахтёров", 2785, 4365, "Рабочий костёр у палатки шахтёров.")
	_spawn("forest_campfire", "campfire", "Костёр на поляне", 4562, 3740, "Тихая поляна в Эйваре. У костра остались следы путников.")
	_spawn("farm_supply", "crate", "Запасы фермы", 4039, 4377, "Деревянный ящик с хозяйственными припасами.")
	_spawn("mine_supply", "crate", "Шахтёрский ящик", 2783, 4347, "В ящике хранились инструменты и сухари.")
	_spawn("sign_farm", "sign", "Указатель на ферму", 3987, 4386, "Ферма Марты — на восток. Арденхольм — на север. Штольни — на запад.")
	_spawn("sign_crossroads", "sign", "Лиорский тракт", 3319, 4326, "Дорога связывает город, ферму и западные шахты.")
	_spawn("sign_town", "sign", "Арденхольм", 3508, 3744, "Городские дворы, рынок и пост стражи.")
	_spawn("exit_mine", "exit", "Проход в глубину штольни", 2760, 4344, "Тёмный проход ведёт в старую выработку.")
	for group_index in 2:
		var center := Vector2(3988, 4395) if group_index == 0 else Vector2(3312, 4333)
		for i in 12:
			var a: float = float(i) * 2.399963 + group_index
			var radius: float = (8.0 + i * 2.0) if i < 4 else (21.0 + float(i % 4) * 8.0)
			var p: Vector2 = center + Vector2(cos(a), sin(a)) * radius
			_spawn("branch_%d_%d" % [group_index, i], "branch", "Сухая ветка", p.x, p.y, "Подойдёт для рукояти, костра или простого оружия.")
			var stone: Vector2 = center + Vector2(cos(a + 0.42), sin(a + 0.42)) * (radius + 6.0)
			_spawn("stone_%d_%d" % [group_index, i], "stone", "Крепкий камень", stone.x, stone.y, "Камень с острым краем пригодится для первого инструмента.")
	for i in 8:
		var a: float = i * 0.78
		var x: float = 2771 + cos(a) * (13 + i % 3 * 4)
		var z: float = 4354 + sin(a) * (13 + i % 3 * 4)
		_spawn("ore_%d" % i, "ore", "Железная руда", x, z, "Рудная жила выходит на поверхность. Для добычи нужна кирка.")
	for i in 18:
		var a: float = i * 2.4
		var p := Vector2(4562, 3740) + Vector2(cos(a), sin(a)) * (18 + i % 5 * 7)
		_spawn("herb_%d" % i, "herb", "Лечебные травы", p.x, p.y, "Свежие листья подходят для повязки.")
	for i in 12:
		var p := Vector2(4031, 4385) if i < 6 else Vector2(4562, 3740)
		var angle: float = i * 2.4
		p += Vector2(cos(angle), sin(angle)) * (42 + i % 3 * 9)
		_spawn("berry_%d" % i, "berry", "Лесные ягоды", p.x, p.y, "Спелые ягоды помогут пережить дорогу.")
	var covers: Array[Vector2] = [Vector2(4510,3820),Vector2(3660,4050),Vector2(2820,4360),Vector2(2735,4320)]
	for i in covers.size():
		var p: Vector2 = covers[i]
		_spawn("cover_bush_%d" % i, "bush", "Густые заросли", p.x - 11, p.y + 8, "В густой листве можно спрятаться и подготовить обход.")
		_spawn("cover_barrel_%d" % i, "barrel", "Пустая бочка", p.x + 9, p.y + 10, "Большая пустая бочка служит укрытием.")
		_prop(NATURE + "rock_largeA", p.x - 13, p.y + 4, 6, 1.0, 1.7)
	for i in 4:
		_spawn("farm_barrel_%d" % i, "barrel", "Хозяйственная бочка", 4040 + i * 1.25, 4376, "Бочка у стены фермерского дома.")
	for i in 10:
		_spawn("mint_%d" % i,"mint","Душистая мята",3907+(i%5)*1.6,4308+(i/5)*2.1,"Свежая мята усиливает целебный настой. Её выращивает травница.")
		_spawn("lavender_%d" % i,"lavender","Лаванда",3919+(i%5)*1.6,4312+(i/5)*2.1,"Лаванда возвращает бодрость. Нужна для алхимических рецептов.")
	for i in 6:
		_spawn("farm_hay_%d" % i,"hay","Сено для лошади",4050+(i%3)*1.5,4392+(i/3)*1.5,"Высушенное луговое сено подходит вьючному животному.")
		_spawn("farm_carrot_%d" % i,"carrot","Свежая морковь",4000+(i%3)*1.4,4406+(i/3)*1.4,"Сочная морковь — лакомство и корм для лошади.")
	for i in 4:
		_spawn("farm_mint_%d" % i,"mint","Полевая мята",3988+i*2.2,4403,"Мята у края огорода пригодится на уроке травницы.")
	for info in [["student_herb_0",4103,3885],["student_herb_1",4115,3897],["student_herb_2",4098,3898]]:
		_spawn(info[0],"herb","Лечебные листья у тропы",info[1],info[2],"Ученик травницы собирает эти листья у лесной дороги.")


func _approach_distance(type: String) -> float:
	match type:
		"bush": return 0.0
		"branch","herb","mint","lavender","carrot": return 0.55
		"stone": return 0.7
		"npc": return 1.15
		"well": return 2.1
		"ore","cauldron": return 1.7
		"campfire": return 1.6
		"barrel","hay","berry": return 1.1
		"crate","sign","exit": return 1.3
	return 1.0


func _standing_clear(p: Vector2) -> bool:
	if not bounds.grow(-2.0).has_point(p) or sample_height(p.x,p.y) < 0.5 or _normal(p.x,p.y).y < 0.78:
		return false
	for obstacle: Dictionary in obstacles:
		var center: Vector3 = obstacle.position
		if p.distance_squared_to(Vector2(center.x,center.z)) < pow(float(obstacle.radius)+0.85,2):
			return false
	return true


func _finalize_approaches() -> void:
	var movable: Array[String] = ["branch","stone","ore","herb","mint","lavender","berry","hay","carrot"]
	for id: String in objects:
		var entry: Dictionary = objects[id]
		var node: Node3D = entry.node
		var center := Vector2(node.position.x,node.position.z)
		# Procedural pickups may land beside a later tree or a large camp prop.
		# Move the pickup and its collider together, then resolve a close approach.
		if str(entry.type) in movable and not _standing_clear(center):
			var relocated: bool = false
			for distance: float in [2.0,4.0,6.0,9.0]:
				for i in 16:
					var angle: float = i*TAU/16
					var point: Vector2 = center+Vector2(cos(angle),sin(angle))*distance
					if _standing_clear(point):
						center = point
						node.position = _point(point.x,point.y)
						entry.position = node.position
						relocated = true
						break
				if relocated:
					break
		var offset: float = _approach_distance(str(entry.type))
		var found: bool = false
		for extra: float in [0.0,0.3,0.6]:
			for i in 16:
				var angle: float = PI*0.5+i*TAU/16
				var point: Vector2 = center+Vector2(cos(angle),sin(angle))*(offset+extra)
				if _standing_clear(point):
					entry.approach = _point(point.x,point.y)
					found = true
					break
			if found:
				break
		if not found:
			push_warning("No close walkable approach for object: "+id)


func _distance_to_paths(p: Vector2) -> float:
	var best: float = 1000000.0
	for path: Dictionary in _paths:
		var points: Array = path.points
		for i in points.size() - 1:
			var a := Vector2(points[i][0], points[i][1])
			var b := Vector2(points[i + 1][0], points[i + 1][1])
			if p.x < minf(a.x, b.x) - 15 or p.x > maxf(a.x, b.x) + 15 or p.y < minf(a.y, b.y) - 15 or p.y > maxf(a.y, b.y) + 15:
				continue
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


func _is_clearing(p: Vector2, margin: float = 0.0) -> bool:
	for clearing: Dictionary in _clearings:
		if p.distance_to(clearing.p) < float(clearing.r) + margin:
			return true
	return false


func _scatter_landscape() -> void:
	var trees: Array[String] = ["tree_oak", "tree_detailed", "tree_pineTallA_detailed", "tree_pineTallB_detailed", "tree_small"]
	var tree_count: int = 0
	for z in range(3180, 5150, 15):
		for x in range(2010, 5150, 15):
			var px: float = x + _rng.randf_range(-6.8, 6.8)
			var pz: float = z + _rng.randf_range(-6.8, 6.8)
			var p := Vector2(px, pz)
			var h: float = sample_height(px, pz)
			if h < 4.0 or _normal(px, pz).y < 0.79 or _is_clearing(p):
				continue
			var forest: bool = _region(px, pz) == 1
			var cluster: float = sin(px * 0.023 + cos(pz * 0.019)) + cos(pz * 0.021 + sin(px * 0.017))
			var probability: float = 0.79 if forest else (0.38 if cluster > 0.8 else 0.032)
			if _rng.randf() > probability or _distance_to_paths(p) < 7.0:
				continue
			var choice: int = _rng.randi_range(0, trees.size() - 1)
			if not forest and choice in [2, 3]:
				choice = 0
			var scale_value: float = _rng.randf_range(6.0, 10.2)
			_batch(NATURE + trees[choice], px, pz, scale_value, _rng.randf() * TAU, 1000.0)
			tree_count += 1
			if Vector2(px, pz).distance_to(Vector2(4031, 4385)) < 150 or Vector2(px, pz).distance_to(Vector2(4562, 3740)) < 180:
				obstacles.append({"position": _point(px, pz), "radius": 0.65})
	for i in 8500:
		var p := Vector2(_rng.randf_range(2050, 5130), _rng.randf_range(3200, 5120))
		if sample_height(p.x, p.y) < 3 or _normal(p.x, p.y).y < 0.73 or _is_clearing(p, -3):
			continue
		if _distance_to_paths(p) < 3.0:
			continue
		var kind: int = i % 7
		var asset: String = ["grass_large", "grass_leafs", "flower_yellowA", "plant_bushDetailed", "rock_largeA", "rock_largeC", "flower_purpleA"][kind]
		var factor: float = _rng.randf_range(1.6, 3.8)
		if kind in [3, 4, 5]:
			factor = _rng.randf_range(3.0, 6.5)
		_batch(NATURE + asset, p.x, p.y, factor, _rng.randf() * TAU, 240.0 if kind < 3 or kind == 6 else 650.0)
	# A denser meadow around the player's first footsteps.
	for i in 1100:
		var p := Vector2(3988, 4395) + Vector2(_rng.randf_range(-110, 110), _rng.randf_range(-95, 95))
		if _is_clearing(p, -15) or _distance_to_paths(p) < 3.0 or sample_height(p.x,p.y)<2:
			continue
		_batch(NATURE + ("flower_yellowA" if i % 5 == 0 else "grass_large"), p.x, p.y, _rng.randf_range(1.3, 2.5), _rng.randf() * TAU, 170.0)
	print("Placed trees: ", tree_count)


func _gather_parts(node: Node, transform: Transform3D, list: Array[Dictionary]) -> void:
	var current: Transform3D = transform
	if node is Node3D:
		current = transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			list.append({"mesh": instance.mesh, "transform": current})
	for child: Node in node.get_children():
		_gather_parts(child, current, list)


func _batch(asset: String, x: float, z: float, scale_value: float, angle: float, visible_distance: float) -> void:
	var cell_x: int = floori(x / 160)
	var cell_z: int = floori(z / 160)
	var key: String = asset + "_%d_%d" % [cell_x, cell_z]
	if not _batches.has(key):
		_batches[key] = {"asset": asset, "origin": Vector3(cell_x * 160 + 80, 0, cell_z * 160 + 80), "transforms": [], "distance": visible_distance}
	var item: Dictionary = _batches[key]
	var transform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale_value), _point(x, z, 0.05 * scale_value) - item.origin)
	item.transforms.append(transform)


func _flush_batches() -> void:
	for key: String in _batches:
		var item: Dictionary = _batches[key]
		var asset: String = item.asset
		if not _parts.has(asset):
			var root: Node = NATURE_VISUALS.instantiate(asset,_load_model(asset))
			var parts: Array[Dictionary] = []
			_gather_parts(root, Transform3D.IDENTITY, parts)
			_parts[asset] = parts
			root.free()
		for part: Dictionary in _parts[asset]:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = part.mesh
			multi.instance_count = item.transforms.size()
			for i in item.transforms.size():
				multi.set_instance_transform(i, item.transforms[i] * part.transform)
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multi
			instance.position = item.origin
			instance.visibility_range_end = float(item.distance)
			instance.visibility_range_end_margin = 30.0
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if float(item.distance) > 500 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
