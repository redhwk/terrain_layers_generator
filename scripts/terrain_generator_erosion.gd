@tool
## Final polish after shapes are done: softens slopes (thermal) and optionally nudges light flow.
## Does not run during TerrainGenerator Generate — press Generate on this node only. Prefer Scope =
## Area 256–512; Flow Strength 0 first (weaker PCs). Toast shows time and max height change.
class_name TerrainGeneratorErosion
extends TerrainGeneratorShape



## How many erosion passes to run. 10–20 is usually enough on a 256–512 Area; higher gets expensive.
@export_range(1, 80, 1) var iterations := 16:
	set(value):
		iterations = value
		update_configuration_warnings()

## How strongly slopes shed material each pass (0 = off, 0.45 typical, 0.7 aggressive).
@export_range(0.0, 1.0, 0.01) var thermal_strength := 0.45

## Max stable slope as height-difference / spacing (≈ tan of the repose angle). ~0.4 ≈ 22°,
## ~0.7 ≈ 35°, ~1.0 ≈ 45°. Lower = more rounding (visible on rolling hills); higher = only cliffs move.
@export_range(0.1, 2.0, 0.05) var talus := 0.4

@export_group("Flow", "flow_")
## Optional hydraulic sediment move. 0 = thermal only (recommended first). 0.1–0.3 = light gullies;
## higher is slower and can over-carve. Keep Iterations modest when this is on.
@export_range(0.0, 1.0, 0.01) var flow_strength := 0.0:
	set(value):
		flow_strength = value
		update_configuration_warnings()
## Rain deposited per flow pass (relative). Only used when Flow Strength > 0.
@export_range(0.01, 1.0, 0.01) var flow_rain := 0.12
## How quickly water evaporates each pass (higher = shorter travel).
@export_range(0.01, 0.5, 0.01) var flow_evaporation := 0.08
@export_group("")


## Snapshot for worker threads (no node access).
class Job extends RefCounted:
	var heights := PackedFloat32Array()
	var writable := PackedByteArray() # 1 = cell may change (scope); 0 = halo read-only
	var width := 0
	var height := 0
	var spacing := 1.0
	var iterations := 16
	var thermal_strength := 0.35
	var talus := 0.7
	var flow_strength := 0.0
	var flow_rain := 0.12
	var flow_evaporation := 0.08
	var iterations_done := 0
	var result := PackedFloat32Array()


## Erosion is a post-pass; it never participates in TerrainGenerator's full Generate.

func documentation_file() -> String:
	return "erosion.md"

func snapshot() -> TerrainGeneratorShapeData:
	return null


func generate() -> void:
	var gen := get_generator()
	if gen == null:
		push_warning("%s: put this node under a TerrainGenerator." % name)
		return
	if not enabled:
		push_warning("%s: Enabled is off." % name)
		return
	await gen.apply_erosion(self)


func make_job() -> Job:
	var j := Job.new()
	j.iterations = iterations
	j.thermal_strength = thermal_strength
	j.talus = talus
	j.flow_strength = flow_strength
	j.flow_rain = flow_rain
	j.flow_evaporation = flow_evaporation
	return j


## Worker-safe: thermal + optional light flow over the height grid.
static func run_job(job: Job) -> void:
	var h := job.heights.duplicate()
	var w := job.width
	var ht := job.height
	var talus_h := job.talus * job.spacing
	var do_flow := job.flow_strength > 0.0
	var water := PackedFloat32Array()
	if do_flow:
		water.resize(h.size())
	for iter in job.iterations:
		if job.thermal_strength > 0.0:
			_thermal_pass(h, job.writable, w, ht, talus_h, job.thermal_strength)
		if do_flow:
			_flow_pass(h, water, job.writable, w, ht, job.flow_strength, job.flow_rain, job.flow_evaporation)
		job.iterations_done = iter + 1
	job.result = h


static func _thermal_pass(h: PackedFloat32Array, writable: PackedByteArray, w: int, ht: int, talus_h: float, amount: float) -> void:
	var delta := PackedFloat32Array()
	delta.resize(h.size())
	for y in range(1, ht - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if writable[i] == 0:
				continue
			var hi := h[i]
			var best_diff := 0.0
			var best_j := -1
			# Steepest downhill among 4-neighbors.
			var j := i - 1
			var d := hi - h[j]
			if d > best_diff:
				best_diff = d
				best_j = j
			j = i + 1
			d = hi - h[j]
			if d > best_diff:
				best_diff = d
				best_j = j
			j = i - w
			d = hi - h[j]
			if d > best_diff:
				best_diff = d
				best_j = j
			j = i + w
			d = hi - h[j]
			if d > best_diff:
				best_diff = d
				best_j = j
			if best_j < 0 or best_diff <= talus_h:
				continue
			var move := (best_diff - talus_h) * amount * 0.5
			delta[i] -= move
			delta[best_j] += move
	for i in h.size():
		h[i] += delta[i]


## Light hydraulic: rain, flow to lowest neighbor with a little sediment, evaporate.
static func _flow_pass(h: PackedFloat32Array, water: PackedFloat32Array, writable: PackedByteArray, w: int, ht: int, strength: float, rain: float, evaporation: float) -> void:
	var n := h.size()
	var rain_amt := rain * strength
	for i in n:
		if writable[i] != 0:
			water[i] += rain_amt
	var h_delta := PackedFloat32Array()
	var w_delta := PackedFloat32Array()
	h_delta.resize(n)
	w_delta.resize(n)
	var capacity := 0.15 * strength
	var erode_k := 0.08 * strength
	var deposit_k := 0.08 * strength
	for y in range(1, ht - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if writable[i] == 0 or water[i] <= 0.0001:
				continue
			var hi := h[i]
			var best_j := i
			var best_h := hi
			var j := i - 1
			if h[j] < best_h:
				best_h = h[j]
				best_j = j
			j = i + 1
			if h[j] < best_h:
				best_h = h[j]
				best_j = j
			j = i - w
			if h[j] < best_h:
				best_h = h[j]
				best_j = j
			j = i + w
			if h[j] < best_h:
				best_h = h[j]
				best_j = j
			if best_j == i:
				# Flat / pit: deposit a little sediment and evaporate.
				var dep := minf(water[i] * deposit_k, water[i])
				h_delta[i] += dep
				w_delta[i] -= dep
				continue
			var slope := hi - best_h
			var transfer := minf(water[i] * 0.5, water[i] * (0.25 + slope * 0.1))
			w_delta[i] -= transfer
			w_delta[best_j] += transfer
			# Erode at source, deposit a fraction downhill (scaled by how full the "capacity" is).
			var sediment := minf(transfer * erode_k * clampf(slope, 0.0, 2.0), capacity)
			if writable[i] != 0:
				h_delta[i] -= sediment
			if writable[best_j] != 0:
				h_delta[best_j] += sediment * 0.85
	for i in n:
		h[i] += h_delta[i]
		water[i] = maxf(water[i] + w_delta[i], 0.0) * (1.0 - evaporation)


func outline_key() -> String:
	return "%s:%s:%s:%s:%s" % [iterations, thermal_strength, talus, flow_strength, enabled]


func outline_color() -> Color:
	return Color(0.35, 0.85, 0.55)


## Draws the generator Area (erosion always covers the whole Scope / Area).
func add_outline(mesh: ImmediateMesh, y: float) -> void:
	var gen := get_generator()
	if gen == null or gen.scope != TerrainGenerator.Scope.AREA:
		return
	var r := gen.get_area_rect()
	var color := outline_color()
	var c := [
		Vector3(r.position.x, y, r.position.y),
		Vector3(r.end.x, y, r.position.y),
		Vector3(r.end.x, y, r.end.y),
		Vector3(r.position.x, y, r.end.y),
	]
	mesh.surface_set_color(color)
	for i in 4:
		mesh.surface_add_vertex(c[i])
		mesh.surface_add_vertex(c[(i + 1) % 4])


func get_footprint_rect() -> Rect2:
	var gen := get_generator()
	if gen and gen.scope == TerrainGenerator.Scope.AREA:
		return gen.get_area_rect()
	return Rect2()


func _validate_property(property: Dictionary) -> void:
	if property.name == "blend_mode":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var w := super._get_configuration_warnings()
	var gen := get_generator()
	if gen and gen.scope == TerrainGenerator.Scope.AREA:
		var cells := int(gen.area_size.x * gen.area_size.y)
		if cells > 512 * 512 and iterations > 24:
			w.append("Large Area + high Iterations will be slow. Try Area 256–512 or fewer Iterations.")
		if flow_strength > 0.0 and cells > 512 * 512:
			w.append("Flow on a large Area is especially slow. Prefer thermal only (Flow Strength 0) first.")
	return w