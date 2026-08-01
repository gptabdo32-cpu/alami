class_name ChunkDataGenerator
extends RefCounted

enum Biome { OCEAN, BEACH, PLAINS, FOREST, HILLS, MOUNTAINS, ALPINE, DESERT, SWAMP }
enum PropKind { TREE, ROCK, BUSH }

static func generate(config: Dictionary) -> Dictionary:
	var chunk_x := int(config.get("chunk_x", 0))
	var chunk_z := int(config.get("chunk_z", 0))
	var chunk_size := float(config.get("chunk_size", 256.0))
	var resolution := maxi(4, int(config.get("resolution", 24)))
	var map_seed := int(config.get("seed", 424242))
	var height_scale := float(config.get("height_scale", 34.0))
	var water_level := float(config.get("water_level", -1.5))
	var vegetation_density := clampf(float(config.get("vegetation_density", 0.7)), 0.0, 1.0)
	var include_props := bool(config.get("include_props", true))
	var theme := str(config.get("theme", "rural"))
	var flattening := clampf(float(config.get("flattening", 0.8)), 0.15, 1.5)
	var cell_data: Variant = config.get("cell_data", {})
	height_scale *= _theme_height_multiplier(theme, flattening)
	vegetation_density *= _theme_vegetation_multiplier(theme)
	if typeof(cell_data) == TYPE_DICTIONARY:
		var cell_dict: Dictionary = cell_data
		vegetation_density *= clampf(float(cell_dict.get("vegetation_density", 1.0)), 0.0, 1.5)

	var continent := FastNoiseLite.new()
	continent.seed = map_seed + 11
	continent.frequency = 0.0015
	var hills := FastNoiseLite.new()
	hills.seed = map_seed + 23
	hills.frequency = 0.0045
	var detail := FastNoiseLite.new()
	detail.seed = map_seed + 37
	detail.frequency = 0.022
	var ridge := FastNoiseLite.new()
	ridge.seed = map_seed + 41
	ridge.frequency = 0.010
	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = map_seed + 53
	moisture_noise.frequency = 0.0025
	var temperature_noise := FastNoiseLite.new()
	temperature_noise.seed = map_seed + 67
	temperature_noise.frequency = 0.0018
	var plateau_noise := FastNoiseLite.new()
	plateau_noise.seed = map_seed + 79
	plateau_noise.frequency = 0.0032
	var erosion_noise := FastNoiseLite.new()
	erosion_noise.seed = map_seed + 89
	erosion_noise.frequency = 0.0068

	var side := resolution + 1
	var step := chunk_size / float(resolution)
	var half := chunk_size * 0.5
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	var biomes := PackedByteArray()
	biomes.resize(side * side)
	var min_height := INF
	var max_height := -INF

	for z in range(side):
		for x in range(side):
			var lx := -half + float(x) * step
			var lz := -half + float(z) * step
			var wx := float(chunk_x) * chunk_size + lx
			var wz := float(chunk_z) * chunk_size + lz
			var h := _height(wx, wz, map_seed, height_scale, continent, hills, detail, ridge, plateau_noise, erosion_noise)
			h = _apply_theme_height(h, theme, flattening)
			heights[z * side + x] = h
			min_height = minf(min_height, h)
			max_height = maxf(max_height, h)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)

	for z in range(side):
		for x in range(side):
			var index := z * side + x
			var lx := -half + float(x) * step
			var lz := -half + float(z) * step
			var h := heights[index]
			var h_l := heights[z * side + maxi(x - 1, 0)]
			var h_r := heights[z * side + mini(x + 1, resolution)]
			var h_d := heights[maxi(z - 1, 0) * side + x]
			var h_u := heights[mini(z + 1, resolution) * side + x]
			var normal := Vector3(h_l - h_r, step * 2.0, h_d - h_u).normalized()
			var slope := 1.0 - normal.y
			var moisture := _sample_moisture(wx_from_local(chunk_x, chunk_size, lx), wz_from_local(chunk_z, chunk_size, lz), moisture_noise)
			var temperature := _sample_temperature(wx_from_local(chunk_x, chunk_size, lx), wz_from_local(chunk_z, chunk_size, lz), temperature_noise)
			var biome := _select_biome(h, slope, moisture, temperature, water_level)
			biomes[index] = biome
			vertices[index] = Vector3(lx, h, lz)
			normals[index] = normal
			colors[index] = _terrain_color(h, slope, water_level, biome, wx_from_local(chunk_x, chunk_size, lx), wz_from_local(chunk_z, chunk_size, lz))
			uvs[index] = Vector2(float(x) / resolution, float(z) / resolution)

	var indices := PackedInt32Array()
	indices.resize(resolution * resolution * 6)
	var write := 0
	for z in range(resolution):
		for x in range(resolution):
			var i0 := z * side + x
			var i1 := i0 + 1
			var i2 := i0 + side
			var i3 := i2 + 1
			indices[write] = i0; write += 1
			indices[write] = i2; write += 1
			indices[write] = i3; write += 1
			indices[write] = i0; write += 1
			indices[write] = i3; write += 1
			indices[write] = i1; write += 1

	var tree_transforms: Array[Transform3D] = []
	var rock_transforms: Array[Transform3D] = []
	var bush_transforms: Array[Transform3D] = []
	if include_props:
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed ^ (chunk_x * 92821) ^ (chunk_z * 68917)
		var density := _chunk_vegetation_factor(chunk_x, chunk_z, map_seed)
		var tree_count := roundi(rng.randi_range(10, 28) * vegetation_density * density)
		var rock_count := roundi(rng.randi_range(4, 10) * vegetation_density * (0.85 + density * 0.35))
		var bush_count := roundi(rng.randi_range(8, 22) * vegetation_density * (1.0 + density * 0.25))
		_scatter_props(tree_transforms, tree_count, rng, heights, biomes, side, resolution, step, half, water_level, PropKind.TREE)
		_scatter_props(rock_transforms, rock_count, rng, heights, biomes, side, resolution, step, half, water_level, PropKind.ROCK)
		_scatter_props(bush_transforms, bush_count, rng, heights, biomes, side, resolution, step, half, water_level, PropKind.BUSH)

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"uvs": uvs,
		"indices": indices,
		"heights": heights,
		"biomes": biomes,
		"resolution": resolution,
		"chunk_size": chunk_size,
		"min_height": min_height,
		"max_height": max_height,
		"tree_transforms": tree_transforms,
		"rock_transforms": rock_transforms,
		"bush_transforms": bush_transforms
	}

static func sample_world_height(world_x: float, world_z: float, p_seed: int = 424242, height_scale: float = 34.0) -> float:
	var continent := FastNoiseLite.new(); continent.seed = p_seed + 11; continent.frequency = 0.0015
	var hills := FastNoiseLite.new(); hills.seed = p_seed + 23; hills.frequency = 0.0045
	var detail := FastNoiseLite.new(); detail.seed = p_seed + 37; detail.frequency = 0.022
	var ridge := FastNoiseLite.new(); ridge.seed = p_seed + 41; ridge.frequency = 0.010
	var plateau_noise := FastNoiseLite.new(); plateau_noise.seed = p_seed + 79; plateau_noise.frequency = 0.0032
	var erosion_noise := FastNoiseLite.new(); erosion_noise.seed = p_seed + 89; erosion_noise.frequency = 0.0068
	return _height(world_x, world_z, p_seed, height_scale, continent, hills, detail, ridge, plateau_noise, erosion_noise)

static func _height(wx: float, wz: float, p_seed: int, height_scale: float, continent: FastNoiseLite, hills: FastNoiseLite, detail: FastNoiseLite, ridge: FastNoiseLite, plateau_noise: FastNoiseLite, erosion_noise: FastNoiseLite) -> float:
	var continental_base := continent.get_noise_2d(wx * 0.5, wz * 0.5) * 0.5 + 0.5
	var continental := pow(clampf(continental_base, 0.0, 1.0), 1.68)
	var hill_value := hills.get_noise_2d(wx, wz) * 0.85
	var detail_value := detail.get_noise_2d(wx * 1.12, wz * 1.12) * 0.38
	var ridge_value := pow(absf(ridge.get_noise_2d(wx, wz)), 1.82) * 1.1
	var plateau_value := pow(plateau_noise.get_noise_2d(wx * 0.68, wz * 0.68) * 0.5 + 0.5, 2.15) * 6.5
	var erosion := pow(absf(erosion_noise.get_noise_2d(wx * 1.4, wz * 1.4)), 1.28) * 3.6
	var river := _river_carve(wx, wz, p_seed)
	var base := (continental * 25.0) + (hill_value * 7.2) + (detail_value * 2.8) + (ridge_value * 15.0) + plateau_value - erosion - river - 7.5
	return base * (height_scale / 34.0)

static func _sample_moisture(wx: float, wz: float, moisture_noise: FastNoiseLite) -> float:
	return clampf(moisture_noise.get_noise_2d(wx * 0.95, wz * 0.95) * 0.5 + 0.5, 0.0, 1.0)

static func _sample_temperature(wx: float, wz: float, temperature_noise: FastNoiseLite) -> float:
	var temperature := temperature_noise.get_noise_2d(wx * 0.7 + 211.0, wz * 0.7 - 127.0) * 0.5 + 0.5
	return clampf(temperature, 0.0, 1.0)

static func _select_biome(height: float, slope: float, moisture: float, temperature: float, water_level: float) -> int:
	if height < water_level - 2.0:
		return Biome.OCEAN
	if height <= water_level + 1.6:
		return Biome.BEACH
	if height > 42.0 or slope > 0.68:
		return Biome.ALPINE if height > 42.0 else Biome.MOUNTAINS
	if moisture < 0.24 and temperature > 0.48:
		return Biome.DESERT
	if moisture > 0.80 and height < 8.0:
		return Biome.SWAMP
	if height > 20.0 and moisture > 0.55:
		return Biome.FOREST
	if height > 12.0:
		return Biome.HILLS
	return Biome.PLAINS

static func _terrain_color(height: float, slope: float, water_level: float, biome: int, wx: float, wz: float) -> Color:
	var tint := _biome_color(biome)
	var micro := 0.95 + (sin(wx * 0.08 + wz * 0.05) * 0.025) + (cos(wx * 0.031 - wz * 0.047) * 0.02)
	var c := tint * micro
	if slope > 0.42:
		var rock_mix := clampf((slope - 0.42) / 0.38, 0.0, 1.0)
		c = c.lerp(Color(0.52, 0.52, 0.54), rock_mix * 0.72)
	if height > water_level + 28.0:
		var snow_mix := clampf((height - (water_level + 28.0)) / 18.0, 0.0, 1.0)
		c = c.lerp(Color(0.93, 0.95, 0.97), snow_mix)
	if biome == Biome.DESERT:
		c = c.lerp(Color(0.95, 0.82, 0.54), 0.2)
	elif biome == Biome.FOREST:
		c = c.lerp(Color(0.11, 0.33, 0.13), 0.1)
	elif biome == Biome.SWAMP:
		c = c.lerp(Color(0.16, 0.24, 0.14), 0.08)
	return c

static func _biome_color(biome: int) -> Color:
	match biome:
		Biome.OCEAN:
			return Color(0.04, 0.13, 0.28)
		Biome.BEACH:
			return Color(0.82, 0.75, 0.53)
		Biome.DESERT:
			return Color(0.81, 0.66, 0.38)
		Biome.SWAMP:
			return Color(0.20, 0.30, 0.18)
		Biome.FOREST:
			return Color(0.16, 0.46, 0.18)
		Biome.HILLS:
			return Color(0.29, 0.38, 0.20)
		Biome.MOUNTAINS:
			return Color(0.50, 0.50, 0.52)
		Biome.ALPINE:
			return Color(0.84, 0.86, 0.88)
		_:
			return Color(0.18, 0.58, 0.22)

static func _chunk_vegetation_factor(chunk_x: int, chunk_z: int, p_seed: int) -> float:
	var n := sin(float(chunk_x) * 0.73 + float(p_seed) * 0.0007) * 0.5 + 0.5
	n *= cos(float(chunk_z) * 0.61 - float(p_seed) * 0.0004) * 0.5 + 0.5
	return clampf(0.65 + n * 0.7, 0.55, 1.35)

static func _prop_biome_weight(biome: int, kind: int) -> float:
	match kind:
		PropKind.TREE:
			match biome:
				Biome.FOREST: return 1.75
				Biome.HILLS: return 1.10
				Biome.PLAINS: return 0.72
				Biome.SWAMP: return 1.00
				Biome.ALPINE: return 0.15
				Biome.DESERT, Biome.OCEAN, Biome.BEACH: return 0.0
				_: return 0.55
		PropKind.ROCK:
			match biome:
				Biome.MOUNTAINS: return 2.0
				Biome.ALPINE: return 1.25
				Biome.HILLS: return 1.0
				Biome.DESERT: return 1.15
				Biome.BEACH: return 0.55
				Biome.OCEAN: return 0.0
				_: return 0.45
		PropKind.BUSH:
			match biome:
				Biome.PLAINS: return 1.2
				Biome.FOREST: return 1.05
				Biome.SWAMP: return 1.35
				Biome.DESERT: return 0.45
				Biome.BEACH, Biome.OCEAN: return 0.0
				_: return 0.8
		_:
			return 1.0


static func _theme_height_multiplier(theme: String, flattening: float) -> float:
	match theme:
		"city", "industrial", "airport":
			return 0.18 + flattening * 0.22
		"port", "coastal":
			return 0.55 + flattening * 0.20
		"forest":
			return 0.82 + flattening * 0.10
		"mountain":
			return 1.10 + flattening * 0.18
		"desert":
			return 0.62 + flattening * 0.12
		_:
			return 0.80 + flattening * 0.10

static func _theme_vegetation_multiplier(theme: String) -> float:
	match theme:
		"city":
			return 0.12
		"industrial":
			return 0.18
		"airport":
			return 0.08
		"port":
			return 0.28
		"coastal":
			return 0.42
		"forest":
			return 1.15
		"mountain":
			return 0.55
		"desert":
			return 0.08
		_:
			return 0.75

static func _apply_theme_height(height: float, theme: String, flattening: float) -> float:
	match theme:
		"city", "industrial", "airport":
			return lerpf(height, 1.6, 0.80)
		"port", "coastal":
			return lerpf(height, -0.6, 0.28)
		"forest":
			return height * lerpf(1.0, 0.92, clampf(flattening, 0.0, 1.0))
		"mountain":
			return height * lerpf(1.0, 1.18, clampf(flattening, 0.0, 1.0)) + 2.5
		"desert":
			return height * lerpf(1.0, 0.72, clampf(flattening, 0.0, 1.0))
		_:
			return height

static func _scatter_props(output: Array[Transform3D], count: int, rng: RandomNumberGenerator, heights: PackedFloat32Array, biomes: PackedByteArray, side: int, resolution: int, step: float, half: float, water_level: float, kind: int) -> void:
	for _i in range(count):
		for _attempt in range(10):
			var lx := rng.randf_range(-half * 0.92, half * 0.92)
			var lz := rng.randf_range(-half * 0.92, half * 0.92)
			var gx := clampi(roundi((lx + half) / step), 0, resolution)
			var gz := clampi(roundi((lz + half) / step), 0, resolution)
			var index := gz * side + gx
			var height := heights[index]
			if height <= water_level + 0.15 and kind != PropKind.ROCK:
				continue
			var h_l := heights[gz * side + maxi(gx - 1, 0)]
			var h_r := heights[gz * side + mini(gx + 1, resolution)]
			var h_d := heights[maxi(gz - 1, 0) * side + gx]
			var h_u := heights[mini(gz + 1, resolution) * side + gx]
			var normal_y := Vector3(h_l - h_r, step * 2.0, h_d - h_u).normalized().y
			var slope := 1.0 - normal_y
			if kind == PropKind.TREE and slope > 0.30:
				continue
			if kind == PropKind.BUSH and slope > 0.52:
				continue
			var biome := int(biomes[index])
			var weight := _prop_biome_weight(biome, kind)
			if weight <= 0.0:
				continue
			if rng.randf() > weight:
				continue
			var scale_factor := 1.0
			var y_offset := 0.0
			if kind == PropKind.TREE:
				scale_factor = rng.randf_range(0.82, 1.42)
				y_offset = 0.0
			elif kind == PropKind.ROCK:
				scale_factor = rng.randf_range(0.65, 1.55)
				y_offset = 0.15
			else:
				scale_factor = rng.randf_range(0.55, 1.10)
				y_offset = -0.02
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_factor)
			output.append(Transform3D(basis, Vector3(lx, height + y_offset, lz)))
			break

static func _river_carve(wx: float, wz: float, p_seed: int) -> float:
	var meander := sin(wx * 0.0024 + float(p_seed) * 0.0001) * 110.0
	meander += sin(wx * 0.0071 + float(p_seed) * 0.00023) * 18.0
	meander += cos(wx * 0.0012) * 22.0
	var distance := absf(wz - meander)
	var normalized := clampf(1.0 - distance / 18.0, 0.0, 1.0)
	return pow(normalized, 1.45) * 16.0

static func wx_from_local(chunk_x: int, chunk_size: float, local_x: float) -> float:
	return float(chunk_x) * chunk_size + local_x

static func wz_from_local(chunk_z: int, chunk_size: float, local_z: float) -> float:
	return float(chunk_z) * chunk_size + local_z
