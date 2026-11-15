@tool
class_name TerrainNoiseMask
extends TerrainMask
## Masks with world-space noise. Noise holds every noise setting (type Perlin / Value /
## Cellular (Voronoi) / Simplex, fractal FBM / Ridged / Ping-Pong, octaves, lacunarity,
## gain (persistence), domain warp). It is baked to a seamless tile that repeats across the terrain.

## Noise settings. Frequency is per pixel of the tile (TerrainLayerMasks > Noise Resolution).
@export var noise: FastNoiseLite:
	set(value):
		_watch(noise, value)
		noise = value
		emit_changed()

## Billow look: folds the noise around its middle (soft puffy shapes).
@export var billow := false:
	set(value):
		billow = value
		emit_changed()

## Remap of the noise value before Invert / Strength Transform. Empty = unchanged.
@export var noise_curve: Curve:
	set(value):
		_watch(noise_curve, value)
		noise_curve = value
		emit_changed()

@export_group("Transform")
## World size (meters) of one noise tile before it repeats.
@export var tile_size := 256.0:
	set(value):
		tile_size = maxf(value, 0.01)
		emit_changed()

## When on, the tile is Terrain Scale x the terrain's width instead of Tile Size.
@export var scale_with_terrain := false:
	set(value):
		scale_with_terrain = value
		emit_changed()

## Tile size as a fraction of the terrain width (used with Scale With Terrain; 1 = one tile across).
@export var terrain_scale := 1.0:
	set(value):
		terrain_scale = maxf(value, 0.001)
		emit_changed()

## Moves the noise (meters, X / Z).
@export var offset := Vector2.ZERO:
	set(value):
		offset = value
		emit_changed()

## Rotates the noise around the world origin.
@export_range(-180.0, 180.0, 0.1, "suffix:°") var rotation_degrees := 0.0:
	set(value):
		rotation_degrees = value
		emit_changed()


func _init() -> void:
	if noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.frequency = 0.01
		noise = n


func get_mask_type() -> int:
	return TYPE_NOISE


func get_mask_curve() -> Curve:
	return noise_curve


## Changes whenever any noise setting changes (used to cache the baked tile).
func noise_signature(resolution: int) -> String:
	if noise == null:
		return ""
	var parts := PackedStringArray([str(resolution)])
	for p in noise.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE:
			parts.append(str(noise.get(p.name)))
	return "|".join(parts)
