@tool
class_name TerrainMask
extends Resource
## One mask in a TerrainMaskLayer. A layer's masks run top to bottom;
## each one combines with the result of the masks above it using Blend Mode.

enum BlendMode { MULTIPLY, GREATER_THAN, SMALLER_THAN, ADD, SUBTRACT }
enum OutsideRange { ZERO, EXTEND_EDGES }

## Mask type ids used by terrain_layer_masks.gdshaderinc.
const TYPE_HEIGHT := 0
const TYPE_SLOPE := 1
const TYPE_NOISE := 2
const TYPE_TEXTURE := 3
const TYPE_TERRAIN3D_AUTO := 4

## Texture names of the active Terrain3D (set by TerrainLayerMasks) for the texture dropdowns.
static var texture_names: PackedStringArray = []

## Turn the mask off without deleting it.
@export var enabled := true:
	set(value):
		enabled = value
		emit_changed()

## How this mask combines with the masks above it in the same layer.
## Hidden on the layer's first enabled mask (that one sets the starting value).
@export var blend_mode: BlendMode = BlendMode.MULTIPLY:
	set(value):
		blend_mode = value
		emit_changed()

## Flips the mask (1 - value) before Strength Transform.
@export var invert := false:
	set(value):
		invert = value
		emit_changed()

## Final remap of the mask value (x = mask value 0..1, y = strength 0..1). Empty = unchanged.
@export var strength_transform: Curve:
	set(value):
		_watch(strength_transform, value)
		strength_transform = value
		emit_changed()


## Set by the owning TerrainMaskLayer: true on its first enabled mask.
var is_first_mask := false


func get_mask_type() -> int:
	return -1


func _validate_property(property: Dictionary) -> void:
	if property.name == "blend_mode" and is_first_mask:
		property.usage = PROPERTY_USAGE_STORAGE


## The type-specific curve (height / slope / noise). Null = linear.
func get_mask_curve() -> Curve:
	return null


func _watch(old: Resource, new: Resource) -> void:
	if old and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	if new and not new.changed.is_connected(emit_changed):
		new.changed.connect(emit_changed)


## Enum hint like "Dry_Sand:1" for texture id properties, named as in Terrain3D ("" if no terrain yet).
static func texture_enum_hint() -> String:
	if texture_names.is_empty():
		return ""
	var parts := PackedStringArray()
	for i in texture_names.size():
		var label := texture_names[i].replace(",", " ").replace(":", " ")
		parts.append("%s:%d" % [label, i])
	return ",".join(parts)


static func apply_texture_hint(property: Dictionary) -> void:
	var hint := texture_enum_hint()
	if hint != "":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = hint
