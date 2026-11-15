@tool
class_name Terrain3DBridge
extends RefCounted
## Every direct use of Terrain3D's data API by the terrain layer tools lives here, so a future
## Terrain3D change only needs fixing in one file. Written against Terrain3D 1.1.0.

## Terrain3DRegion map types.
const MAP_HEIGHT := 0
const MAP_CONTROL := 1
const MAP_ALL := 3

## Region locations Terrain3D accepts (its region map is 32 x 32, centred on 0).
const REGION_MIN := -16
const REGION_MAX := 15

## Control map bits (32-bit uint stored in a float texel).
const CONTROL_AUTO := 0x1
const CONTROL_BASE_SHIFT := 27
const CONTROL_OVERLAY_SHIFT := 22
const CONTROL_BLEND_SHIFT := 14
## Base, overlay, blend and auto: what a bake writes. Everything else (holes, navigation,
## UV angle / scale) is kept.
const CONTROL_TEXTURE_BITS := 0xFFFFC001


static func is_terrain(node: Object) -> bool:
	return node != null and node.is_class("Terrain3D")


static func region_size(terrain) -> int:
	return int(terrain.region_size)


static func vertex_spacing(terrain) -> float:
	return float(terrain.vertex_spacing)


static func region_locations(terrain) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if terrain.data:
		for loc in terrain.data.get_region_locations():
			out.append(Vector2i(loc))
	return out


static func region_location_at(terrain, global_position: Vector3) -> Vector2i:
	return Vector2i(terrain.data.get_region_location(global_position))


## World XZ of a region's first vertex.
static func region_origin(terrain, location: Vector2i) -> Vector2:
	return Vector2(location) * float(region_size(terrain)) * vertex_spacing(terrain)


static func get_map(terrain, location: Vector2i, map_type: int) -> Image:
	var region = terrain.data.get_region(location)
	return region.get_map(map_type) if region else null


static func set_map(terrain, location: Vector2i, map_type: int, image: Image) -> void:
	var region = terrain.data.get_region(location)
	if region == null:
		return
	region.set_map(map_type, image)
	region.modified = true
	region.edited = true


## Call after set_map so the GPU sees the change.
static func update_maps(terrain, map_type: int) -> void:
	terrain.data.update_maps(map_type, true, false)


static func height_at(terrain, global_position: Vector3) -> float:
	return float(terrain.data.get_height(global_position))


## Uses the region list, not Terrain3D's has_region(): that reads the region map, which is stale
## between several add / remove calls and the next update.
static func has_region(terrain, location: Vector2i) -> bool:
	return terrain.data != null and Vector2i(location) in terrain.data.get_region_locations()


static func is_valid_location(location: Vector2i) -> bool:
	return location.x >= REGION_MIN and location.x <= REGION_MAX and location.y >= REGION_MIN and location.y <= REGION_MAX


## Adds an empty (flat, height 0) region. Call refresh_heights afterwards.
static func add_region(terrain, location: Vector2i) -> void:
	if not has_region(terrain, location):
		var region = terrain.data.add_region_blank(location, false)
		if region:
			region.modified = true
			region.edited = true


## Removes a region (its file is deleted when the scene is saved). Call refresh_heights afterwards.
static func remove_region(terrain, location: Vector2i) -> void:
	if has_region(terrain, location):
		terrain.data.remove_regionl(location, false)


## Call after changing height maps or adding / removing regions: GPU maps, height range, collision.
static func refresh_heights(terrain) -> void:
	terrain.data.update_maps(MAP_ALL, true, false)
	terrain.data.calc_height_range(true)
	var collision = terrain.get("collision")
	if collision and collision.is_enabled():
		collision.build()


static func encode_textures(base_id: int, overlay_id: int, blend: float) -> int:
	return ((base_id & 0x1F) << CONTROL_BASE_SHIFT) | ((overlay_id & 0x1F) << CONTROL_OVERLAY_SHIFT) \
		| ((int(clampf(blend, 0.0, 1.0) * 255.0 + 0.5) & 0xFF) << CONTROL_BLEND_SHIFT)


## Terrain3D's data directory (for saving bake data next to the region files).
static func data_directory(terrain) -> String:
	return str(terrain.data_directory)
