@tool
class_name TerrainLayerBakeData
extends Resource
## What TerrainLayerBaker last wrote into each region's control map. A vertex whose control value
## still matches was baked and may be re-baked; one that differs was hand-painted since and is kept.

## Region location (Vector2i) -> PackedByteArray of the baked control map (raw FORMAT_RF bytes).
@export var regions: Dictionary = {}


func get_region(location: Vector2i) -> PackedByteArray:
	return regions.get(location, PackedByteArray())


func set_region(location: Vector2i, data: PackedByteArray) -> void:
	if data.is_empty():
		regions.erase(location)
	else:
		regions[location] = data
	emit_changed()
