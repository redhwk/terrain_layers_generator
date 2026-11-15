@tool
## A feature placed under a TerrainGenerator (Mountain, Valley, ...). Move and scale it in the
## viewport, then press Generate (here or on the TerrainGenerator). Applied after the base noise,
## in Scene dock order.
class_name TerrainGeneratorShape
extends Node3D


enum BlendMode {
	ADD, ## Stacks on the base noise and earlier shapes.
	MAX, ## Uses the higher of the current height and this shape's height.
	MIN, ## Uses the lower of the two.
	SUBTRACT, ## Carves this shape's height out of the current height.
}

## Off: ignored when Generate runs.
@export var enabled := true

## How this shape combines with the base noise and earlier shapes (Scene dock order).
@export var blend_mode: BlendMode = BlendMode.ADD

## Applies only this shape onto the terrain you see now (does not rebuild base noise or other shapes).
## Use the TerrainGenerator's Generate to rebuild everything (noise + all shapes).
@export_tool_button("Generate", "Reload") var generate_button := generate


## Override in each shape (e.g. "mountain.md"). Used by the Inspector Doc control.
func documentation_file() -> String:
	return "terrain_generator.md"


func get_generator() -> TerrainGenerator:
	var p := get_parent()
	return p as TerrainGenerator


func generate() -> void:
	var gen := get_generator()
	if gen == null:
		push_warning("%s: put this node under a TerrainGenerator." % name)
		return
	await gen.generate_shape(self)


## Main-thread snapshot for worker threads. Override in each shape.
func snapshot() -> TerrainGeneratorShapeData:
	return null


## World-space axis-aligned bounds of this shape's footprint. Used to warn when it's outside the Area.
func get_footprint_rect() -> Rect2:
	return Rect2()


## Editor outline colour for this shape.
func outline_color() -> Color:
	return Color(0.4, 0.85, 1.0)


## Draws this shape's footprint into an ImmediateMesh (editor outline). Override in each shape.
func add_outline(mesh: ImmediateMesh, y: float) -> void:
	pass


## Included in the generator's outline cache key so Inspector edits refresh the oval / circle.
func outline_key() -> String:
	return "%s:%s" % [global_position, scale]


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var gen := get_generator()
	if gen == null:
		w.append("Put this node under a TerrainGenerator.")
		return w
	if not enabled:
		return w
	if gen.scope != TerrainGenerator.Scope.AREA:
		return w
	var area := gen.get_area_rect()
	var foot := get_footprint_rect()
	if foot.size == Vector2.ZERO:
		return w
	var center := foot.get_center()
	# How far the footprint sticks out past the Area (0 = fully inside).
	var overflow := maxf(maxf(area.position.x - foot.position.x, foot.end.x - area.end.x),
		maxf(area.position.y - foot.position.y, foot.end.y - area.end.y))
	if not area.has_point(center):
		w.append("This shape's centre is outside the TerrainGenerator's Area, so Generate won't raise a peak here. Move it inside the yellow outline, or enlarge Area Size.")
	elif overflow > 1.0:
		# Clipping is allowed (e.g. Area 256 with a wider Radius); only nudge, and spell out the fix.
		var area_w := mini(area.size.x, area.size.y)
		var shape_d := maxf(foot.size.x, foot.size.y)
		w.append("Orange footprint is wider than the yellow Area (%.0f m vs %.0f m). Shrink Radius (or Scale), or enlarge Area Size. Only the overlap is generated." % [shape_d, area_w])
	return w