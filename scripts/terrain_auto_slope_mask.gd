@tool
class_name TerrainAutoSlopeMask
extends TerrainMask
## Terrain3D's own auto shader formula: strong on flat ground, fading out on slopes and with height.
## Put it on the texture that Terrain3D calls the Auto Overlay (e.g. grass), above the base texture,
## to get exactly Terrain3D's auto shader blend; add more masks / layers on top for more textures.

## Use Auto Slope and Auto Height Reduction from the Terrain3D material (Auto Shader section).
@export var use_material_settings := true:
	set(value):
		use_material_settings = value
		emit_changed()
		notify_property_list_changed()

## Same as Terrain3D's Auto Slope: higher = fades out on gentler slopes.
@export_range(0.0, 10.0, 0.001) var auto_slope := 1.0:
	set(value):
		auto_slope = value
		emit_changed()

## Same as Terrain3D's Auto Height Reduction: higher = fades out more with height.
@export_range(0.0, 1.0, 0.001) var height_reduction := 0.1:
	set(value):
		height_reduction = value
		emit_changed()

## Optional remap of the result before Invert / Strength Transform. Empty = unchanged.
@export var auto_curve: Curve:
	set(value):
		_watch(auto_curve, value)
		auto_curve = value
		emit_changed()


func get_mask_type() -> int:
	return TYPE_TERRAIN3D_AUTO


func get_mask_curve() -> Curve:
	return auto_curve


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if use_material_settings and property.name in ["auto_slope", "height_reduction"]:
		property.usage |= PROPERTY_USAGE_READ_ONLY
