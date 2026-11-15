@tool
class_name TerrainMaskLayer
extends Resource
## The layer for one Terrain3D texture (the stack's Layer N is Terrain3D texture N).
## It paints over lower Paint Order layers wherever its masks are strong.
## No masks = covers everything below it (use that for the base layer).

## Terrain3D texture of this layer (set automatically: Layer N = texture N).
@export_range(0, 31) var texture_id := 0:
	set(value):
		texture_id = value
		emit_changed()

## Off = this texture isn't placed by the layer stack.
@export var enabled := true:
	set(value):
		enabled = value
		emit_changed()

## Which layers this one paints over: higher numbers paint over lower ones
## (equal numbers: the higher texture number is on top). Starts as the texture number.
@export var paint_order := 0:
	set(value):
		paint_order = value
		emit_changed()

## Overall strength of the layer (multiplies its mask result).
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(value):
		opacity = value
		emit_changed()

## How sharp this texture's edges are where it blends with another (-1 = the Terrain3D material's
## Blend Sharpness). Where two textures meet, the softer of the two wins: e.g. Sand at 0.2 makes
## grass-to-sand soft while grass-to-rock keeps the material's crisper, crevice-following look.
## Also applies to hand-painted and baked areas.
@export_range(-1.0, 1.0, 0.01) var blend_sharpness := -1.0:
	set(value):
		blend_sharpness = value
		emit_changed()

## None to many masks, evaluated top to bottom. Add with "New TerrainSlopeMask" etc.
@export var masks: Array[TerrainMask] = []:
	set(value):
		for m in masks:
			if m and m.changed.is_connected(_on_mask_changed):
				m.changed.disconnect(_on_mask_changed)
		masks = value
		for m in masks:
			if m and not m.changed.is_connected(_on_mask_changed):
				m.changed.connect(_on_mask_changed)
		_update_first_mask()
		emit_changed()


func _on_mask_changed() -> void:
	_update_first_mask()
	emit_changed()


## The first enabled mask sets the starting value, so its Blend Mode is hidden.
func _update_first_mask() -> void:
	var found := false
	for m in masks:
		if m == null:
			continue
		var first := m.enabled and not found
		if m.enabled:
			found = true
		if m.is_first_mask != first:
			m.is_first_mask = first
			m.notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "texture_id":
		TerrainMask.apply_texture_hint(property)
		property.usage |= PROPERTY_USAGE_READ_ONLY
