@tool
## Generates Terrain3D heights from a base noise and optional shape children (Mountain, Valley, Mesa,
## Island, Lake, Flatten, Erosion, ...).
## Add as a child of Terrain3D and press Generate. Move the node and generate again to build the
## world piece by piece: Edge Falloff blends each piece into what's around it. Whatever you sculpt
## by hand stays on top (Keep Hand Sculpting). Ctrl+Z undoes a Generate.
##
## @tutorial(Full Guide): res://addons/terrain_layers_generator/docs/terrain_generator.md
class_name TerrainGenerator
extends Node3D


enum Scope {
	## Meters rectangle centred on this node (Area Size). Regions under it are added if missing.
	## Best for placing shapes: keep the shape footprint inside the yellow Area.
	AREA,
	## Every region the terrain already has. Can be slow on large worlds.
	ALL_REGIONS,
	## Only the grid cells in Regions (rx, rz — not world meters). Fill with Add Regions From Area
	## or Add Selected Node's Region. Shapes still need to sit over those cells to change them.
	LISTED_REGIONS,
}
enum Combine {
	## New heights replace what earlier Generates made here.
	REPLACE,
	## New heights are added on top of what earlier Generates made here.
	ADD,
}
enum NoiseStyle {
	## Smooth hills.
	ROLLING_HILLS,
	## Sharp crests and ridge lines.
	RIDGED_MOUNTAINS,
	## Round bumps with creases between them.
	BILLOWY,
}

const CURVE_SAMPLES := 256
const MANY_REGIONS := 64

## The Terrain3D to generate. Empty = the parent.
@export var terrain: Node:
	set(value):
		terrain = value
		update_configuration_warnings()

## Where Generate runs. Area: a meters rectangle centred on this node (regions added where
## missing). All Regions: every region the terrain already has. Listed Regions: only the grid
## cells in Regions — those are Terrain3D region indices (rx, rz), not world X/Z meters.
@export var scope: Scope = Scope.AREA:
	set(value):
		scope = value
		notify_property_list_changed()

## Width (X) and depth (Z) of the area in meters, centred on this node. Only ground inside it
## changes (Edge Falloff blends from its edge inwards).
@export var area_size := Vector2(1024, 1024)

## Terrain3D region grid cells (rx, rz) for Scope = Listed Regions. One step = one region (often
## 256 m). Prefer Add Regions From Area or Add Selected Node's Region instead of typing these.
@export var regions: Array[Vector2i] = []

## Changes the whole pattern. The same seed and settings always give the same terrain.
@export var world_seed := 0

## Replace: the new heights replace what earlier Generates made here. Add: they're added on top
## (e.g. Billowy bumps over Ridged Mountains).
@export var combine: Combine = Combine.REPLACE

## On: everything the generator didn't make stays on top: your hand sculpting, and terrain that
## was there before the first Generate. Off: that is replaced too (fresh generated ground).
@export var keep_hand_sculpting := true

## What the generator has made so far (used by Keep Hand Sculpting and Remove Generated Heights).
## Created next to the Terrain3D data (terrain_generator.res) on the first Generate.
@export var generator_data: TerrainGeneratorData

## Meters added everywhere (e.g. -20 to start below sea level). With Combine = Add it lifts the
## whole Area before the noise and shapes are added.
@export_range(-1000.0, 1000.0, 0.1, "or_greater", "or_less", "suffix:m") var base_height := 0.0

## Blends the new terrain into what's around it over this many meters, from the edge of the Area
## (or the scope's regions) inwards: into neighbouring terrain, or down to height 0 (the flat World
## Background at Terrain3D's default Ground Level) where there's none. 0 = a hard edge.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:m") var edge_falloff := 200.0

@export_group("Base Noise", "noise_")
## Off: flat ground at Base Height.
@export var noise_enabled := true
## Rolling Hills: smooth hills. Ridged Mountains: sharp crests and ridge lines. Billowy: round
## bumps with creases between them.
@export var noise_style: NoiseStyle = NoiseStyle.ROLLING_HILLS
## The noise pattern (Godot FastNoiseLite). Simplex Smooth and Perlin suit terrain best.
@export var noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
## About how far it is from the lowest valley to the highest top, in meters.
@export_range(0.0, 2000.0, 0.1, "or_greater", "suffix:m") var noise_height := 80.0
## About how wide one hill is, in meters.
@export_range(10.0, 8000.0, 1.0, "or_greater", "suffix:m") var noise_size := 500.0
## Layers of smaller detail on top of the big shapes (noise octaves).
@export_range(1, 10) var noise_detail := 5
## How strong each smaller detail layer is (0.5 = half as tall as the one before). Higher = rougher.
@export_range(0.0, 1.0, 0.01) var noise_roughness := 0.5
## Bends the pattern sideways by up to this many meters: twistier, less regular shapes.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:m") var noise_warp := 0.0
## Slides the pattern, in meters.
@export var noise_offset := Vector2.ZERO
## Remaps the noise (left = lowest, right = highest) before Height. Empty = unchanged.
## E.g. Ease In: wide flat lowlands with steeper hills; Ease Out: wide high plateaus.
@export var noise_curve: Curve
@export_group("")

## Rebuilds the Area from base noise + every enabled shape. To carve/add one shape onto what you
## already see, press Generate on that shape instead.
@export_tool_button("Generate", "Reload") var generate_button := generate
## Takes the generated heights back out (all Generates, blended with Edge Falloff), leaving
## your hand sculpting and the terrain that was there before.
@export_tool_button("Remove Generated Heights", "Remove") var remove_button := remove_generated
@export_tool_button("Randomize Seed", "RandomNumberGenerator") var randomize_button := randomize_seed
## Copies every region the yellow Area overlaps into Regions and switches Scope to Listed
## Regions. Frame the patch with Area Size first, then press this (easiest way to fill Listed).
@export_tool_button("Add Regions From Area", "ActionCopy") var add_from_area_button := add_regions_from_area
## Adds the region under a Node3D selected in the Scene dock to Regions (and switches to Listed).
## Select the marker/player in the region, then select this TerrainGenerator, then press this.
@export_tool_button("Add Selected Node's Region", "Add") var add_region_button := add_selected_region


func documentation_file() -> String:
	return "terrain_generator.md"


var _busy := false
var _jobs: Array[RegionJob] = []
var _erosion_job: TerrainGeneratorErosion.Job
var _outline: MeshInstance3D
var _outline_key := ""


## Everything a worker thread needs for one region (no node access from threads).
class RegionJob extends RefCounted:
	var location := Vector2i.ZERO
	var size := 0
	var spacing := 1.0
	var origin := Vector2.ZERO
	var current := PackedFloat32Array()
	var previous := PackedFloat32Array() # generated so far (NaN = never); may be empty
	var is_new := false
	var remove := false
	var keep_hand_sculpting := true
	var replace := true
	var base_height := 0.0
	var edge_falloff := 0.0
	var use_rect := false
	var rect := Rect2()
	var edges: Array[Rect2] = [] # regions outside the scope to blend towards
	var noise: FastNoiseLite # null = no noise
	var noise_style := 0
	var noise_height := 0.0
	var warp: FastNoiseLite # null = no warp
	var warp_amount := 0.0
	var noise_curve := PackedFloat32Array() # empty = linear
	var shapes: Array = [] # Array[TerrainGeneratorShapeData]
	var shape_only := false # true: apply shapes as a delta onto current terrain (no base noise rebuild)
	var result := PackedFloat32Array()
	var generated := PackedFloat32Array()
	var rows_done := 0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_outline()


func get_terrain():
	if terrain:
		return terrain
	var p := get_parent()
	return p if Terrain3DBridge.is_terrain(p) else null


func generate() -> void:
	await _run(false)


## Applies one shape (or a list) onto the current terrain without rebuilding base noise or other
## shapes. Used by each shape's Generate button.
func generate_shape(shape: TerrainGeneratorShape) -> void:
	await _run(false, shape)


## Thermal (+ optional light flow) post-pass over existing heights in the Scope / Area.
## Called by TerrainGeneratorErosion.Generate — not by a full Generate.
func apply_erosion(erosion: TerrainGeneratorErosion) -> void:
	if _busy:
		push_warning("TerrainGenerator: still working on the last job; that press was ignored.")
		return
	var t = get_terrain()
	if t == null or t.get("data") == null:
		push_warning("TerrainGenerator: put this node under a Terrain3D (or assign Terrain).")
		return
	if erosion == null or not erosion.enabled:
		push_warning("TerrainGenerator: erosion is disabled or missing.")
		return
	var locations := get_target_locations()
	locations = locations.filter(func(l): return Terrain3DBridge.has_region(t, l))
	if locations.is_empty():
		push_warning("TerrainGenerator: no existing regions to erode. Generate ground first.")
		return
	if locations.size() > MANY_REGIONS:
		push_warning("TerrainGenerator: %d regions to erode — this can take a while." % locations.size())

	_busy = true
	_ensure_data(t)
	var started := Time.get_ticks_msec()
	_notify("TerrainGenerator: applying %s to %d region(s)..." % [erosion.name, locations.size()])

	var size := Terrain3DBridge.region_size(t)
	var spacing := Terrain3DBridge.vertex_spacing(t)
	var min_l := locations[0]
	var max_l := locations[0]
	for loc in locations:
		min_l = Vector2i(mini(min_l.x, loc.x), mini(min_l.y, loc.y))
		max_l = Vector2i(maxi(max_l.x, loc.x), maxi(max_l.y, loc.y))
	var halo_min := Vector2i(
		maxi(min_l.x - 1, Terrain3DBridge.REGION_MIN),
		maxi(min_l.y - 1, Terrain3DBridge.REGION_MIN))
	var halo_max := Vector2i(
		mini(max_l.x + 1, Terrain3DBridge.REGION_MAX),
		mini(max_l.y + 1, Terrain3DBridge.REGION_MAX))
	var gw := (halo_max.x - halo_min.x + 1) * size
	var gh := (halo_max.y - halo_min.y + 1) * size
	var cell_count := gw * gh
	if cell_count > 512 * 512:
		_notify("TerrainGenerator: erosion grid is %d×%d (%d cells) — expect heavier CPU." % [gw, gh, cell_count])

	var scope_set := {}
	for loc in locations:
		scope_set[loc] = true

	var job := erosion.make_job()
	job.width = gw
	job.height = gh
	job.spacing = spacing
	job.heights.resize(cell_count)
	job.writable.resize(cell_count)
	for rz in range(halo_min.y, halo_max.y + 1):
		for rx in range(halo_min.x, halo_max.x + 1):
			var loc := Vector2i(rx, rz)
			var in_scope: bool = scope_set.has(loc)
			var has := Terrain3DBridge.has_region(t, loc)
			var map_data := PackedFloat32Array()
			if has:
				map_data = Terrain3DBridge.get_map(t, loc, Terrain3DBridge.MAP_HEIGHT).get_data().to_float32_array()
			var ox := (rx - halo_min.x) * size
			var oz := (rz - halo_min.y) * size
			for y in size:
				for x in size:
					var gi := (oz + y) * gw + (ox + x)
					job.heights[gi] = map_data[y * size + x] if has else 0.0
					job.writable[gi] = 1 if in_scope else 0

	_erosion_job = job
	var task := WorkerThreadPool.add_task(_run_erosion_task, true, "TerrainGeneratorErosion")
	var next_report := Time.get_ticks_msec() + 1000
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
		if Time.get_ticks_msec() >= next_report:
			next_report += 1000
			print("TerrainGenerator: erosion %d%%" % int(100.0 * float(job.iterations_done) / float(maxi(job.iterations, 1))))
	WorkerThreadPool.wait_for_task_completion(task)

	var eroded := job.result
	var region_m := size * spacing
	var ring := ceili(edge_falloff / region_m) if edge_falloff > 0.0 and scope != Scope.AREA else 0
	var changes := []
	var new_locations: Array[Vector2i] = []
	for loc in locations:
		var current := Terrain3DBridge.get_map(t, loc, Terrain3DBridge.MAP_HEIGHT).get_data().to_float32_array()
		var previous := generator_data.get_region(loc) if generator_data else PackedFloat32Array()
		var has_previous := previous.size() == size * size
		var out := PackedFloat32Array()
		out.resize(size * size)
		var gen_map := PackedFloat32Array()
		gen_map.resize(size * size)
		var ox := (loc.x - halo_min.x) * size
		var oz := (loc.y - halo_min.y) * size
		var region_origin := Terrain3DBridge.region_origin(t, loc)
		var wjob := RegionJob.new()
		wjob.size = size
		wjob.spacing = spacing
		wjob.origin = region_origin
		wjob.edge_falloff = edge_falloff
		wjob.use_rect = scope == Scope.AREA
		wjob.rect = get_area_rect()
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var n := loc + Vector2i(dx, dy)
				if not n in locations and Terrain3DBridge.has_region(t, n):
					wjob.edges.append(Rect2(Terrain3DBridge.region_origin(t, n), Vector2(region_m, region_m)))
		var any_generated := false
		for y in size:
			var z := region_origin.y + y * spacing
			for x in size:
				var i := y * size + x
				var gi := (oz + y) * gw + (ox + x)
				var cur := current[i]
				var c_old := previous[i] if has_previous else NAN
				var c0 := 0.0 if is_nan(c_old) else c_old
				var wx := region_origin.x + x * spacing
				var w := _weight(wjob, wx, z)
				var delta := eroded[gi] - cur
				if w <= 0.0:
					out[i] = cur
					gen_map[i] = c_old
				else:
					out[i] = cur + w * delta
					gen_map[i] = (c0 + w * delta) if (not is_nan(c_old) or absf(delta) > 0.0001) else c_old
				if not any_generated and not is_nan(gen_map[i]):
					any_generated = true
		changes.append([loc, out, gen_map if any_generated else PackedFloat32Array(), current, previous, false])

	var max_delta := 0.0
	for c in changes:
		var before: PackedFloat32Array = c[3]
		var after: PackedFloat32Array = c[1]
		for i in mini(before.size(), after.size()):
			max_delta = maxf(max_delta, absf(after[i] - before[i]))
	_apply_changes(t, changes, new_locations, "Apply %s" % erosion.name)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	_notify("TerrainGenerator: applied %s to %d region(s) in %.1f s (max height change %.2f m)." % [
		erosion.name, locations.size(), seconds, max_delta])
	if max_delta < 0.05:
		push_warning("TerrainGenerator: erosion barely changed heights. Lower Talus (e.g. 0.3) or raise Thermal Strength / Iterations.")
	_erosion_job = null
	_busy = false


func _run_erosion_task() -> void:
	if _erosion_job:
		TerrainGeneratorErosion.run_job(_erosion_job)


func remove_generated() -> void:
	await _run(true)


func randomize_seed() -> void:
	world_seed = randi() % 1000000
	notify_property_list_changed()


func add_regions_from_area() -> void:
	var t = get_terrain()
	if t == null:
		push_warning("TerrainGenerator: put this node under a Terrain3D (or assign Terrain).")
		return
	var added := 0
	for loc in get_area_region_locations():
		if not loc in regions:
			regions.append(loc)
			added += 1
	scope = Scope.LISTED_REGIONS
	notify_property_list_changed()
	print("TerrainGenerator: Add Regions From Area — added %d cell(s), Regions now has %d." % [
		added, regions.size()
	])


func add_selected_region() -> void:
	var t = get_terrain()
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if t == null or editor == null:
		return
	for n in editor.get_selection().get_selected_nodes():
		if n is Node3D:
			var loc := Terrain3DBridge.region_location_at(t, n.global_position)
			if Terrain3DBridge.is_valid_location(loc) and not loc in regions:
				regions.append(loc)
				print("TerrainGenerator: added region %s." % loc)
	scope = Scope.LISTED_REGIONS
	notify_property_list_changed()


## World XZ rectangle of the Area (Scope = Area).
func get_area_rect() -> Rect2:
	var half := area_size.abs() * 0.5
	return Rect2(Vector2(global_position.x, global_position.z) - half, half * 2.0)


## Region grid cells overlapped by the current Area rectangle (same math as Scope = Area).
func get_area_region_locations() -> Array[Vector2i]:
	var t = get_terrain()
	var out: Array[Vector2i] = []
	if t == null:
		return out
	var rs := Terrain3DBridge.region_size(t) * Terrain3DBridge.vertex_spacing(t)
	if rs <= 0.0:
		return out
	var r := get_area_rect()
	var lo := Vector2i(floori(r.position.x / rs), floori(r.position.y / rs))
	var hi := Vector2i(ceili(r.end.x / rs) - 1, ceili(r.end.y / rs) - 1)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var loc := Vector2i(x, y)
			if Terrain3DBridge.is_valid_location(loc):
				out.append(loc)
	return out


## True if the shape's footprint overlaps any of the given region cells in world XZ.
func _shape_overlaps_locations(t, shape: TerrainGeneratorShape, locations: Array[Vector2i]) -> bool:
	var foot := shape.get_footprint_rect()
	if foot.size == Vector2.ZERO:
		return true # Unknown footprint — let Generate run.
	var rs := Terrain3DBridge.region_size(t) * Terrain3DBridge.vertex_spacing(t)
	for loc in locations:
		var cell := Rect2(Terrain3DBridge.region_origin(t, loc), Vector2(rs, rs))
		if foot.intersects(cell):
			return true
	return false


## The region locations Generate would touch (existing or not).
func get_target_locations() -> Array[Vector2i]:
	var t = get_terrain()
	var out: Array[Vector2i] = []
	if t == null:
		return out
	match scope:
		Scope.ALL_REGIONS:
			out = Terrain3DBridge.region_locations(t)
		Scope.LISTED_REGIONS:
			for loc in regions:
				if Terrain3DBridge.is_valid_location(loc) and not loc in out:
					out.append(loc)
		Scope.AREA:
			out = get_area_region_locations()
	return out


func _run(remove: bool, only_shape: TerrainGeneratorShape = null) -> void:
	if _busy:
		push_warning("TerrainGenerator: still working on the last %s; that press was ignored." % ("Remove" if remove else "Generate"))
		return
	var t = get_terrain()
	if t == null or t.get("data") == null:
		push_warning("TerrainGenerator: put this node under a Terrain3D (or assign Terrain).")
		return
	if only_shape and (not only_shape.enabled or only_shape.snapshot() == null):
		push_warning("TerrainGenerator: that shape is disabled or has nothing to apply.")
		return
	var locations := get_target_locations()
	var new_locations: Array[Vector2i] = []
	if remove:
		locations = locations.filter(func(l): return Terrain3DBridge.has_region(t, l))
	else:
		for loc in locations:
			if not Terrain3DBridge.has_region(t, loc):
				new_locations.append(loc)
	if locations.is_empty():
		push_warning("TerrainGenerator: no regions in the scope.")
		return
	if only_shape and not _shape_overlaps_locations(t, only_shape, locations):
		push_warning(
			"TerrainGenerator: %s's footprint does not overlap the current Scope regions — nothing will change. Move the shape's Transform position (X and Z) so that it is over those regions, or switch Scope to Area and cover the shape with the yellow rectangle."
			% only_shape.name
		)
		return
	if locations.size() > MANY_REGIONS:
		push_warning("TerrainGenerator: %d regions, this can take a while." % locations.size())
	_busy = true
	_ensure_data(t)
	var started := Time.get_ticks_msec()
	var label := "removing generated heights from"
	if not remove:
		label = ("applying %s to" % only_shape.name) if only_shape else "generating"
	_notify("TerrainGenerator: %s %d region(s)..." % [label, locations.size()])
	_jobs = _prepare_jobs(t, locations, remove, only_shape)

	var task := WorkerThreadPool.add_group_task(_run_job, _jobs.size(), -1, true, "TerrainGenerator")
	var next_report := Time.get_ticks_msec() + 1000
	while not WorkerThreadPool.is_group_task_completed(task):
		await get_tree().process_frame
		if Time.get_ticks_msec() >= next_report:
			next_report += 1000
			var rows := 0
			var total := 0
			for j in _jobs:
				rows += j.rows_done
				total += j.size
			print("TerrainGenerator: %d%%" % int(100.0 * rows / maxi(total, 1)))
	WorkerThreadPool.wait_for_group_task_completion(task)

	var changes := []
	for j in _jobs:
		changes.append([j.location, j.result, j.generated, j.current, j.previous, j.is_new])
	var action := "Remove generated terrain heights"
	if not remove:
		action = ("Apply %s" % only_shape.name) if only_shape else "Generate terrain"
	_apply_changes(t, changes, new_locations, action)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if remove:
		_notify("TerrainGenerator: removed generated heights from %d region(s) in %.1f s." % [_jobs.size(), seconds])
	elif only_shape:
		_notify("TerrainGenerator: applied %s to %d region(s) in %.1f s." % [only_shape.name, _jobs.size(), seconds])
	else:
		_notify("TerrainGenerator: generated %d region(s) (%d new) in %.1f s." % [_jobs.size(), new_locations.size(), seconds])
	_jobs.clear()
	_busy = false


## Output panel, plus a pop-up in the editor's bottom-right corner.
func _notify(message: String) -> void:
	print(message)
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if editor and editor.has_method(&"get_editor_toaster"):
		editor.get_editor_toaster().push_toast(message)


func get_shapes() -> Array[TerrainGeneratorShape]:
	var out: Array[TerrainGeneratorShape] = []
	for c in get_children():
		if c is TerrainGeneratorShape:
			out.append(c)
	return out


func _prepare_jobs(t, locations: Array[Vector2i], remove: bool, only_shape: TerrainGeneratorShape = null) -> Array[RegionJob]:
	var jobs: Array[RegionJob] = []
	var size := Terrain3DBridge.region_size(t)
	var spacing := Terrain3DBridge.vertex_spacing(t)
	var curve := _curve_samples(noise_curve)
	var region_m := size * spacing
	var ring := ceili(edge_falloff / region_m) if edge_falloff > 0.0 and scope != Scope.AREA else 0
	var shapes: Array = []
	var shape_only := only_shape != null and not remove
	if not remove:
		if only_shape:
			var data := only_shape.snapshot()
			if data:
				shapes.append(data)
		else:
			for shape in get_shapes():
				var data := shape.snapshot()
				if data:
					shapes.append(data)
	for loc in locations:
		var job := RegionJob.new()
		job.location = loc
		job.size = size
		job.spacing = spacing
		job.origin = Terrain3DBridge.region_origin(t, loc)
		job.is_new = not Terrain3DBridge.has_region(t, loc)
		if job.is_new:
			job.current.resize(size * size)
		else:
			job.current = Terrain3DBridge.get_map(t, loc, Terrain3DBridge.MAP_HEIGHT).get_data().to_float32_array()
		job.previous = generator_data.get_region(loc) if generator_data else PackedFloat32Array()
		job.remove = remove
		job.keep_hand_sculpting = keep_hand_sculpting
		job.replace = combine == Combine.REPLACE
		job.shape_only = shape_only
		job.base_height = base_height
		job.edge_falloff = edge_falloff
		job.use_rect = scope == Scope.AREA
		job.rect = get_area_rect()
		# Blend towards regions outside the scope: existing terrain, and (when generating) empty space.
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var n := loc + Vector2i(dx, dy)
				if not n in locations and (not remove or Terrain3DBridge.has_region(t, n)):
					job.edges.append(Rect2(Terrain3DBridge.region_origin(t, n), Vector2(region_m, region_m)))
		# Shape-only: leave base noise off so we only apply the shape delta onto current heights.
		if not shape_only and noise_enabled:
			job.noise = _make_noise()
			if noise_warp > 0.0:
				job.warp = FastNoiseLite.new()
				job.warp.seed = world_seed + 1
				job.warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
				job.warp.frequency = 1.0 / maxf(noise_size, 0.01)
				job.warp.fractal_octaves = 2
				job.warp_amount = noise_warp
		job.noise_style = noise_style
		job.noise_height = noise_height
		job.noise_curve = curve
		job.shapes = shapes
		jobs.append(job)
	return jobs


## One FastNoiseLite per job: worker threads never share one.
func _make_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = world_seed
	n.noise_type = noise_type
	n.frequency = 1.0 / maxf(noise_size, 0.01)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if noise_style == NoiseStyle.RIDGED_MOUNTAINS else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = noise_detail
	n.fractal_gain = noise_roughness
	n.fractal_lacunarity = 2.0
	n.offset = Vector3(noise_offset.x, noise_offset.y, 0.0)
	return n


static func _curve_samples(curve: Curve) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if curve == null or curve.point_count == 0:
		return out
	out.resize(CURVE_SAMPLES)
	for i in CURVE_SAMPLES:
		out[i] = curve.sample(float(i) / (CURVE_SAMPLES - 1))
	return out


static func _sample(samples: PackedFloat32Array, x: float) -> float:
	if samples.is_empty():
		return x
	var f := clampf(x, 0.0, 1.0) * (CURVE_SAMPLES - 1)
	var i := mini(int(f), CURVE_SAMPLES - 2)
	return lerpf(samples[i], samples[i + 1], f - i)


## Generated height at a world XZ position (worker thread).
## The noise rarely reaches its extremes, so each style is stretched to make Height roughly the
## lowest-to-highest difference over a few km. Shapes are applied after, in Scene dock order.
static func _height(job: RegionJob, x: float, z: float) -> float:
	var h := 0.0
	if job.noise:
		var nx := x
		var nz := z
		if job.warp:
			nx += job.warp.get_noise_2d(x, z) * job.warp_amount * 1.5
			nz += job.warp.get_noise_2d(x + 5291.7, z - 7423.3) * job.warp_amount * 1.5
		var n := job.noise.get_noise_2d(nx, nz)
		var v: float
		match job.noise_style:
			NoiseStyle.BILLOWY:
				v = absf(n) * 1.5
			NoiseStyle.RIDGED_MOUNTAINS:
				v = (n * 0.5 + 0.5 - 0.3) / 0.7
			_:
				v = 0.5 + n * 0.75
		h = _sample(job.noise_curve, v) * job.noise_height
	h = job.base_height + h
	for shape in job.shapes:
		h = shape.apply(h, x, z)
	return h


## How much of the new result a vertex takes: 0 at the edge of the Area / scope (unchanged),
## rising smoothly to 1 at Edge Falloff meters inside.
static func _weight(job: RegionJob, x: float, z: float) -> float:
	var w := 1.0
	if job.use_rect:
		var r := job.rect
		if job.edge_falloff > 0.0:
			var inside := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
			if inside <= 0.0:
				return 0.0
			w = smoothstep(0.0, job.edge_falloff, inside)
		elif x < r.position.x or x >= r.end.x or z < r.position.y or z >= r.end.y:
			# Hard edge: start inclusive, end exclusive, so Areas that touch share no vertex and miss none.
			return 0.0
	if not job.edges.is_empty():
		var region_m := job.size * job.spacing
		var own := minf(minf(x - job.origin.x, job.origin.x + region_m - x), minf(z - job.origin.y, job.origin.y + region_m - z))
		if own < job.edge_falloff:
			var d := INF
			for r in job.edges:
				var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
				var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
				d = minf(d, sqrt(dx * dx + dz * dz))
			# The last vertex sits one spacing before the next region starts: make it exactly 0 there.
			w = minf(w, smoothstep(0.0, 1.0, (d - job.spacing) / maxf(job.edge_falloff - job.spacing, 0.001)))
	return w


## Worker thread: one region. The terrain is (what the generator made) + (everything else: hand
## sculpting and older terrain). generated keeps the first part per vertex (NaN = never generated).
func _run_job(index: int) -> void:
	var job := _jobs[index]
	var s := job.size
	var out := PackedFloat32Array()
	out.resize(s * s)
	var gen := PackedFloat32Array()
	gen.resize(s * s)
	var has_previous := job.previous.size() == s * s
	var any_generated := false
	for y in s:
		var z := job.origin.y + y * job.spacing
		for x in s:
			var i := y * s + x
			var cur := job.current[i]
			var c_old := job.previous[i] if has_previous else NAN
			var c0 := 0.0 if is_nan(c_old) else c_old
			var wx := job.origin.x + x * job.spacing
			var w := _weight(job, wx, z)
			if w <= 0.0:
				out[i] = cur
				gen[i] = c_old
			elif job.remove:
				out[i] = cur - w * c0
				gen[i] = NAN if is_nan(c_old) or w >= 1.0 else c0 * (1.0 - w)
			elif job.shape_only:
				# Apply blend modes against the terrain you see (Add stacks; Max raises to at least
				# the shape height; Subtract carves). Weight blends the change at Area edges.
				var shaped := cur
				for shape in job.shapes:
					shaped = shape.apply(shaped, wx, z)
				var delta := shaped - cur
				var c_new := c0 + w * delta
				out[i] = cur + w * delta
				gen[i] = c_new if not is_nan(c_old) or absf(delta) > 0.0001 else c_old
			else:
				var g := _height(job, wx, z)
				var c_new := lerpf(c0, g, w) if job.replace else c0 + w * g
				var rest := cur - c0
				if not job.keep_hand_sculpting:
					rest *= 1.0 - w
				out[i] = c_new + rest
				gen[i] = c_new
			if not any_generated and not is_nan(gen[i]):
				any_generated = true
		job.rows_done = y + 1
	job.result = out
	job.generated = gen if any_generated else PackedFloat32Array()


## changes: [location, new heights, new generated, old heights, old generated, is new region]
func _apply_changes(t, changes: Array, new_locations: Array[Vector2i], action_name: String) -> void:
	if changes.is_empty():
		return
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if editor:
		var ur = editor.get_editor_undo_redo()
		ur.create_action(action_name)
		for loc in new_locations:
			ur.add_do_method(self, &"_add_region", loc)
		for c in changes:
			ur.add_do_method(self, &"_apply_region", c[0], c[1], c[2])
			if not c[5]:
				ur.add_undo_method(self, &"_apply_region", c[0], c[3], c[4])
		ur.add_do_method(self, &"_finish_apply")
		for loc in new_locations:
			ur.add_undo_method(self, &"_remove_region", loc)
		ur.add_undo_method(self, &"_finish_apply")
		ur.commit_action()
	else:
		for loc in new_locations:
			_add_region(loc)
		for c in changes:
			_apply_region(c[0], c[1], c[2])
		_finish_apply()


func _add_region(location: Vector2i) -> void:
	var t = get_terrain()
	if t:
		Terrain3DBridge.add_region(t, location)


func _remove_region(location: Vector2i) -> void:
	var t = get_terrain()
	if t:
		Terrain3DBridge.remove_region(t, location)
	if generator_data:
		generator_data.set_region(location, PackedFloat32Array())


func _apply_region(location: Vector2i, heights: PackedFloat32Array, generated: PackedFloat32Array) -> void:
	var t = get_terrain()
	if t == null:
		return
	var s := Terrain3DBridge.region_size(t)
	Terrain3DBridge.set_map(t, location, Terrain3DBridge.MAP_HEIGHT, Image.create_from_data(s, s, false, Image.FORMAT_RF, heights.to_byte_array()))
	if generator_data:
		generator_data.set_region(location, generated)


func _finish_apply() -> void:
	var t = get_terrain()
	if t:
		Terrain3DBridge.refresh_heights(t)
	if generator_data and not generator_data.resource_path.is_empty():
		ResourceSaver.save(generator_data, generator_data.resource_path)


func _ensure_data(t) -> void:
	if generator_data:
		return
	var dir := Terrain3DBridge.data_directory(t)
	if dir.is_empty():
		generator_data = TerrainGeneratorData.new()
		return
	var path := dir.path_join("terrain_generator.res")
	if ResourceLoader.exists(path):
		generator_data = load(path)
	else:
		generator_data = TerrainGeneratorData.new()
		ResourceSaver.save(generator_data, path)
		generator_data = load(path)


## Editor only, while this node or a shape child is selected: the Area (yellow), where Edge Falloff
## reaches full strength (pale), the regions Generate touches (orange), and each shape's footprint.
func _update_outline() -> void:
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	var t = get_terrain()
	var selected: Array = editor.get_selection().get_selected_nodes() if editor else []
	var shown: bool = t != null and (self in selected or selected.any(func(n): return n is TerrainGeneratorShape and n.get_parent() == self))
	var shape_key := ""
	for shape in get_shapes():
		shape_key += "|%s:%s" % [shape.get_instance_id(), shape.outline_key()]
	var key := "%s|%s|%s|%s|%s|%s%s" % [shown, scope, area_size, global_position, regions, edge_falloff, shape_key] if shown else "hidden"
	if key == _outline_key:
		return
	_outline_key = key
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.top_level = true
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_outline.material_override = mat
		add_child(_outline, false, Node.INTERNAL_MODE_BACK)
	_outline.visible = shown
	if not shown:
		return
	_outline.global_transform = Transform3D.IDENTITY
	var locations := get_target_locations()
	var y := global_position.y
	var mesh := ImmediateMesh.new()
	var open := false
	var drew := false
	if not locations.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		open = true
		var rs := Terrain3DBridge.region_size(t) * Terrain3DBridge.vertex_spacing(t)
		for loc in locations:
			_add_rect_lines(mesh, Rect2(Terrain3DBridge.region_origin(t, loc), Vector2(rs, rs)), Color(1.0, 0.55, 0.1))
		if scope == Scope.AREA:
			var r := get_area_rect()
			_add_rect_lines(mesh, r, Color(1.0, 0.95, 0.2))
			if edge_falloff > 0.0 and r.size.x > edge_falloff * 2.0 and r.size.y > edge_falloff * 2.0:
				_add_rect_lines(mesh, r.grow(-edge_falloff), Color(1.0, 1.0, 0.75))
		drew = true
	for shape in get_shapes():
		if not shape.enabled or not shape.can_draw_outline():
			continue
		if not open:
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			open = true
		if shape.add_outline(mesh, y):
			drew = true
	if open and drew:
		mesh.surface_end()
		_outline.mesh = mesh
	else:
		# Empty Listed/All, or shapes that skip drawing — never surface_end with 0 vertices.
		_outline.mesh = null


func _add_rect_lines(mesh: ImmediateMesh, r: Rect2, color: Color) -> void:
	var y := global_position.y
	var c := [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)]
	mesh.surface_set_color(color)
	for i in 4:
		mesh.surface_add_vertex(c[i])
		mesh.surface_add_vertex(c[(i + 1) % 4])


func _validate_property(property: Dictionary) -> void:
	if property.name == "regions" and scope != Scope.LISTED_REGIONS:
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "area_size" and scope != Scope.AREA:
		property.usage = PROPERTY_USAGE_STORAGE


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var t = get_terrain()
	if t == null:
		w.append("Put this node under a Terrain3D (or assign Terrain).")
	elif Terrain3DBridge.data_directory(t).is_empty():
		w.append("The Terrain3D has no Data Directory: generated terrain (and what Keep Hand Sculpting remembers) can't be saved.")
	return w