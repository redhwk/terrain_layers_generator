@tool
class_name TerrainGeneratorShapeData
extends RefCounted
## Snapshot of one TerrainGeneratorShape for worker threads (no node access from threads).

enum Type { MOUNTAIN, VALLEY, MESA, ISLAND, LAKE, FLATTEN }

var type := Type.MOUNTAIN
var blend_mode := 0
var center := Vector2.ZERO
var radius := 1.0 # Mountain: foot. Valley/Mesa/Island/Lake/Flatten: half-width (local Z).
var half_length := 1.0 # Valley/Mesa/Island/Lake/Flatten: half-length (local X).
var rotation := 0.0 # Oriented shapes: radians around Y.
var floor_width := 0.0 # Valley/Lake bed. Mesa top. Island shore. Flatten edge-width fraction.
var height := 0.0 # Mountain/Mesa/Island/Flatten target / Valley/Lake depth.
var shore_height := 0.0 # Island: absolute height at the outer shore.
var falloff_curve := PackedFloat32Array() # empty = (1 - t)^2
var roughness := 0.0
var roughness_noise: FastNoiseLite # null = none
var warp_amount := 0.0
var warp_noise: FastNoiseLite # null = none


func is_inside(x: float, z: float) -> bool:
	match type:
		Type.MOUNTAIN:
			return _mountain_t(x, z) < 1.0
		Type.VALLEY:
			return _ellipse_t(x, z) < 1.0
		Type.MESA, Type.ISLAND, Type.LAKE, Type.FLATTEN:
			return _mesa_t(x, z) < 1.0
	return false


## Height this shape contributes at world XZ, before blend_mode (0 outside the footprint).
func contribution(x: float, z: float) -> float:
	match type:
		Type.MOUNTAIN:
			return _mountain(x, z)
		Type.VALLEY:
			return _valley(x, z)
		Type.MESA:
			return _mesa(x, z)
		Type.ISLAND:
			return _island(x, z)
		Type.LAKE:
			return _lake(x, z)
		Type.FLATTEN:
			return height # Target elevation; apply() lerps current toward this by mask.
	return 0.0


## Normalised distance from the peak (0) to the foot (1+), with optional warp so the footprint
## isn't a perfect circle.
func _mountain_t(x: float, z: float) -> float:
	var dx := x - center.x
	var dz := z - center.y
	if warp_noise and warp_amount > 0.0:
		var w := warp_amount * radius
		dx += warp_noise.get_noise_2d(x, z) * w
		dz += warp_noise.get_noise_2d(x + 3911.7, z - 2843.1) * w
	return sqrt(dx * dx + dz * dz) / maxf(radius, 0.001)


func _mountain(x: float, z: float) -> float:
	var t := _mountain_t(x, z)
	if t >= 1.0:
		return 0.0
	var falloff := _shape_falloff(t)
	var h := height * falloff
	if roughness_noise and roughness > 0.0:
		h += roughness_noise.get_noise_2d(x, z) * height * roughness * falloff
	return h


func _to_oriented_local(x: float, z: float) -> Vector2:
	var dx := x - center.x
	var dz := z - center.y
	if warp_noise and warp_amount > 0.0:
		var w := warp_amount * maxf(half_length, radius)
		dx += warp_noise.get_noise_2d(x, z) * w
		dz += warp_noise.get_noise_2d(x + 3911.7, z - 2843.1) * w
	var cos_y := cos(rotation)
	var sin_y := sin(rotation)
	return Vector2(dx * cos_y + dz * sin_y, -dx * sin_y + dz * cos_y)


## Elliptical normalised radius (0 at centre, 1 at the foot).
func _ellipse_t(x: float, z: float) -> float:
	var local := _to_oriented_local(x, z)
	var nx := local.x / maxf(half_length, 0.001)
	var nz := local.y / maxf(radius, 0.001)
	return sqrt(nx * nx + nz * nz)


func _valley(x: float, z: float) -> float:
	var local := _to_oriented_local(x, z)
	var ta := absf(local.x) / maxf(half_length, 0.001)
	var tc := absf(local.y) / maxf(radius, 0.001)
	if ta >= 1.0 or tc >= 1.0:
		return 0.0
	# Soft ends along the valley.
	var along := (1.0 - ta) * (1.0 - ta)
	var across: float
	var floor_t := clampf(floor_width, 0.0, 0.95)
	if tc <= floor_t:
		across = 1.0
	else:
		var u := (tc - floor_t) / maxf(1.0 - floor_t, 0.001)
		across = _shape_falloff(u)
	var strength := across * along
	var h := height * strength
	if roughness_noise and roughness > 0.0:
		h += roughness_noise.get_noise_2d(x, z) * height * roughness * strength
	return h


## Mesa normalised radius. Warp varies the outline by angle (irregular plateau) instead of
## domain-warping XZ, which caused castle-spike rims on thin cliff bands.
func _mesa_t(x: float, z: float) -> float:
	var dx := x - center.x
	var dz := z - center.y
	var cos_y := cos(rotation)
	var sin_y := sin(rotation)
	var local := Vector2(dx * cos_y + dz * sin_y, -dx * sin_y + dz * cos_y)
	var nx := local.x / maxf(half_length, 0.001)
	var nz := local.y / maxf(radius, 0.001)
	var r := sqrt(nx * nx + nz * nz)
	if r < 0.0001:
		return 0.0
	if warp_noise and warp_amount > 0.0:
		# One broad lobe only — fine harmonics read as rim spikes on steep cliffs.
		var ang := atan2(nz, nx)
		var w1 := warp_noise.get_noise_2d(cos(ang) * 1.15, sin(ang) * 1.15)
		var mod := 1.0 + warp_amount * w1
		r /= maxf(mod, 0.65)
	return r


func _mesa(x: float, z: float) -> float:
	var t := _mesa_t(x, z)
	# Soft outer fade at the foot only (talus into the surroundings).
	const FOOT_FADE := 0.14
	if t >= 1.0:
		return 0.0
	var foot := 1.0
	if t > 1.0 - FOOT_FADE:
		foot = smoothstep(0.0, 1.0, (1.0 - t) / FOOT_FADE)
	var top := clampf(floor_width, 0.0, 0.95)
	var strength: float
	if t <= top:
		# Flat plateau — no rim bevel (a bevel + cliff restart made a raised walking lip).
		strength = 1.0
	else:
		var u := (t - top) / maxf(1.0 - top, 0.001)
		if falloff_curve.is_empty():
			strength = _mesa_cliff(u)
		else:
			strength = _shape_falloff(u)
	var h := height * strength * foot
	if roughness_noise and roughness > 0.0:
		var n := roughness_noise.get_noise_2d(x, z)
		if t <= top:
			# Rolling / washes; fade out before the rim so the edge stays clean.
			var taper := 1.0 if top <= 0.05 else smoothstep(top * 0.85, top * 0.55, t)
			h += n * height * roughness * 0.12 * foot * taper
		else:
			var band := strength * (1.0 - strength) * 4.0
			h += n * height * roughness * 0.18 * band * foot
	h = minf(h, height)
	return maxf(h, 0.0)


## Steep near the rim, eases into talus at the foot. One continuous curve (no mid-cliff shelf).
## u = 0 at rim, 1 at foot.
func _mesa_cliff(u: float) -> float:
	return pow(1.0 - u, 2.35)


## Lake bowl: flat bed in the centre, banks rising to the rim. Strength 1 = full Depth (Subtract).
func _lake(x: float, z: float) -> float:
	var t := _mesa_t(x, z)
	if t >= 1.0:
		return 0.0
	var bed := clampf(floor_width, 0.0, 0.95)
	var strength: float
	if t <= bed:
		strength = 1.0
	else:
		var u := (t - bed) / maxf(1.0 - bed, 0.001)
		strength = _shape_falloff(u)
	# Soft outer fade so the rim doesn't cut a hard ring into the banks.
	const RIM_FADE := 0.10
	if t > 1.0 - RIM_FADE:
		strength *= smoothstep(0.0, 1.0, (1.0 - t) / RIM_FADE)
	var h := height * strength
	if roughness_noise and roughness > 0.0:
		h += roughness_noise.get_noise_2d(x, z) * height * roughness * strength
	return maxf(h, 0.0)


## Island: interior near Height, coastal band falls to Shore Height. Uses mesa-style angular outline.
func _island(x: float, z: float) -> float:
	var t := _mesa_t(x, z)
	if t >= 1.0:
		return shore_height
	var coast := clampf(1.0 - floor_width, 0.05, 0.95)
	var mask: float
	if t <= coast:
		# Slight dome so the interior isn't a perfect table.
		mask = lerpf(1.0, 0.92, t / coast)
	else:
		var u := (t - coast) / maxf(1.0 - coast, 0.001)
		if falloff_curve.is_empty():
			mask = 0.92 * (1.0 - u) * (1.0 - u)
		else:
			mask = 0.92 * _shape_falloff(u)
	var span := height - shore_height
	var h := shore_height + span * mask
	if roughness_noise and roughness > 0.0:
		h += roughness_noise.get_noise_2d(x, z) * absf(span) * roughness * mask
	return h


## 1 at the centre / floor, 0 at the rim. Empty = ((1 - t)^2).
## Rising curves (Godot Smoothstep / Ease) are sampled from the right so the centre stays high.
func _shape_falloff(t: float) -> float:
	if falloff_curve.is_empty():
		return (1.0 - t) * (1.0 - t)
	if falloff_curve[0] < falloff_curve[falloff_curve.size() - 1]:
		return TerrainGenerator._sample(falloff_curve, 1.0 - t)
	return TerrainGenerator._sample(falloff_curve, t)


## Flatten strength (base Edge Width only). Prefer _flatten_apply — it also widens near cliffs.
func _flatten_mask(x: float, z: float) -> float:
	return _flatten_strength(x, z, 0.0)


## 0..1 blend weight. height_delta widens the soft zone so tall cliffs/banks don't form a short stretched slope.
func _flatten_strength(x: float, z: float, height_delta: float) -> float:
	var t := _mesa_t(x, z)
	if t >= 1.0:
		return 0.0
	var base_inner := clampf(1.0 - floor_width, 0.05, 0.95)
	# Up to ~40% extra feather when |current - Height| is large (cliffs / steep banks).
	var expand := clampf(height_delta / 70.0, 0.0, 0.4)
	var inner := clampf(base_inner - expand * (1.0 - base_inner), 0.02, base_inner)
	if t <= inner:
		return 1.0
	var u := (t - inner) / maxf(1.0 - inner, 0.001)
	# Perlin smootherstep — zero 1st/2nd derivatives at ends (gentler texture slopes than a linear rim).
	u = clampf(u, 0.0, 1.0)
	var s := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	return 1.0 - s


func _flatten_apply(current: float, x: float, z: float) -> float:
	return lerpf(current, height, _flatten_strength(x, z, absf(current - height)))


## Combines this shape into the height built so far.
func apply(current: float, x: float, z: float) -> float:
	if not is_inside(x, z):
		return current
	var c := contribution(x, z)
	# Island always sets absolute height inside the footprint (forces the shore down to Shore Height).
	if type == Type.ISLAND:
		return c
	# Flatten lerps existing ground toward the target Height (soft edge; widens near cliffs).
	if type == Type.FLATTEN:
		return _flatten_apply(current, x, z)
	match blend_mode:
		TerrainGeneratorShape.BlendMode.ADD:
			return current + c
		TerrainGeneratorShape.BlendMode.MAX:
			return maxf(current, c)
		TerrainGeneratorShape.BlendMode.MIN:
			return minf(current, c)
		TerrainGeneratorShape.BlendMode.SUBTRACT:
			return current - c
	return current
