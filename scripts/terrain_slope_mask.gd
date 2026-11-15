@tool
class_name TerrainSlopeMask
extends TerrainMask
## Masks by slope steepness (0 = flat, 90 = vertical). Inside Min..Max the Slope Curve
## sets the value (x 0 = Min Slope, x 1 = Max Slope).

## Flattest slope of the range.
@export_range(0.0, 90.0, 0.1, "suffix:°") var min_slope := 0.0:
	set(value):
		min_slope = value
		emit_changed()

## Steepest slope of the range.
@export_range(0.0, 90.0, 0.1, "suffix:°") var max_slope := 45.0:
	set(value):
		max_slope = value
		emit_changed()

## Mask value across the range (x 0 = Min Slope, x 1 = Max Slope). Empty = linear ramp up.
@export var slope_curve: Curve:
	set(value):
		_watch(slope_curve, value)
		slope_curve = value
		emit_changed()

## Extend Edges (default): keeps the curve's end values outside the range, so the mask is a ramp:
## 0 below Min, rising to 1 at Max, 1 above. Zero: no mask outside Min..Max (a band).
@export var outside_range: OutsideRange = OutsideRange.EXTEND_EDGES:
	set(value):
		outside_range = value
		emit_changed()


func get_mask_type() -> int:
	return TYPE_SLOPE


func get_mask_curve() -> Curve:
	return slope_curve
