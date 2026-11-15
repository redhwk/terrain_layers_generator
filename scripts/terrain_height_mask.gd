@tool
class_name TerrainHeightMask
extends TerrainMask
## Masks by terrain height. Inside Min..Max the Height Curve sets the value
## (x 0 = Min Height, x 1 = Max Height).

enum HeightReference { RELATIVE_TO_SEA_LEVEL, WORLD_SPACE }
enum HeightUnit { PERCENT, METERS }

## Relative To Sea Level: heights are measured from the TerrainLayerMasks sea level.
## World Space: heights are world Y (Percent then starts at the terrain's lowest point).
@export var height_reference: HeightReference = HeightReference.RELATIVE_TO_SEA_LEVEL:
	set(value):
		height_reference = value
		emit_changed()

## Meters: fixed heights (1 Godot unit = 1 m). Percent: % of the terrain's total height range
## (lowest to highest sculpted point), so it moves when you sculpt higher peaks.
@export var unit: HeightUnit = HeightUnit.METERS:
	set(value):
		unit = value
		emit_changed()

## Bottom of the range (percent or meters, see Unit).
@export var min_height := 0.0:
	set(value):
		min_height = value
		emit_changed()

## Top of the range (percent or meters, see Unit).
@export var max_height := 10.0:
	set(value):
		max_height = value
		emit_changed()

## Mask value across the range (x 0 = Min Height, x 1 = Max Height). Empty = linear ramp up.
@export var height_curve: Curve:
	set(value):
		_watch(height_curve, value)
		height_curve = value
		emit_changed()

## Extend Edges (default): keeps the curve's end values outside the range, so the mask is a ramp:
## 0 below Min, rising to 1 at Max, 1 above. Zero: no mask outside Min..Max (a band).
@export var outside_range: OutsideRange = OutsideRange.EXTEND_EDGES:
	set(value):
		outside_range = value
		emit_changed()


func get_mask_type() -> int:
	return TYPE_HEIGHT


func get_mask_curve() -> Curve:
	return height_curve


## Min / max as world heights. height_range = Terrain3D's lowest and highest point.
func resolve_range(sea_level: float, height_range: Vector2) -> Vector2:
	var span := maxf(height_range.y - height_range.x, 0.001)
	var origin := 0.0
	if height_reference == HeightReference.RELATIVE_TO_SEA_LEVEL:
		origin = sea_level
	elif unit == HeightUnit.PERCENT:
		origin = height_range.x
	if unit == HeightUnit.PERCENT:
		return Vector2(origin + min_height * 0.01 * span, origin + max_height * 0.01 * span)
	return Vector2(origin + min_height, origin + max_height)
