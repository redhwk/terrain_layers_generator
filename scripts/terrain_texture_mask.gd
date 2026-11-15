@tool
class_name TerrainTextureMask
extends TerrainMask
## Masks by how visible another texture is from the layers BELOW this one
## (e.g. Mossy Floor only where Grass ended up strong). Layers above don't count yet.

## Texture to follow.
@export_range(0, 31) var texture_id := 0:
	set(value):
		texture_id = value
		emit_changed()

## Only counts the texture where it is at least this visible (0..1), fading in from there to fully
## visible. E.g. scree following rock with Start At 0.6 stays off the grass edge, so rock always sits
## between grass and scree (Terrain3D blends those pairs nicely; grass straight against scree looks harsh).
@export_range(0.0, 0.95, 0.01) var start_at := 0.0:
	set(value):
		start_at = value
		emit_changed()

## Remap of that texture's visibility before Invert / Strength Transform. Empty = unchanged.
@export var texture_curve: Curve:
	set(value):
		_watch(texture_curve, value)
		texture_curve = value
		emit_changed()


func get_mask_type() -> int:
	return TYPE_TEXTURE


func get_mask_curve() -> Curve:
	return texture_curve


func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property.name == "texture_id":
		TerrainMask.apply_texture_hint(property)
