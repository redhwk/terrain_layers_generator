@tool
## Terrain layers for Terrain3D's auto shader: every Terrain3D texture can be placed by masks.
## Add as a child of Terrain3D and assign a Layer Stack. Applies wherever Terrain3D's auto shader
## applies (outside regions and areas painted with the Autoshader brush); hand painting stays.
## Uses the addon layer shader (Rebuild Shader) as the material's Shader Override,
## built from Terrain3D's own shader by Rebuild Shader (automatic in the editor).
##
## @tutorial(Full Guide): res://addons/terrain_layers_generator/docs/terrain_layers.md
class_name TerrainLayerMasks
extends Node


const MAX_LAYERS := 32
const MAX_MASKS := 64
const CURVE_WIDTH := 256
const UPDATE_DELAY := 0.15
const SHADER_PATH := TerrainLayerShaderBuilder.SHADER_PATH

## Terrain3D to texture. Empty = the parent node.
@export var terrain: Node:
	set(value):
		terrain = value
		_disconnect_terrain()
		_queue_update()
		update_configuration_warnings()

## The layers and masks (save as .tres to reuse as a preset).
@export var stack: TerrainLayerStack:
	set(value):
		if stack and stack.changed.is_connected(_queue_update):
			stack.changed.disconnect(_queue_update)
		stack = value
		if stack and not stack.changed.is_connected(_queue_update):
			stack.changed.connect(_queue_update)
		_names_dirty = true
		_queue_update()
		update_configuration_warnings()

## Off = Terrain3D's own 2-texture auto shader.
@export var enabled := true:
	set(value):
		enabled = value
		_queue_update()
		update_configuration_warnings()

enum SeaLevelSource { MANUAL, TERRAIN3D_OCEAN, NODE }

@export_group("Sea Level")
## Where "Relative To Sea Level" height masks get sea level from.
## Manual: the Sea Level value below.
## Terrain3D Ocean: the Sea Level setting of Terrain3D's Ocean Material (works with the ocean off too).
## Node: the height of Sea Level Node (any Node3D, e.g. your own water plane or a Marker3D at the waterline).
@export var sea_level_source: SeaLevelSource = SeaLevelSource.MANUAL:
	set(value):
		sea_level_source = value
		_queue_update()
		notify_property_list_changed()

## Sea level height (meters) for Manual, and the fallback if the other sources are missing.
@export var sea_level := 0.0:
	set(value):
		sea_level = value
		_queue_update()

## Node whose height is sea level (Source = Node).
@export var sea_level_node: Node3D:
	set(value):
		sea_level_node = value
		_queue_update()

@export_group("Noise")
## Pixel size of each baked noise tile. Higher = finer detail, slower to rebuild.
@export_enum("256:256", "512:512", "1024:1024") var noise_resolution := 512:
	set(value):
		noise_resolution = value
		_queue_update()

@export_group("Shader")
## Editor: rebuild the layer shader automatically when Terrain3D material shader options change
## (Texture Filtering, Auto Shader, Dual Scaling, Macro Variation, Projection, Max Regions, PBR Output).
@export var auto_rebuild_shader := true

## Regenerates terrain_layer_shader.gdshader from Terrain3D's shader with the material's current
## options (all World Backgrounds included) and sets it as the material's Shader Override.
@export_tool_button("Rebuild Shader", "Shader") var rebuild_shader_button := rebuild_shader

@export_group("")
## Makes the stack match Terrain3D's textures (Layer N = texture N). Normally automatic.
@export_tool_button("Sync Textures", "Add") var add_missing_textures_button := add_missing_textures
## Rebuilds everything now (normally automatic).
@export_tool_button("Refresh", "Reload") var refresh_button := refresh


func documentation_file() -> String:
	return "terrain_layers.md"

var _dirty := true
var _names_dirty := true
var _wait := 0.0
var _material_rid := RID()
var _last_sea_level := 0.0
var _noise_cache := {}
var _curve_texture_ref: ImageTexture
var _noise_texture_ref: Texture2DArray
var _last_noise_images: Array[Image] = []
var _connected_terrain: Node
var _warned := {}
var _check_timer := 0.0
var _pushed_layer_count := -1
var _pushed_shader := ""
var _rebuilding := false


func _ready() -> void:
	_queue_update()


func _exit_tree() -> void:
	_disconnect_terrain()


func _process(delta: float) -> void:
	var rid := _get_material_rid()
	if rid != _material_rid:
		_dirty = true
		_wait = 0.0
	_check_timer -= delta
	if _check_timer <= 0.0 and rid.is_valid() and not _dirty:
		# Terrain3D can re-apply its own shader params (e.g. after material edits); re-push ours if lost.
		_check_timer = 0.5
		if _shader_key() != _pushed_shader or RenderingServer.material_get_param(rid, "_tlm_layer_count") != _pushed_layer_count:
			_dirty = true
			_wait = 0.0
	var t = get_terrain()
	if t and not is_equal_approx(get_sea_level(t), _last_sea_level):
		_queue_update()
	if not _dirty:
		return
	_wait -= delta
	if _wait <= 0.0:
		refresh()


## Batches changes: the update runs UPDATE_DELAY after the first change (later changes don't
## push it back, so constant changes can't starve it).
func _queue_update() -> void:
	if not _dirty:
		_dirty = true
		_wait = UPDATE_DELAY


func get_terrain() -> Node:
	var t := terrain if terrain else get_parent()
	if t and t.is_class("Terrain3D"):
		return t
	return null


## Pushes the stack to the terrain shader.
func refresh() -> void:
	_dirty = false
	var t = get_terrain()
	if t == null:
		return
	_connect_terrain(t)
	if _names_dirty:
		_update_texture_names(t)
	var rid := _get_material_rid()
	_material_rid = rid
	if not rid.is_valid():
		return
	var no_sharpness := PackedFloat32Array()
	no_sharpness.resize(32)
	var params := {"_tlm_layer_count": 0, "_tlm_texture_sharpness": no_sharpness}
	if enabled and stack:
		params = _build_params(t)
	for key in params:
		var value = params[key]
		if value is Texture:
			value = value.get_rid()
		RenderingServer.material_set_param(rid, key, value)
	_pushed_layer_count = params["_tlm_layer_count"]
	_pushed_shader = _shader_key()
	update_configuration_warnings()


## A CPU evaluator with exactly the data the shader gets (for baking / texture lookups).
## Uses the stack even when Enabled is off. Null without a terrain or stack.
func create_evaluator() -> TerrainLayerEvaluator:
	var t = get_terrain()
	if t == null or stack == null:
		return null
	if _names_dirty:
		_update_texture_names(t)
	# _build_params replaces the textures the live shader is using; put those back afterwards.
	var keep_curves := _curve_texture_ref
	var keep_noise := _noise_texture_ref
	var keep_images := _last_noise_images
	var params := _build_params(t)
	var evaluator := TerrainLayerEvaluator.new(params, _curve_texture_ref.get_image(), _last_noise_images)
	_curve_texture_ref = keep_curves
	_noise_texture_ref = keep_noise
	_last_noise_images = keep_images
	return evaluator


func add_missing_textures() -> void:
	var t = get_terrain()
	if t == null or t.assets == null or t.assets.get_texture_count() == 0:
		push_warning("TerrainLayerMasks: no Terrain3D with textures found.")
		return
	if stack == null:
		stack = TerrainLayerStack.new()
	_names_dirty = true
	refresh()
	notify_property_list_changed()


## Layer N = Terrain3D texture N. Older stacks (layers in painting order) are converted once,
## keeping their painting order as Paint Order. New layers start off, except texture 0 in a new stack.
func _sync_stack(texture_count: int) -> void:
	if stack == null or texture_count <= 0:
		return
	var layers := stack.layers
	var in_order := true
	for i in layers.size():
		if layers[i] == null or layers[i].texture_id != i:
			in_order = false
			break
	if in_order and layers.size() >= texture_count:
		return
	var by_id := {}
	var highest := texture_count - 1
	for i in layers.size():
		var layer := layers[i]
		if layer == null:
			continue
		if by_id.has(layer.texture_id):
			push_warning("TerrainLayerMasks: texture %d had more than one layer; kept the first." % layer.texture_id)
			continue
		if not in_order:
			layer.paint_order = i
		by_id[layer.texture_id] = layer
		highest = maxi(highest, layer.texture_id)
	var was_empty := by_id.is_empty()
	var synced: Array[TerrainMaskLayer] = []
	for i in highest + 1:
		if by_id.has(i):
			synced.append(by_id[i])
		else:
			var layer := TerrainMaskLayer.new()
			layer.texture_id = i
			layer.paint_order = i
			layer.enabled = was_empty and i == 0
			synced.append(layer)
	stack.layers = synced
	stack.notify_property_list_changed()


## Sea level for "Relative To Sea Level" height masks (see Sea Level Source).
func get_sea_level(t) -> float:
	if sea_level_source == SeaLevelSource.NODE and sea_level_node:
		return sea_level_node.global_position.y
	if sea_level_source == SeaLevelSource.TERRAIN3D_OCEAN and t:
		var ocean = t.get("ocean_material")
		if ocean is ShaderMaterial:
			var v = ocean.get_shader_parameter("sea_level")
			if v != null:
				return float(v)
	return sea_level


func _build_params(t) -> Dictionary:
	var sea := get_sea_level(t)
	_last_sea_level = sea
	var height_range := Vector2(0.0, 100.0)
	if t.data:
		height_range = t.data.get_height_range()
	var texture_count: int = t.assets.get_texture_count() if t.assets else 0
	if texture_count <= 0:
		texture_count = MAX_LAYERS

	var layers := PackedVector4Array()
	layers.resize(MAX_LAYERS)
	var mask_a := PackedVector4Array()
	var mask_b := PackedVector4Array()
	var mask_c := PackedVector4Array()
	mask_a.resize(MAX_MASKS)
	mask_b.resize(MAX_MASKS)
	mask_c.resize(MAX_MASKS)
	var curves: Array[Curve] = []
	var noise_images: Array[Image] = []
	var layer_count := 0
	var mask_count := 0

	var active: Array[TerrainMaskLayer] = []
	for layer in stack.layers:
		if layer and layer.enabled:
			active.append(layer)
	active.sort_custom(func(a: TerrainMaskLayer, b: TerrainMaskLayer) -> bool:
		return a.paint_order < b.paint_order or (a.paint_order == b.paint_order and a.texture_id < b.texture_id))

	for layer in active:
		if layer.texture_id >= texture_count:
			_warn_once("texture_%d" % layer.texture_id, "TerrainLayerMasks: layer uses texture %d, but Terrain3D has only %d textures; skipped." % [layer.texture_id, texture_count])
			continue
		if layer_count >= MAX_LAYERS:
			_warn_once("layers", "TerrainLayerMasks: more than %d layers; the rest are ignored." % MAX_LAYERS)
			break
		var first := mask_count
		for mask in layer.masks:
			if mask == null or not mask.enabled:
				continue
			if mask_count >= MAX_MASKS:
				_warn_once("masks", "TerrainLayerMasks: more than %d masks in total; the rest are ignored." % MAX_MASKS)
				break
			var type := mask.get_mask_type()
			var b := Vector4.ZERO
			var c := Vector4.ZERO
			var inv := float(mask.invert)
			if mask is TerrainHeightMask:
				var hm := mask as TerrainHeightMask
				var r := hm.resolve_range(sea, height_range)
				b = Vector4(r.x, r.y, hm.outside_range, inv)
			elif mask is TerrainSlopeMask:
				var sm := mask as TerrainSlopeMask
				b = Vector4(sm.min_slope, sm.max_slope, sm.outside_range, inv)
			elif mask is TerrainNoiseMask:
				var nm := mask as TerrainNoiseMask
				b = Vector4(noise_images.size(), float(nm.billow), 0.0, inv)
				noise_images.append(_noise_image(nm))
				var tile := nm.tile_size
				if nm.scale_with_terrain:
					tile = nm.terrain_scale * _terrain_width(t)
				c = Vector4(1.0 / maxf(tile, 0.01), deg_to_rad(nm.rotation_degrees), nm.offset.x, nm.offset.y)
			elif mask is TerrainTextureMask:
				var tm := mask as TerrainTextureMask
				b = Vector4(tm.texture_id, tm.start_at, 0.0, inv)
			elif mask is TerrainAutoSlopeMask:
				var am := mask as TerrainAutoSlopeMask
				var slope := am.auto_slope
				var reduction := am.height_reduction
				if am.use_material_settings:
					var rid := _get_material_rid()
					var v = RenderingServer.material_get_param(rid, "auto_slope")
					if v != null:
						slope = float(v)
					v = RenderingServer.material_get_param(rid, "auto_height_reduction")
					if v != null:
						reduction = float(v)
				b = Vector4(slope, reduction, 0.0, inv)
			else:
				continue
			mask_a[mask_count] = Vector4(type, mask.blend_mode, _curve_row(curves, mask.get_mask_curve()), _curve_row(curves, mask.strength_transform))
			mask_b[mask_count] = b
			mask_c[mask_count] = c
			mask_count += 1
		layers[layer_count] = Vector4(layer.texture_id, layer.opacity, first, mask_count - first)
		layer_count += 1

	# Kept on the node: the material only holds the texture RIDs.
	_curve_texture_ref = _curve_texture(curves)
	_noise_texture_ref = _noise_array(noise_images)
	_last_noise_images = noise_images
	return {
		"_tlm_layer_count": layer_count,
		"_tlm_texture_sharpness": _texture_sharpness(),
		"_tlm_layers": layers,
		"_tlm_mask_a": mask_a,
		"_tlm_mask_b": mask_b,
		"_tlm_mask_c": mask_c,
		"_tlm_curve_rows": float(maxi(curves.size(), 1)),
		"_tlm_curves": _curve_texture_ref,
		"_tlm_noise": _noise_texture_ref,
	}


## Per texture id: layer Blend Sharpness + 1, or 0 for "use the material's". All layers count
## (also disabled ones), so hand-painted textures get their edge sharpness too.
func _texture_sharpness() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(32)
	for layer in stack.layers:
		if layer and layer.blend_sharpness >= 0.0 and layer.texture_id < 32:
			out[layer.texture_id] = layer.blend_sharpness + 1.0
	return out


func _curve_row(curves: Array[Curve], curve: Curve) -> float:
	if curve == null:
		return -1.0
	var idx := curves.find(curve)
	if idx < 0:
		idx = curves.size()
		curves.append(curve)
	return float(idx)


func _curve_texture(curves: Array[Curve]) -> ImageTexture:
	var img := Image.create_empty(CURVE_WIDTH, maxi(curves.size(), 1), false, Image.FORMAT_RF)
	for row in curves.size():
		var curve := curves[row]
		curve.bake()
		for x in CURVE_WIDTH:
			var at := lerpf(curve.min_domain, curve.max_domain, float(x) / float(CURVE_WIDTH - 1))
			img.set_pixel(x, row, Color(curve.sample_baked(at), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _noise_image(mask: TerrainNoiseMask) -> Image:
	var key := mask.get_instance_id()
	var sig := mask.noise_signature(noise_resolution)
	if _noise_cache.has(key) and _noise_cache[key][0] == sig:
		return _noise_cache[key][1]
	var img: Image
	if mask.noise:
		img = mask.noise.get_seamless_image(noise_resolution, noise_resolution, false, false, 0.1, true)
	else:
		img = Image.create_empty(noise_resolution, noise_resolution, false, Image.FORMAT_L8)
		img.fill(Color(0.5, 0.5, 0.5))
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	_noise_cache[key] = [sig, img]
	return img


func _noise_array(images: Array[Image]) -> Texture2DArray:
	if images.is_empty():
		var blank := Image.create_empty(4, 4, false, Image.FORMAT_L8)
		blank.generate_mipmaps()
		images = [blank]
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr


func _terrain_width(t) -> float:
	if t.data == null:
		return 1024.0
	var locs: Array = t.data.get_region_locations()
	if locs.is_empty():
		return float(t.region_size) * t.vertex_spacing
	var lo: Vector2i = locs[0]
	var hi: Vector2i = locs[0]
	for l: Vector2i in locs:
		lo = Vector2i(mini(lo.x, l.x), mini(lo.y, l.y))
		hi = Vector2i(maxi(hi.x, l.x), maxi(hi.y, l.y))
	var regions := maxi(hi.x - lo.x, hi.y - lo.y) + 1
	return float(regions * t.region_size) * t.vertex_spacing


func _update_texture_names(t) -> void:
	_names_dirty = false
	var names := PackedStringArray()
	if t.assets:
		for i in t.assets.get_texture_count():
			var asset = t.assets.get_texture_asset(i)
			names.append(asset.name if asset else "Texture %d" % i)
	# Terrain3D empties its texture list in a running game; names are only needed in the editor.
	if names.is_empty():
		return
	TerrainMask.texture_names = names
	if stack == null:
		return
	_sync_stack(names.size())
	for layer in stack.layers:
		if layer == null:
			continue
		var label: String = names[layer.texture_id] if layer.texture_id < names.size() else "Missing texture %d" % layer.texture_id
		if layer.resource_name != label:
			layer.resource_name = label
		layer.notify_property_list_changed()
		for mask in layer.masks:
			if mask:
				mask.notify_property_list_changed()


## Changes when the terrain's shader is swapped or rebuilt (its uniforms then need re-sending).
func _shader_key() -> String:
	var t = get_terrain()
	if t == null or t.material == null:
		return ""
	var mat = t.material
	var sh: Shader = mat.shader_override if mat.shader_override_enabled else null
	return "%s|%d|%d" % [str(mat.get_shader_rid()), sh.get_instance_id() if sh else 0, sh.code.hash() if sh else 0]


func _get_material_rid() -> RID:
	var t = get_terrain()
	if t and t.material:
		return t.material.get_material_rid()
	return RID()


func _connect_terrain(t) -> void:
	if _connected_terrain == t:
		return
	_disconnect_terrain()
	_connected_terrain = t
	if t.assets and t.assets.has_signal("textures_changed"):
		t.assets.textures_changed.connect(_on_textures_changed)
	if t.data and t.data.has_signal("height_maps_changed"):
		t.data.height_maps_changed.connect(_queue_update)
	if t.material:
		t.material.changed.connect(_on_material_changed)
	if Engine.is_editor_hint() and auto_rebuild_shader and shader_out_of_date():
		rebuild_shader.call_deferred()


func _disconnect_terrain() -> void:
	var t = _connected_terrain
	_connected_terrain = null
	if not is_instance_valid(t):
		return
	if t.assets and t.assets.has_signal("textures_changed") and t.assets.textures_changed.is_connected(_on_textures_changed):
		t.assets.textures_changed.disconnect(_on_textures_changed)
	if t.data and t.data.has_signal("height_maps_changed") and t.data.height_maps_changed.is_connected(_queue_update):
		t.data.height_maps_changed.disconnect(_queue_update)
	if t.material and t.material.changed.is_connected(_on_material_changed):
		t.material.changed.disconnect(_on_material_changed)


func _on_textures_changed() -> void:
	_names_dirty = true
	_queue_update()


func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(message)


## True when the material uses (or should use) the layer shader and it doesn't match the material's options.
func shader_out_of_date() -> bool:
	var t = get_terrain()
	return t != null and TerrainLayerShaderBuilder.is_out_of_date(t.material)


## Regenerates the layer shader from Terrain3D's own shader with the material's current options
## (see TerrainLayerShaderBuilder).
func rebuild_shader() -> void:
	var t = get_terrain()
	if _rebuilding or t == null or t.material == null:
		return
	_rebuilding = true
	var mat = t.material
	var code: String = await TerrainLayerShaderBuilder.generate_terrain3d_code(self, mat)
	var merged := TerrainLayerShaderBuilder.merge(code, TerrainLayerShaderBuilder.material_features(mat))
	if not merged.is_empty():
		var err := TerrainLayerShaderBuilder.save_and_assign(mat, merged)
		if err != OK:
			push_error("TerrainLayerMasks: could not save %s (error %d)." % [SHADER_PATH, err])
		else:
			print("TerrainLayerMasks: rebuilt %s from Terrain3D's shader." % SHADER_PATH)
	_rebuilding = false
	update_configuration_warnings()
	_queue_update()

func _on_material_changed() -> void:
	_queue_update()
	if Engine.is_editor_hint() and auto_rebuild_shader and not _rebuilding and shader_out_of_date():
		rebuild_shader.call_deferred()


func _validate_property(property: Dictionary) -> void:
	if property.name == "sea_level_node" and sea_level_source != SeaLevelSource.NODE:
		property.usage = PROPERTY_USAGE_STORAGE


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var t = get_terrain()
	if t == null:
		warnings.append("Put this node under a Terrain3D node, or assign Terrain.")
		return warnings
	var mat = t.material
	if mat == null:
		warnings.append("Terrain3D has no material.")
		return warnings
	if not mat.shader_override_enabled or mat.shader_override == null:
		warnings.append("The Terrain3D material needs the layer shader: press Rebuild Shader.")
	elif not mat.shader_override.code.contains("tlm_control"):
		warnings.append("The material's Shader Override isn't the layer shader: press Rebuild Shader (writes %s)." % SHADER_PATH)
	elif shader_out_of_date():
		warnings.append("Terrain3D material shader options changed since the layer shader was built: press Rebuild Shader.")
	if not mat.auto_shader_enabled:
		warnings.append("Turn on Auto Shader in the Terrain3D material; the layers replace it.")
	if stack:
		var lowest: TerrainMaskLayer = null
		for l in stack.layers:
			if l and l.enabled and (lowest == null or l.paint_order < lowest.paint_order \
					or (l.paint_order == lowest.paint_order and l.texture_id < lowest.texture_id)):
				lowest = l
		if lowest and not lowest.masks.is_empty():
			warnings.append("Layer %d has the lowest Paint Order, so it fills whatever the other layers leave: its masks and Opacity have no effect." % lowest.texture_id)
	if stack == null:
		warnings.append("Assign a Layer Stack (or create a New TerrainLayerStack; it fills with your Terrain3D textures).")
	return warnings