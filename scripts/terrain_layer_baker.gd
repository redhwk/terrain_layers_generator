@tool
## Bakes the TerrainLayerMasks result into Terrain3D's control map (the same data the paint brush
## writes): no per-pixel layer cost for baked areas, and you can hand-paint on top afterwards.
## Add as a child of TerrainLayerMasks. Bake again after sculpting or changing layers.
## Areas outside regions (World Background) can't be baked and stay live.
class_name TerrainLayerBaker
extends Node


enum Scope { ALL_REGIONS, LISTED_REGIONS }

## Value stored in the bake data for vertices this bake left alone (never matches a real control).
const NOT_BAKED := 0xFFFFFFFF

## The TerrainLayerMasks to bake. Empty = the parent (or a sibling TerrainLayerMasks).
@export var layer_masks: TerrainLayerMasks:
	set(value):
		layer_masks = value
		update_configuration_warnings()

## All Regions, or only the regions in Regions.
@export var scope: Scope = Scope.ALL_REGIONS:
	set(value):
		scope = value
		notify_property_list_changed()

## Region locations to bake (Scope = Listed Regions). "Add Selected Node's Region" fills this.
@export var regions: Array[Vector2i] = []

## On: only rewrites vertices that are still auto or still exactly what the last bake wrote, so
## anything you hand-painted since stays. Off: rewrites every vertex in the scope.
@export var keep_hand_painting := true

## What the last bake wrote (used by Keep Hand Painting). Created next to the Terrain3D data
## (terrain_layer_bake.res) on the first bake.
@export var bake_data: TerrainLayerBakeData

@export_tool_button("Bake", "Bake") var bake_button := bake
## Sets baked vertices (that you haven't painted over) back to auto, so the live layers show again.
@export_tool_button("Return Baked To Auto", "Reload") var return_button := return_to_auto
## Adds the region under the node selected in the Scene dock to Regions (and switches to Listed).
@export_tool_button("Add Selected Node's Region", "Add") var add_region_button := add_selected_region


func documentation_file() -> String:
	return "terrain_layer_baking_tests.md"

var _busy := false
var _jobs: Array[RegionJob] = []
var _evaluator: TerrainLayerEvaluator


class RegionJob extends RefCounted:
	var location := Vector2i.ZERO
	var size := 0
	var spacing := 1.0
	var origin := Vector2.ZERO
	var heights := PackedFloat32Array() # (size + 2)^2, 1 vertex border from neighbors
	var control := PackedByteArray()
	var previous := PackedByteArray() # last bake for this region (may be empty)
	var keep_hand_painting := true
	var return_to_auto := false
	var result := PackedByteArray()
	var baked := PackedByteArray()
	var changed := 0
	var rows_done := 0


func get_layer_masks() -> TerrainLayerMasks:
	if layer_masks:
		return layer_masks
	var p := get_parent()
	if p is TerrainLayerMasks:
		return p
	if p:
		for c in p.get_children():
			if c is TerrainLayerMasks:
				return c
	return null


func get_terrain():
	var lm := get_layer_masks()
	return lm.get_terrain() if lm else null


func bake() -> void:
	await _run(false)


func return_to_auto() -> void:
	await _run(true)


func add_selected_region() -> void:
	var t = get_terrain()
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if t == null or editor == null:
		return
	var existing := Terrain3DBridge.region_locations(t)
	for n in editor.get_selection().get_selected_nodes():
		if n is Node3D:
			var loc := Terrain3DBridge.region_location_at(t, n.global_position)
			if loc in existing and not loc in regions:
				regions.append(loc)
				print("TerrainLayerBaker: added region %s." % loc)
	scope = Scope.LISTED_REGIONS
	notify_property_list_changed()


func _run(to_auto: bool) -> void:
	if _busy:
		return
	var t = get_terrain()
	var lm := get_layer_masks()
	if t == null or lm == null:
		push_warning("TerrainLayerBaker: put this node under a TerrainLayerMasks (on a Terrain3D).")
		return
	if not to_auto:
		_evaluator = lm.create_evaluator()
		if _evaluator == null or _evaluator.layer_count <= 0:
			push_warning("TerrainLayerBaker: the Layer Stack has no enabled layers to bake.")
			return
	_busy = true
	_ensure_bake_data(t)
	var started := Time.get_ticks_msec()
	_jobs = _prepare_jobs(t, to_auto)
	if _jobs.is_empty():
		push_warning("TerrainLayerBaker: no regions to %s." % ("return to auto" if to_auto else "bake"))
		_busy = false
		return

	var task := WorkerThreadPool.add_group_task(_run_job, _jobs.size(), -1, true, "TerrainLayerBaker")
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
			print("TerrainLayerBaker: %d%%" % int(100.0 * rows / maxi(total, 1)))
	WorkerThreadPool.wait_for_group_task_completion(task)

	var changed := 0
	var changes := []
	for j in _jobs:
		if j.changed > 0:
			changed += j.changed
			var old_control := j.control
			var old_baked := j.previous
			changes.append([j.location, j.result, j.baked, old_control, old_baked])
	_apply_changes(t, changes, "Return baked terrain layers to auto" if to_auto else "Bake terrain layers")
	var verb := "returned to auto" if to_auto else "baked"
	print("TerrainLayerBaker: %s %d vertices in %d region(s) in %.1f s." % [verb, changed, _jobs.size(), (Time.get_ticks_msec() - started) / 1000.0])
	_jobs.clear()
	_evaluator = null
	_busy = false


func _prepare_jobs(t, to_auto: bool) -> Array[RegionJob]:
	var jobs: Array[RegionJob] = []
	var all := Terrain3DBridge.region_locations(t)
	var locations: Array[Vector2i] = []
	for loc in (all if scope == Scope.ALL_REGIONS else regions):
		if loc in all and not loc in locations:
			locations.append(loc)
	var size := Terrain3DBridge.region_size(t)
	var spacing := Terrain3DBridge.vertex_spacing(t)
	for loc in locations:
		var control_img := Terrain3DBridge.get_map(t, loc, Terrain3DBridge.MAP_CONTROL)
		var height_img := Terrain3DBridge.get_map(t, loc, Terrain3DBridge.MAP_HEIGHT)
		if control_img == null or height_img == null:
			continue
		var job := RegionJob.new()
		job.location = loc
		job.size = size
		job.spacing = spacing
		job.origin = Terrain3DBridge.region_origin(t, loc)
		job.control = control_img.get_data()
		job.previous = bake_data.get_region(loc) if bake_data else PackedByteArray()
		job.keep_hand_painting = keep_hand_painting
		job.return_to_auto = to_auto
		if not to_auto:
			job.heights = _padded_heights(t, height_img, job)
		jobs.append(job)
	return jobs


## Region heights with a 1-vertex border taken from the neighbours, for edge normals.
func _padded_heights(t, height_img: Image, job: RegionJob) -> PackedFloat32Array:
	var s := job.size
	var w := s + 2
	var inner := height_img.get_data().to_float32_array()
	var out := PackedFloat32Array()
	out.resize(w * w)
	for y in s:
		for x in s:
			out[(y + 1) * w + x + 1] = inner[y * s + x]
	for i in w:
		for p in [Vector2i(i, 0), Vector2i(i, w - 1), Vector2i(0, i), Vector2i(w - 1, i)]:
			var world := Vector3(job.origin.x + (p.x - 1) * job.spacing, 0.0, job.origin.y + (p.y - 1) * job.spacing)
			var h := Terrain3DBridge.height_at(t, world)
			if is_nan(h):
				var cx := clampi(p.x - 1, 0, s - 1)
				var cy := clampi(p.y - 1, 0, s - 1)
				h = inner[cy * s + cx]
			out[p.y * w + p.x] = h
	return out


## Worker thread: one region.
func _run_job(index: int) -> void:
	var job := _jobs[index]
	var s := job.size
	var w := s + 2
	var out := job.control.duplicate()
	var baked := PackedByteArray()
	baked.resize(out.size())
	var has_previous := job.previous.size() == out.size()
	var keep_mask := ~Terrain3DBridge.CONTROL_TEXTURE_BITS
	for y in s:
		for x in s:
			var o := (y * s + x) * 4
			var cur := out.decode_u32(o)
			var ours := has_previous and job.previous.decode_u32(o) == cur
			var value := cur
			if job.return_to_auto:
				if ours or not job.keep_hand_painting:
					value = cur | Terrain3DBridge.CONTROL_AUTO
				baked.encode_u32(o, NOT_BAKED)
			else:
				var allowed := (cur & Terrain3DBridge.CONTROL_AUTO) != 0 or ours or not job.keep_hand_painting
				if allowed:
					var i := (y + 1) * w + x + 1
					var normal := Vector3(job.heights[i - 1] - job.heights[i + 1], 2.0 * job.spacing,
						job.heights[i - w] - job.heights[i + w]).normalized()
					var pos := Vector3(job.origin.x + x * job.spacing, job.heights[i], job.origin.y + y * job.spacing)
					value = (cur & keep_mask) | _evaluator.evaluate(pos, normal)
					baked.encode_u32(o, value)
				else:
					baked.encode_u32(o, NOT_BAKED)
			if value != cur:
				out.encode_u32(o, value)
				job.changed += 1
		job.rows_done = y + 1
	job.result = out
	job.baked = PackedByteArray() if job.return_to_auto else baked


## changes: [location, new control, new bake data, old control, old bake data]
func _apply_changes(t, changes: Array, action_name: String) -> void:
	if changes.is_empty():
		return
	var editor = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if editor:
		var ur = editor.get_editor_undo_redo()
		ur.create_action(action_name)
		for c in changes:
			ur.add_do_method(self, &"_apply_region", c[0], c[1], c[2])
			ur.add_undo_method(self, &"_apply_region", c[0], c[3], c[4])
		ur.add_do_method(self, &"_finish_apply")
		ur.add_undo_method(self, &"_finish_apply")
		ur.commit_action()
	else:
		for c in changes:
			_apply_region(c[0], c[1], c[2])
		_finish_apply()


func _apply_region(location: Vector2i, control: PackedByteArray, baked: PackedByteArray) -> void:
	var t = get_terrain()
	if t == null:
		return
	var s := Terrain3DBridge.region_size(t)
	Terrain3DBridge.set_map(t, location, Terrain3DBridge.MAP_CONTROL, Image.create_from_data(s, s, false, Image.FORMAT_RF, control))
	if bake_data:
		bake_data.set_region(location, baked)


func _finish_apply() -> void:
	var t = get_terrain()
	if t:
		Terrain3DBridge.update_maps(t, Terrain3DBridge.MAP_CONTROL)
	if bake_data and not bake_data.resource_path.is_empty():
		ResourceSaver.save(bake_data, bake_data.resource_path)


func _ensure_bake_data(t) -> void:
	if bake_data:
		return
	var dir := Terrain3DBridge.data_directory(t)
	if dir.is_empty():
		bake_data = TerrainLayerBakeData.new()
		return
	var path := dir.path_join("terrain_layer_bake.res")
	if ResourceLoader.exists(path):
		bake_data = load(path)
	else:
		bake_data = TerrainLayerBakeData.new()
		ResourceSaver.save(bake_data, path)
		bake_data = load(path)


func _validate_property(property: Dictionary) -> void:
	if property.name == "regions" and scope != Scope.LISTED_REGIONS:
		property.usage = PROPERTY_USAGE_STORAGE


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var lm := get_layer_masks()
	if lm == null:
		w.append("Put this node under a TerrainLayerMasks node (or assign Layer Masks).")
	elif lm.stack == null:
		w.append("The TerrainLayerMasks node has no Layer Stack to bake.")
	return w