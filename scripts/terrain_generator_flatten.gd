@tool
## Levels ground toward a target Height inside the footprint — for landing pads, base sites, or
## building plots. The centre is fully flat; Edge Width blends softly into the surrounding terrain
## (smootherstep + extra widen near cliffs, so joins are gentler). Always lerps toward Height
## (Blend Mode hidden). Use Pick Height or Set Height from Centre instead of guessing. Then Generate.
class_name TerrainGeneratorFlatten
extends TerrainGeneratorShape



## Set by Pick Height; the Terrain Generator editor plugin samples the next viewport click.
static var height_pick_target: TerrainGeneratorFlatten = null


## Target elevation in meters (absolute). The pad is leveled toward this height. Use Pick Height
## or Set Height from Centre instead of guessing.
@export_range(-500.0, 2000.0, 0.1, "suffix:m") var height := 25.0:
	set(value):
		height = value
		update_configuration_warnings()

## Click the terrain in the 3D viewport to set Height (same idea as Terrain3D's height picker). Esc cancels.
@export_tool_button("Pick Height", "ColorPick") var pick_height_button := begin_pick_height

## Samples terrain height at this Flatten node's XZ and writes it into Height.
@export_tool_button("Set Height from Centre", "ColorPick") var pick_centre_button := set_height_from_centre

## Distance from the centre to the outer edge of the soft blend in meters (at Scale X/Z = 1).
@export_range(5.0, 2000.0, 1.0, "or_greater", "suffix:m") var radius := 80.0:
	set(value):
		radius = value
		update_configuration_warnings()

## Soft blend as a fraction of Radius (0.25 = tighter pad, 0.45 = typical, 0.6 = wide feather into
## cliffs). Near tall cliffs the blend widens automatically. Raise this if textures still look stretched.
@export_range(0.05, 0.9, 0.01) var edge_width := 0.45

@export_group("Natural look", "natural_")
## Bends the pad outline so it isn't a perfect circle/ellipse. 0 = round; 0.1 - 0.25 = slight
## irregularity. Keep low for a clean landing pad.
@export_range(0.0, 1.0, 0.01) var natural_warp := 0.12:
	set(value):
		natural_warp = value
		update_configuration_warnings()
@export_group("")


func begin_pick_height() -> void:
	height_pick_target = self
	print("%s: click the terrain to set Height (Esc cancels)." % name)


func apply_picked_height(world_pos: Vector3) -> void:
	var h := _sample_terrain_height(world_pos)
	if is_nan(h):
		h = world_pos.y
	height = snappedf(h, 0.1)
	height_pick_target = null
	notify_property_list_changed()
	print("%s: Height set to %.1f m (picked at %.1f, %.1f)." % [name, height, world_pos.x, world_pos.z])


func set_height_from_centre() -> void:
	var h := _sample_terrain_height(global_position)
	if is_nan(h):
		push_warning("%s: no terrain height at centre (%.1f, %.1f)." % [name, global_position.x, global_position.z])
		return
	height = snappedf(h, 0.1)
	notify_property_list_changed()
	print("%s: Height set to %.1f m from centre." % [name, height])


func _sample_terrain_height(at: Vector3) -> float:
	var gen := get_generator()
	if gen == null:
		return NAN
	var t = gen.get_terrain()
	if t == null or t.get("data") == null:
		return NAN
	return Terrain3DBridge.height_at(t, at)


func outline_key() -> String:
	return "%s:%s:%s:%s:%s:%s:%s" % [global_position, global_rotation.y, scale, height, radius, edge_width, natural_warp]


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
	return "flatten.md"

func snapshot() -> TerrainGeneratorShapeData:
	if not enabled:
		return null
	var d := TerrainGeneratorShapeData.new()
	d.type = TerrainGeneratorShapeData.Type.FLATTEN
	d.blend_mode = BlendMode.MAX # Unused; apply() lerps toward Height.
	d.center = Vector2(global_position.x, global_position.z)
	d.rotation = global_rotation.y
	d.half_length = radius * absf(scale.x)
	d.radius = radius * absf(scale.z)
	d.height = height
	d.floor_width = edge_width
	d.warp_amount = natural_warp
	var gen := get_generator()
	var seed_base := (gen.world_seed + 131) if gen else 131
	if natural_warp > 0.0:
		var w := FastNoiseLite.new()
		w.seed = seed_base + 3
		w.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		w.frequency = 1.0
		w.fractal_octaves = 1
		d.warp_noise = w
	return d


func outline_color() -> Color:
	return Color(0.75, 0.55, 0.95)


func add_outline(mesh: ImmediateMesh, y: float) -> void:
	var rx := radius * absf(scale.x)
	var rz := radius * absf(scale.z)
	var c := Vector2(global_position.x, global_position.z)
	var yaw := global_rotation.y
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var color := outline_color()
	var gen := get_generator()
	var seed_base := (gen.world_seed + 131) if gen else 131
	var wobble: FastNoiseLite = null
	if natural_warp > 0.0:
		wobble = FastNoiseLite.new()
		wobble.seed = seed_base + 3
		wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		wobble.frequency = 1.0
		wobble.fractal_octaves = 1
	const SEGMENTS := 48
	mesh.surface_set_color(color)
	for i in SEGMENTS:
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		mesh.surface_add_vertex(_flatten_outline_point(c, rx, rz, cos_y, sin_y, y, a0, 1.0, wobble))
		mesh.surface_add_vertex(_flatten_outline_point(c, rx, rz, cos_y, sin_y, y, a1, 1.0, wobble))
	var flat := clampf(1.0 - edge_width, 0.05, 0.95)
	mesh.surface_set_color(Color(color.r, color.g, color.b, 0.8))
	for i in SEGMENTS:
		var a0 := TAU * float(i) / SEGMENTS
		var a1 := TAU * float(i + 1) / SEGMENTS
		mesh.surface_add_vertex(_flatten_outline_point(c, rx, rz, cos_y, sin_y, y, a0, flat, wobble))
		mesh.surface_add_vertex(_flatten_outline_point(c, rx, rz, cos_y, sin_y, y, a1, flat, wobble))


func _flatten_outline_point(c: Vector2, rx: float, rz: float, cos_y: float, sin_y: float, y: float, angle: float, ring: float, wobble: FastNoiseLite) -> Vector3:
	var mod := 1.0
	if wobble and natural_warp > 0.0:
		var w1 := wobble.get_noise_2d(cos(angle) * 1.15, sin(angle) * 1.15)
		mod = maxf(1.0 + natural_warp * w1, 0.7)
	var local := Vector2(cos(angle) * rx * ring * mod, sin(angle) * rz * ring * mod)
	return Vector3(c.x + local.x * cos_y - local.y * sin_y, y, c.y + local.x * sin_y + local.y * cos_y)


func _validate_property(property: Dictionary) -> void:
	if property.name == "blend_mode":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_notify_transform(true)
		update_configuration_warnings()