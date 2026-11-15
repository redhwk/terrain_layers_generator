@tool
## A flat-topped plateau with steep sides. Height is the plateau elevation (always Max blend, like
## Valley always carves). Radius is the foot. Transform Scale X/Z stretches the footprint; Scale Y
## multiplies Height. Add under a TerrainGenerator, then press Generate on this node.
class_name TerrainGeneratorMesa
extends TerrainGeneratorShape



## Plateau height in meters (at Scale Y = 1). With Max blend this is the absolute top elevation.
@export_range(0.0, 2000.0, 0.1, "or_greater", "suffix:m") var height := 80.0:
	set(value):
		height = value
		update_configuration_warnings()

## Distance from the centre to the foot in meters (at Scale X/Z = 1).
@export_range(10.0, 4000.0, 1.0, "or_greater", "suffix:m") var radius := 120.0:
	set(value):
		radius = value
		update_configuration_warnings()

## Flat top as a fraction of Radius (0 = pointed like a mountain, 0.72 = typical mesa, 0.85 = wide
## table with thin cliffs). Higher = more vertical sides (narrower cliff band).
@export_range(0.0, 0.95, 0.01) var top_width := 0.72

## Optional. Leave empty for the built-in steep face + soft talus (recommended). Only set a curve if
## you want a custom cliff profile: left = rim, right = foot. You do not need this for normal use.
@export var falloff_curve: Curve

@export_group("Natural look", "natural_")
## How irregular the plateau outline is (real mesas are rarely perfect circles). 0 = ellipse/circle;
## 0.2 - 0.3 = broad natural lobes.
@export_range(0.0, 1.0, 0.01) var natural_warp := 0.22:
	set(value):
		natural_warp = value
		update_configuration_warnings()
## Mid-cliff bumps plus light plateau detail (rolling / shallow washes), as a fraction of Height.
## 0 = table-flat top; 0.08 - 0.12 = natural. Fades before the rim.
@export_range(0.0, 1.0, 0.01) var natural_roughness := 0.09
@export_range(5.0, 500.0, 1.0, "or_greater", "suffix:m") var natural_roughness_size := 80.0
@export_group("")


func outline_key() -> String:
	return "%s:%s:%s:%s:%s:%s:%s" % [global_position, global_rotation.y, scale, height, radius, top_width, natural_warp]


func get_footprint_rect() -> Rect2:
	# Outline wobble can push the foot out by about Natural Warp.
	var rx := radius * absf(scale.x) * (1.0 + natural_warp)
	var rz := radius * absf(scale.z) * (1.0 + natural_warp)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_a := absf(cos(yaw))
	var sin_a := absf(sin(yaw))
	var ext := Vector2(rx * cos_a + rz * sin_a, rx * sin_a + rz * cos_a)
	return Rect2(c - ext, ext * 2.0)



func documentation_file() -> String:
	return "mesa.md"

func snapshot() -> TerrainGeneratorShapeData:
	if not enabled:
		return null
	var d := TerrainGeneratorShapeData.new()
	d.type = TerrainGeneratorShapeData.Type.MESA
	d.blend_mode = BlendMode.MAX # Always Max: Add on hills makes a jagged rim / walking shelf look.
	d.center = Vector2(global_position.x, global_position.z)
	d.rotation = global_rotation.y
	d.half_length = radius * absf(scale.x)
	d.radius = radius * absf(scale.z)
	d.height = height * absf(scale.y)
	d.floor_width = top_width
	d.falloff_curve = PackedFloat32Array()
	if falloff_curve and falloff_curve.point_count > 0 and not TerrainGeneratorMountain._is_plain_rising_line(falloff_curve):
		d.falloff_curve = TerrainGenerator._curve_samples(falloff_curve)
	d.roughness = natural_roughness
	d.warp_amount = natural_warp
	var gen := get_generator()
	var seed_base := (gen.world_seed + 53) if gen else 53
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
		n.fractal_gain = 0.4
		d.roughness_noise = n
	return d


func outline_color() -> Color:
	return Color(0.85, 0.65, 0.25)


func can_draw_outline() -> bool:
	return true


func add_outline(mesh: ImmediateMesh, y: float) -> bool:
	var rx := radius * absf(scale.x)
	var rz := radius * absf(scale.z)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var color := outline_color()
	var gen := get_generator()
	var seed_base := (gen.world_seed + 53) if gen else 53
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
		mesh.surface_add_vertex(_mesa_outline_point(c, rx, rz, cos_y, sin_y, y, a0, 1.0, wobble))
		mesh.surface_add_vertex(_mesa_outline_point(c, rx, rz, cos_y, sin_y, y, a1, 1.0, wobble))
	var top := clampf(top_width, 0.0, 0.95)
	if top > 0.05:
		mesh.surface_set_color(Color(color.r, color.g, color.b, 0.85))
		for i in SEGMENTS:
			var a0 := TAU * float(i) / SEGMENTS
			var a1 := TAU * float(i + 1) / SEGMENTS
			mesh.surface_add_vertex(_mesa_outline_point(c, rx, rz, cos_y, sin_y, y, a0, top, wobble))
			mesh.surface_add_vertex(_mesa_outline_point(c, rx, rz, cos_y, sin_y, y, a1, top, wobble))
	return true


func _mesa_outline_point(c: Vector2, rx: float, rz: float, cos_y: float, sin_y: float, y: float, angle: float, ring: float, wobble: FastNoiseLite) -> Vector3:
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