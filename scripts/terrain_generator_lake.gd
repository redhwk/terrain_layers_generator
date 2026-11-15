@tool
## A bowl carve with a flat bottom (lake bed) and banks rising to the rim. Depth is how far to
## carve down. Radius is centre to shore. Floor Width is the flat bed fraction of Radius. Always
## Subtract (Blend Mode hidden). Transform Scale X/Z stretches the footprint; Scale Y multiplies
## Depth. Add under a TerrainGenerator, then press Generate on this node.
class_name TerrainGeneratorLake
extends TerrainGeneratorShape



## How deep to carve in meters (at Scale Y = 1).
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var depth := 14.0:
	set(value):
		depth = value
		update_configuration_warnings()

## Distance from the centre to the shore / rim in meters (at Scale X/Z = 1).
@export_range(10.0, 4000.0, 1.0, "or_greater", "suffix:m") var radius := 120.0:
	set(value):
		radius = value
		update_configuration_warnings()

## Flat lake bed as a fraction of Radius (0 = V-bowl, 0.45 = typical pond, 0.65 = wide flat bed).
@export_range(0.0, 0.95, 0.01) var floor_width := 0.50

## How the banks rise from the bed (left) to the rim (right). Empty = smooth ((1 - t)^2).
@export var falloff_curve: Curve

@export_group("Natural look", "natural_")
## Bends the shoreline so it isn't a perfect circle/ellipse. 0 = round pond; 0.25 - 0.4 = natural;
## 0.5 - 0.65 = very broken, rocky cove look.
@export_range(0.0, 1.0, 0.01) var natural_warp := 0.26:
	set(value):
		natural_warp = value
		update_configuration_warnings()
## Extra bumpy detail on the lake bed and banks, as a fraction of Depth. 0 = smooth bowl;
## 0.1 - 0.2 = gentle; 0.5 - 0.7 = rough cliffs and uneven bed (pairs well with deeper Depth so
## Terrain Layers can autoshade steep banks as rock).
@export_range(0.0, 1.0, 0.01) var natural_roughness := 0.12
## About how wide one roughness bump is, in meters. Smaller = finer grit on the banks; larger
## (80 - 150) = broad rocky shelves and uneven bed patches.
@export_range(5.0, 500.0, 1.0, "or_greater", "suffix:m") var natural_roughness_size := 45.0
@export_group("")


func outline_key() -> String:
	return "%s:%s:%s:%s:%s:%s:%s" % [global_position, global_rotation.y, scale, depth, radius, floor_width, natural_warp]


func get_footprint_rect() -> Rect2:
	var rx := radius * absf(scale.x) * (1.0 + natural_warp)
	var rz := radius * absf(scale.z) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_a := absf(cos(yaw))
	var sin_a := absf(sin(yaw))
	var ext := Vector2(rx * cos_a + rz * sin_a, rx * sin_a + rz * cos_a)
	return Rect2(c - ext, ext * 2.0)



func documentation_file() -> String:
	return "lake.md"

func snapshot() -> TerrainGeneratorShapeData:
	if not enabled:
		return null
	var d := TerrainGeneratorShapeData.new()
	d.type = TerrainGeneratorShapeData.Type.LAKE
	d.blend_mode = BlendMode.SUBTRACT
	d.center = Vector2(global_position.x, global_position.z)
	d.rotation = global_rotation.y
	d.half_length = radius * absf(scale.x)
	d.radius = radius * absf(scale.z)
	d.height = depth * absf(scale.y)
	d.floor_width = floor_width
	d.falloff_curve = PackedFloat32Array()
	if falloff_curve and falloff_curve.point_count > 0 and not TerrainGeneratorMountain._is_plain_rising_line(falloff_curve):
		d.falloff_curve = TerrainGenerator._curve_samples(falloff_curve)
	d.roughness = natural_roughness
	d.warp_amount = natural_warp
	var gen := get_generator()
	var seed_base := (gen.world_seed + 113) if gen else 113
	if natural_warp > 0.0:
		var w := FastNoiseLite.new()
		w.seed = seed_base + 3
		w.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		w.frequency = 1.0
		w.fractal_octaves = 1
		d.warp_noise = w
	if natural_roughness > 0.0:
		var n := FastNoiseLite.new()
		n.seed = seed_base
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0 / maxf(natural_roughness_size, 0.01)
		n.fractal_octaves = 2
		n.fractal_gain = 0.45
		d.roughness_noise = n
	return d


func outline_color() -> Color:
	return Color(0.2, 0.45, 0.95)


func add_outline(mesh: ImmediateMesh, y: float) -> void:
	var rx := radius * absf(scale.x)
	var rz := radius * absf(scale.z)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var color := outline_color()
	var gen := get_generator()
	var seed_base := (gen.world_seed + 113) if gen else 113
	var wobble: FastNoiseLite = null
	if natural_warp > 0.0:
		wobble = FastNoiseLite.new()
		wobble.seed = seed_base + 3
		wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		wobble.frequency = 1.0
		wobble.fractal_octaves = 1
	const SEGMENTS := 64
	mesh.surface_set_color(color)
	for i in SEGMENTS:
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		mesh.surface_add_vertex(_lake_outline_point(c, rx, rz, cos_y, sin_y, y, a0, 1.0, wobble))
		mesh.surface_add_vertex(_lake_outline_point(c, rx, rz, cos_y, sin_y, y, a1, 1.0, wobble))
	var bed := clampf(floor_width, 0.0, 0.95)
	if bed > 0.05:
		mesh.surface_set_color(Color(color.r, color.g, color.b, 0.8))
		for i in SEGMENTS:
			var a0 := TAU * float(i) / SEGMENTS
			var a1 := TAU * float(i + 1) / SEGMENTS
			mesh.surface_add_vertex(_lake_outline_point(c, rx, rz, cos_y, sin_y, y, a0, bed, wobble))
			mesh.surface_add_vertex(_lake_outline_point(c, rx, rz, cos_y, sin_y, y, a1, bed, wobble))


func _lake_outline_point(c: Vector2, rx: float, rz: float, cos_y: float, sin_y: float, y: float, angle: float, ring: float, wobble: FastNoiseLite) -> Vector3:
	var mod := 1.0
	if wobble and natural_warp > 0.0:
		var w1 := wobble.get_noise_2d(cos(angle) * 1.15, sin(angle) * 1.15)
		mod = maxf(1.0 + natural_warp * w1, 0.65)
	var local := Vector2(cos(angle) * rx * ring * mod, sin(angle) * rz * ring * mod)
	return Vector3(c.x + local.x * cos_y - local.y * sin_y, y, c.y + local.x * sin_y + local.y * cos_y)


func _validate_property(property: Dictionary) -> void:
	if property.name == "blend_mode":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_notify_transform(true)
		update_configuration_warnings()