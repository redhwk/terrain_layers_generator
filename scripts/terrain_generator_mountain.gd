@tool
## A peak: tallest at this node's XZ position, falling off to nothing at Radius (scaled by the
## node's XZ scale). Y scale multiplies Height. Add under a TerrainGenerator, then press Generate
## (on this node or on the TerrainGenerator).
class_name TerrainGeneratorMountain
extends TerrainGeneratorShape


## Peak height in meters (at Scale Y = 1). Steep and narrow = high Height, small Radius.
@export_range(0.0, 2000.0, 0.1, "or_greater", "suffix:m") var height := 200.0:
	set(value):
		height = value
		update_configuration_warnings()

## Distance from the centre to the foot in meters (at Scale X/Z = 1). Keep the orange circle inside
## the yellow Area (or only the overlap is generated). Scale the node to widen or narrow it.
@export_range(10.0, 4000.0, 1.0, "or_greater", "suffix:m") var radius := 100.0:
	set(value):
		radius = value
		update_configuration_warnings()

## How the height falls off from the peak to the foot. Empty = a smooth dome (recommended).
## Smoothstep / Ease presets work. A plain line from 0 to 1 used to look like a pyramid; that now
## uses the same dome as Empty.
@export var falloff_curve: Curve

@export_group("Natural look", "natural_")
## Bends the round footprint sideways so it isn't a perfect circle (breaks the pyramid / cross-ridge
## look). 0.25 - 0.45 looks natural. 0 = a round dome.
@export_range(0.0, 1.0, 0.01) var natural_warp := 0.35
## Extra bumpy detail on the slopes, as a fraction of Height (0 = smooth).
@export_range(0.0, 1.0, 0.01) var natural_roughness := 0.2
## About how wide one roughness bump is, in meters.
@export_range(5.0, 500.0, 1.0, "or_greater", "suffix:m") var natural_roughness_size := 60.0
@export_group("")


static func _is_plain_rising_line(curve: Curve) -> bool:
	if curve.point_count != 2:
		return false
	var a := curve.get_point_position(0)
	var b := curve.get_point_position(1)
	return is_equal_approx(a.x, 0.0) and is_equal_approx(a.y, 0.0) \
		and is_equal_approx(b.x, 1.0) and is_equal_approx(b.y, 1.0) \
		and is_equal_approx(curve.get_point_left_tangent(0), 0.0) \
		and is_equal_approx(curve.get_point_right_tangent(0), 0.0) \
		and is_equal_approx(curve.get_point_left_tangent(1), 0.0) \
		and is_equal_approx(curve.get_point_right_tangent(1), 0.0)


func get_footprint_rect() -> Rect2:
	# Warp pushes the foot outward, so warnings / outlines use the expanded radius.
	var r := radius * maxf(absf(scale.x), absf(scale.z)) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)



func documentation_file() -> String:
	return "mountain.md"

func snapshot() -> TerrainGeneratorShapeData:
	if not enabled:
		return null
	var d := TerrainGeneratorShapeData.new()
	d.type = TerrainGeneratorShapeData.Type.MOUNTAIN
	d.blend_mode = blend_mode
	d.center = Vector2(global_position.x, global_position.z)
	d.radius = radius * maxf(absf(scale.x), absf(scale.z))
	d.height = height * absf(scale.y)
	# Empty, or a plain 0→1 line (New Curve / unedited Smoothstep points): smooth dome.
	# A straight 1 - t falloff looks like a pyramid.
	d.falloff_curve = PackedFloat32Array()
	if falloff_curve and falloff_curve.point_count > 0 and not _is_plain_rising_line(falloff_curve):
		d.falloff_curve = TerrainGenerator._curve_samples(falloff_curve)
	d.roughness = natural_roughness
	d.warp_amount = natural_warp
	var gen := get_generator()
	var seed_base := (gen.world_seed + 17) if gen else 17
	if natural_warp > 0.0:
		var w := FastNoiseLite.new()
		w.seed = seed_base + 3
		w.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		w.frequency = 1.0 / maxf(d.radius * 0.9, 1.0)
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


func outline_key() -> String:
	return "%s:%s:%s:%s:%s" % [global_position, scale, height, radius, natural_warp]


func outline_color() -> Color:
	return Color(1.0, 0.45, 0.2)


func add_outline(mesh: ImmediateMesh, y: float) -> void:
	var r := radius * maxf(absf(scale.x), absf(scale.z)) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	var color := outline_color()
	const SEGMENTS := 48
	mesh.surface_set_color(color)
	for i in SEGMENTS:
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		mesh.surface_add_vertex(Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r))
		mesh.surface_add_vertex(Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r))
	# Cross at the peak so it's easy to grab.
	mesh.surface_add_vertex(Vector3(c.x - 8.0, y, c.y))
	mesh.surface_add_vertex(Vector3(c.x + 8.0, y, c.y))
	mesh.surface_add_vertex(Vector3(c.x, y, c.y - 8.0))
	mesh.surface_add_vertex(Vector3(c.x, y, c.y + 8.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_notify_transform(true)
		update_configuration_warnings()