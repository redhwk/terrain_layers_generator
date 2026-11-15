@tool
## A carve: deepest along this node's X axis, rising to the banks at Width. Scale X lengthens it,
## Scale Z widens it, Scale Y multiplies Depth. Rotation Y aims the valley. Default Blend Mode is
## Subtract. Add under a TerrainGenerator, then press Generate.
class_name TerrainGeneratorValley
extends TerrainGeneratorShape


## How deep to carve in meters (at Scale Y = 1).
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var depth := 40.0:
	set(value):
		depth = value
		update_configuration_warnings()

## Along the cyan centre line: metres from the centre to each end (total valley length ≈ Length x 2).
## For a long canyon, make Length much larger than Width and aim with Rotation Y.
@export_range(10.0, 4000.0, 1.0, "or_greater", "suffix:m") var length := 200.0:
	set(value):
		length = value
		update_configuration_warnings()

## Across the cyan centre line: metres from the centre out to each bank (total span ≈ Width x 2).
## Keep this smaller than Length for a canyon; larger than Length makes a wide short bowl.
@export_range(5.0, 2000.0, 1.0, "or_greater", "suffix:m") var width := 80.0:
	set(value):
		width = value
		update_configuration_warnings()

## Flat bottom as a fraction of Width (0 = V-shape / knife cut, 0.35 = U-shape, 0.55 - 0.7 = canyon
## floor). Raise this for a flat-bottomed canyon.
@export_range(0.0, 0.95, 0.01) var floor_width := 0.35

## How the banks rise from the floor (left) to the rim (right). Empty = smooth ((1 - t)^2).
@export var falloff_curve: Curve

@export_group("Natural look", "natural_")
## Bends the banks sideways so the valley isn't a perfect oval. 0.25 - 0.45 looks natural.
@export_range(0.0, 1.0, 0.01) var natural_warp := 0.35:
	set(value):
		natural_warp = value
		update_configuration_warnings()
## Extra bumpy detail on the banks, as a fraction of Depth.
@export_range(0.0, 1.0, 0.01) var natural_roughness := 0.15
@export_range(5.0, 500.0, 1.0, "or_greater", "suffix:m") var natural_roughness_size := 50.0
@export_group("")


func outline_key() -> String:
	return "%s:%s:%s:%s:%s:%s:%s" % [global_position, global_rotation.y, scale, depth, length, width, natural_warp]


func get_footprint_rect() -> Rect2:
	var hl := length * absf(scale.x) * (1.0 + natural_warp)
	var hw := width * absf(scale.z) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	# Axis-aligned bounds of the rotated ellipse (conservative).
	var yaw := global_rotation.y
	var cos_a := absf(cos(yaw))
	var sin_a := absf(sin(yaw))
	var ext := Vector2(hl * cos_a + hw * sin_a, hl * sin_a + hw * cos_a)
	return Rect2(c - ext, ext * 2.0)



func documentation_file() -> String:
	return "valley.md"

func snapshot() -> TerrainGeneratorShapeData:
	if not enabled:
		return null
	var d := TerrainGeneratorShapeData.new()
	d.type = TerrainGeneratorShapeData.Type.VALLEY
	d.blend_mode = BlendMode.SUBTRACT # Valley always carves.
	d.center = Vector2(global_position.x, global_position.z)
	d.rotation = global_rotation.y
	d.half_length = length * absf(scale.x)
	d.radius = width * absf(scale.z) # half-width stored in radius for valleys
	d.height = depth * absf(scale.y)
	d.floor_width = floor_width
	d.falloff_curve = PackedFloat32Array()
	if falloff_curve and falloff_curve.point_count > 0 and not TerrainGeneratorMountain._is_plain_rising_line(falloff_curve):
		d.falloff_curve = TerrainGenerator._curve_samples(falloff_curve)
	d.roughness = natural_roughness
	d.warp_amount = natural_warp
	var gen := get_generator()
	var seed_base := (gen.world_seed + 91) if gen else 91
	if natural_warp > 0.0:
		var w := FastNoiseLite.new()
		w.seed = seed_base + 3
		w.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		w.frequency = 1.0 / maxf(maxf(d.half_length, d.radius) * 0.9, 1.0)
		w.fractal_octaves = 2
		d.warp_noise = w
	if natural_roughness > 0.0:
		var n := FastNoiseLite.new()
		n.seed = seed_base
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0 / maxf(natural_roughness_size, 0.01)
		n.fractal_octaves = 3
		n.fractal_gain = 0.5
		d.roughness_noise = n
	return d


func outline_color() -> Color:
	return Color(0.35, 0.75, 1.0)


func add_outline(mesh: ImmediateMesh, y: float) -> void:
	var hl := length * absf(scale.x) * (1.0 + natural_warp)
	var hw := width * absf(scale.z) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var color := outline_color()
	const SEGMENTS := 48
	mesh.surface_set_color(color)
	for i in SEGMENTS:
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		var p0 := _ellipse_point(c, hl, hw, cos_y, sin_y, y, a0)
		var p1 := _ellipse_point(c, hl, hw, cos_y, sin_y, y, a1)
		mesh.surface_add_vertex(p0)
		mesh.surface_add_vertex(p1)
	# Centre line so the aim is obvious.
	var axis := Vector2(cos_y, sin_y) * hl
	mesh.surface_add_vertex(Vector3(c.x - axis.x, y, c.y - axis.y))
	mesh.surface_add_vertex(Vector3(c.x + axis.x, y, c.y + axis.y))


func _ellipse_point(c: Vector2, hl: float, hw: float, cos_y: float, sin_y: float, y: float, angle: float) -> Vector3:
	var local := Vector2(cos(angle) * hl, sin(angle) * hw)
	return Vector3(c.x + local.x * cos_y - local.y * sin_y, y, c.y + local.x * sin_y + local.y * cos_y)


func _validate_property(property: Dictionary) -> void:
	if property.name == "blend_mode":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_notify_transform(true)
		update_configuration_warnings()