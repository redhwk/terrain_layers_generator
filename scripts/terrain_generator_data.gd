@tool
class_name TerrainGeneratorData
extends Resource
## The heights TerrainGenerator last generated in each region. The difference between a region's
## current heights and these is your hand sculpting, which the next Generate keeps on top.

## Region location (Vector2i) -> PackedFloat32Array of generated heights (region_size^2).
@export var regions: Dictionary = {}


func get_region(location: Vector2i) -> PackedFloat32Array:
	return regions.get(location, PackedFloat32Array())


func set_region(location: Vector2i, heights: PackedFloat32Array) -> void:
	if heights.is_empty():
		regions.erase(location)
	else:
		regions[location] = heights
	emit_changed()
